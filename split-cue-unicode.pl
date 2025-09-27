#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use File::Find;
use File::Basename qw/dirname/;
use File::Spec;
use Encode qw/decode encode FB_DEFAULT/;
use Unicode::Normalize qw/NFC NFD/;

# --------------------------
# Config
# --------------------------
my $AUDIO_EXT_OK = qr/\.flac$/i;   # only cue+flac
my $OUT_DIR_NAME = 'split';
my $REENCODE     = 1;              # 1=re-encode FLAC, 0=copy
my $FLAC_LEVEL   = 8;

# Ensure console prints UTF-8 cleanly
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
$ENV{LC_ALL} //= 'en_US.UTF-8';
$ENV{LANG}   //= 'en_US.UTF-8';

my $IS_DARWIN = ($^O eq 'darwin');

# --------------------------
# Helpers
# --------------------------
sub say { print @_, "\n" }

sub os_norm {
    my ($s) = @_;
    # On macOS filenames are typically decomposed; use NFD to match Finder/FS.
    return $IS_DARWIN ? NFD($s) : NFC($s);
}
sub os_encode_path {
    my ($s) = @_;
    return encode('UTF-8', os_norm($s));
}
sub decode_line {
    my ($bytes) = @_;
    # Try UTF-8 first (most modern cues), then cp1251 (common for RU), then latin1.
    for my $enc ('UTF-8','cp1251','latin1') {
        my $str = eval { decode($enc, $bytes, FB_DEFAULT) };
        return $str if defined $str && $str ne '';
    }
    return decode('UTF-8', $bytes); # last resort
}
sub cue_time_to_seconds {
    my ($t) = @_;
    return undef unless defined $t && $t =~ /^(\d+):(\d+):(\d+)$/;
    my ($mm,$ss,$ff) = ($1,$2,$3);
    return sprintf('%.3f', $mm*60 + $ss + $ff/75.0);
}
sub run_cmd_ok {
    my ($argv) = @_;
    system(@$argv) == 0;
}
sub read_ffprobe_duration {
    my ($audio_path_utf8) = @_;
    my @cmd = (
        'ffprobe','-v','error','-show_entries','format=duration',
        '-of','default=noprint_wrappers=1:nokey=1',
        os_encode_path($audio_path_utf8)
    );
    open my $ph, "-|", @cmd or return undef;
    my $out = <$ph>;
    close $ph;
    return undef unless defined $out;
    chomp $out;
    return ($out =~ /^\d+(?:\.\d+)?$/) ? $out : undef;
}

# Resolve a CUE FILE name to an actual file on disk, ignoring Unicode normalization/case
sub resolve_fs_path {
    my ($dir_utf8, $name_utf8) = @_;
    my $want = NFC($name_utf8);
    my $dir_os = os_encode_path($dir_utf8);

    if (opendir my $dh, $dir_os) {
        while (defined(my $entry_bytes = readdir $dh)) {
            next if $entry_bytes eq '.' || $entry_bytes eq '..';
            my $entry = eval { decode('UTF-8', $entry_bytes, FB_DEFAULT) } // $entry_bytes;
            # Compare with normalization-insensitive & case-insensitive match
            if (NFC($entry) eq $want || lc(NFC($entry)) eq lc($want)) {
                closedir $dh;
                return File::Spec->catfile($dir_utf8, $entry);
            }
        }
        closedir $dh;
    }
    # Fallback to the raw name; may still work if spelling/normalization match
    return File::Spec->catfile($dir_utf8, $name_utf8);
}

# --------------------------
# CUE parsing
# --------------------------
sub parse_cue {
    my ($cue_path_utf8) = @_;
    open my $fh, '<:raw', os_encode_path($cue_path_utf8) or return (undef, "Cannot open CUE: $!");
    my @bytes = <$fh>;
    close $fh;

    my @L = map { s/\r\n?/\n/; $_ } @bytes;
    @L = map { decode_line($_) } @L;

    my %disc = ( rem => {}, performer => undef, title => undef, file => undef, tracks => [] );
    my $current;

    for my $line (@L) {
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;

        if ($line =~ /^REM\s+(\S+)\s+(.+)$/i) {
            $disc{rem}->{uc($1)} = $2; next;
        }
        if ($line =~ /^PERFORMER\s+"(.*)"$/i) {
            if ($current) { $current->{performer} = $1; }
            else          { $disc{performer}  = $1; }
            next;
        }
        if ($line =~ /^TITLE\s+"(.*)"$/i) {
            if ($current) { $current->{title} = $1; }
            else          { $disc{title}     = $1; }
            next;
        }
        if ($line =~ /^FILE\s+"(.*)"\s+(\S+)/i) {
            $disc{file} = $1; next;  # single-file album assumed
        }
        if ($line =~ /^TRACK\s+(\d+)\s+(\S+)/i) {
            $current = { num => int($1), type => uc($2), index => {}, performer => undef, title => undef };
            push @{$disc{tracks}}, $current; next;
        }
        if ($line =~ /^INDEX\s+(\d+)\s+(\d+:\d+:\d+)/i && $current) {
            $current->{index}->{sprintf("%02d",$1)} = $2; next;
        }
    }
    return (\%disc, undef);
}

