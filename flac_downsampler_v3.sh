#!/bin/bash

# FLAC Downsampler to 44.1kHz/16-bit using ffmpeg
# Usage: ./downsample_flac.sh [options] [input_directory] [output_directory]

set -e  # Exit on any error

# Default options
REPLACE_ORIGINALS=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if ffmpeg is installed
check_ffmpeg() {
    if ! command -v ffmpeg &> /dev/null; then
        print_error "ffmpeg is not installed or not in PATH"
        echo "Install ffmpeg using Homebrew: brew install ffmpeg"
        exit 1
    fi
    print_success "ffmpeg found: $(ffmpeg -version | head -n1)"
}

# Function to get file info
get_file_info() {
    local file="$1"
    ffprobe -v quiet -print_format json -show_streams "$file" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'streams' in data:
        for stream in data['streams']:
            if stream.get('codec_type') == 'audio':
                sample_rate = stream.get('sample_rate', 'unknown')
                bits_per_sample = stream.get('bits_per_sample', stream.get('bits_per_raw_sample', 'unknown'))
                print(f'{sample_rate}Hz {bits_per_sample}bit')
                break
        else:
            print('unknown format')
    else:
        print('unknown format')
except (json.JSONDecodeError, KeyError):
    print('unknown format')
"
}

# Function to downsample a single file
downsample_file() {
    local input_file="$1"
    local output_file="$2"
    local relative_display="$3"
    local replace_mode="$4"
    
    print_status "Processing: $relative_display"
    
    # Get original file info
    local original_info=$(get_file_info "$input_file")
    print_status "Original format: $original_info"
    
    # Create output directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    
    # Use temp file if replacing originals
    local actual_output="$output_file"
    if [ "$replace_mode" = true ]; then
        # Create temp file with .flac extension in same directory
        local temp_dir=$(dirname "$output_file")
        local temp_name=$(basename "$output_file" .flac)
        actual_output="${temp_dir}/.${temp_name}_tmp.flac"
    fi
    
    # FFmpeg command with high-quality downsampling
    # Capture stderr to check for errors
    local ffmpeg_output=$(mktemp)
    if ! ffmpeg -i "$input_file" \
           -ar 44100 \
           -sample_fmt s16 \
           -af "aresample=resampler=soxr:precision=28:cheby=1" \
           -compression_level 8 \
           -y \
           "$actual_output" 2>"$ffmpeg_output"; then
        print_error "FFmpeg failed. Last error:"
        tail -5 "$ffmpeg_output" | grep -i "error" || tail -3 "$ffmpeg_output"
        rm "$ffmpeg_output"
        [ -f "$actual_output" ] && rm "$actual_output"
        return 1
    fi
    rm "$ffmpeg_output"
    
    if ! [ -f "$actual_output" ]; then
        print_error "Output file was not created"
        return 1
    fi
    
    local new_info=$(get_file_info "$actual_output")
    print_success "Converted to: $new_info"
    
    # Show file sizes
    local original_size=$(stat -f%z "$input_file" 2>/dev/null || echo "0")
    local new_size=$(stat -f%z "$actual_output" 2>/dev/null || echo "0")
    if [ "$original_size" -gt 0 ]; then
        local size_reduction=$((100 - (new_size * 100 / original_size)))
        # Convert bytes to human readable format (macOS compatible)
        local orig_mb=$((original_size / 1024 / 1024))
        local new_mb=$((new_size / 1024 / 1024))
        print_status "Size reduction: ${size_reduction}% (${orig_mb}MB → ${new_mb}MB)"
    fi
    
    # Replace original if in replace mode
    if [ "$replace_mode" = true ]; then
        mv "$actual_output" "$input_file"
        print_success "Replaced original file"
    fi
}

# Main function
main() {
    print_status "FLAC Downsampler - Converting to 44.1kHz/16-bit"
    echo "=================================================="
    
    # Check dependencies
    check_ffmpeg
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--replace)
                REPLACE_ORIGINALS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Set default directories
    local input_dir="${1:-$(pwd)}"
    local output_dir="${2:-${input_dir}/downsampled}"
    
    # If replace mode, ignore output directory
    if [ "$REPLACE_ORIGINALS" = true ]; then
        output_dir="$input_dir"
        print_warning "REPLACE MODE: Original files will be overwritten!"
        echo -n "Are you sure you want to continue? (yes/no): "
        read confirmation
        if [ "$confirmation" != "yes" ]; then
            print_status "Operation cancelled"
            exit 0
        fi
    fi
    
    # Validate input directory
    if [ ! -d "$input_dir" ]; then
        print_error "Input directory does not exist: $input_dir"
        exit 1
    fi
    
    print_status "Input directory: $input_dir"
    if [ "$REPLACE_ORIGINALS" = false ]; then
        print_status "Output directory: $output_dir"
    fi
    
    # Find all FLAC files (case insensitive)
    local flac_files=()
    while IFS= read -r -d '' file; do
        flac_files+=("$file")
    done < <(find "$input_dir" \( -iname "*.flac" \) -type f -print0)
    
    if [ ${#flac_files[@]} -eq 0 ]; then
        print_warning "No FLAC files found in $input_dir"
        exit 0
    fi
    
    print_status "Found ${#flac_files[@]} FLAC files"
    echo
    
    # Process each file
    local processed=0
    local failed=0
    
    for file in "${flac_files[@]}"; do
        # Get the directory containing the file
        local file_dir=$(dirname "$file")
        
        # Calculate relative path using Python for reliable handling of special characters
        local relative_path=$(python3 -c "
import os
input_dir = '''$input_dir'''
file_path = '''$file'''
# Get relative path from input_dir to file
rel_path = os.path.relpath(file_path, input_dir)
print(rel_path)
")
        
        local output_file="$output_dir/$relative_path"
        
        if downsample_file "$file" "$output_file" "$relative_path" "$REPLACE_ORIGINALS"; then
            ((processed++))
        else
            ((failed++))
        fi
        echo
    done
    
    # Summary
    echo "=================================================="
    print_success "Processing complete!"
    print_status "Successfully processed: $processed files"
    if [ $failed -gt 0 ]; then
        print_warning "Failed: $failed files"
    fi
    if [ "$REPLACE_ORIGINALS" = false ]; then
        print_status "Output location: $output_dir"
    else
        if [ $processed -gt 0 ]; then
            print_status "Original files have been replaced"
        fi
    fi
}

# Show usage if help is requested
show_help() {
    echo "FLAC Downsampler - Convert FLAC files to 44.1kHz/16-bit"
    echo
    echo "Usage: $0 [options] [input_directory] [output_directory]"
    echo
    echo "Options:"
    echo "  -r, --replace     Replace original files instead of creating copies"
    echo "  -h, --help        Show this help message"
    echo
    echo "Arguments:"
    echo "  input_directory   Directory containing FLAC files (default: current directory)"
    echo "  output_directory  Directory for converted files (default: ./downsampled)"
    echo "                    (ignored when using --replace)"
    echo
    echo "Examples:"
    echo "  $0                                    # Process current directory"
    echo "  $0 /path/to/music                    # Process specific directory"
    echo "  $0 /path/to/music /path/to/output   # Specify both input and output"
    echo "  $0 --replace /path/to/music          # Replace original files (DESTRUCTIVE)"
    echo
    echo "Requirements:"
    echo "  - ffmpeg (install with: brew install ffmpeg)"
    echo "  - Python 3 (for file info parsing)"
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Run main function
main "$@"