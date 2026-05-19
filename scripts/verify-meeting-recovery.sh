#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

db="$tmpdir/transcripts.sqlite"
meeting_id="11111111-1111-1111-1111-111111111111"

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

INSERT INTO meeting_segments (
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
  0,
  0,
  60,
  'raw recovered text',
  'Recovered text.',
  'chunk_complete',
  '$tmpdir/chunk-0000.wav'
);
SQL

found="$(sqlite3 "$db" "SELECT DISTINCT meeting_id FROM meeting_segments WHERE meeting_id NOT IN (SELECT id FROM transcripts WHERE type = 'meeting');")"
test "$found" = "$meeting_id"

sqlite3 "$db" "INSERT INTO transcripts (id, type, created_at, duration_seconds, raw_text, polished_text, audio_path, model_used, language, status) VALUES ('$meeting_id', 'meeting', 0, 60, 'raw recovered text', 'Recovered text.', '$tmpdir', 'ggml-base.en.bin', 'en', 'recovered');"
found_after="$(sqlite3 "$db" "SELECT DISTINCT meeting_id FROM meeting_segments WHERE meeting_id NOT IN (SELECT id FROM transcripts WHERE type = 'meeting');")"
test -z "$found_after"

echo "meeting recovery sql verified"

