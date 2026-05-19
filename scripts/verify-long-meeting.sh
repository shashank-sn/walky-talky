#!/usr/bin/env bash
set -euo pipefail

minutes="${1:-60}"
chunk_seconds="${CHUNK_SECONDS:-60}"
audio_device="${AUDIO_DEVICE:-:2}"
root="${HOME}/Library/Application Support/Walky Talky"
run_id="$(date +%Y%m%d-%H%M%S)"
run_dir="${root}/verification/meeting-${run_id}"
db="${run_dir}/transcripts.sqlite"
meeting_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
whisper="${root}/whisper"
model="${root}/models/ggml-base.en.bin"
export_md="${run_dir}/walky-talky-meeting-${run_id}.md"
export_txt="${run_dir}/walky-talky-meeting-${run_id}.txt"

mkdir -p "${run_dir}/chunks" "${run_dir}/transcripts"

if [[ ! -x "$whisper" ]]; then
  echo "missing whisper runtime at $whisper" >&2
  exit 1
fi

if [[ ! -f "$model" ]]; then
  echo "missing model at $model" >&2
  exit 1
fi

sqlite3 "$db" <<SQL
CREATE TABLE transcripts (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  created_at REAL NOT NULL,
  duration_seconds REAL NOT NULL,
  raw_text TEXT NOT NULL,
  polished_text TEXT NOT NULL,
  audio_path TEXT,
  model_used TEXT NOT NULL,
  source_app TEXT,
  language TEXT NOT NULL DEFAULT 'en',
  status TEXT NOT NULL
);

CREATE INDEX idx_transcripts_type_created_at
ON transcripts(type, created_at DESC);

CREATE TABLE meeting_segments (
  meeting_id TEXT NOT NULL,
  segment_index INTEGER NOT NULL,
  start_time REAL NOT NULL,
  end_time REAL NOT NULL,
  raw_text TEXT NOT NULL,
  polished_text TEXT NOT NULL,
  status TEXT NOT NULL,
  audio_chunk_path TEXT,
  PRIMARY KEY (meeting_id, segment_index)
);
SQL

transcribe_chunk() {
  local index="$1"
  local chunk="$2"
  local start="$3"
  local end="$4"
  local out="${run_dir}/transcripts/chunk-$(printf '%04d' "$index").txt"
  local text

  if "$whisper" -m "$model" -f "$chunk" -nt -np > "$out" 2>"${out}.err"; then
    text="$(tr '\n' ' ' < "$out" | sed 's/[[:space:]]\\+/ /g; s/^ //; s/ $//')"
  else
    text=""
  fi

  if [[ -z "$text" ]]; then
    text="[no speech detected in chunk ${index}]"
  fi

  sqlite3 "$db" <<SQL
INSERT OR REPLACE INTO meeting_segments (
  meeting_id,
  segment_index,
  start_time,
  end_time,
  raw_text,
  polished_text,
  status,
  audio_chunk_path
) VALUES (
  '$meeting_id',
  $index,
  $start,
  $end,
  $(printf '%s' "$text" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  $(printf '%s' "$text" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  'chunk_complete',
  '$chunk'
);
SQL
}

total_chunks="$minutes"
pids=()
start_epoch="$(date +%s)"

echo "meeting_id=$meeting_id"
echo "run_dir=$run_dir"
echo "minutes=$minutes chunk_seconds=$chunk_seconds audio_device=$audio_device"

for ((index=0; index<total_chunks; index++)); do
  chunk="${run_dir}/chunks/chunk-$(printf '%04d' "$index").wav"
  start=$((index * chunk_seconds))
  end=$(((index + 1) * chunk_seconds))

  (sleep 5; say "Walky Talky verification chunk ${index}") >/dev/null 2>&1 &
  speech_pid="$!"

  ffmpeg \
    -nostdin \
    -hide_banner \
    -loglevel error \
    -f avfoundation \
    -i "$audio_device" \
    -t "$chunk_seconds" \
    -ar 16000 \
    -ac 1 \
    -c:a pcm_s16le \
    "$chunk"

  wait "$speech_pid" 2>/dev/null || true
  transcribe_chunk "$index" "$chunk" "$start" "$end" &
  pids+=("$!")

  completed=$((index + 1))
  sqlite_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM meeting_segments;")"
  echo "recorded chunk ${completed}/${total_chunks}; transcribed_so_far=${sqlite_count}"

  if [[ "$completed" -eq 30 ]]; then
    chunk_count="$(find "${run_dir}/chunks" -name 'chunk-*.wav' | wc -l | tr -d ' ')"
    if [[ "$chunk_count" -lt 30 ]]; then
      echo "30-minute checkpoint failed: only $chunk_count chunks" >&2
      exit 1
    fi
    echo "30-minute checkpoint ok: $chunk_count chunks recorded"
  fi
done

for pid in "${pids[@]}"; do
  wait "$pid"
done

segment_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM meeting_segments WHERE meeting_id = '$meeting_id';")"
if [[ "$segment_count" -ne "$total_chunks" ]]; then
  echo "expected $total_chunks segments, found $segment_count" >&2
  exit 1
fi

body="$(sqlite3 "$db" "SELECT '[' || printf('%02d:%02d', start_time / 60, start_time % 60) || '-' || printf('%02d:%02d', end_time / 60, end_time % 60) || '] ' || polished_text FROM meeting_segments WHERE meeting_id = '$meeting_id' ORDER BY segment_index;" | sed 's/$/\
/')"
duration_seconds=$((minutes * chunk_seconds))

cat > "$export_md" <<EOF
# Walky Talky Meeting Verification

- meeting_id: $meeting_id
- duration_seconds: $duration_seconds
- chunks: $segment_count
- audio_device: $audio_device
- model: $(basename "$model")

$body
EOF

printf '%s\n' "$body" > "$export_txt"

sqlite3 "$db" <<SQL
INSERT OR REPLACE INTO transcripts (
  id,
  type,
  created_at,
  duration_seconds,
  raw_text,
  polished_text,
  audio_path,
  model_used,
  language,
  status
) VALUES (
  '$meeting_id',
  'meeting',
  $start_epoch,
  $duration_seconds,
  $(printf '%s' "$body" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  $(printf '%s' "$body" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  '${run_dir}/chunks',
  '$(basename "$model")',
  'en',
  'verification_complete'
);
SQL

echo "60-minute verification ok"
echo "segments=$segment_count"
echo "export_md=$export_md"
echo "export_txt=$export_txt"
echo "db=$db"

