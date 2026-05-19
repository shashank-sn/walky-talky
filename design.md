# Walky Talky Design

Walky Talky should feel like a tiny native Mac utility that happens to do transcription extremely well. The current production direction is `Coss Primitive`: sharp, quiet, component-like controls with low-radius panels, restrained borders, and a clear active meeting patch.

## Design position

The app is:

- quiet
- compact
- local
- fast
- keyboard-first
- native to macOS
- useful immediately

The app is not:

- social
- collaborative
- cloud-first
- dashboard-heavy
- marketing-led
- visually loud
- account-centered
- feature-bloated

## First-screen rule

The first visible surface must show the useful thing immediately.

Default popover priority:

1. Brand row with settings gear.
2. Dictation and Meeting action patches.
3. Active meeting progress when recording.
4. Recent dictations.
5. Meetings.

Do not open with a dashboard. Do not open with onboarding copy. Do not open with a marketing explanation of the product.

## Visual feel

Use current macOS conventions:

- SwiftUI
- Coss-style primitive surfaces
- compact controls
- system typography
- low-radius borders
- restrained color
- mild green for active recording states

The design should feel closer to a polished menu-bar tool than a dashboard or marketing app.

## Layout

### Menu-bar popover

The popover should be small by default. It should expand only when the user opens details, settings, or a meeting transcript.

Recommended structure:

```text
Brand row with settings gear
Dictation and Meeting action patches
Recent dictations
Recent meetings
```

### Mode patches

Must support:

- Dictation
- Meeting

Do not show a `Mode` label. Dictation and Meeting are separate patches. Selecting Meeting starts meeting recording immediately. When Meeting is active, its patch turns mild green. The shortcut `control + option + m` also starts or stops meeting mode.

Do not show a separate `Start meeting` button.

### Recent dictations

Rows should be dense and scannable.

Each row:

- time
- first-line preview
- copy button
- delete button

### Meetings

Meeting rows need slightly more structure than dictation rows.

Each row:

- title or date
- transcript preview or markdown filename
- copy
- open in Finder
- delete

Do not show export controls in the popover.

Active meeting progress can appear as a row, not as a large status section.

Meeting detail can be a separate lightweight window because long transcripts do not belong inside a tiny popover.

## Typography

Use system typography.

Suggested hierarchy:

- status label: system body or callout
- transcript preview: body
- row metadata: caption
- buttons: standard system controls
- settings labels: standard form labels

Do not use oversized hero type. This app has no hero surface.

## Color

Keep the palette restrained.

Use color primarily for state:

- idle: neutral
- recording meeting: mild green active patch
- transcribing: blue or accent color
- success/available: neutral with active controls
- error: red with plain recovery action

Do not create a branded gradient palette. Do not make the app feel like a website.

## Motion

Motion should clarify state changes.

Use subtle animation for:

- recording indicator pulse
- transition from recording to transcribing
- transcript appearing after completion
- row insertion in history

Avoid decorative animation. Nothing should bounce, float, spin continuously, or compete with the recording state.

## Copy

Copy should be plain and functional.

Good:

- `Recording`
- `Transcribing`
- `Copied`
- `Model missing`
- `Allow microphone access`
- `System audio unavailable`

Bad:

- long explanations in the popover
- marketing claims
- cute voice-assistant language
- generic productivity slogans

## Empty states

Empty states should be short and useful.

Examples:

- `No dictations yet`
- `No meetings yet`
- `Choose a local model to start`

Do not explain the whole app in an empty state.

## Settings

Settings should live inside the popover behind the gear icon. The gear replaces quit in the main popover.

Sections:

- Shortcuts
- Appearance
- Quit

Settings must show the three shortcuts:

- `control + option`: hold to dictate
- `control + option + space`: latch dictation
- `control + option + m`: meeting mode

Settings must include dark/light appearance. Quit belongs only inside settings.

## Permission prompts

Permission prompts must be contextual.

- Microphone: first recording attempt.
- Accessibility: only when auto-paste is enabled.
- Screen/audio capture: only when meeting system audio is enabled.

The UI should say what permission is needed and what action unlocks it. Keep logs out of the main UI.

## Design checks

Before calling any UI work complete, verify:

- Copy is one click.
- Recording state is unmistakable.
- Meeting mode does not crowd dictation mode.
- Settings are findable but not dominant.
- The app does not look like a dashboard.
- The app does not look like a web product.
- No screen asks for an account.
- No screen suggests cloud processing is required.
