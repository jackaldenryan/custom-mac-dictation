# Custom Dictation

## Test locally without a release

Build a second app that does not replace `/Applications/Custom Dictation.app` and does not use `~/.custom-dictation-config`.

```
./scripts/run-local.sh
```

That installs **Custom Dictation Local** to `/Applications` (not the released app). Config is `~/.custom-dictation-config-local`. Login items and update checks are off.

Typing is Accessibility in native fields, keyboard events everywhere else. An Input Method (IMK) path was tried and removed in 0.1.40: macOS 26 does not list classic IMK apps in Keyboard → Input Sources, so it could never be selected.

Enable **Custom Dictation Local** in System Settings → Privacy & Security → Accessibility (and Microphone). It is a different app from Custom Dictation. If it is not in the list, click + and choose it from Applications.

Quit the released Custom Dictation app, or stop listening on it, so only the local app uses the microphone. First local launch may show onboarding.

Do not use `./scripts/install-local.sh` for this. That overwrites Applications and is not a side-by-side test.

## AX writes never in web engines

Slack, Cursor, VS Code, OpenCode, Chrome, Safari pages and any Electron/Chromium/WebKit view answer AX text writes with success but apply them late or never, and the attempt moves the caret first. Falling back to keystrokes after that typed into the middle of earlier words (Oct 3: "hey guess what I don't know you tell me" in Slack came out "Hey, guess? I don't know you tell .me don't"). `Output/AXWritePolicy.swift` blocks AX writes there up front; `FieldEditor.write` restores the selection on any failed write and turns AX off for that app for the session; `PhrasePathLock` keeps a phrase on HID once it starts on HID. Regression: `slackLogReplay` in CheckLogic.

## Apple automatic punctuation is always off

The DictationTranscriber runs without `.punctuation` (`Recognition/TranscriberOptions.swift`): no marks guessed from pauses; spoken "period" / "comma" / "question mark" / "exclamation point" still convert. It is not a setting: the typing logic assumes every mark was spoken, so turning Apple's guesses back on would bring back doubled and stray marks. Check real-model behavior with `./scripts/probe-punctuation.sh` (speaks samples with `say`, transcribes each with it on and off via `swift run ProbeSpeech`).

Because every mark is spoken, the app types every mark it gets. Removed in 0.1.40 because they only existed to undo Apple's guesses: dropping repeated boundary punctuation, the lone-punctuation pause setting, and stripping a trailing ". ? ..." when inserting mid-sentence. Kept: lowering Apple's segment-start capital mid-sentence (Apple still capitalizes each segment).

## Post-process is built in

`Output/PostProcess.swift` (`DefaultPostProcess`) is the only post-process: capitals, spacing, mid-sentence fit. There is no Post-process tab or JavaScript config anymore (removed in 0.1.40); change behavior in code and cover it in CheckPhraseRules.

## Clicks

Modifier clicks ("shift click", "command click", "option click") are real mouse events posted with the modifier keys held (`Typist.click`). Never System Events `click at`: that is an Accessibility press, so the app never sees the modifier (shift-click selected one Finder item, command-click opened links in the same tab). Plain clicks may use an Accessibility press, except on items in lists/tables/file browsers, which need a real click to set the selection anchor. "command click" in a browser first tries `LinkOpener` (open the link under the pointer in a new tab).

## Spoken emoji

`Output/EmojiPhrases.swift`: "<name> emoji" anywhere in dictation becomes the emoji ("thanks prayer hands emoji" -> "thanks 🙏"), live and final, before the post-process. Only phrases ending in "emoji" change. Add names or aliases to `EmojiPhrases.table`; cover them in CheckLogic.

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

CheckPhraseRules is the desired typing rules (spaces, capitals, spoken punctuation, acronyms). It can fail while you change the post-process. CheckLogic is the existing parser/command checks. CheckFieldScenarios is Notes/Slack/Cursor/browser field behavior (live mark, selection, stub, spoken punctuation). CheckConfigMatrix runs each insertion strategy (`releaseHID` = v0.1.39 baseline, `axHID` = current, in `Output/InsertConfig.swift`) through the same simulated fields and reports final-text, flicker, safety plus measured capabilities: live-shown (text before finalize) and underlined (mark vs plain keystrokes). CheckLogic drives the real `LivePhrase` + `Router` into a `SimulatedField` via `LivePhrase.simulatedField` (no AX, no keystrokes). The in-app Playground tab was removed in 0.1.41; its code is kept only locally in `local-archive/playground/` (gitignored).

## Tests for every bug

When we fix a bug, add a regression test in the same change. Do not ship the fix without it.

- Phrase/spacing/punctuation → `CheckPhraseRules`
- Parser, commands, live-mark rules, “must not shift-select / stick modifiers” → `CheckLogic`
- Text-box / caret / selection / Slack / Cursor / Notes insertion → `CheckFieldScenarios`

Name the case after the failure (e.g. next sentence must go at the caret, not the old live mark).
