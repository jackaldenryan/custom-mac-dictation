# Custom Dictation

Always-on macOS dictation in the menu bar. It types into the focused app and runs voice commands, using Apple’s on-device dictation engine. Audio stays on this Mac.

You are the only user right now. Test by installing the app on this Mac and talking to it. Product goals are in `GOALS.md`. The build plan is in `ARCHITECTURE.md`.

## Test it on this Mac

Do this from the repo root. It builds the app, copies it to Applications, and launches it.

```
./scripts/install-local.sh
```

If macOS blocks the unsigned app:

```
xattr -cr "/Applications/Custom Dictation.app"
```

Then open **Custom Dictation** from Applications again.

### First launch

1. Grant **Microphone**.
2. Grant **Speech Recognition** if macOS asks.
3. Turn on **Custom Dictation** in System Settings → Privacy & Security → Accessibility. Click the onboarding button again after it is enabled.
4. Wait if it downloads Apple speech models.
5. Import Voice Control when asked. That pulls the vocabulary and custom commands already on this machine.
6. Pick the USB headset, not the built-in mic.
7. Finish. The menu bar mic icon should show it is listening.

Keep Voice Control **off** while you test this app. They should not both listen.

### What to try

Open TextEdit, click in the window, and speak.

- Dictate a sentence. Text should appear in TextEdit.
- Say **stop listening Mac**. Further speech should do nothing.
- Say **start listening Mac**. Dictation should resume.
- Say **press return**. That should press Return.
- Say **press command shift q** only in a throwaway window. That should send that shortcut.
- Say **open Safari**, then **quit Safari**.
- Say **quit Terminal**. It should refuse. Same for Zoom.
- Select a word, say **uppercase that**. If nothing is selected, it should say so.
- Say **comma**. It should type `,`.
- Say **the word comma**. It should type the word.

Put the Mac to sleep. After it wakes, listening must stay off until you open the menu bar icon and choose **Start Listening**. A head-pointer click on that menu is the intended path.

With Cursor holding a long agent conversation, dictate into TextEdit. It should feel no slower than with Cursor closed.

### Menu bar

The icon is the daily UI.

- Filled mic: listening
- Pause: suspended by voice
- Slashed mic: off

**Start Listening** and **Stop Listening** are in that menu. **Settings** has the microphone, never-quit list, Voice Control import/export, punctuation defaults, and **Check for updates**.

## Install from a GitHub release

After a tagged release exists, download `CustomDictation-*.zip` from [Releases](https://github.com/jackaldenryan/custom-mac-dictation/releases/latest). Unzip it and drag **Custom Dictation** into Applications, then open it. If macOS blocks it, run the `xattr` command above.

## Updates

The app checks GitHub Releases when it opens. Settings also has **Check for updates**. If a newer version exists, you can install it or choose Later.

You do not need to download a new zip after the first install unless you prefer to.

## Publish a version

Do this after the code you want is on `origin/main`.

1. Set `VERSION` to the new number, such as `0.1.1`. Keep it in sync with what you want the tag to be.
2. Commit that bump and push it to `origin/main`.
3. From the repo root:

```
./scripts/publish-tag.sh
```

That tags `vX.Y.Z` and pushes it. GitHub Actions builds `CustomDictation-X.Y.Z.zip` and attaches it to the GitHub release.

Confirm Actions can write releases: **Settings → Actions → General → Workflow permissions → Read and write permissions**.

If Actions cannot build (the runner needs the macOS 26 SDK), build on this Mac and attach the zip:

```
./scripts/package-app.sh
```

```
gh release create v0.1.0 dist/CustomDictation-0.1.0.zip --title "Custom Dictation v0.1.0" --notes "First installable build."
```

## Build without installing

```
./scripts/package-app.sh
```

The app lands at `dist/Custom Dictation.app`.

## Requirements

macOS 26 or newer. Apple Silicon is the machine this was built for. No paid API key.

Do not run Voice Control at the same time. This app does not number on-screen controls and does not inspect other apps’ interface trees.
