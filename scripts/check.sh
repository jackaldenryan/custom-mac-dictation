#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Prefer full Xcode when present: CommandLineTools alone cannot build
# the SwiftUI parts of CustomDictationKit (macro plugin missing).
if [[ -d /Applications/Xcode.app && -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build --product CheckLogic
swift build --product CheckPhraseRules
swift build --product CheckFieldScenarios
swift build --product CheckConfigMatrix

bin=".build/debug"
out="$(mktemp -d)"
fail=0

# Hermetic config: CheckLogic drives the real LivePhrase, which reads
# settings; never the user's real config.
mkdir -p "$out/config"
CUSTOM_DICTATION_CONFIG="$out/config" "$bin/CheckLogic" >"$out/logic.out" 2>"$out/logic.err" &
p1=$!
"$bin/CheckPhraseRules" >"$out/phrase.out" 2>"$out/phrase.err" &
p2=$!
"$bin/CheckFieldScenarios" >"$out/field.out" 2>"$out/field.err" &
p3=$!
"$bin/CheckConfigMatrix" >"$out/matrix.out" 2>"$out/matrix.err" &
p4=$!

wait $p1 || fail=1
wait $p2 || fail=1
wait $p3 || fail=1
wait $p4 || fail=1

for name in logic phrase field matrix; do
  echo "----- $name -----"
  cat "$out/$name.out"
  if [[ -s "$out/$name.err" ]]; then
    cat "$out/$name.err" >&2
  fi
done

rm -rf "$out"
exit $fail
