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

## AX writes never in web engines

Slack, Cursor, VS Code, OpenCode, Chrome, Safari pages and any Electron/Chromium/WebKit view answer AX text writes with success but apply them late or never, and the attempt moves the caret first. Falling back to keystrokes after that typed into the middle of earlier words (Oct 3: "hey guess what I don't know you tell me" in Slack came out "Hey, guess? I don't know you tell .me don't"). `Output/AXWritePolicy.swift` blocks AX writes there up front; `FieldEditor.write` restores the selection on any failed write and turns AX off for that app for the session; `PhrasePathLock` keeps a phrase on HID once it starts on HID. Regression: `slackLogReplay` in CheckLogic.

## Apple automatic punctuation is off by default

Setting `appleAutoPunctuation` (Listen → Punctuation, `settings.json` in the config folder). Off removes `.punctuation` from the DictationTranscriber options (`Recognition/TranscriberOptions.swift`): no marks guessed from pauses, spoken "period" / "comma" / "question mark" / "exclamation point" still convert. Check real-model behavior with `./scripts/probe-punctuation.sh` (speaks samples with `say`, transcribes each with it on and off via `swift run ProbeSpeech`).

Because every mark is now spoken, the app types every mark it gets. Removed (Oct 3, rollback tag `snapshot-auto-punct-off-before-cleanup`) because they only existed to undo Apple's guesses: dropping repeated boundary punctuation, the lone-punctuation pause setting, and stripping a trailing ". ? ..." when inserting mid-sentence. Kept: lowering Apple's segment-start capital mid-sentence (Apple still capitalizes each segment).

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

```
swift run CheckConfigMatrix
```

Or all four in parallel:

```
./scripts/check.sh
```

CheckPhraseRules is the desired typing rules (spaces, capitals, spoken punctuation, acronyms). It can fail while you change the default post-process. CheckLogic is the existing parser/command checks. CheckFieldScenarios is Notes/Slack/Cursor/browser field behavior (live mark, selection, stub, spoken punctuation). CheckConfigMatrix runs every insertion strategy (`releaseHID`, `axHID`, `imkOnly`, `imkFallback` in `Output/InsertConfig.swift`) through the same simulated fields and reports final-text, flicker, safety plus measured capabilities: live-shown (text before finalize) and underlined (mark vs plain keystrokes). The app Playground sidebar speaks into simulated boxes and logs raw speech, writes, timers, and path (AX/HID/IMK).

## Tests for every bug

When we fix a bug, add a regression test in the same change. Do not ship the fix without it.

- Phrase/spacing/punctuation → `CheckPhraseRules`
- Parser, commands, live-mark rules, “must not shift-select / stick modifiers” → `CheckLogic`
- Text-box / caret / selection / Slack / Cursor / Notes insertion → `CheckFieldScenarios`

Name the case after the failure (e.g. next sentence must go at the caret, not the old live mark).
