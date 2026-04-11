#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${ARIA_RUNTIME_VERSION:-1.0.0}"
BUILD_NUMBER="${ARIA_RUNTIME_BUILD:-1}"
"${ROOT_DIR}/scripts/build_universal.sh"

DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/Aria Runtime.app"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp "${DIST_DIR}/AriaRuntimeApp" "${APP_BUNDLE}/Contents/MacOS/AriaRuntimeApp"
cp "${DIST_DIR}/aria" "${APP_BUNDLE}/Contents/MacOS/aria"
cp "${DIST_DIR}/aria-runtime-daemon" "${APP_BUNDLE}/Contents/MacOS/aria-runtime-daemon"
cp "${ROOT_DIR}/packaging/AriaRuntimeApp-Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_BUNDLE}/Contents/Info.plist"

chmod +x "${APP_BUNDLE}/Contents/MacOS/AriaRuntimeApp"
chmod +x "${APP_BUNDLE}/Contents/MacOS/aria"
chmod +x "${APP_BUNDLE}/Contents/MacOS/aria-runtime-daemon"

if [[ "${ARIA_RUNTIME_ADHOC_CODESIGN:-1}" == "1" ]]; then
  codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "App bundle created at: ${APP_BUNDLE}"
