#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build --product CheckLogic
swift build --product CheckPhraseRules
swift build --product CheckFieldScenarios

bin=".build/debug"
out="$(mktemp -d)"
fail=0

"$bin/CheckLogic" >"$out/logic.out" 2>"$out/logic.err" &
p1=$!
"$bin/CheckPhraseRules" >"$out/phrase.out" 2>"$out/phrase.err" &
p2=$!
"$bin/CheckFieldScenarios" >"$out/field.out" 2>"$out/field.err" &
p3=$!

wait $p1 || fail=1
wait $p2 || fail=1
wait $p3 || fail=1

for name in logic phrase field; do
  echo "----- $name -----"
  cat "$out/$name.out"
  if [[ -s "$out/$name.err" ]]; then
    cat "$out/$name.err" >&2
  fi
done

rm -rf "$out"
exit $fail
