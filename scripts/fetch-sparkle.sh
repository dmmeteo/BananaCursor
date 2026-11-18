#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cache="$PWD/build/dependencies"
version=2.10.1
sha=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
archive="$cache/Sparkle-$version.tar.xz"
sdk="$cache/Sparkle-$version"
mkdir -p "$cache"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --proto '=https' --tlsv1.2 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
        --output "$archive.download"
    mv "$archive.download" "$archive"
fi
actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
[[ "$actual" == "$sha" ]] || { echo 'Sparkle archive SHA-256 mismatch' >&2; exit 1; }
if [[ ! -d "$sdk" ]]; then
    mkdir "$sdk"
    tar -xf "$archive" -C "$sdk"
fi
codesign --verify --deep --strict "$sdk/Sparkle.framework"
[[ -L "$sdk/Sparkle.framework/Sparkle" && -f "$sdk/LICENSE" ]]
printf '%s\n' "$sdk"
