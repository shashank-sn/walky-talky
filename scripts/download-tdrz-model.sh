#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT="${HOME}/Library/Application Support/Walky Talky"
WHISPER_REPO="${ROOT}/vendor/whisper.cpp"

if [[ ! -x "${WHISPER_REPO}/models/download-ggml-model.sh" ]]; then
  echo "whisper.cpp is missing. run ./scripts/bootstrap-whisper.sh first." >&2
  exit 1
fi

mkdir -p "${APP_SUPPORT}/models"

if [[ ! -f "${APP_SUPPORT}/models/ggml-small.en-tdrz.bin" ]]; then
  "${WHISPER_REPO}/models/download-ggml-model.sh" small.en-tdrz "${APP_SUPPORT}/models"
fi

ls -lh "${APP_SUPPORT}/models/ggml-small.en-tdrz.bin"
