#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${ROOT}/dist"
APP_PATH="${DIST}/Walky Talky.app"
DMG_PATH="${DIST}/Walky-Talky-mac.dmg"
TMPDIR="$(mktemp -d)"
STAGING="${TMPDIR}/dmg-staging"
trap 'rm -rf "${TMPDIR}"' EXIT

cd "${ROOT}"
"${ROOT}/scripts/build-app-bundle.sh" >/dev/null

rm -f "${DMG_PATH}"
mkdir -p "${STAGING}"
ditto --norsrc "${APP_PATH}" "${STAGING}/Walky Talky.app"
xattr -cr "${STAGING}/Walky Talky.app" >/dev/null 2>&1 || true
dot_clean -m "${STAGING}/Walky Talky.app" >/dev/null 2>&1 || true
codesign --force --deep --sign - "${STAGING}/Walky Talky.app" >/dev/null
ln -s /Applications "${STAGING}/Applications"

hdiutil create \
  -volname "Walky Talky" \
  -srcfolder "${STAGING}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null
echo "${DMG_PATH}"
