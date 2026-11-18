#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
asset="Mousecape/Mousecape/Images.xcassets/AppIcon.appiconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Artwork/AppIcon.png --out "$asset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Artwork/AppIcon.png --out "$asset/icon_${size}x${size}@2x.png" >/dev/null
done
