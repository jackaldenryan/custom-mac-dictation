#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(tr -d '[:space:]' < VERSION)"
app_name="Custom Dictation Local"
binary_name="CustomDictation"
dist="$root/dist/local"
app="$dist/$app_name.app"
config="${CUSTOM_DICTATION_CONFIG:-$HOME/.custom-dictation-config-local}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"

swift build -c release --product "$binary_name"
bin="$(swift build -c release --show-bin-path)/$binary_name"

rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

sed "s/VERSION_PLACEHOLDER/$version-local/g" "$root/Resources/Info.plist" > "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $app_name" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $app_name" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.jackaldenryan.custom-mac-dictation.local" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:CUSTOM_DICTATION_DEV string 1" "$app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSEnvironment:CUSTOM_DICTATION_DEV 1" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:CUSTOM_DICTATION_CONFIG string $config" "$app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSEnvironment:CUSTOM_DICTATION_CONFIG $config" "$app/Contents/Info.plist"

cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$bin" "$app/Contents/MacOS/$binary_name"
chmod +x "$app/Contents/MacOS/$binary_name"

codesign --force --deep --sign - --identifier com.jackaldenryan.custom-mac-dictation.local "$app"

xattr -dr com.apple.quarantine "$app" || true

dst="/Applications/Custom Dictation Local.app"
if pgrep -f "Custom Dictation Local.app/Contents/MacOS/CustomDictation" >/dev/null 2>&1; then
  pkill -f "Custom Dictation Local.app/Contents/MacOS/CustomDictation" || true
  sleep 0.4
fi
rm -rf "$dst"
ditto "$app" "$dst"
xattr -dr com.apple.quarantine "$dst" || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dst" >/dev/null

open -n "$dst"
echo "Local app: $dst"
echo "Config: $config"
echo "In System Settings → Privacy & Security → Accessibility, enable Custom Dictation Local (use + and pick it from Applications if it is missing)."
echo "Quit the released Custom Dictation app, or stop listening on it, so only the local app uses the mic."
