#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${ROOT}/dist/Walky Talky.app"
ZIP_PATH="${ROOT}/dist/Walky-Talky-mac.zip"
TMPDIR="$(mktemp -d)"
BUILD_DIST="${TMPDIR}/build-dist"
TMP_APP="${TMPDIR}/Walky Talky.app"
trap 'rm -rf "${TMPDIR}"' EXIT

cd "${ROOT}"
mkdir -p "${ROOT}/dist"
WALKY_DIST_ROOT="${BUILD_DIST}" "${ROOT}/scripts/build-app-bundle.sh" >/dev/null
APP_PATH="${BUILD_DIST}/Walky Talky.app"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "${APP_PATH}" "${TMP_APP}"
"${ROOT}/scripts/sign-app.sh" "${TMP_APP}"

rm -f "${ZIP_PATH}"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "${TMP_APP}" "${ZIP_PATH}"

echo "${ZIP_PATH}"
