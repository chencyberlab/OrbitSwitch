#!/usr/bin/env bash
# Render the app-icon SVG into Resources/AppIcon.icns, where build.sh expects it.
# Every size is rendered straight from the vector rather than downsampled from one
# large bitmap, so small sizes stay crisp.
set -euo pipefail
cd "$(dirname "$0")/../.."

SVG="${1:-Resources/icon/OrbitSwitch-Flow.svg}"
OUT="${OUT:-Resources/AppIcon.icns}"

# macOS draws app icons on a grid: the rounded-rect body fills 824 of a 1024
# canvas (80.46875%), leaving a 100px margin for shadow and optical balance.
# Our SVG draws its body at ~91.8% of its own viewBox (x 175..4091.667 of 4266.667),
# so rendering it edge-to-edge would sit ~14% larger than every neighbour in the
# Dock. Scale the artwork down and pad it back out to restore the grid.
#
# Set FULL_BLEED=1 to render the SVG edge-to-edge instead.
TARGET_BODY_RATIO="0.8046875"   # 824 / 1024
SVG_BODY_RATIO="${SVG_BODY_RATIO:-0.917969}"  # body width / viewBox width

if [[ "${FULL_BLEED:-0}" == "1" ]]; then
  SCALE="1.0"
else
  SCALE="$(awk -v t="$TARGET_BODY_RATIO" -v s="$SVG_BODY_RATIO" 'BEGIN{printf "%.9f", t/s}')"
fi
INSET="$(awk -v k="$SCALE" 'BEGIN{printf "%.9f", (1-k)/2}')"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "ERROR: rsvg-convert is required. Install it with: brew install librsvg" >&2
  exit 1
fi
if [[ ! -f "$SVG" ]]; then
  echo "ERROR: no such SVG: $SVG" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

# name:pixels — the full set macOS expects, including every @2x variant.
for entry in \
  icon_16x16:16 icon_16x16@2x:32 \
  icon_32x32:32 icon_32x32@2x:64 \
  icon_128x128:128 icon_128x128@2x:256 \
  icon_256x256:256 icon_256x256@2x:512 \
  icon_512x512:512 icon_512x512@2x:1024
do
  name="${entry%:*}"
  size="${entry#*:}"
  body="$(awk -v s="$size" -v k="$SCALE" 'BEGIN{printf "%.4f", s*k}')"
  inset="$(awk -v s="$size" -v i="$INSET" 'BEGIN{printf "%.4f", s*i}')"
  rsvg-convert --width "${body}px" --height "${body}px" --keep-aspect-ratio \
    --page-width "${size}px" --page-height "${size}px" \
    --top "${inset}px" --left "${inset}px" \
    --background-color none --format png \
    --output "$ICONSET/$name.png" "$SVG"
done

iconutil --convert icns "$ICONSET" --output "$OUT"
echo "OK: wrote $PWD/$OUT from $SVG"
