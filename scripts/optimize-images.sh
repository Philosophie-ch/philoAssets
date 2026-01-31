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
#   sudo apt-get install imagemagick jpegoptim optipng gifsicle webp libimage-exiftool-perl
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
WEBP_QUALITY=95
AGGRESSIVE_QUALITY=75

# Counters for summary
TOTAL_ORIGINAL_SIZE=0
TOTAL_OPTIMIZED_SIZE=0
PROCESSED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

parse_size() {
    local val="$1"
    case "${val^^}" in
        *MB) echo $(( ${val%%[Mm]*} * 1048576 )) ;;
        *KB) echo $(( ${val%%[Kk]*} * 1024 )) ;;
        *)   echo "$val" ;;
    esac
}

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
    echo "  -f, --force             Re-optimize even if already marked as optimized"
    echo "  -s, --size-threshold <size>  Min file size to optimize (default: 1MB, e.g. 500KB, 2MB)"
    echo "  -j, --jobs <N>          Max parallel jobs (default: 3)"
    echo "  -a, --aggressive        Aggressive mode: convert large optimized files to WebP"
    echo "  --aggressive-quality <N>  WebP quality for aggressive re-encode (default: 75)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 ./uploads"
    echo "  $0 ./uploads --dry-run"
    echo "  $0 ./uploads -r -w                    # recursive + webp generation"
    echo "  $0 image1.png image2.jpg -o ./out      # optimize specific files"
    echo "  $0 ./uploads ./photos -r -o ./out      # multiple directories"
    echo "  $0 ./optimized -a                        # aggressive pass on optimized output"
    echo "  $0 ./optimized -a --aggressive-quality 60  # even more aggressive"
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
        local mb_int=$((bytes / 1048576))
        local mb_frac=$(( (bytes % 1048576) * 100 / 1048576 ))
        printf '%d.%02dMB' "$mb_int" "$mb_frac"
    elif [ "$bytes" -ge 1024 ]; then
        local kb_int=$((bytes / 1024))
        local kb_frac=$(( (bytes % 1024) * 100 / 1024 ))
        printf '%d.%02dKB' "$kb_int" "$kb_frac"
    else
        echo "${bytes}B"
    fi
}

check_dependencies() {
    local missing=()

    command -v convert >/dev/null 2>&1 || missing+=("imagemagick")
    command -v jpegoptim >/dev/null 2>&1 || missing+=("jpegoptim")
    command -v optipng >/dev/null 2>&1 || missing+=("optipng")
    command -v gifsicle >/dev/null 2>&1 || missing+=("gifsicle")
    command -v cwebp >/dev/null 2>&1 || missing+=("webp")
    command -v exiftool >/dev/null 2>&1 || missing+=("libimage-exiftool-perl")
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  sudo apt-get install imagemagick jpegoptim optipng gifsicle webp libimage-exiftool-perl"
        exit 1
    fi
}

needs_optimization() {
    local file="$1"
    local dimensions="$2"
    local size
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)

    # Check file size
    if [ "$size" -gt "$SIZE_THRESHOLD_BYTES" ]; then
        return 0
    fi

    # Check dimensions (passed in from pre-built map)
    local width="${dimensions%%x*}"
    local height="${dimensions##*x}"

    if [ -n "$width" ] && [ -n "$height" ]; then
        if [ "$width" -gt "$MAX_DIMENSION" ] || [ "$height" -gt "$MAX_DIMENSION" ]; then
            return 0
        fi
    fi

    return 1
}

is_already_optimized() {
    local file="$1"
    local comment
    comment=$(exiftool -s3 -Comment "$file" 2>/dev/null)
    [ "$comment" = "philoassets-optimized" ]
}

