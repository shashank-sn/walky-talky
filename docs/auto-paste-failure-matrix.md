# auto-paste failure matrix

auto-paste is a core product path. do not reduce it to a single global `cmd+v`.

## required sequence

1. capture the frontmost non-walky app when dictation starts.
2. copy the final transcript to the pasteboard.
3. resolve the target by pid first, bundle id second, current frontmost app third.
4. attempt paste in this order:
   - accessibility insert into the focused ui element.
   - system events paste scoped to the target process id.
   - cg keyboard event scoped to the target process id.
   - global cg keyboard event as the last fallback.
5. update the visible status with the method that worked, or the concrete missing permission/failure.

## covered failure modes

- target app is slow to activate: activate target and wait before paste.
- automation permission is missing or stale after reinstall: accessibility insert and cg event fallbacks do not depend on system events.
- target pid is stale: fall back to bundle id, then frontmost regular app.
- focused field does not accept accessibility value writes: fall through to keyboard paste.
- system events cannot find the process: fall through to cg keyboard paste.
- global paste has no useful focused target: status remains copied with failure detail instead of pretending paste worked.

## manual regression checklist

- textedit plain text field.
- safari address bar.
- safari/web text editor.
- notes body field.
- messages compose field.
- focused app closed before transcription completes.
- accessibility granted but automation denied.
- automation granted but target app activation is slow.
