# Fast Dictation — Architecture

Use Apple's on-device dictation engine, type into the focused app with synthetic key events, and never walk another app's accessibility tree.

This document is the build plan. Product goals and acceptance tests live in `GOALS.md`. No decision is needed unless you disagree.

## The choice that gates everything

**Recognizer:** `DictationTranscriber` from the macOS 26 Speech framework.

It uses the same on-device models as keyboard dictation. That is how we hit both speed and accuracy without a tradeoff, without a paid API, and without sending audio off the machine.

Do not use Whisper, mlx-whisper, Vosk, or a cloud STT API. Those either leave the machine, cost money, miss the keyboard-dictation baseline, or burn idle CPU. Do not use the legacy `SFSpeechRecognizer` path. It has a one-minute cap and network throttling.

`SpeechTranscriber` is the newer general-purpose model. Keep it as a measured fallback only. It does not document custom language-model hooks the way `DictationTranscriber` does, and we need those hooks for the 95% vocabulary bar.

**Cost to run:** $0. Apple hosts the model assets. After the first download they stay on device and are shared with the system.

## What we are not building

No UI-element numbering. No AX tree walks of other apps. No mouse or pointer control. No cloud audio. No telemetry. No companion phone app.

Pointer work stays with the system Head Pointer. This app only listens, types, presses keys, and launches or quits apps.

## System shape

A single unsigned-for-now Swift menu bar app. Not sandboxed. Agent app, no Dock icon. Login item via `SMAppService`.

```
Microphone
    → AudioCapture (chosen USB headset)
    → SpeechAnalyzer
         ├ SpeechDetector          (VAD, save idle work)
         └ DictationTranscriber    (same models as keyboard dictation)
    → Transcript
    → Router
         ├ command  → CommandRegistry → Typist / AppController / Session
         └ dictation → Typist (CGEvent keystrokes into the focused app)
```

The focused app never has to expose its interface. We only post keyboard events, the same way a physical keyboard would.

## Listening states

Three states. Not two.

| State | Mic | What speech does | How you leave |
| --- | --- | --- | --- |
| Off | Dead | Nothing | Menu bar click (head pointer after sleep) |
| Suspended | Live | Only "start listening Mac" | That phrase, or menu bar |
| Listening | Live | Commands first, else type | "stop listening Mac", menu bar, or Mac sleep |

Mac sleep always forces Off and stops the capture session. Wake leaves it Off. That is required, not a fallback.

"stop listening Mac" / "start listening Mac" only apply while the Mac is awake. After sleep, voice must not turn listening back on.

Keep the Speech models loaded across Suspended and Listening (`SpeechAnalyzer.Options.ModelRetention` plus `prepareToAnalyze`). Tear the capture session down in Off. Resume from Off has to be fast enough for a head-pointer click, not for a half-second wake phrase.

## Recognizer setup

**Preset:** `progressiveLongDictation` with punctuation on.

`shortForm` / `shortDictation` are built for about a minute of audio. Always-on dictation is not that. `progressive*` emits volatile (live) results; v1 ignores those and types only finalized phrases. Live replacement is a later option, not the default. Code editors hate text that rewrites itself.

**VAD:** `SpeechDetector` at `.medium` sensitivity, in the same `SpeechAnalyzer` as the transcriber. This is how idle listening stays quiet enough that the fans do not spin.

**Locale:** `en_US`. First launch calls `AssetInventory.assetInstallationRequest` and downloads whatever is missing, with a progress line in the onboarding window.

**Mic:** `AVCaptureDevice` discovery, not the system default. Persist the chosen USB headset UID. If it is missing at launch, fall back and say so in the menu bar.

**Audio path on macOS 26.6.2:** Drive `AVAudioEngine` ourselves and feed `AnalyzerInput` buffers into `SpeechAnalyzer`. `CaptureInputSequenceProvider` and `AnalyzerInputConverter` are documented as macOS 27. Use them if they are actually present at runtime; do not depend on them to compile.

**Session lifetime:** One long-lived analyzer while Listening or Suspended. If the analyzer errors, rebuild it. Do not create overlapping analyzers.

