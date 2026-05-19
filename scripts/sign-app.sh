#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?usage: sign-app.sh <app-path>}"
SIGN_IDENTITY="${WALKY_CODESIGN_IDENTITY:-Walky Talky Local Code Signing}"
SIGN_KEYCHAIN="${WALKY_CODESIGN_KEYCHAIN:-${HOME}/Library/Keychains/walky-talky-build.keychain-db}"
SIGN_KEYCHAIN_PASSWORD="${WALKY_CODESIGN_KEYCHAIN_PASSWORD:-walky-local-build}"

strip_metadata() {
  local path="$1"

  find "${path}" -name '._*' -delete 2>/dev/null || true
  dot_clean -m "${path}" >/dev/null 2>&1 || true

  xattr -cr "${path}" >/dev/null 2>&1 || true
  xattr -d com.apple.FinderInfo "${path}" >/dev/null 2>&1 || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "${path}" >/dev/null 2>&1 || true
  xattr -d com.apple.provenance "${path}" >/dev/null 2>&1 || true
  xattr -dr com.apple.FinderInfo "${path}" >/dev/null 2>&1 || true
  xattr -dr 'com.apple.fileprovider.fpfs#P' "${path}" >/dev/null 2>&1 || true
  xattr -dr com.apple.provenance "${path}" >/dev/null 2>&1 || true
}

strip_metadata "${APP_PATH}"

if [[ -f "${SIGN_KEYCHAIN}" ]] && security find-identity -v -p codesigning "${SIGN_KEYCHAIN}" | grep -F "${SIGN_IDENTITY}" >/dev/null 2>&1; then
  security unlock-keychain -p "${SIGN_KEYCHAIN_PASSWORD}" "${SIGN_KEYCHAIN}" >/dev/null 2>&1 || true
  SIGN_HASH="$(security find-identity -v -p codesigning "${SIGN_KEYCHAIN}" | awk -v name="${SIGN_IDENTITY}" 'index($0, name) {print $2; exit}')"
  codesign --force --deep --keychain "${SIGN_KEYCHAIN}" --sign "${SIGN_HASH}" "${APP_PATH}" >/dev/null
elif security find-identity -v -p codesigning | grep -F "${SIGN_IDENTITY}" >/dev/null 2>&1; then
  codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_PATH}" >/dev/null
else
  codesign --force --deep --sign - "${APP_PATH}" >/dev/null 2>&1 || true
fi
