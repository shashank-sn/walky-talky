# Walky Talky Whisper

Whisper is the operating manual for how Walky Talky behaves internally: recording, transcription, indexing, memory, deletion, and durability. This is the system contract behind the small UI.

The product can look simple only if the operating rules underneath are strict.

## Core contract

Walky Talky is local-first.

That means:

- audio stays on the Mac
- transcripts stay on the Mac
- models stay on the Mac
- processing runs on the Mac
- logs stay on the Mac
- no analytics events are emitted
- no cloud transcription exists in the default path
- no server is required for any core feature

If a future feature breaks this contract, it must be explicitly optional and visibly separate from the default app behavior.

## Local filesystem

Use:

```text
~/Library/Application Support/Walky Talky/
  models/
  recordings/
    dictation/
    meetings/
  transcripts.sqlite
  settings.json
  logs/
```

No other storage location should become the silent source of truth.

## Database role

`transcripts.sqlite` is the source of truth for transcript metadata, text, status, and segment records.

It should store:

- id
- type
- created_at
- duration_seconds
- raw_text
- polished_text
- audio_path
- model_used
- source_app
- language
- status

For meetings it should also store:

- meeting_id
- segment_index
- start_time
- end_time
- raw_text
- polished_text
- segment_status
- audio_chunk_path

The database should know enough to recover from interruption without guessing from loose files.

## Recording lifecycle

### Dictation

Dictation is short and immediate.

Lifecycle:

1. User starts recording with hold or latch shortcut.
2. App writes microphone audio to a temporary local file.
3. App stops recording.
4. App creates a pending transcript row.
5. App sends the audio file to local `whisper.cpp`.
6. App stores raw transcript.
7. App runs deterministic polishing.
8. App stores polished transcript.
9. App copies polished transcript if enabled.
10. App deletes or keeps audio according to dictation retention settings.

Default: delete dictation audio after successful transcription.

### Meeting

Meeting recording is long-running and chunked.

Lifecycle:

1. User starts meeting recording.
2. App creates a meeting row.
3. App writes fixed-length audio chunks.
4. Each completed chunk is queued for transcription.
5. Each segment is saved as soon as transcription finishes.
6. Meeting can show partial progress before it ends.
7. On stop, app finalizes the active chunk.
8. App stitches segments into a complete transcript.
9. App stores final meeting transcript.
10. App keeps or deletes audio according to meeting retention settings.

Default: keep meeting audio until the user deletes it.

## Chunking rules

Meeting audio must be chunked. A 60-minute meeting must not be treated as one giant dictation file.

Recommended default:

- 30-60 second chunks
- sequential segment indexes
- durable database write after each completed segment
- active chunk flushed on stop
- failed chunk marked failed, not silently discarded

Chunking exists to protect:

- responsiveness
- memory use
- crash recovery
- progress visibility
- reprocessing

## Transcription engine

Use local `whisper.cpp`.

Initial integration:

- shell out to a bundled or user-installed `whisper.cpp` binary
- pass local audio path
- capture stdout/stderr
- parse result into raw transcript text
- store model name and command status

Later integration can move closer to a native library only if the shell-out path is already proven.

## Model policy

Models live outside the app binary under:

```text
~/Library/Application Support/Walky Talky/models/
```

Recommended tiers:

- `base.en`: smallest and fastest
- `small.en`: default dictation model
- `medium.en`: optional meeting-quality model

The app should clearly handle:

- model missing
- model too slow
- model deleted
- model path invalid
- model changed between jobs

Do not silently download large models without an explicit user action.

## Polishing pipeline

Always keep both:

- raw transcript
- polished transcript

Deterministic cleanup runs first:

- trim whitespace
- normalize repeated spaces
- fix spacing around punctuation
- capitalize sentence starts
- convert spoken punctuation
- conservatively remove obvious filler
- remove obvious repeated fragments only when confidence is high

The pipeline must not aggressively rewrite meaning.

Local LLM cleanup is optional. The app may use an installed local runtime such as Ollama or llama.cpp, but it must:

- preserve raw transcript
- be disableable
- show that a local model is being used
- never become required for baseline dictation

## Audio retention

Dictation default:

- delete audio after successful transcription

Dictation options:

- delete immediately after transcription
- keep for 24 hours
- keep until manual deletion

Meeting default:

- keep audio until manual deletion

Meeting options:

- keep meeting audio
- delete after transcription
- delete manually

Deletion must remove the file and update the database state. Failed deletion should be visible as a local error, not silently ignored.

## Cleanup behavior

Cleanup is conservative. The app should never delete user-valuable artifacts just because a background job is confused.

Safe cleanup:

- delete dictation audio after successful transcription when policy says so
- delete temporary files older than a defined threshold when no database job references them
- delete failed partial files only when they are not referenced by a pending job
- vacuum or compact database only through an explicit maintenance path

Unsafe cleanup:

- deleting meeting audio by default
- deleting raw transcripts
- deleting model files automatically
- deleting failed chunks before the user can retry
- using filename guessing as the only deletion criterion

## Job states

Use explicit job states.

Suggested states:

- `recording`
- `pending_transcription`
- `transcribing`
- `transcribed`
- `polishing`
- `complete`
- `failed`
- `deleted_audio`
- `cancelled`

Meeting segment states:

- `chunk_recording`
- `chunk_pending`
- `chunk_transcribing`
- `chunk_complete`
- `chunk_failed`

State transitions should be durable. If the app quits, it should resume or clearly show what is unfinished.

## Error behavior

Errors should be plain.

Important errors:

- microphone permission denied
- accessibility permission denied
- screen/audio capture unavailable
- shortcut conflict
- model missing
- model too slow
- transcription failed
- disk full
- audio file missing
- database write failed

Main UI error format:

```text
What happened
What to do next
```

Detailed command output belongs in local logs, not the popover.

## Logs

Logs are local debugging artifacts.

They may include:

- job id
- model name
- duration
- command exit code
- local file path
- error category

They must not include:

- analytics events
- remote telemetry
- uploaded audio
- uploaded transcripts

## Permissions

Permissions are requested only when needed.

- Microphone: first recording.
- Accessibility: enabling auto-paste.
- Screen/audio capture: enabling system audio for meetings.

Do not request all permissions on first launch.

## Recovery

On launch, the app should inspect unfinished work.

Recovery rules:

- pending dictation transcription can resume if audio exists
- failed dictation can show retry if audio exists
- meeting segments already completed remain valid
- active meeting chunks from a crash are marked recoverable or failed
- final meeting stitching can be rerun from completed segments

Never discard completed transcript segments during recovery.

## Non-goals

Whisper must reject:

- cloud transcription as the default path
- analytics
- accounts
- billing
- team workspaces
- web dashboards
- automatic sharing
- mandatory local LLM rewriting
- fake v1 speaker diarization without a real local diarization model
- v1 real-time streaming transcript UI

## Implementation check

Before shipping any change, check:

- Does it keep audio local?
- Does it keep transcripts local?
- Does it preserve raw text?
- Does it preserve crash recovery?
- Does it respect audio retention settings?
- Does it avoid silent destructive cleanup?
- Does it keep dictation fast?
- Does it keep meetings chunked?
- Does it avoid dashboard bloat?
- Does it avoid cloud, account, analytics, and billing paths?
