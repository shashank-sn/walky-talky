# auto-paste failure matrix

auto-paste is a core product path. do not reduce it to a single global `cmd+v`.

## required sequence

1. capture the frontmost non-walky app when dictation starts.
2. copy the final transcript to the pasteboard.
3. resolve the target by captured pid first, captured bundle id second.
4. paste only through direct accessibility insertion into the focused ui element.
5. update the visible status only after a verified direct insertion, or show a concrete copied-but-not-pasted detail.

## covered failure modes

- target app is slow to activate: activate target and wait before paste.
- automation permission is missing or stale after reinstall: direct accessibility insertion does not depend on system events.
- target pid is stale: fall back only to the captured bundle id.
- target app cannot be resolved: leave transcript copied and report that the original target app was unavailable.
- focused field does not accept accessibility value writes: status remains copied with failure detail instead of pretending paste worked.
- keyboard-event paste paths are intentionally not used in production because smoke tests showed they can report success without changing the focused field.

## manual regression checklist

- textedit plain text field.
- safari address bar.
- safari/web text editor.
- notes body field.
- messages compose field.
- focused app closed before transcription completes.
- target pid stale with no bundle id fallback.
- accessibility granted but automation denied.
- target app activation is slow.

## verified smoke cases

- captured pid points to a focused editable cocoa text view: inserted through accessibility.
- captured pid is stale but captured bundle id resolves to the same app: inserted through accessibility.
- captured pid is stale and no bundle id is available: does not insert and reports unavailable.
- system events and cg keyboard event routes were tested and removed from production because they returned success while the target text did not change.