stamp_optimized() {
    local file="$1"
    exiftool -overwrite_original -Comment="philoassets-optimized" "$file" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Optimization Functions
# -----------------------------------------------------------------------------

optimize_jpeg() {
    local input="$1"
    local output="$2"

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
        cwebp -q "$WEBP_QUALITY" -quiet "$output" -o "${output%.*}.webp"
    fi

    stamp_optimized "$output"
}

optimize_png() {
    local input="$1"
    local output="$2"

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
        cwebp -q "$WEBP_QUALITY" -quiet "$output" -o "${output%.*}.webp"
    fi

    stamp_optimized "$output"
}

optimize_gif() {
    local input="$1"
    local output="$2"
    local output_dir=$(dirname "$output")

    # Optimize GIF
    gifsicle --optimize=3 "$input" -o "$output"

    # Generate static WebP from first frame
    if [ "$GENERATE_WEBP" = true ]; then
        local tmp_frame
        tmp_frame=$(mktemp "${output_dir}/.gifframe-XXXXXX.png")
        convert "${input}[0]" -resize "${MAX_DIMENSION}x${MAX_DIMENSION}>" "$tmp_frame"
        cwebp -q "$WEBP_QUALITY" -quiet "$tmp_frame" -o "${output%.*}.webp"
        rm -f "$tmp_frame"
    fi

    stamp_optimized "$output"
}

optimize_webp() {
    local input="$1"
    local output="$2"

    # Resize and recompress
    cwebp -q "$WEBP_QUALITY" -quiet -resize "$MAX_DIMENSION" 0 "$input" -o "$output" 2>/dev/null || \
        cwebp -q "$WEBP_QUALITY" -quiet "$input" -o "$output"

    stamp_optimized "$output"
}

aggressive_compress() {
    local input="$1"
    local output="$2"
    local ext_lower
    ext_lower=$(echo "${input##*.}" | tr '[:upper:]' '[:lower:]')

    local webp_output="${output%.*}.webp"
    local quality=95

    # Initial conversion to WebP at quality 95
    if [ "$ext_lower" != "webp" ]; then
        cwebp -q "$quality" -quiet "$input" -o "$webp_output"
    else
        local tmp="${webp_output}.tmp"
        cwebp -q "$quality" -quiet "$input" -o "$tmp"
        mv "$tmp" "$webp_output"
    fi

    # Iteratively reduce quality (-5 each step) until below threshold or floor
    local min_quality=$AGGRESSIVE_QUALITY
    while [ "$quality" -gt "$min_quality" ]; do
        local size
        size=$(stat -c%s "$webp_output" 2>/dev/null || stat -f%z "$webp_output" 2>/dev/null)
        if [ "$size" -le "$SIZE_THRESHOLD_BYTES" ]; then
            break
        fi
        quality=$((quality - 5))
        local tmp="${webp_output}.tmp"
        cwebp -q "$quality" -quiet "$input" -o "$tmp"
        mv "$tmp" "$webp_output"
    done

    exiftool -overwrite_original -Comment="philoassets-aggressive" "$webp_output" >/dev/null 2>&1
    echo "$quality"
}

process_single_aggressive() {
    local image="$1"
    local output_path="$2"
    local result_file="$3"
    local rel_path="$4"
    local original_size
    original_size=$(stat -c%s "$image" 2>/dev/null || stat -f%z "$image" 2>/dev/null)

    local final_quality
    final_quality=$(aggressive_compress "$image" "$output_path")
    if [ $? -eq 0 ] || [ -n "$final_quality" ]; then
        local webp_output="${output_path%.*}.webp"
        local new_size
        new_size=$(stat -c%s "$webp_output" 2>/dev/null || stat -f%z "$webp_output" 2>/dev/null)
        local savings=$((original_size - new_size))
        local savings_pct=0
        if [ "$original_size" -gt 0 ]; then
            savings_pct=$((savings * 100 / original_size))
        fi
        local level="webp${final_quality}"
        echo "ok $original_size $new_size $level ${rel_path%.*}.webp" > "$result_file"
        echo -e "  ${GREEN}OK${NC} $rel_path → ${rel_path%.*}.webp [$level] ($(format_size $original_size) → $(format_size $new_size), -${savings_pct}%)"
    else
        echo "fail $original_size 0 none $rel_path" > "$result_file"
        echo -e "  ${RED}FAILED${NC} $rel_path"
    fi
}

process_single_image() {
    local image="$1"
    local output_path="$2"
    local result_file="$3"
    local rel_path="$4"
    local original_size
    original_size=$(stat -c%s "$image" 2>/dev/null || stat -f%z "$image" 2>/dev/null)

    # Determine compression level label from file extension
    local ext_lower
    ext_lower=$(echo "${image##*.}" | tr '[:upper:]' '[:lower:]')
    local level
    case "$ext_lower" in
        jpg|jpeg) level="jpeg${JPEG_QUALITY}" ;;
        png)      level="png-lossless" ;;
        gif)      level="gif-o3" ;;
        webp)     level="webp${WEBP_QUALITY}" ;;
        *)        level="unknown" ;;
    esac

    if process_image "$image" "$output_path"; then
        local new_size
        new_size=$(stat -c%s "$output_path" 2>/dev/null || stat -f%z "$output_path" 2>/dev/null)
        local savings=$((original_size - new_size))
        local savings_pct=0
        if [ "$original_size" -gt 0 ]; then
            savings_pct=$((savings * 100 / original_size))
        fi
        echo "ok $original_size $new_size $level $rel_path" > "$result_file"
        echo -e "  ${GREEN}OK${NC} $rel_path [$level] ($(format_size $original_size) → $(format_size $new_size), -${savings_pct}%)"
    else
        echo "fail $original_size 0 none $rel_path" > "$result_file"
        echo -e "  ${RED}FAILED${NC} $rel_path"
    fi
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
FORCE=false
AGGRESSIVE=false
OUTPUT_DIR_SET=false
JOBS=3

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|-d)   DRY_RUN=true ;;
        --recursive|-r) RECURSIVE=true ;;
        --webp|-w)      GENERATE_WEBP=true ;;
        --force|-f)     FORCE=true ;;
        --aggressive|-a) AGGRESSIVE=true ;;
        --aggressive-quality)
            shift
            AGGRESSIVE_QUALITY="${1:?'--aggressive-quality requires a number'}"
            ;;
        --size-threshold|-s)
            shift
            SIZE_THRESHOLD_BYTES=$(parse_size "${1:?'--size-threshold requires a size value'}")
            ;;
        --jobs|-j)
            shift
            JOBS="${1:?'--jobs requires a number'}"
            ;;
        --output|-o)
            shift
            OUTPUT_DIR="${1:?'--output requires a directory argument'}"
            OUTPUT_DIR_SET=true
            ;;
        --help|-h)      print_usage; exit 0 ;;
        -*)             log_error "Unknown option: $1"; print_usage; exit 1 ;;
        *)              INPUTS+=("$1") ;;
    esac
    shift
