# Custom Dictation

## Test locally without a release

Build a second app that does not replace `/Applications/Custom Dictation.app` and does not use `~/.custom-dictation-config`.

```
./scripts/run-local.sh
```

That installs **Custom Dictation Local** to `/Applications` (not the released app). Config is `~/.custom-dictation-config-local`. Login items and update checks are off.

Local app only: Listen → **Use Input Method (IMK)**. Off (default) is Accessibility then keyboard events. On macOS 26, Keyboard → Input Sources does not list classic IMK apps (only Apple `textinputmethod-services` extensions), so IMK usually cannot be selected. Clicks and “press the C key” still use Accessibility.

Enable **Custom Dictation Local** in System Settings → Privacy & Security → Accessibility (and Microphone). It is a different app from Custom Dictation. If it is not in the list, click + and choose it from Applications.

Quit the released Custom Dictation app, or stop listening on it, so only the local app uses the microphone. First local launch may show onboarding.

Do not use `./scripts/install-local.sh` for this. That overwrites Applications and is not a side-by-side test.

## Phrase / post-process rules

Speech is not involved. These feed a fake field + fake transcript into the default post-process.

```
swift run CheckPhraseRules
```

```
swift run CheckLogic
```

```
swift run CheckFieldScenarios
```

Or all three in parallel:

```
./scripts/check.sh
```

CheckPhraseRules is the desired typing rules (spaces, capitals, leftover punctuation, acronyms). It can fail while you change the default post-process. CheckLogic is the existing parser/command checks. CheckFieldScenarios is Notes/Slack/Cursor/browser field behavior (live mark, selection, stub, leftover period). The app Playground sidebar speaks into simulated boxes and logs raw speech, writes, timers, and path (AX/HID/IMK).

## Tests for every bug

When we fix a bug, add a regression test in the same change. Do not ship the fix without it.

- Phrase/spacing/punctuation → `CheckPhraseRules`
- Parser, commands, live-mark rules, “must not shift-select / stick modifiers” → `CheckLogic`
- Text-box / caret / selection / Slack / Cursor / Notes insertion → `CheckFieldScenarios`

Name the case after the failure (e.g. next sentence must go at the caret, not the old live mark).
