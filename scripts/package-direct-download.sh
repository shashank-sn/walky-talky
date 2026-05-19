#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${ROOT}/dist/Walky Talky.app"
ZIP_PATH="${ROOT}/dist/Walky-Talky-mac.zip"
TMPDIR="$(mktemp -d)"
TMP_APP="${TMPDIR}/Walky Talky.app"
trap 'rm -rf "${TMPDIR}"' EXIT

cd "${ROOT}"
"${ROOT}/scripts/build-app-bundle.sh" >/dev/null
ditto --norsrc "${APP_PATH}" "${TMP_APP}"
xattr -cr "${TMP_APP}" >/dev/null 2>&1 || true
dot_clean -m "${TMP_APP}" >/dev/null 2>&1 || true
codesign --force --deep --sign - "${TMP_APP}" >/dev/null

rm -f "${ZIP_PATH}"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "${TMP_APP}" "${ZIP_PATH}"

echo "${ZIP_PATH}"
