#!/usr/bin/env bash
set -euo pipefail

RECURSIVE=false
while getopts "r" opt; do
  case $opt in
    r) RECURSIVE=true ;;
    *) ;;
  esac
done
shift $((OPTIND - 1))

if [ $# -lt 2 ]; then
  echo "Usage: $0 [-r] <source_folder> <target_folder>"
  echo "Copies non-webp images that have no .webp counterpart to the target folder."
  echo "  -r  Recurse into subdirectories (preserves directory structure)"
  exit 1
fi

SOURCE="$1"
TARGET="$2"
DEPTH_ARG="-maxdepth 1"
if [ "$RECURSIVE" = true ]; then
  DEPTH_ARG=""
fi

mkdir -p "$TARGET"

find "$SOURCE" $DEPTH_ARG -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.tiff' -o -iname '*.tif' \) | while read -r filepath; do
  dir="$(dirname "$filepath")"
  filename="$(basename "$filepath")"
  name_no_ext="${filename%.*}"
  webp_path="${dir}/${name_no_ext}.webp"

  if [ ! -f "$webp_path" ]; then
    rel_dir="${dir#"$SOURCE"}"
    dest_dir="${TARGET}${rel_dir}"
    mkdir -p "$dest_dir"
    cp "$filepath" "${dest_dir}/${filename}"
    echo "Copied: ${rel_dir:+${rel_dir}/}${filename}"
  fi
done
