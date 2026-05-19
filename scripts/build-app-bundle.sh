#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="Walky Talky.app"
DIST_ROOT="${WALKY_DIST_ROOT:-${HOME}/Library/Caches/WalkyTalkyBuild/dist}"
APP_DIR="${DIST_ROOT}/${APP_NAME}"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

cd "${ROOT}"
swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

COPYFILE_DISABLE=1 cp -X ".build/release/WalkyTalky" "${MACOS}/WalkyTalky"
COPYFILE_DISABLE=1 cp -X "Resources/Info.plist" "${CONTENTS}/Info.plist"
if [[ -f "Resources/WalkyTalkyIcon.icns" ]]; then
  COPYFILE_DISABLE=1 cp -X "Resources/WalkyTalkyIcon.icns" "${RESOURCES}/WalkyTalkyIcon.icns"
fi
for logo in WalkyTalkyLogoBlack.png WalkyTalkyLogoWhite.png WalkyTalkyLogoTemplate.png; do
  if [[ -f "Resources/${logo}" ]]; then
    COPYFILE_DISABLE=1 cp -X "Resources/${logo}" "${RESOURCES}/${logo}"
  fi
done

chmod +x "${MACOS}/WalkyTalky"

"${SCRIPT_DIR}/sign-app.sh" "${APP_DIR}"

echo "${APP_DIR}"
