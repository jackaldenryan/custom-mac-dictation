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
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Resources/default-commands"
cp "$root/Sources/CustomDictationKit/Defaults/commands/"*.json "$app/Contents/Resources/default-commands/" 2>/dev/null || true
cp "$bin" "$app/Contents/MacOS/$binary_name"
chmod +x "$app/Contents/MacOS/$binary_name"

identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$("$root/scripts/ensure-signing-identity.sh")"
fi
if [[ -n "$identity" ]]; then
  codesign --force --deep --sign "$identity" --identifier com.jackaldenryan.custom-mac-dictation "$app"
else
  codesign --force --deep --sign - --identifier com.jackaldenryan.custom-mac-dictation "$app"
fi

ditto -c -k --keepParent "$app" "$dist/CustomDictation-$version.zip"

dmg_root="$dist/dmg"
rm -rf "$dmg_root"
mkdir -p "$dmg_root"
ditto "$app" "$dmg_root/$app_name.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create \
  -volname "$app_name" \
  -srcfolder "$dmg_root" \
  -ov \
  -format UDZO \
  "$dist/CustomDictation-$version.dmg" >/dev/null
rm -rf "$dmg_root"

echo "$app"
echo "$dist/CustomDictation-$version.zip"
echo "$dist/CustomDictation-$version.dmg"
