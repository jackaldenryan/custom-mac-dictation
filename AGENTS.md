# Custom Dictation

## Test locally without a release

Build a second app that does not replace `/Applications/Custom Dictation.app` and does not use `~/.custom-dictation-config`.

```
./scripts/run-local.sh
```

That installs **Custom Dictation Local** to `/Applications` (not the released app). Config is `~/.custom-dictation-config-local`. Login items and update checks are off.

Enable **Custom Dictation Local** in System Settings → Privacy & Security → Accessibility (and Microphone). It is a different app from Custom Dictation. If it is not in the list, click + and choose it from Applications.

Quit the released Custom Dictation app, or stop listening on it, so only the local app uses the microphone. First local launch may show onboarding.

Do not use `./scripts/install-local.sh` for this. That overwrites Applications and is not a side-by-side test.
