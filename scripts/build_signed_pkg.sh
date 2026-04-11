#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
UNSIGNED_PKG="${DIST_DIR}/AriaRuntime-unsigned.pkg"
SIGNED_PKG="${DIST_DIR}/AriaRuntime-signed.pkg"
APP_BUNDLE="${DIST_DIR}/Aria Runtime.app"
VERSION="${ARIA_RUNTIME_VERSION:-1.0.0}"
APP_SIGN_IDENTITY="${ARIA_CODESIGN_APP_IDENTITY:?Set ARIA_CODESIGN_APP_IDENTITY to your Developer ID Application certificate.}"
INSTALLER_SIGN_IDENTITY="${ARIA_CODESIGN_INSTALLER_IDENTITY:?Set ARIA_CODESIGN_INSTALLER_IDENTITY to your Developer ID Installer certificate.}"

"${ROOT_DIR}/scripts/build_app_bundle.sh"

codesign --force --timestamp --options runtime --sign "${APP_SIGN_IDENTITY}" "${APP_BUNDLE}/Contents/MacOS/aria"
codesign --force --timestamp --options runtime --sign "${APP_SIGN_IDENTITY}" "${APP_BUNDLE}/Contents/MacOS/aria-runtime-daemon"
codesign --force --timestamp --options runtime --sign "${APP_SIGN_IDENTITY}" "${APP_BUNDLE}/Contents/MacOS/AriaRuntimeApp"
codesign --force --timestamp --options runtime --sign "${APP_SIGN_IDENTITY}" "${APP_BUNDLE}"

rm -rf "${UNSIGNED_PKG}" "${SIGNED_PKG}"

pkgbuild \
  --component "${APP_BUNDLE}" \
  --identifier "com.getariaos.runtime.pkg" \
  --version "${VERSION}" \
  --install-location "/Applications" \
  --scripts "${ROOT_DIR}/packaging/scripts" \
  "${UNSIGNED_PKG}"

productsign \
  --sign "${INSTALLER_SIGN_IDENTITY}" \
  "${UNSIGNED_PKG}" \
  "${SIGNED_PKG}"

echo "Signed installer package created at: ${SIGNED_PKG}"
