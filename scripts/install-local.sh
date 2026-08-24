#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/package-app.sh"

app_src="$root/dist/Custom Dictation.app"
app_dst="/Applications/Custom Dictation.app"

if pgrep -x CustomDictation >/dev/null 2>&1; then
  killall CustomDictation || true
  sleep 0.4
fi

ditto "$app_src" "$app_dst"
xattr -dr com.apple.quarantine "$app_dst" || true
open "$app_dst"
echo "Installed and launched $app_dst"
