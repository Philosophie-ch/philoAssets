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

if [ $# -lt 1 ]; then
  echo "Usage: $0 [-r] <target_folder>"
  echo "For every non-webp image where a .webp version exists, renames it to TO-DELETE-{filename}"
  echo "  -r  Recurse into subdirectories"
  exit 1
fi

TARGET="$1"
DEPTH_ARG="-maxdepth 1"
if [ "$RECURSIVE" = true ]; then
  DEPTH_ARG=""
fi

find "$TARGET" $DEPTH_ARG -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.tiff' -o -iname '*.tif' \) | while read -r filepath; do
  dir="$(dirname "$filepath")"
  filename="$(basename "$filepath")"
  name_no_ext="${filename%.*}"
  webp_path="${dir}/${name_no_ext}.webp"

  if [ -f "$webp_path" ]; then
    mv "$filepath" "${dir}/TO-DELETE-${filename}"
    echo "Renamed: ${filename} -> TO-DELETE-${filename}"
  fi
done
