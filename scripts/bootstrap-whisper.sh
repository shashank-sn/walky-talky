#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT="${HOME}/Library/Application Support/Walky Talky"
WHISPER_REPO="${ROOT}/vendor/whisper.cpp"
WHISPER_REMOTE="https://github.com/ggml-org/whisper.cpp.git"

if ! command -v cmake >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install cmake
  else
    echo "cmake is required. install cmake, then rerun this script." >&2
    exit 1
  fi
fi

mkdir -p "${ROOT}/vendor"

if [[ ! -d "${WHISPER_REPO}/.git" ]]; then
  git clone --depth 1 "${WHISPER_REMOTE}" "${WHISPER_REPO}"
else
  git -C "${WHISPER_REPO}" pull --ff-only
fi

cmake -S "${WHISPER_REPO}" -B "${WHISPER_REPO}/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "${WHISPER_REPO}/build" -j --config Release

mkdir -p "${APP_SUPPORT}/models" "${APP_SUPPORT}/lib"

cp "${WHISPER_REPO}/build/bin/whisper-cli" "${APP_SUPPORT}/whisper"
cp "${WHISPER_REPO}/build/src/libwhisper.dylib" "${APP_SUPPORT}/lib/"
cp "${WHISPER_REPO}/build/ggml/src/libggml.dylib" "${APP_SUPPORT}/lib/"
cp "${WHISPER_REPO}/build/ggml/src/libggml-base.dylib" "${APP_SUPPORT}/lib/"
cp "${WHISPER_REPO}/build/ggml/src/libggml-cpu.dylib" "${APP_SUPPORT}/lib/"
cp "${WHISPER_REPO}/build/ggml/src/ggml-blas/libggml-blas.dylib" "${APP_SUPPORT}/lib/"
cp "${WHISPER_REPO}/build/ggml/src/ggml-metal/libggml-metal.dylib" "${APP_SUPPORT}/lib/"
chmod +x "${APP_SUPPORT}/whisper"

install_name_tool -add_rpath "${APP_SUPPORT}/lib" "${APP_SUPPORT}/whisper" 2>/dev/null || true

if [[ ! -f "${APP_SUPPORT}/models/ggml-base.en.bin" ]]; then
  "${WHISPER_REPO}/models/download-ggml-model.sh" base.en "${APP_SUPPORT}/models"
fi

"${APP_SUPPORT}/whisper" \
  -m "${APP_SUPPORT}/models/ggml-base.en.bin" \
  -f "${WHISPER_REPO}/samples/jfk.wav" \
  -nt \
  -np