## Routing speech

Every finalized transcript goes through the router before anything is typed.

1. Normalize: lowercase, collapse spaces, strip trailing punctuation.
2. Match the command table, longest phrase first.
3. On a match, run the command and do not type the words.
4. On no match in Listening, type the original (not normalized) text.
5. On no match in Suspended, discard.

Built-in grammars, in match order:

1. `stop listening Mac` / `start listening Mac`
2. Imported custom commands (exact spoken phrases)
3. `press …` key grammar
4. `open <app>` / `quit <app>`
5. `capitalize that` / `uppercase that` / `lowercase that`
6. Spoken punctuation words, subject to the punctuation policy below

**"press" is required.** Optional "press" collides with ordinary prose ("shift this down", "return the value"). Existing Voice Control phrasing already includes "press". Revisit only if real use shows the extra word is a problem.

## Typing and keys without Accessibility inspection

**Permission we do need:** Accessibility, so we can post `CGEvent` taps to other apps. That is event injection, not UI-tree inspection.

**Text:** Convert the string to Unicode key downs via `CGEventKeyboardSetUnicodeString`, or fall back to character-by-character events. Do not use AX `set value` on the focused element.

**Keys:** A table from spoken names to key codes and modifier flags. The grammar must accept:

- Letters and digits, including "the one key"
- Modifiers in any order: command, shift, option, control, function
- Named keys: return, tab, escape, space, delete, forward delete, arrows
- Function keys F1–F20

Match Voice Control phrasing exactly. The parser is a small recursive descent over tokens, not an LLM.

**Case transforms:** Clipboard round-trip, because we refuse AX.

1. Snapshot the pasteboard.
2. Post command-C.
3. If the pasteboard did not change, speak "nothing selected" and stop.
4. Transform the copied string.
5. Paste it back.
6. Restore the previous pasteboard.

Silently editing the wrong text is worse than refusing.

**App control:** `NSWorkspace` to launch or activate. `NSRunningApplication.terminate()` to quit. Resolve spoken names against localized names, bundle names, and `/Applications` with token overlap, not exact bundle IDs.

## Vocabulary and custom commands

Voice Control data already on this machine:

- 104 vocabulary entries (89 with IPA) in `~/Library/Preferences/com.apple.SpeechRecognitionCore.Vocabulary.plist`, key `CACVocabularyEntries`
- 54 custom commands in the `com.apple.speech.recognition.AppleSpeechRecognition.CustomCommands` defaults domain: 21 shortcuts, 18 pastes, 15 open-file

**Import is one menu action.** Read those files directly. The app is not sandboxed, so it can. Verify first against the two commands that have fired ~3,000 times each.

**Vocabulary path into the recognizer:**

1. Store our own copy (JSON in Application Support) so export and machine moves work.
2. Put every term in `AnalysisContext.contextualStrings`.
3. Build an `SFSpeechLanguageModel` from `SFCustomLanguageModelData` and attach it with `DictationTranscriber.ContentHint.customizedLanguage`.
4. Convert Voice Control IPA pronunciations to X-SAMPA. Apple's custom terms take X-SAMPA (`supportedPhonemes(locale:)`). Drop or warn on symbols the locale does not support. Terms without pronunciation still go in as graphemes plus phrase-count bias.

Also insert imported command phrases as `PhraseCount` samples so "press command shift Q" is preferred over a prose interpretation.

**Export:** write the same JSON. Import that file on a new Mac.

**Custom command execution:**

| Voice Control type | What we do |
| --- | --- |
| Keyboard shortcut | Post the stored key code and modifier flags |
| Paste text | Type or paste the stored string |
| Open a file | `NSWorkspace.open` |

Honor enabled flags and per-app vs system-wide scope using the frontmost bundle ID. Still no AX.

## Punctuation

v1: a spoken-name table (`comma` → `,`, and the rest listed in the goals). Default is the character.

Literal-word escape, always available: `the word comma` (and the same shape for every mapped word).

Per-word override in settings: character, literal word, or off.

