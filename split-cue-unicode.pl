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
# Defaults (override via CLI)
# --------------------------
my $DELETE_ORIGINAL = 0;     # --delete    (deletes .flac and .cue after full success)
my $DRY_RUN         = 0;     # --dry-run   (preview deletions/moves)
my $FINAL_IN_ROOT   = 0;     # --to-root   (place final files in album dir after success)
my $OVERWRITE_FINAL = 0;     # --overwrite-final (overwrite existing files when moving)
my $AUDIO_EXT_OK    = qr/\.flac$/i;   # only cue+flac
my $OUT_DIR_NAME    = 'split';        # used when NOT --to-root
my $REENCODE        = 1;              # 1=re-encode FLAC, 0=copy
my $FLAC_LEVEL      = 8;

# --------------------------
# CLI flags: [--delete] [--dry-run] [--to-root] [--overwrite-final] [ROOT]
# --------------------------
while (@ARGV && $ARGV[0] =~ /^--/) {
    my $f = shift @ARGV;
    if    ($f eq '--delete')          { $DELETE_ORIGINAL = 1; next; }
    elsif ($f eq '--dry-run')         { $DRY_RUN         = 1; next; }
    elsif ($f eq '--to-root')         { $FINAL_IN_ROOT   = 1; next; }
    elsif ($f eq '--overwrite-final') { $OVERWRITE_FINAL = 1; next; }
    else  { die "Unknown flag: $f\n"; }
}
my $ROOT = shift @ARGV // '.';

# --------------------------
# I/O & locale
# --------------------------
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
$ENV{LC_ALL} //= 'en_US.UTF-8';
$ENV{LANG}   //= 'en_US.UTF-8';
my $IS_DARWIN = ($^O eq 'darwin');

# --------------------------
# Helpers
# --------------------------
sub say { print @_, "\n" }

sub os_norm   { my ($s)=@_; return $IS_DARWIN ? NFD($s) : NFC($s) }
sub os_encode { my ($s)=@_; return encode('UTF-8', os_norm($s)) }

