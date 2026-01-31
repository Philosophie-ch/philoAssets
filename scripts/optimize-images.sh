#!/bin/bash
set -e

# =============================================================================
# Image Optimization Script for PhiloAssets
# =============================================================================
# Identifies heavy images (>1MB or >1920px), optimizes them, and generates
# WebP versions. Outputs to a separate folder (non-destructive).
#
# Usage:
#   ./optimize-images.sh <input...> [options]
#
# Dependencies:
#   sudo apt-get install imagemagick jpegoptim optipng gifsicle webp bc
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SIZE_THRESHOLD_BYTES=1048576  # 1MB in bytes
MAX_DIMENSION=1920
JPEG_QUALITY=92
WEBP_QUALITY=90

# Counters for summary
TOTAL_ORIGINAL_SIZE=0
TOTAL_OPTIMIZED_SIZE=0
PROCESSED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_usage() {
    echo "Usage: $0 <input...> [options]"
    echo ""
    echo "Arguments:"
    echo "  input...                One or more files or directories to optimize"
    echo ""
    echo "Options:"
    echo "  -o, --output <dir>      Destination folder (default: ./optimized)"
    echo "  -d, --dry-run           Preview what would be processed without making changes"
    echo "  -r, --recursive         Traverse subdirectories (default: top-level only)"
    echo "  -w, --webp              Generate WebP versions of optimized images"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 ./uploads"
    echo "  $0 ./uploads --dry-run"
    echo "  $0 ./uploads -r -w                    # recursive + webp generation"
    echo "  $0 image1.png image2.jpg -o ./out      # optimize specific files"
    echo "  $0 ./uploads ./photos -r -o ./out      # multiple directories"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

format_size() {
    local bytes=$1
    if [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc)MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

check_dependencies() {
    local missing=()

    command -v convert >/dev/null 2>&1 || missing+=("imagemagick")
    command -v identify >/dev/null 2>&1 || missing+=("imagemagick")
    command -v jpegoptim >/dev/null 2>&1 || missing+=("jpegoptim")
    command -v optipng >/dev/null 2>&1 || missing+=("optipng")
    command -v gifsicle >/dev/null 2>&1 || missing+=("gifsicle")
    command -v cwebp >/dev/null 2>&1 || missing+=("webp")
    command -v bc >/dev/null 2>&1 || missing+=("bc")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  sudo apt-get install imagemagick jpegoptim optipng gifsicle webp bc"
        exit 1
    fi
}

needs_optimization() {
    local file="$1"
    local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)

    # Check file size
    if [ "$size" -gt "$SIZE_THRESHOLD_BYTES" ]; then
        return 0
    fi

    # Check dimensions
    local dimensions=$(identify -format "%wx%h" "$file" 2>/dev/null | head -1)
    local width=$(echo "$dimensions" | cut -d'x' -f1)
    local height=$(echo "$dimensions" | cut -d'x' -f2)

    if [ -n "$width" ] && [ -n "$height" ]; then
        if [ "$width" -gt "$MAX_DIMENSION" ] || [ "$height" -gt "$MAX_DIMENSION" ]; then
            return 0
        fi
    fi

    return 1
}

# -----------------------------------------------------------------------------
# Optimization Functions
# -----------------------------------------------------------------------------

optimize_jpeg() {
    local input="$1"
    local output="$2"
    local output_dir=$(dirname "$output")

    mkdir -p "$output_dir"

    # Resize if needed and compress (convert to sRGB before stripping profiles)
    convert "$input" \
        -colorspace sRGB \
        -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" \
        -quality "$JPEG_QUALITY" \
        -strip \
        "$output"

    # Further optimize with jpegoptim
    jpegoptim --quiet --strip-all "$output"

    # Generate WebP version
    if [ "$GENERATE_WEBP" = true ]; then
        cwebp -q "$WEBP_QUALITY" -quiet "$output" -o "${output}.webp"
    fi
}

optimize_png() {
    local input="$1"
    local output="$2"
    local output_dir=$(dirname "$output")

    mkdir -p "$output_dir"

    # Resize if needed (convert to sRGB before stripping profiles to preserve colors)
    convert "$input" \
        -colorspace sRGB \
        -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" \
        -strip \
        "$output"

    # Lossless optimization only (no lossy quantization to preserve colors)
    optipng -quiet -o2 "$output"

    # Generate WebP version
    if [ "$GENERATE_WEBP" = true ]; then
        cwebp -q "$WEBP_QUALITY" -quiet "$output" -o "${output}.webp"
    fi
}

optimize_gif() {
    local input="$1"
    local output="$2"
    local output_dir=$(dirname "$output")

    mkdir -p "$output_dir"

    # Optimize GIF
    gifsicle --optimize=3 "$input" -o "$output"

    # Generate static WebP from first frame
    if [ "$GENERATE_WEBP" = true ]; then
        local tmp_frame
        tmp_frame=$(mktemp "${output_dir}/.gifframe-XXXXXX.png")
        convert "${input}[0]" -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" "$tmp_frame"
        cwebp -q "$WEBP_QUALITY" -quiet "$tmp_frame" -o "${output}.webp"
        rm -f "$tmp_frame"
    fi
}

optimize_webp() {
    local input="$1"
    local output="$2"
    local output_dir=$(dirname "$output")

    mkdir -p "$output_dir"

    # Resize and recompress
    cwebp -q "$WEBP_QUALITY" -quiet -resize "$MAX_DIMENSION" 0 "$input" -o "$output" 2>/dev/null || \
        cwebp -q "$WEBP_QUALITY" -quiet "$input" -o "$output"
}

process_image() {
    local input="$1"
    local output="$2"
    local extension="${input##*.}"
    local ext_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')

    case "$ext_lower" in
        jpg|jpeg)
            optimize_jpeg "$input" "$output"
            ;;
        png)
            optimize_png "$input" "$output"
            ;;
        gif)
            optimize_gif "$input" "$output"
            ;;
        webp)
            optimize_webp "$input" "$output"
            ;;
        *)
            log_warn "Unsupported format: $extension"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Main Script
