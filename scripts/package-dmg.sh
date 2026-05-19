#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${ROOT}/dist"
APP_PATH="${DIST}/Walky Talky.app"
DMG_PATH="${DIST}/Walky-Talky-mac.dmg"
TMPDIR="$(mktemp -d)"
STAGING="${TMPDIR}/dmg-staging"
RW_DMG="${TMPDIR}/Walky-Talky-rw.dmg"
trap 'rm -rf "${TMPDIR}"' EXIT

cd "${ROOT}"
"${ROOT}/scripts/build-app-bundle.sh" >/dev/null

rm -f "${DMG_PATH}"
mkdir -p "${STAGING}"
mkdir -p "${STAGING}/.background"
"${ROOT}/scripts/generate-dmg-background.swift" "${STAGING}/.background/dmg-background.png"
ditto --norsrc "${APP_PATH}" "${STAGING}/Walky Talky.app"
xattr -cr "${STAGING}/Walky Talky.app" >/dev/null 2>&1 || true
dot_clean -m "${STAGING}/Walky Talky.app" >/dev/null 2>&1 || true
codesign --force --deep --sign - "${STAGING}/Walky Talky.app" >/dev/null
ln -s /Applications "${STAGING}/Applications"

hdiutil create \
  -volname "Walky Talky" \
  -srcfolder "${STAGING}" \
  -ov \
  -format UDRW \
  "${RW_DMG}" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}")"
VOLUME="$(printf '%s\n' "${MOUNT_OUTPUT}" | awk -F '\t' '/\/Volumes\/Walky Talky/ {print $NF; exit}')"
if [[ -z "${VOLUME}" ]]; then
  VOLUME="/Volumes/Walky Talky"
fi

osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
  tell disk "Walky Talky"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 880, 600}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:dmg-background.png"
    set position of item "Walky Talky.app" of container window to {190, 250}
    set position of item "Applications" of container window to {570, 250}
    update without registering applications
    delay 0.5
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "${VOLUME}" >/dev/null
hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
echo "${DMG_PATH}"
