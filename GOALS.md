# Fast Dictation for macOS — Goals

Build an always-on dictation app for macOS that keeps everything useful about Apple's Voice Control and drops the thing that makes Voice Control unusable: its system-wide performance cost. It lives in the menu bar, listens continuously, types what is spoken, executes key presses and application commands by voice, and inherits the vocabulary and custom commands already built up in Voice Control.

This document states goals and how to tell whether they are met. It does not prescribe how to build any of it. Choose whatever approach meets the targets.

## Why this exists

Voice Control makes dictation slow across the entire system, not just in one app. The cause is that it requires every running application to expose its full user interface structure, then inspects that structure on every utterance. Applications with large, constantly changing interfaces — Electron apps especially — make this catastrophic.

This was measured rather than assumed. With Voice Control running, dictation was slow in every application. Quitting apps one at a time changed nothing until Cursor was quit, after which dictation became fast again with a long agent conversation being the specific trigger. Switching to plain macOS keyboard dictation, which does not inspect application interfaces, restored full speed immediately with every app still open.

Keyboard dictation is therefore fast but far too limited: no always-on listening, no key-press commands, no application control, no custom vocabulary, no custom commands. The goal is Voice Control's capability at keyboard dictation's speed.

## Environment

The app must work on the machine it is built for: macOS 26.6.2 (build 25G83), Apple M3 Max, locale `en_US`, using a USB headset microphone rather than the built-in mic. Working on older macOS versions is not a goal. Working on the newest macOS version is.

## Goals

### Always-on listening with a menu bar switch

Speech becomes text in whatever application has keyboard focus, with nothing to press first. The menu bar is the entire day-to-day interface and shows at a glance whether the app is listening. Listening can be turned on and off from that menu bar item.

