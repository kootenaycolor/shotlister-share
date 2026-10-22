#!/bin/bash
# A stack of pages, in the two colours of the look book. Run once; the .icns
# is committed, so a rebuild does not need ImageMagick.
set -e
cd "$(dirname "$0")"
W=1024
OUT=build-icon
rm -rf "$OUT" AppIcon.iconset
mkdir -p "$OUT"

# Rounded slab, oxblood into near-black.
magick -size ${W}x${W} gradient:'#4A0B16-#140A0C' \
  \( -size ${W}x${W} xc:none -fill white \
     -draw "roundrectangle 0,0 $((W-1)),$((W-1)) 230,230" \) \
  -alpha set -compose CopyOpacity -composite "$OUT/base.png"

# Three pages, back to front.
magick "$OUT/base.png" \
  -fill '#8C5A4E' -draw "roundrectangle 300,232 812,700 26,26" \
  -fill '#CF8692' -draw "roundrectangle 250,282 762,750 26,26" \
  -fill '#F1BB65' -draw "roundrectangle 200,332 712,800 26,26" \
  -fill '#3A1116' -draw "roundrectangle 236,376 676,590 10,10" \
  "$OUT/icon.png"

mkdir -p AppIcon.iconset
for s in 16 32 64 128 256 512; do
  magick "$OUT/icon.png" -resize ${s}x${s} "AppIcon.iconset/icon_${s}x${s}.png"
  magick "$OUT/icon.png" -resize $((s*2))x$((s*2)) "AppIcon.iconset/icon_${s}x${s}@2x.png"
done
mv AppIcon.iconset/icon_512x512@2x.png AppIcon.iconset/icon_1024x1024.png 2>/dev/null || true
magick "$OUT/icon.png" -resize 1024x1024 AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset "$OUT"
echo "wrote $(pwd)/AppIcon.icns"
