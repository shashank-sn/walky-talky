#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Walky Talky.app"
APP_DIR="${ROOT}/dist/${APP_NAME}"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

cd "${ROOT}"
swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp ".build/release/WalkyTalky" "${MACOS}/WalkyTalky"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"
if [[ -f "Resources/WalkyTalkyIcon.icns" ]]; then
  cp "Resources/WalkyTalkyIcon.icns" "${RESOURCES}/WalkyTalkyIcon.icns"
fi
for logo in WalkyTalkyLogoBlack.png WalkyTalkyLogoWhite.png WalkyTalkyLogoTemplate.png; do
  if [[ -f "Resources/${logo}" ]]; then
    cp "Resources/${logo}" "${RESOURCES}/${logo}"
  fi
done

chmod +x "${MACOS}/WalkyTalky"

xattr -cr "${APP_DIR}" >/dev/null 2>&1 || true
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "${APP_DIR}"