sub decode_line {
    my ($bytes) = @_;
    for my $enc ('UTF-8','cp1251','latin1') {
        my $str = eval { decode($enc, $bytes, FB_DEFAULT) };
        return $str if defined $str && $str ne '';
    }
    return decode('UTF-8', $bytes);
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
    my ($audio_utf8) = @_;
    my @cmd = (
        'ffprobe','-v','error','-show_entries','format=duration',
        '-of','default=noprint_wrappers=1:nokey=1',
        os_encode($audio_utf8)
    );
    open my $ph, "-|", @cmd or return undef;
    my $out = <$ph>;
    close $ph;
    return undef unless defined $out;
    chomp $out;
    return ($out =~ /^\d+(?:\.\d+)?$/) ? $out : undef;
}
sub resolve_fs_path {
    my ($dir_utf8, $name_utf8) = @_;
    my $want = NFC($name_utf8);
    my $dir_os = os_encode($dir_utf8);
    if (opendir my $dh, $dir_os) {
        while (defined(my $ent_b = readdir $dh)) {
            next if $ent_b eq '.' || $ent_b eq '..';
            my $ent = eval { decode('UTF-8', $ent_b, FB_DEFAULT) } // $ent_b;
            if (NFC($ent) eq $want || lc(NFC($ent)) eq lc($want)) {
                closedir $dh;
                return File::Spec->catfile($dir_utf8, $ent);
            }
        }
        closedir $dh;
    }
    return File::Spec->catfile($dir_utf8, $name_utf8);
}
sub ensure_dir {
    my ($dir_utf8) = @_;
    my $os = os_encode($dir_utf8);
    return 1 if -d $os;
    mkdir $os or return 0;
    return 1;
}
sub unique_path_in_dir {
    my ($dir_utf8, $file_utf8, $allow_overwrite) = @_;
    my ($base,$ext) = ($file_utf8 =~ /^(.*?)(\.[^.]+)?$/);
    my $candidate = File::Spec->catfile($dir_utf8, "$base".($ext//""));
    my $cand_os = os_encode($candidate);
    return $candidate if $allow_overwrite || !-e $cand_os;

    my $i = 1;
    while (1) {
        my $try = File::Spec->catfile($dir_utf8, sprintf("%s (%d)%s", $base, $i, ($ext//"")));
        my $try_os = os_encode($try);
        return $try unless -e $try_os;
        $i++;
    }
}

# --------------------------
# CUE parsing
# --------------------------
sub parse_cue {
    my ($cue_utf8) = @_;
    open my $fh, '<:raw', os_encode($cue_utf8) or return (undef, "Cannot open CUE: $!");
    my @bytes = <$fh>;
    close $fh;

    my @L = map { s/\r\n?/\n/; $_ } @bytes;
    @L = map { decode_line($_) } @L;

    my %disc = ( rem => {}, performer => undef, title => undef, file => undef, tracks => [] );
    my $cur;

    for my $line (@L) {
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;

        if ($line =~ /^REM\s+(\S+)\s+(.+)$/i) { $disc{rem}->{uc($1)} = $2; next; }
        if ($line =~ /^PERFORMER\s+"(.*)"$/i) {
            if    ($cur) { $cur->{performer} = $1; }
            else         { $disc{performer} = $1; }
            next;
        }
        if ($line =~ /^TITLE\s+"(.*)"$/i) {
            if    ($cur) { $cur->{title} = $1; }
            else         { $disc{title} = $1; }
            next;
        }
        if ($line =~ /^FILE\s+"(.*)"\s+(\S+)/i) { $disc{file} = $1; next; }
        if ($line =~ /^TRACK\s+(\d+)\s+(\S+)/i) {
            $cur = { num => int($1), type => uc($2), index => {}, performer => undef, title => undef };
            push @{$disc{tracks}}, $cur; next;
        }
        if ($line =~ /^INDEX\s+(\d+)\s+(\d+:\d+:\d+)/i && $cur) {
            $cur->{index}->{sprintf("%02d",$1)} = $2; next;
        }
    }
    return (\%disc, undef);
}

# --------------------------
# Split one album (+ staged → root move on success)
# --------------------------
sub split_album_using_cue {
    my ($cue_utf8) = @_;

    my ($disc, $err) = parse_cue($cue_utf8);
    if (!$disc) { say "[SKIP] $cue_utf8: $err"; return; }

    if (!defined $disc->{file} || $disc->{file} !~ $AUDIO_EXT_OK) {
        say "[SKIP] $cue_utf8: FILE line not found or not FLAC."; return;
    }

    my $album_dir  = dirname($cue_utf8);
    my $audio_path = resolve_fs_path($album_dir, $disc->{file});
    if (!-f os_encode($audio_path)) {
        say "[SKIP] $cue_utf8: audio file not found -> $audio_path"; return;
    }

    my $duration = read_ffprobe_duration($audio_path);
    if (!defined $duration) {
        say "[SKIP] $cue_utf8: cannot get duration via ffprobe."; return;
    }

    my @tracks = @{$disc->{tracks} || []};
    if (!@tracks) { say "[SKIP] $cue_utf8: no TRACK entries."; return; }

    # Choose output dir
    my $staging_dir;
    my $final_dir;
    if ($FINAL_IN_ROOT) {
        $final_dir   = $album_dir;                                   # final destination
        $staging_dir = File::Spec->catdir($album_dir, ".split.tmp-$$");
    } else {
        $final_dir   = File::Spec->catdir($album_dir, $OUT_DIR_NAME); # normal behavior
        $staging_dir = $final_dir;                                    # write directly
    }

    unless (ensure_dir($staging_dir)) {
        say "[ERR] Cannot create output directory: $staging_dir"; return;
    }
    ensure_dir($final_dir) or do { say "[ERR] Cannot create final directory: $final_dir"; return; };

    my $album_artist = $disc->{performer} // '';
    my $album_title  = $disc->{title}     // '';
    my $date         = $disc->{rem}->{DATE}  // '';
    my $genre        = $disc->{rem}->{GENRE} // '';

    my @planned_staged;     # staged paths we intend to create
    my @planned_final;      # intended final filenames (in final_dir)
    my @succeeded_staged;   # staged paths successfully created

    for my $i (0..$#tracks) {
        my $t = $tracks[$i];

        my $start   = $t->{index}->{'01'} // $t->{index}->{'00'};
        my $start_s = cue_time_to_seconds($start);
        my $end_s   = ($i < $#tracks)
                      ? cue_time_to_seconds($tracks[$i+1]{index}{'01'} // $tracks[$i+1]{index}{'00'})
                      : $duration;

        unless (defined $start_s && defined $end_s) { say "[WARN] Skipping track $t->{num}: cannot resolve start/end."; next; }
        my $seg_dur = $end_s - $start_s;
        if ($seg_dur <= 0) { say "[WARN] Skipping track $t->{num}: non-positive duration."; next; }

        my $t_title  = $t->{title}     // sprintf("Track %02d", $t->{num});
        my $t_artist = $t->{performer} // $album_artist;

        my $nn   = sprintf("%02d", $t->{num});
        my $base = "$nn - $t_title";
        $base =~ s/[\/\\:\*\?\"<>\|]/_/g;

        my $staged_path = File::Spec->catfile($staging_dir, "$base.flac");
        my $final_name  = "$base.flac";

        push @planned_staged, $staged_path;
        push @planned_final,  $final_name;

        my @cmd = (
            'ffmpeg','-hide_banner','-loglevel','error',
            '-ss', sprintf('%.3f', $start_s),
            '-i',  os_encode($audio_path),
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
        if ($REENCODE) { push @cmd, ('-c:a','flac','-compression_level',$FLAC_LEVEL); }
        else           { push @cmd, ('-c','copy'); }

        push @cmd, os_encode($staged_path);

        say "[CUT] $staged_path";
        if (run_cmd_ok(\@cmd)) {
            if (-f os_encode($staged_path)) {
                my $size = (stat(os_encode($staged_path)))[7] || 0;
                push @succeeded_staged, $staged_path if $size > 0;
            }
        } else {
            say "[ERR] ffmpeg failed for track $nn.";
        }
    }

    my $planned_n   = scalar @planned_staged;
    my $succeeded_n = scalar @succeeded_staged;

    # --------------------------
    # Finalize: move staged → final dir, then delete originals if requested
    # --------------------------
    if ($FINAL_IN_ROOT) {
        if ($planned_n > 0 && $planned_n == $succeeded_n) {
            for my $idx (0..$#planned_staged) {
                my $src  = $planned_staged[$idx];
                my $name = $planned_final[$idx];
                my $dst  = unique_path_in_dir($final_dir, $name, $OVERWRITE_FINAL);

                if ($DRY_RUN) {
                    say "[DRY] Would move: $src  ->  $dst";
                } else {
                    my $ok = rename os_encode($src), os_encode($dst);
                    unless ($ok) { say "[ERR] Move failed: $src -> $dst ($!)"; }
                    else         { say "[MOVE] $dst"; }
                }
            }
            # Cleanup temp dir
            if ($DRY_RUN) {
                say "[DRY] Would remove staging dir: $staging_dir";
            } else {
                rmdir os_encode($staging_dir) or say "[WARN] Staging not empty: $staging_dir";
            }
        } else {
            say "[KEEP] Staging kept ($succeeded_n/$planned_n ok): $staging_dir";
        }
    }

    # Optional deletion of originals (only after full success AND (not --to-root OR moves done))
    if ($DELETE_ORIGINAL) {
        if ($planned_n > 0 && $planned_n == $succeeded_n) {
            if ($DRY_RUN) {
                say "[DRY] Would delete FLAC: $audio_path";
                say "[DRY] Would delete CUE: $cue_utf8";
            } else {
                if (unlink os_encode($audio_path)) { say "[DEL] Deleted FLAC: $audio_path"; }
                else                               { say "[ERR] Failed to delete FLAC: $audio_path ($!)"; }
                if (unlink os_encode($cue_utf8))   { say "[DEL] Deleted CUE: $cue_utf8"; }
                else                               { say "[ERR] Failed to delete CUE: $cue_utf8 ($!)"; }
            }
        } else {
            say "[KEEP] Originals kept (success $succeeded_n/$planned_n).";
        }
    } else {
        say "[KEEP] Originals kept (use --delete to remove after success).";
    }
}

# --------------------------
# Walk tree
# --------------------------
sub wanted {
    return unless -f $_ && $_ =~ /\.cue$/i;
    my $cue_path = $File::Find::name;
    my $cue_utf8 = eval { decode('UTF-8', $cue_path, FB_DEFAULT) } // $cue_path;
    split_album_using_cue($cue_utf8);
}

# --------------------------
# Main
# --------------------------
for my $bin (qw/ffmpeg ffprobe perl/) {
    my $which = qx{which $bin}; chomp $which;
    die "Required tool '$bin' not found in PATH.\n" unless $which;
}

say "[INFO] Root: $ROOT";
say "[INFO] Final in album root: ".($FINAL_IN_ROOT ? 'ON' : 'OFF');
say "[INFO] Overwrite existing finals: ".($OVERWRITE_FINAL ? 'ON' : 'OFF');
say "[INFO] Delete originals after success: ".($DELETE_ORIGINAL ? 'ON' : 'OFF').($DRY_RUN ? ' (dry-run)' : '');
find({ wanted => \&wanted, no_chdir => 1 }, $ROOT);

__END__

=pod

USAGE:
  chmod +x split_cue_tree.pl
  # stage in a temp dir, then move finished tracks into the album folder
  ./split_cue_tree.pl --to-root "/path/to/music/root"

  # also delete original .flac and .cue, preview first
  ./split_cue_tree.pl --to-root --delete --dry-run "/Volumes/media/music/lib"
  ./split_cue_tree.pl --to-root --delete "/Volumes/media/music/lib"

NOTES:
  • When --to-root is OFF (default), files go to ./split/ as before.
  • With --to-root, tracks are written to .split.tmp-<pid> and moved atomically
    into the album directory after full success. If any track fails, staging is kept.
  • Use --overwrite-final to replace existing files in the album folder; otherwise
    the script appends “ (1)”, “ (2)”, … to avoid collisions.

UNICODE:
  • Handles UTF-8/cp1251/latin1 CUEs, macOS NFD filenames, UTF-8 tags & paths.

DEPENDENCIES:
  • ffmpeg, ffprobe, perl (no extra CPAN modules).
=cut
=pod

USAGE:
  chmod +x split_cue_tree.pl
  ./split_cue_tree.pl --delete [--dry-run] "/path/to/music/root"

BEHAVIOR:
  • Deletes BOTH the source .flac and its .cue only when ALL tracks were created (>0 bytes).
  • --dry-run previews deletions.

UNICODE:
  • Handles UTF-8/cp1251/latin1 CUEs, macOS NFD filenames, and UTF-8 tags.

DEPENDENCIES:
  • ffmpeg, ffprobe, perl.
=cut

