#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(tr -d '[:space:]' < VERSION)"
app_name="Custom Dictation"
binary_name="CustomDictation"
dist="$root/dist"
app="$dist/$app_name.app"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

swift build -c release --product "$binary_name"
bin="$(swift build -c release --show-bin-path)/$binary_name"

rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

sed "s/VERSION_PLACEHOLDER/$version/g" "$root/Resources/Info.plist" > "$app/Contents/Info.plist"
cp "$bin" "$app/Contents/MacOS/$binary_name"
chmod +x "$app/Contents/MacOS/$binary_name"

if command -v codesign >/dev/null; then
  codesign --force --deep --sign - "$app" >/dev/null
fi

ditto -c -k --keepParent "$app" "$dist/CustomDictation-$version.zip"
echo "$app"
echo "$dist/CustomDictation-$version.zip"
