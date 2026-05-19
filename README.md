# Walky Talky

Walky Talky is a local-first macOS menu bar app for dictation and meeting transcription.

It records locally, transcribes locally with whisper.cpp, formats the transcript, copies it to the clipboard, and can auto-paste back into the app you were using.

## Download

Latest direct-download DMG:

[download Walky Talky for Mac](https://github.com/shashank-sn/walky-talky/releases/latest/download/Walky-Talky-mac.dmg)

This app is distributed directly, not through the Mac App Store.

## What it does

- menu bar dictation app for macOS
- hold-to-dictate shortcut
- latch dictation shortcut
- meeting transcription shortcut
- microphone meeting recording
- optional system-audio meeting recording
- local whisper.cpp transcription
- automatic lowercase transcript cleanup
- custom dictionary for product names and repeated corrections
- automatic dictionary learning from transcript cleanup
- auto-copy and auto-paste after dictation
- local SQLite transcript history
- meeting transcripts saved as `.md`
- first-launch onboarding for permissions and local model setup
- customizable shortcuts from settings
- light and dark popover appearance

## Default shortcuts

- hold to dictate: `control + option`
- latch dictation: `control + option + space`
- meeting start/stop: `control + option + m`

Shortcuts can be changed from settings. Double-click a shortcut row and press the new shortcut.

## Local model/runtime contract

Walky Talky is intentionally kept small. The app bundle does not include Whisper models or the whisper.cpp runtime.

Local files live outside the app at:

```text
~/Library/Application Support/Walky Talky/
```

Expected runtime/model locations:

```text
~/Library/Application Support/Walky Talky/whisper
~/Library/Application Support/Walky Talky/lib/
~/Library/Application Support/Walky Talky/models/
```

If a selected model is already installed, onboarding marks it as installed and continues. It does not download the same model again.

Supported onboarding model choices:

- `large v3 turbo` - recommended for accent handling and better dictation quality
- `base english` - smaller fallback model
- `small tdrz` - optional model for tinydiarize speaker-turn support

## Install

1. Download the DMG from the latest release.
2. Open the DMG.
3. Drag `Walky Talky.app` to Applications.
4. Open the app.
5. Complete onboarding:
   - microphone permission
   - accessibility permission
   - screen recording permission if you want system-audio meetings
   - local Whisper runtime/model check

Because this build is not Developer ID signed/notarized yet, macOS may show a Gatekeeper warning on other Macs.

## Build from source

Clone the repo:

```bash
git clone https://github.com/shashank-sn/walky-talky.git
cd walky-talky
```

Build the Swift app:

```bash
swift build
```

Run from source:

```bash
swift run WalkyTalky
```

Create a local app bundle:

```bash
./scripts/build-app-bundle.sh
```

Create release packages:

```bash
./scripts/package-direct-download.sh
./scripts/package-dmg.sh
```

## Install local whisper.cpp for development

The repo does not vendor or commit whisper.cpp, Whisper models, or model binaries.

For development, run:

```bash
./scripts/bootstrap-whisper.sh
```

That script:

- clones `ggml-org/whisper.cpp` into `vendor/`
- builds `whisper-cli`
- installs the runtime to `~/Library/Application Support/Walky Talky/`
- downloads `ggml-base.en.bin` if missing
- runs a small local smoke test

To install the optional tinydiarize model:

```bash
./scripts/download-tdrz-model.sh
```

## Packaging notes

The app package is intentionally tiny. Current local release size is only a few MB because large runtime and model files are not inside the app bundle.

Do not commit:

- `.build/`
- `dist/`
- `vendor/`
- Whisper model binaries
- local recordings
- transcript databases
- exported user transcripts

Those paths are ignored in `.gitignore`.

## Privacy

Walky Talky is local-first:

- no account system
- no cloud transcription
- no server upload path
- no bundled analytics
- no remote storage

Audio, transcripts, models, and runtime files stay on the Mac.
