#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$project_dir/dist/Chorreador.app"
contents_dir="$app_dir/Contents"
iconset_dir="$project_dir/.build/AppIcon.iconset"

cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swift-cache"
swift build --disable-sandbox -c "$configuration"

rm -rf "$app_dir" "$project_dir/dist/Agentpresso.app" "$project_dir/dist/Wakeful.app" "$iconset_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$iconset_dir"

cp ".build/$configuration/Chorreador" "$contents_dir/MacOS/Chorreador"
cp "Resources/Info.plist" "$contents_dir/Info.plist"

for size in 16 32 128 256 512; do
    magick -background none "Resources/AppIcon.svg" -resize "${size}x${size}" -colorspace sRGB -depth 8 -define png:color-type=6 "$iconset_dir/icon_${size}x${size}.png"
    double_size=$((size * 2))
    magick -background none "Resources/AppIcon.svg" -resize "${double_size}x${double_size}" -colorspace sRGB -depth 8 -define png:color-type=6 "$iconset_dir/icon_${size}x${size}@2x.png"
done

xcrun swift "$project_dir/scripts/build-icns.swift" "$iconset_dir" "$contents_dir/Resources/AppIcon.icns"
if [[ ! -f "$contents_dir/Resources/AppIcon.icns" ]]; then
    echo "App icon packaging failed" >&2
    exit 1
fi
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
