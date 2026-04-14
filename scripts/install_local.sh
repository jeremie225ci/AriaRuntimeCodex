#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
SOURCE_APP="${DIST_DIR}/Aria Runtime.app"

INSTALL_DIR="${ARIA_RUNTIME_INSTALL_DIR:-$HOME/Applications}"
TARGET_APP="${INSTALL_DIR}/Aria Runtime.app"
LOCAL_BIN_DIR="${ARIA_RUNTIME_BIN_DIR:-$HOME/.local/bin}"
CLI_LINK="${LOCAL_BIN_DIR}/aria"
PERMISSION_WAIT_SECONDS="${ARIA_RUNTIME_PERMISSION_WAIT_SECONDS:-45}"
REBUILD="${ARIA_RUNTIME_REBUILD:-auto}"

if [[ "${REBUILD}" == "1" || "${REBUILD}" == "true" || ! -d "${SOURCE_APP}" ]]; then
  "${ROOT_DIR}/scripts/build_app_bundle.sh"
else
  echo "Using existing app bundle: ${SOURCE_APP}"
  echo "Set ARIA_RUNTIME_REBUILD=1 to rebuild before installing."
fi

mkdir -p "${INSTALL_DIR}"
mkdir -p "${LOCAL_BIN_DIR}"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aria-runtime-install.XXXXXX")"
STAGING_APP="${STAGING_DIR}/Aria Runtime.app"
ditto "${SOURCE_APP}" "${STAGING_APP}"

if [[ -e "${TARGET_APP}" ]]; then
  BACKUP_PATH="${TARGET_APP}.backup-$(date +%Y%m%d%H%M%S)"
  mv "${TARGET_APP}" "${BACKUP_PATH}"
  echo "Previous install moved to: ${BACKUP_PATH}"
fi

mv "${STAGING_APP}" "${TARGET_APP}"
rmdir "${STAGING_DIR}" 2>/dev/null || true

BUNDLE_ARIA="${TARGET_APP}/Contents/MacOS/aria"
chmod +x "${TARGET_APP}/Contents/MacOS/AriaRuntimeApp" "${BUNDLE_ARIA}" "${TARGET_APP}/Contents/MacOS/aria-runtime-daemon"
ln -sfn "${BUNDLE_ARIA}" "${CLI_LINK}"

open "${TARGET_APP}" >/dev/null 2>&1 || true
SETUP_READY=0
if "${BUNDLE_ARIA}" setup >/dev/null 2>&1; then
  SETUP_READY=1
fi

PERMISSIONS_READY=0
for _ in $(seq 1 "${PERMISSION_WAIT_SECONDS}"); do
  HEALTH_OUTPUT="$("${BUNDLE_ARIA}" health 2>/dev/null || true)"
  if [[ "${HEALTH_OUTPUT}" == *'"accessibility_trusted" : true'* ]] && [[ "${HEALTH_OUTPUT}" == *'"screen_recording_trusted" : true'* ]]; then
    PERMISSIONS_READY=1
    break
  fi
  sleep 1
done

echo ""
echo "Aria Runtime installed locally."
echo "App: ${TARGET_APP}"
echo "CLI: ${CLI_LINK}"
if [[ "${PERMISSIONS_READY}" == "1" ]]; then
  echo "Permissions: ready"
else
  echo "Permissions: pending approval in macOS prompts/settings"
fi
if [[ "${SETUP_READY}" == "1" ]]; then
  echo "Codex mode: default profile \`aria\` installed"
else
  echo "Codex mode: rerun \`aria setup\` after install"
fi
echo ""
echo "Next:"
echo "  aria setup status"
echo "  codex"
echo "  use Aria for a visual task"
