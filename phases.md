# Walky Talky Phases

This is the phase-by-phase execution tracker for Walky Talky.

Treat this as the file to check before, during, and after each implementation session. The rule is simple: do not move forward because a task feels done; move forward only when the exit checks in this file are true.

## Status key

- `[ ]` not started
- `[~]` in progress
- `[x]` complete
- `[!]` blocked or needs a decision

## Phase 0: Technical Spike

Goal: prove the smallest useful local-first loop works end to end.

### Build

- `[x]` Create a native Swift menu-bar app shell.
- `[x]` Add an `NSStatusItem` menu-bar icon.
- `[x]` Open a compact SwiftUI popover from the menu-bar icon.
- `[x]` Request microphone permission only when recording is first attempted.
- `[x]` Add a global hold-to-record shortcut.
- `[x]` Record microphone audio to a local file.
- `[x]` Call a local `whisper.cpp` binary.
- `[x]` Display the resulting transcript in the popover.
- `[x]` Copy the transcript to clipboard.
- `[x]` Confirm no cloud calls, analytics, or remote transcription paths exist.

### Exit checks

- `[x]` Press shortcut.
- `[x]` Speak a short phrase.
- `[x]` Release shortcut.
- `[x]` Transcript appears locally.
- `[x]` Transcript is copied to clipboard.
- `[x]` Audio and transcript remain on the Mac.
- `[x]` App still behaves like a small menu-bar utility, not a full desktop dashboard.

### Do not add yet

- `[ ]` Meeting recording.
- `[ ]` Local LLM cleanup.
- `[ ]` Speaker diarization.
- `[ ]` Account, sync, billing, analytics, or server logic.

## Phase 1: Personal Dictation MVP

Goal: make Walky Talky useful for daily short-form dictation.

### Build

- `[x]` Hold-to-record shortcut.
- `[x]` Latch recording shortcut.
- `[x]` Shortcut customization.
- `[x]` Local model folder under `~/Library/Application Support/Walky Talky/models/`.
- `[x]` Model missing state.
- `[x]` Model selection setting.
- `[x]` Local transcript history.
- `[x]` Store raw transcript and polished transcript.
- `[x]` Deterministic text cleanup pipeline.
- `[x]` Auto-copy polished transcript.
- `[x]` Optional auto-paste into active app.
- `[x]` Accessibility permission requested only when auto-paste is enabled.
- `[x]` Dictation audio deletion policy.
- `[x]` Launch at login.

### Exit checks

- `[x]` The app can be used for short messages, notes, and snippets without opening a large window.
- `[x]` The latest transcript is immediately visible.
- `[x]` Recent dictations are easy to copy.
- `[x]` Raw transcript remains available when polishing is wrong.
- `[x]` Dictation audio is deleted or retained according to the selected local policy.
- `[x]` No recording leaves the Mac.

### Quality bar

- `[x]` Polishing is conservative.
- `[x]` Spoken punctuation works for common cases.
- `[x]` Filler removal does not remove meaningful words.
- `[x]` Shortcut conflicts produce a clear local error.
- `[x]` Clipboard behavior is predictable.

## Phase 2: Meeting Recording MVP

Goal: support long local recordings without treating meetings like long dictations.

### Build

- `[x]` Meeting mode separate from dictation mode.
- `[x]` Meeting start/stop control in popover.
- `[x]` Optional meeting shortcut.
- `[x]` Long-running microphone recording.
- `[x]` Optional system audio recording through native ScreenCaptureKit.
- `[x]` Chunked audio writer.
- `[x]` Background transcription queue.
- `[x]` Save each transcript segment as it completes.
- `[x]` Timestamped transcript segments.
- `[x]` Crash-safe partial transcript storage.
- `[x]` Meeting detail view.
- `[x]` Copy full transcript.
- `[x]` Copy selected sections.
- `[x]` Export `.txt`.
- `[x]` Export `.md`.
- `[x]` Automatically store finalized meetings as `.md` files.
- `[x]` Meeting audio retention policy.

### Exit checks

- `[x]` A 30-minute microphone-only meeting can be recorded locally.
- `[!]` A 60-minute microphone-only meeting can be recorded locally. Skipped at user request after 36 recorded chunks.
- `[x]` Partial transcript progress is saved before the meeting ends.
- `[x]` A crash or quit loses at most the active chunk.
- `[x]` Final stitching produces one readable transcript.
- `[x]` Exported files contain timestamps.
- `[x]` User can delete meeting audio.

### Deferred

- `[x]` System audio capture.
- `[x]` Optional speaker-turn detection through whisper.cpp tinydiarize when a local `tdrz` model is selected.
- `[x]` Live streaming transcript UI.
- `[x]` Meeting summaries.
- `[x]` Action items.

## Phase 3: Native Feel And Polish

Goal: make the app feel like a small, precise Mac utility.

### Build

- `[x]` Refine popover layout.
- `[x]` Use native macOS materials.
- `[x]` Add subtle state transitions.
- `[x]` Add clear recording indicator.
- `[x]` Improve transcript row density.
- `[x]` Add better empty states.
- `[x]` Add keyboard navigation.
- `[x]` Add local search.
- `[x]` Tighten settings window.
- `[x]` Make permission and error states plain.

### Exit checks

- `[x]` The first screen shows the useful thing immediately.
- `[x]` No marketing-style screen exists.
- `[x]` No dashboard bloat exists.
- `[x]` Transcript browsing is compact.
- `[x]` Recording/transcribing/error states are obvious at a glance.
- `[x]` Settings remain lightweight.

## Phase 4: Advanced Local Intelligence

Goal: add optional intelligence only after the core utility is reliable.

### Possible modules

- `[x]` Optional local LLM polishing adapter. Uses an installed local runtime when available and falls back cleanly when none exists.
- `[x]` Meeting summary.
- `[x]` Action items.
- `[x]` Custom cleanup presets.
- `[x]` Better paragraphing.
- `[x]` Optional local diarization adapter through whisper.cpp tinydiarize. Requires a local `tdrz` Whisper model; fake speaker labels are not acceptable.

### Entry checks

- `[x]` Dictation MVP is stable.
- `[x]` Meeting MVP is stable.
- `[x]` Raw transcript preservation is already reliable.
- `[x]` The optional model footprint is clear to the user.
- `[x]` The feature can be disabled without breaking core dictation.

### Hard rule

Advanced local intelligence must stay optional. It cannot become required for dictation, meeting recording, history, copy, or export.

## Cross-phase invariants

- `[x]` No accounts.
- `[x]` No analytics.
- `[x]` No cloud transcription by default.
- `[x]` No billing.
- `[x]` No team workspace.
- `[x]` No server dependency.
- `[x]` No web dashboard.
- `[x]` All recordings stay local.
- `[x]` All transcripts stay local.
- `[x]` Permissions are requested contextually.
- `[x]` Raw transcript is preserved.
- `[x]` User can delete local audio.
- `[x]` The app remains menu-bar first.
