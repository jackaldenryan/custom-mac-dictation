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

rm -rf "$app_dst"
ditto "$app_src" "$app_dst"
xattr -cr "$app_dst" || true
open "$app_dst"
echo "Installed and launched $app_dst"