# -----------------------------------------------------------------------------

# Parse arguments
INPUTS=()
OUTPUT_DIR="./optimized"
DRY_RUN=false
RECURSIVE=false
GENERATE_WEBP=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|-d)   DRY_RUN=true ;;
        --recursive|-r) RECURSIVE=true ;;
        --webp|-w)      GENERATE_WEBP=true ;;
        --output|-o)
            shift
            OUTPUT_DIR="${1:?'--output requires a directory argument'}"
            ;;
        --help|-h)      print_usage; exit 0 ;;
        -*)             log_error "Unknown option: $1"; print_usage; exit 1 ;;
        *)              INPUTS+=("$1") ;;
    esac
    shift
done

# Validate inputs
if [ ${#INPUTS[@]} -eq 0 ]; then
    log_error "At least one input file or directory is required"
    print_usage
    exit 1
fi

for input in "${INPUTS[@]}"; do
    if [ ! -f "$input" ] && [ ! -d "$input" ]; then
        log_error "Input does not exist: $input"
        exit 1
    fi
done

# Check dependencies
check_dependencies

# Convert output to absolute path
case "$OUTPUT_DIR" in
    /*) ;;  # already absolute
    *)  OUTPUT_DIR="$(pwd)/$OUTPUT_DIR" ;;
esac
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$OUTPUT_DIR"
fi

echo ""
echo "=============================================="
echo "  Image Optimization Script"
echo "=============================================="
echo ""
log_info "Inputs: ${INPUTS[*]}"
log_info "Output folder: $OUTPUT_DIR"
log_info "Size threshold: $(format_size $SIZE_THRESHOLD_BYTES)"
log_info "Max dimension: ${MAX_DIMENSION}px"
log_info "Dry run: $DRY_RUN"
log_info "Recursive: $RECURSIVE"
log_info "WebP generation: $GENERATE_WEBP"
echo ""

# Collect all images from inputs
IMAGES=()
INPUT_DIRS=()
for input in "${INPUTS[@]}"; do
    if [ -f "$input" ]; then
        case "${input,,}" in
            *.jpg|*.jpeg|*.png|*.gif|*.webp)
                IMAGES+=("$(realpath "$input")")
                ;;
            *)
                log_warn "Skipping unsupported file: $input"
                ;;
        esac
    elif [ -d "$input" ]; then
        abs_dir=$(cd "$input" && pwd)
        INPUT_DIRS+=("$abs_dir")
        FIND_ARGS=("$abs_dir")
        if [ "$RECURSIVE" = false ]; then
            FIND_ARGS+=(-maxdepth 1)
        fi
        FIND_ARGS+=(-type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \))
        while IFS= read -r f; do
            IMAGES+=("$f")
        done < <(find "${FIND_ARGS[@]}" 2>/dev/null)
    fi
done

if [ ${#IMAGES[@]} -eq 0 ]; then
    log_warn "No images found in: ${INPUTS[*]}"
    exit 0
fi

log_info "Found ${#IMAGES[@]} images, scanning for optimization candidates..."
echo ""

# Process images
for image in "${IMAGES[@]}"; do
    # Get relative path: try stripping each input dir prefix, fall back to basename
    rel_path=""
    for _dir in "${INPUT_DIRS[@]}"; do
        if [[ "$image" == "$_dir/"* ]]; then
            rel_path="${image#$_dir/}"
            break
        fi
    done
    if [ -z "$rel_path" ]; then
        rel_path="$(basename "$image")"
    fi
    output_path="$OUTPUT_DIR/$rel_path"

    # Check if already processed
    if [ -f "$output_path" ] && [ "$DRY_RUN" = false ]; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Check if needs optimization
    if needs_optimization "$image"; then
        original_size=$(stat -c%s "$image" 2>/dev/null || stat -f%z "$image" 2>/dev/null)

        if [ "$DRY_RUN" = true ]; then
            dimensions=$(identify -format "%wx%h" "$image" 2>/dev/null | head -1)
            echo -e "  ${YELLOW}[WOULD PROCESS]${NC} $rel_path ($(format_size $original_size), ${dimensions})"
            PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
        else
            echo -ne "  Processing: $rel_path ... "

            if process_image "$image" "$output_path"; then
                new_size=$(stat -c%s "$output_path" 2>/dev/null || stat -f%z "$output_path" 2>/dev/null)
                savings=$((original_size - new_size))
                if [ "$original_size" -gt 0 ]; then
                    savings_pct=$((savings * 100 / original_size))
                else
                    savings_pct=0
                fi

                TOTAL_ORIGINAL_SIZE=$((TOTAL_ORIGINAL_SIZE + original_size))
                TOTAL_OPTIMIZED_SIZE=$((TOTAL_OPTIMIZED_SIZE + new_size))
                PROCESSED_COUNT=$((PROCESSED_COUNT + 1))

                echo -e "${GREEN}OK${NC} ($(format_size $original_size) → $(format_size $new_size), -${savings_pct}%)"
            else
                FAILED_COUNT=$((FAILED_COUNT + 1))
                echo -e "${RED}FAILED${NC}"
            fi
        fi
    else
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
done

# Summary
echo ""
echo "=============================================="
echo "  Summary"
echo "=============================================="
echo ""

if [ "$DRY_RUN" = true ]; then
    log_info "Dry run complete"
    log_info "Images to process: $PROCESSED_COUNT"
    log_info "Images to skip: $SKIPPED_COUNT"
else
    log_success "Optimization complete!"
    log_info "Images processed: $PROCESSED_COUNT"
    log_info "Images skipped: $SKIPPED_COUNT"
    if [ "$FAILED_COUNT" -gt 0 ]; then
        log_warn "Images failed: $FAILED_COUNT"
    fi

    if [ "$PROCESSED_COUNT" -gt 0 ]; then
        total_savings=$((TOTAL_ORIGINAL_SIZE - TOTAL_OPTIMIZED_SIZE))
        if [ "$TOTAL_ORIGINAL_SIZE" -gt 0 ]; then
            savings_pct=$((total_savings * 100 / TOTAL_ORIGINAL_SIZE))
            echo ""
            log_info "Total original size:  $(format_size $TOTAL_ORIGINAL_SIZE)"
            log_info "Total optimized size: $(format_size $TOTAL_OPTIMIZED_SIZE)"
            log_success "Total savings: $(format_size $total_savings) (-${savings_pct}%)"
        fi

        # Write report
        REPORT_FILE="$OUTPUT_DIR/optimization-report.txt"
        {
            echo "Image Optimization Report"
            echo "========================="
            echo "Date: $(date)"
            echo "Input: ${INPUTS[*]}"
            echo "Output: $OUTPUT_DIR"
            echo ""
            echo "Images processed: $PROCESSED_COUNT"
            echo "Images skipped: $SKIPPED_COUNT"
            echo "Images failed: $FAILED_COUNT"
            echo "Original size: $(format_size $TOTAL_ORIGINAL_SIZE)"
            echo "Optimized size: $(format_size $TOTAL_OPTIMIZED_SIZE)"
            echo "Savings: $(format_size $total_savings) (-${savings_pct}%)"
        } > "$REPORT_FILE"

        echo ""
        log_info "Report saved to: $REPORT_FILE"
    fi
fi

echo ""
