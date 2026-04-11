#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
PKG_PATH="${1:-${DIST_DIR}/AriaRuntime-signed.pkg}"
NOTARY_PROFILE="${ARIA_NOTARY_PROFILE:?Set ARIA_NOTARY_PROFILE to an xcrun notarytool keychain profile.}"

if [[ ! -f "${PKG_PATH}" ]]; then
  echo "Package not found: ${PKG_PATH}" >&2
  exit 1
fi

xcrun notarytool submit "${PKG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${PKG_PATH}"

echo "Notarized package stapled at: ${PKG_PATH}"
