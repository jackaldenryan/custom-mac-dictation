# Custom Dictation

Download the Mac app from [Releases](https://github.com/jackaldenryan/custom-mac-dictation/releases/latest), drag it into Applications, and open it. It lives in the Dock and types into the focused app when you speak. It uses Apple’s on-device dictation engine. Audio stays on this Mac.

## Install

1. Open the [latest release](https://github.com/jackaldenryan/custom-mac-dictation/releases/latest).
2. Download **CustomDictation-x.y.z.dmg**.
3. Open the disk image and drag **Custom Dictation** into Applications.
4. Open **Custom Dictation** from Applications.

The app is not notarized yet. If macOS says it cannot be opened, right-click the app, choose Open, and confirm. You can also run this once:

```
xattr -cr "/Applications/Custom Dictation.app"
```

Then open it again from Applications.

A `.zip` is attached to the same release. The in-app updater uses that zip. You do not need it for a first install.

## First launch

Keep Voice Control off while this app is listening. They should not both run.

1. Grant **Microphone**.
2. Grant **Speech Recognition** if macOS asks.
3. Turn on **Custom Dictation** in System Settings → Privacy & Security → Accessibility, then continue in the setup window.
4. Wait if it downloads Apple speech models.
5. Pick the USB headset, not the built-in mic.
6. Finish. The main window and Dock icon should show that it is listening.

Voice Control import is optional and lives in Settings. Skip it until basic dictation works.

## What to try after it is installed

Open TextEdit, click in the window, and speak.

- Dictate a sentence. Text should appear in TextEdit.
- Say **stop listening dictation**. Further speech should do nothing.
- Say **start listening dictation**. Dictation should resume.
- Say **press return**. That should press Return.
- Say **open Safari**, then **quit Safari**.
- Select a word, say **uppercase that**. If nothing is selected, it should say so.
- Say **comma**. It should type `,`.
- Say **the word comma**. It should type the word.

Put the Mac to sleep. After it wakes, listening stays off until you click **Start Listening** in the app window or Dock.

With Cursor holding a long agent conversation, dictate into TextEdit. It should feel no slower than with Cursor closed.

## Menu bar and settings

The menu bar icon is the app. Closing the window leaves it running there.

- Filled mic: listening
- Slashed mic: off

That menu has Start/Stop Listening, microphone, Show Window, Check for updates, and Quit. Say **quit application** while the window or that menu is frontmost to quit this app. Otherwise it quits the frontmost app.

## Updates

The app checks GitHub Releases when it opens. Settings also has **Check for updates**. If a newer version exists, you can install it or choose Later.

You do not need to download a new disk image after the first install unless you prefer to.

## Requirements

macOS 26 or newer, on Apple Silicon. No paid API key.

This app does not number on-screen controls and does not inspect other apps’ interface trees.

## Build from source

This section is only for changing the app. Ordinary install is the release download above.

```
./scripts/package-app.sh
```

That writes `dist/Custom Dictation.app`, a zip, and a disk image.

To publish a version, set `VERSION`, commit, push to `origin/main`, then run:

```
./scripts/publish-tag.sh
```

GitHub Actions attaches the disk image and zip to the GitHub release. If the runner cannot build, package on a Mac with the macOS 26 SDK and upload the files with `gh release create`.