done

# Clamp JOBS to 1/4 of available CPU cores to prevent thermal overload
AVAILABLE_CORES=$(nproc 2>/dev/null || echo 2)
MAX_JOBS=$(( AVAILABLE_CORES / 4 ))
if [ "$MAX_JOBS" -lt 1 ]; then
    MAX_JOBS=1
fi
if [ "$JOBS" -gt "$MAX_JOBS" ]; then
    JOBS=$MAX_JOBS
fi

# Default output dir for aggressive mode
if [ "$AGGRESSIVE" = true ] && [ "$OUTPUT_DIR_SET" = false ]; then
    OUTPUT_DIR="./aggressive"
fi

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
log_info "Force: $FORCE"
log_info "Aggressive mode: $AGGRESSIVE"
log_info "Parallel jobs: $JOBS"
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

# Temp directory for parallel job results
RESULTS_DIR=$(mktemp -d)
trap 'rm -rf "$RESULTS_DIR"' EXIT

# Pre-read optimization markers in bulk (single exiftool invocation)
declare -A COMMENT_MAP
while IFS='|' read -r file comment; do
    [ -n "$file" ] && COMMENT_MAP["$file"]="$comment"
done < <(exiftool -p '$Directory/$FileName|$Comment' "${IMAGES[@]}" 2>/dev/null)

