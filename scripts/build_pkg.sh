#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${ARIA_RUNTIME_VERSION:-1.0.0}"
"${ROOT_DIR}/scripts/build_app_bundle.sh"

DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/Aria Runtime.app"
PKG_PATH="${DIST_DIR}/AriaRuntime.pkg"

rm -rf "${PKG_PATH}"

pkgbuild \
  --component "${APP_BUNDLE}" \
  --identifier "com.getariaos.runtime.pkg" \
  --version "${VERSION}" \
  --install-location "/Applications" \
  --scripts "${ROOT_DIR}/packaging/scripts" \
  "${PKG_PATH}"

echo "Installer package created at: ${PKG_PATH}"
