#!/bin/zsh
# Speak test sentences with `say`, transcribe each with Apple's automatic
# punctuation on and off (ProbeSpeech), and print the results side by side.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [[ -d /Applications/Xcode.app && -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build --product ProbeSpeech >/dev/null
dir="$(mktemp -d)"
typeset -A samples
samples=(
  spoken  "hello comma how are you question mark I am fine period"
  bang    "wow exclamation point that is great period"
  pause1  "one annoying issue though [[slnc 1500]] is that sometimes there is punctuation"
  pause2  "that we can fix or is it just [[slnc 1500]] something we cannot change"
  plain   "this sentence has no spoken punctuation at all"
  q1      "how are you doing today"
  q2      "where did you put the keys [[slnc 900]] I could not find them anywhere"
  multi   "I like apples [[slnc 900]] I also like oranges [[slnc 900]] what about you"
)
for name text in "${(@kv)samples}"; do
  say -o "$dir/$name.wav" --file-format=WAVE --data-format=LEI16@16000 "$text"
  echo "=== $name: $text"
  echo "--- auto ON"
  .build/debug/ProbeSpeech "$dir/$name.wav" | grep -E 'joined|options'
  echo "--- auto OFF"
  .build/debug/ProbeSpeech "$dir/$name.wav" --no-auto-punctuation | grep -E 'joined'
done
rm -rf "$dir"