if [ "$AGGRESSIVE" = true ]; then
    # =========================================================================
    # AGGRESSIVE MODE: convert large optimized files to WebP
    # =========================================================================

    # Phase 1: Filter to files that are stamped optimized + above threshold
    TO_PROCESS=()
    for image in "${IMAGES[@]}"; do
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

        comment="${COMMENT_MAP[$image]:-}"

        # Must be stamped as optimized (from first pass)
        if [ "$comment" != "philoassets-optimized" ] && [ "$comment" != "philoassets-aggressive" ]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        # Skip if already aggressively compressed (unless --force)
        if [ "$FORCE" = false ] && [ "$comment" = "philoassets-aggressive" ]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        # Must be above size threshold
        file_size=$(stat -c%s "$image" 2>/dev/null || stat -f%z "$image" 2>/dev/null)
        if [ "$file_size" -le "$SIZE_THRESHOLD_BYTES" ]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${YELLOW}[WOULD PROCESS]${NC} $rel_path ($(format_size $file_size))"
            PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
        else
            TO_PROCESS+=("$image" "$output_path" "$rel_path")
        fi
    done

    # Pre-create output directories
    declare -A SEEN_DIRS
    for ((i=1; i<${#TO_PROCESS[@]}; i+=3)); do
        dir=$(dirname "${TO_PROCESS[$i]}")
        if [ -z "${SEEN_DIRS[$dir]+_}" ]; then
            SEEN_DIRS["$dir"]=1
            mkdir -p "$dir"
        fi
    done

    # Phase 2: Parallel aggressive processing
    if [ "$DRY_RUN" = false ] && [ ${#TO_PROCESS[@]} -gt 0 ]; then
        active_jobs=0
        job_index=0
        for ((i=0; i<${#TO_PROCESS[@]}; i+=3)); do
            image="${TO_PROCESS[$i]}"
            output_path="${TO_PROCESS[$i+1]}"
            rel_path="${TO_PROCESS[$i+2]}"

            (
                renice -n 19 $BASHPID >/dev/null 2>&1 || true
                process_single_aggressive "$image" "$output_path" "$RESULTS_DIR/$job_index.result" "$rel_path"
            ) &
            active_jobs=$((active_jobs + 1))
            job_index=$((job_index + 1))

            if [ "$active_jobs" -ge "$JOBS" ]; then
                wait -n || true
                active_jobs=$((active_jobs - 1))
            fi
        done
        wait || true
    fi

else
    # =========================================================================
    # NORMAL MODE: standard optimization
    # =========================================================================

    # Pre-read dimensions in bulk (single identify invocation)
    declare -A DIMENSIONS_MAP
    while IFS='|' read -r file dims; do
        DIMENSIONS_MAP["$file"]="$dims"
    done < <(identify -format '%d/%f|%wx%h\n' "${IMAGES[@]}" 2>/dev/null | sort -u -t'|' -k1,1)

    # Phase 1: Filter images (sequential)
    TO_PROCESS=()
    for image in "${IMAGES[@]}"; do
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

        # Check if already processed (output exists)
        if [ -f "$output_path" ] && [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        # Check if already optimized or aggressively compressed (skip both)
        if [ "$FORCE" = false ]; then
            comment="${COMMENT_MAP[$image]:-}"
            if [ "$comment" = "philoassets-optimized" ] || [ "$comment" = "philoassets-aggressive" ]; then
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                continue
            fi
        fi

        # Check if needs optimization (dimensions from bulk pre-read)
        dimensions="${DIMENSIONS_MAP[$image]}"
        if needs_optimization "$image" "$dimensions"; then
            if [ "$DRY_RUN" = true ]; then
                original_size=$(stat -c%s "$image" 2>/dev/null || stat -f%z "$image" 2>/dev/null)
                echo -e "  ${YELLOW}[WOULD PROCESS]${NC} $rel_path ($(format_size $original_size), ${dimensions})"
                PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
            else
                TO_PROCESS+=("$image" "$output_path" "$rel_path")
            fi
        else
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        fi
    done

    # Pre-create output directories
    declare -A SEEN_DIRS
    for ((i=1; i<${#TO_PROCESS[@]}; i+=3)); do
        dir=$(dirname "${TO_PROCESS[$i]}")
        if [ -z "${SEEN_DIRS[$dir]+_}" ]; then
            SEEN_DIRS["$dir"]=1
            mkdir -p "$dir"
        fi
    done

    # Phase 2: Process images (parallel)
    if [ "$DRY_RUN" = false ] && [ ${#TO_PROCESS[@]} -gt 0 ]; then
        active_jobs=0
        job_index=0
        for ((i=0; i<${#TO_PROCESS[@]}; i+=3)); do
            image="${TO_PROCESS[$i]}"
            output_path="${TO_PROCESS[$i+1]}"
            rel_path="${TO_PROCESS[$i+2]}"

            (
                renice -n 19 $BASHPID >/dev/null 2>&1 || true
                process_single_image "$image" "$output_path" "$RESULTS_DIR/$job_index.result" "$rel_path"
            ) &
            active_jobs=$((active_jobs + 1))
            job_index=$((job_index + 1))

            if [ "$active_jobs" -ge "$JOBS" ]; then
                wait -n || true
                active_jobs=$((active_jobs - 1))
            fi
        done
        wait || true
    fi

fi

# Phase 3: Aggregate results (shared by both modes)
CSV_ROWS=()
for result_file in "$RESULTS_DIR"/*.result; do
    [ -f "$result_file" ] || continue
    read -r status orig_size new_size compression_level file_name < "$result_file"
    if [ "$status" = "ok" ]; then
        PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
        TOTAL_ORIGINAL_SIZE=$((TOTAL_ORIGINAL_SIZE + orig_size))
        TOTAL_OPTIMIZED_SIZE=$((TOTAL_OPTIMIZED_SIZE + new_size))
        local_pct=0
        if [ "$orig_size" -gt 0 ]; then
            local_pct=$(( (orig_size - new_size) * 100 / orig_size ))
        fi
        CSV_ROWS+=("$file_name,$orig_size,$new_size,$local_pct,$compression_level")
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
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
    if [ "$AGGRESSIVE" = true ]; then
        log_success "Aggressive compression complete!"
    else
        log_success "Optimization complete!"
    fi
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
            echo "Mode: $([ "$AGGRESSIVE" = true ] && echo 'aggressive' || echo 'normal')"
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

        # Write CSV report
        CSV_FILE="$OUTPUT_DIR/optimization-report.csv"
        {
            echo "file_name,original_size,optimized_size,percent_saved,compression_level"
            for row in "${CSV_ROWS[@]}"; do
                echo "$row"
            done
        } > "$CSV_FILE"
        log_info "CSV report saved to: $CSV_FILE"
    fi
fi

echo ""