# --------------------------
# Split one album
# --------------------------
sub split_album_using_cue {
    my ($cue_path_utf8) = @_;

    my ($disc, $err) = parse_cue($cue_path_utf8);
    if (!$disc) { say "[SKIP] $cue_path_utf8: $err"; return; }

    if (!defined $disc->{file} || $disc->{file} !~ $AUDIO_EXT_OK) {
        say "[SKIP] $cue_path_utf8: FILE line not found or not FLAC."; return;
    }

    my $album_dir = dirname($cue_path_utf8);

    # Resolve the actual audio file on disk, accounting for Unicode quirks
    my $audio_path = resolve_fs_path($album_dir, $disc->{file});
    if (!-f os_encode_path($audio_path)) {
        say "[SKIP] $cue_path_utf8: audio file not found -> $audio_path"; return;
    }

    my $duration = read_ffprobe_duration($audio_path);
    if (!defined $duration) {
        say "[SKIP] $cue_path_utf8: cannot get duration via ffprobe."; return;
    }

    my @tracks = @{$disc->{tracks} || []};
    if (!@tracks) { say "[SKIP] $cue_path_utf8: no TRACK entries."; return; }

    # Output dir
    my $out_dir = File::Spec->catdir($album_dir, $OUT_DIR_NAME);
    mkdir os_encode_path($out_dir) unless -d os_encode_path($out_dir);

    # Album-level metadata
    my $album_artist = $disc->{performer} // '';
    my $album_title  = $disc->{title}     // '';
    my $date         = $disc->{rem}->{DATE}  // '';
    my $genre        = $disc->{rem}->{GENRE} // '';

    for my $i (0..$#tracks) {
        my $t = $tracks[$i];
        my $start   = $t->{index}->{'01'} // $t->{index}->{'00'};
        my $start_s = cue_time_to_seconds($start);
        my $end_s;

        if ($i < $#tracks) {
            my $next = $tracks[$i+1];
            my $next_start = $next->{index}->{'01'} // $next->{index}->{'00'};
            $end_s = cue_time_to_seconds($next_start);
        } else {
            $end_s = $duration;
        }
        unless (defined $start_s && defined $end_s) {
            say "[WARN] Skipping track $t->{num}: cannot resolve start/end."; next;
        }

        my $seg_dur = $end_s - $start_s;
        if ($seg_dur <= 0) {
            say "[WARN] Skipping track $t->{num}: non-positive duration."; next;
        }

        my $t_title  = $t->{title}     // sprintf("Track %02d", $t->{num});
        my $t_artist = $t->{performer} // $album_artist;

        my $nn   = sprintf("%02d", $t->{num});
        my $base = "$nn - $t_title";
        $base =~ s/[\/\\:\*\?\"<>\|]/_/g; # sanitize
        my $out_path = File::Spec->catfile($out_dir, "$base.flac");

        my @cmd = (
            'ffmpeg','-hide_banner','-loglevel','error',
            '-ss', sprintf('%.3f', $start_s),
            '-i',  os_encode_path($audio_path),
            '-t',  sprintf('%.3f', $seg_dur),
            '-map_metadata','-1',
            '-metadata', encode('UTF-8', "TITLE=$t_title"),
            '-metadata', encode('UTF-8', "TRACK=$nn"),
            ($t_artist     ? ('-metadata', encode('UTF-8',"ARTIST=$t_artist"))           : ()),
            ($album_title  ? ('-metadata', encode('UTF-8',"ALBUM=$album_title"))         : ()),
            ($album_artist ? ('-metadata', encode('UTF-8',"ALBUM_ARTIST=$album_artist")) : ()),
            ($date         ? ('-metadata', encode('UTF-8',"DATE=$date"))                 : ()),
            ($genre        ? ('-metadata', encode('UTF-8',"GENRE=$genre"))               : ()),
            '-avoid_negative_ts','make_zero',
        );

        if ($REENCODE) {
            push @cmd, ('-c:a','flac','-compression_level',$FLAC_LEVEL);
        } else {
            push @cmd, ('-c','copy');
        }

        push @cmd, os_encode_path($out_path);

        say "[CUT] $out_path";
        run_cmd_ok(\@cmd) or say "[ERR] ffmpeg failed for track $nn.";
    }
}

# --------------------------
# Walk tree
# --------------------------
sub wanted {
    return unless -f $_ && $_ =~ /\.cue$/i;
    my $cue_path = $File::Find::name;
    # Re-decode the discovered path as UTF-8 (filesystem gives us bytes)
    my $cue_utf8 = eval { decode('UTF-8', $cue_path, FB_DEFAULT) } // $cue_path;
    split_album_using_cue($cue_utf8);
}

# --------------------------
# Main
# --------------------------
my $root = shift @ARGV // '.';

for my $bin (qw/ffmpeg ffprobe perl/) {
    my $which = qx{which $bin}; chomp $which;
    die "Required tool '$bin' not found in PATH.\n" unless $which;
}

find({ wanted => \&wanted, no_chdir => 1 }, $root);

__END__

=pod

UNICODE NOTES:
  • Handles Cyrillic/accents in CUE, tags, and filenames.
  • Resolves macOS normalization (NFD) vs NFC mismatches.
  • Sends paths/metadata to ffmpeg/ffprobe as UTF-8 bytes—no shell, so [] () and spaces are safe.

USAGE:
  chmod +x split_cue_tree.pl
  ./split_cue_tree.pl "/Volumes/media/music/lib"

If your terminal still shows mojibake, ensure:
  export LC_ALL=en_US.UTF-8
  export LANG=en_US.UTF-8
=cut