v4 (priority 4 in the goals): use surrounding typed context to pick character vs word when the user did not force it. The escape hatch and the per-word override stay.

## Menu bar and first run

The status item is the whole daily UI. Icon states: Off, Suspended, Listening, Needs permission, Error. Clicking the item toggles Off ↔ Listening. The menu also has Suspend, microphone, import/export, and Quit.

After Mac sleep, a head-pointer click on that item is the intended resume path. The status item must stay a normal `NSStatusItem` so Head Pointer can hit it.

First launch, in order:

1. Explain microphone, then request it.
2. Explain speech recognition if the OS still gates the new API, then request it.
3. Explain Accessibility (for typing into other apps), then open the system pane and wait until it is granted.
4. Download speech assets with a progress line.
5. Offer Voice Control import.
6. Pick the microphone.
7. Register the login item.
8. Start in Listening.

No terminal steps. Later distribution is a notarized `.app` in a DMG, dragged to `/Applications`.

## Feedback for failures

Silent command failure is confusing. Talking after every miss is worse.

- Command that ran: no sound.
- Command that could not run (nothing selected, unknown app name): one short spoken line through `AVSpeechSynthesizer`, plus a menu-bar flash.
- Unrecognized speech in Listening: type it. That is dictation, not a failure.
- Recognizer crash or permission loss: persistent menu-bar error until fixed.

## Project layout

Swift Package or an Xcode project, one app target, macOS 26.0 deployment.

```
fast-dictation/
  GOALS.md
  ARCHITECTURE.md
  App/
    FastDictationApp.swift          MenuBarExtra, login item, lifecycle
    StatusItemController.swift
    OnboardingWindow.swift
    SleepObserver.swift             NSWorkspace willSleep / didWake
  Recognition/
    ListeningSession.swift          Off / Suspended / Listening
    SpeechEngine.swift              SpeechAnalyzer wiring
    AudioCapture.swift              AVAudioEngine, device UID
    TranscriptNormalizer.swift
  Routing/
    Router.swift
    CommandRegistry.swift
    KeyPressGrammar.swift
    AppNameResolver.swift
    PunctuationPolicy.swift
  Output/
    Typist.swift                    CGEvent text and keys
    SelectionTransform.swift        clipboard round-trip
    AppController.swift             open / quit
    SpokenFeedback.swift
  Import/
    VoiceControlImporter.swift
    VocabularyStore.swift
    IPAToXSampa.swift
    LanguageModelBuilder.swift
  Support/
    SettingsStore.swift
    Permissions.swift
```

No nested agents or extra processes. One app, one analyzer.

## Build order

Matches the priority list in `GOALS.md`. Each stage is usable alone.

1. Menu bar, permissions, asset download, mic picker, session state, sleep observer, finalized dictation into the focused app, voice pause/resume.
2. Key-press grammar and open/quit.
3. Voice Control import, custom language model, case transforms.
4. Context-aware punctuation and per-word defaults.

## How we know the architecture is right

Run the acceptance table in `GOALS.md` on this machine, headset mic, Cursor holding a long agent conversation.

The architecture is wrong if any of these happen:

- Dictation into TextEdit gets slower when that Cursor window is open.
- Fans spin while sitting in silence in Listening.
- Audio or transcripts leave the Mac, except Apple's own asset download.
- Any feature walks another app's AX tree.
- Imported vocabulary is only "usually" recognized.

## Open implementation notes

`CaptureInputSequenceProvider` may appear before the documented macOS 27 availability. Probe at compile or runtime; keep the `AVAudioEngine` path.

`DictationTranscriber` custom language models ignore terms already in the system vocabulary. That is fine. Pronunciations with unsupported X-SAMPA symbols are also ignored, so the IPA converter must filter through `supportedPhonemes(locale:)`.

Whether Speech Recognition permission still applies to `SpeechAnalyzer` on 26.6.2 is an on-machine check during stage 1. Onboard it if the API asks.

Live (volatile) text stays off until someone measures it against keyboard dictation and against Cursor's editor. The pipeline already receives those results; the typist just ignores them in v1.