The user cannot reliably use their hands, so no goal may depend on pressing a key or clicking a button as its only path — except after the Mac itself has slept. In that case a head-pointer click on the menu bar is the intended way to turn listening back on. See [Off when the Mac sleeps](#off-when-the-mac-sleeps).

### Listening control by voice

Saying "stop listening Mac" suspends dictation. Saying "start listening Mac" resumes it. This must work the way it does in Voice Control: the phrase is recognized while suspended, and nothing else spoken while suspended has any effect.

This is for pausing while the Mac is still awake. It is not how listening comes back after the Mac has slept.

### Off when the Mac sleeps

When the Mac sleeps, listening must turn off. That is preferred, not a compromise: the microphone should not stay live through sleep.

After the Mac wakes, listening stays off until it is turned on from the menu bar. A head-pointer click is the intended path. There is no requirement to wake dictation by voice after computer sleep.

### Speed matched to system dictation, with high accuracy

Dictation must feel at least as fast as macOS keyboard dictation does today, and must be at least as accurate. Keyboard dictation is the baseline because it is the current fallback, so anything slower or less accurate is a regression rather than a product.

Speed and accuracy are both hard requirements, and neither may be traded away for the other.

### No system-wide performance cost

The app must not make anything else on the machine slower, and specifically must not require applications to expose their interface structure the way Voice Control does.

This is the requirement the whole project exists to satisfy, so it gates every release.

### Key presses by voice

Saying "press shift D", "press the one key", or "press command shift Q" performs that key press, matching current Voice Control phrasing exactly. The full range matters: letters, digits, modifier combinations in any order, named keys such as return, tab, escape, space, delete, and the arrow keys, and function keys.

Existing phrasing habits must keep working. Relearning how to say a key press is a failure.

### Application control by voice

Saying "open ⟨app⟩" launches or focuses an application by spoken name, and "quit ⟨app⟩" quits it. Spoken names must resolve loosely enough to be practical, since applications are rarely called by their exact bundle names out loud.

Certain applications must never be quit by voice, and that list must be editable. Zoom and Terminal start on it.

### Case transforms on the selection

Saying "capitalize that" capitalizes the current selection, "uppercase that" makes it fully uppercase, and "lowercase that" makes it fully lowercase.

When nothing is selected, the command must do nothing and say so. Silently transforming the wrong text is worse than refusing.

### Punctuation by voice, with context awareness

Saying a punctuation name enters that character: "comma" produces `,`, and the same holds for period, question mark, colon, semicolon, dash, quote marks, and brackets.

Ideally the app infers from context whether the punctuation character or the literal word was intended. Since no recognizer resolves that perfectly, there must always be a reliable way to force the literal word, and there must be a way to configure the default for individual words.

### Custom vocabulary, imported from Voice Control

The app supports a custom vocabulary of words and names the recognizer would otherwise get wrong, serving the same purpose as Voice Control's vocabulary.

Existing Voice Control vocabulary and custom commands must import in one action, without retyping. That data already exists on this machine and is described in [What already exists to import](#what-already-exists-to-import). Vocabulary must also export, so it survives a machine migration.

A vocabulary that works most of the time is not acceptable, because it fails invisibly. Imported terms must be recognized reliably.

### Installed as a normal Mac app

The app installs by downloading it and dragging it to Applications, with no terminal commands and no separate installer. It starts automatically at login.

First run must handle whatever permissions it needs with plain explanations, download whatever it needs, offer the Voice Control import, and let the user choose the microphone.

## Non-goals

The app does not label interface elements with numbers so they can be clicked by voice. That feature is the specific cause of Voice Control's slowness, and it is not wanted at any price.

It does not inspect other applications' interface structure for any reason, control the mouse or pointer, send audio off the machine, collect telemetry, or ship a companion mobile app. Pointer control stays with the system Head Pointer and its alternate actions, which already work independently of dictation.

## Acceptance criteria

These are the tests that decide whether the goals were met. Run them on the target machine, with the headset microphone rather than the built-in one.

| What is tested | Passing result |
| --- | --- |
| No system-wide cost | With the app listening and a Cursor window holding a very long agent conversation open, dictating into TextEdit is no slower than with Cursor closed |
| Dictation speed | Text appears at least as fast as macOS keyboard dictation on the same spoken passages |
| Dictation accuracy | Word error rate at or below macOS keyboard dictation on a corpus of the user's own recorded speech |
| Vocabulary reliability | Imported vocabulary terms recognized correctly at least 95% of the time |
| Command speed | A recognized command executes fast enough to feel immediate, and never lags behind dictation |
| Wake phrase while Mac is awake | After "stop listening Mac", "start listening Mac" resumes listening within half a second, from silence, repeatedly |
| Mac sleep | Putting the Mac to sleep turns listening off. After wake, listening is still off until the menu bar is used |
| Resume after Mac sleep | Turning listening back on with a head-pointer click on the menu bar is enough. Voice resume after computer sleep is not required |
| Machine load | Idle listening does not produce audible fan noise or measurable slowdown in other applications |
| Hands-free completeness | While the Mac is awake, every feature including turning listening on and off is reachable without touching the keyboard or trackpad. After Mac sleep, a head-pointer click on the menu bar is the accepted way to resume |
| Import completeness | All existing vocabulary entries and custom commands import, verified first against the most heavily used commands |

## Priority order

Ordered so that each stage is worth using on its own.

1. Always-on dictation, menu bar switch, voice pause and resume while awake, and listening off through Mac sleep. This alone replaces the current keyboard-dictation-plus-panel-button workaround.
2. Key presses and application control. This replaces what Siri and Shortcuts were being considered for.
3. Vocabulary and custom command import, plus case transforms. At this point the app covers everything Voice Control did except element numbering.
4. Context-aware punctuation and per-word configuration.

## What already exists to import

Stated as fact about the current machine, not as instruction about how to read it.

Voice Control vocabulary currently holds 104 entries, 89 of which carry pronunciation data, stored in `~/Library/Preferences/com.apple.SpeechRecognitionCore.Vocabulary.plist` under the key `CACVocabularyEntries`. Each entry has the word, an array of IPA pronunciations, a locale, and a creation date.

Custom commands currently number 54, in the `com.apple.speech.recognition.AppleSpeechRecognition.CustomCommands` preference domain: 21 that trigger a keyboard shortcut, 18 that paste text, and 15 that open a file. Each carries its spoken phrases, whether it applies system-wide or to one application, an enabled flag, and for shortcut commands the key code and modifier flags.

Usage counts live alongside them. The two most-used custom commands have fired 3,124 and 2,975 times, so import correctness should be verified against the heaviest-used commands rather than alphabetically. Dictation itself has run over 2.19 million times, which is the volume this app has to hold up under.

## Open questions

Should "press" be required before a key command, or optional? Optional is more natural to speak, but it makes collisions with ordinary prose more likely.

Should dictation appear live as words are recognized, or only once a phrase is final? Live text feels faster but revises itself on screen.

How should command recognition failures be surfaced? A silent failure is confusing, and an audible one gets tiring quickly.
