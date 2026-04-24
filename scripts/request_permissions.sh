#!/usr/bin/env bash
set -euo pipefail

# Start macOS permission onboarding for Aria Runtime.
#
# macOS does not allow a script to grant Accessibility or Screen Recording
# automatically. This script does everything that is allowed:
#   1. optionally reset stale TCC decisions
#   2. launch Aria Runtime so macOS sees the real app bundle
#   3. ask Aria Runtime to request permissions
#   4. open the exact Privacy & Security panes
#   5. wait while the user flips the toggles manually

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${ARIA_RUNTIME_BUNDLE_ID:-com.getariaos.runtime}"
WAIT_SECONDS="${ARIA_RUNTIME_PERMISSION_WAIT_SECONDS:-180}"
RESET_TCC=0

usage() {
  cat <<EOF
Usage:
  scripts/request_permissions.sh [--reset] [--wait SECONDS]

Options:
  --reset        Reset existing macOS TCC decisions first, then request again.
  --wait N       Poll permission status for N seconds. Default: ${WAIT_SECONDS}.

Environment:
  ARIA_APP       Override path to "Aria Runtime.app".
  ARIA_CLI       Override path to the aria CLI.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset)
      RESET_TCC=1
      shift
      ;;
    --wait)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --wait" >&2
        exit 2
      fi
      WAIT_SECONDS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

find_first_existing() {
  local candidate
  for candidate in "$@"; do
    if [[ -n "${candidate}" && -e "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

APP_PATH="${ARIA_APP:-}"
if [[ -z "${APP_PATH}" ]]; then
  APP_PATH="$(find_first_existing \
    "${HOME}/Applications/Aria Runtime.app" \
    "/Applications/Aria Runtime.app" \
    "${ROOT_DIR}/dist/Aria Runtime.app" \
  || true)"
fi

CLI_PATH="${ARIA_CLI:-}"
if [[ -z "${CLI_PATH}" ]]; then
  CLI_PATH="$(find_first_existing \
    "${HOME}/.local/bin/aria" \
    "${APP_PATH}/Contents/MacOS/aria" \
    "${ROOT_DIR}/.build/debug/aria" \
    "${ROOT_DIR}/dist/aria" \
  || true)"
fi

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  cat >&2 <<EOF
Aria Runtime.app was not found.

Install it first:
  cd "${ROOT_DIR}"
  ./scripts/install_local.sh

Or pass:
  ARIA_APP="/path/to/Aria Runtime.app" scripts/request_permissions.sh
EOF
  exit 1
fi

if [[ -z "${CLI_PATH}" || ! -x "${CLI_PATH}" ]]; then
  CLI_PATH="${APP_PATH}/Contents/MacOS/aria"
fi

echo "Aria app: ${APP_PATH}"
echo "Aria CLI: ${CLI_PATH}"
echo "Bundle id: ${BUNDLE_ID}"
echo ""

if [[ "${RESET_TCC}" == "1" ]]; then
  echo "Resetting previous macOS permission decisions for ${BUNDLE_ID}..."
  tccutil reset Accessibility "${BUNDLE_ID}" >/dev/null 2>&1 || true
  tccutil reset ScreenCapture "${BUNDLE_ID}" >/dev/null 2>&1 || true
fi

echo "Launching Aria Runtime..."
open "${APP_PATH}"

sleep 1

request_permissions() {
  if [[ -x "${CLI_PATH}" ]]; then
    "${CLI_PATH}" permissions request >/dev/null 2>&1 || true
  fi
}

permission_status() {
  if [[ -x "${CLI_PATH}" ]]; then
    "${CLI_PATH}" setup status 2>/dev/null || true
  fi
}

has_accessibility() {
  [[ "$(permission_status)" == *'"accessibility_trusted" : true'* ]]
}

has_screen_recording() {
  [[ "$(permission_status)" == *'"screen_recording_trusted" : true'* ]]
}

wait_until_accessibility_ready() {
  local seconds="$1"
  local deadline=$((SECONDS + seconds))
  while (( SECONDS < deadline )); do
    if has_accessibility; then
      echo ""
      echo "✅ Accessibility is enabled."
      return 0
    fi
    request_permissions
    printf '.'
    sleep 3
  done
  echo ""
  return 1
}

echo "Requesting Accessibility prompt first..."
request_permissions
if ! has_accessibility; then
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
  cat <<'EOF'

ACTION REQUIRED NOW:
  In Accessibility, enable "Aria Runtime".

macOS often shows only one privacy prompt at a time. The script will ask for
Screen Recording after Accessibility is accepted.
EOF
  wait_until_accessibility_ready "$(( WAIT_SECONDS < 90 ? WAIT_SECONDS : 90 ))" || true
fi

echo ""
echo "Requesting Screen Recording prompt..."
# Reopen the app and request again after Accessibility, otherwise macOS can
# suppress the Screen Recording prompt while the Accessibility prompt is active.
open "${APP_PATH}" || true
sleep 1
request_permissions
sleep 1
request_permissions

echo "Opening Screen Recording privacy pane..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" || true

cat <<'EOF'

ACTION REQUIRED:
  1. In Screen Recording, enable "Aria Runtime".
  2. If macOS asks to quit/reopen Aria Runtime, accept.
  3. If no popup appears, use the open Screen Recording pane and toggle
     "Aria Runtime" manually.

This cannot be auto-approved by a script; Apple requires the user click the toggles.

Waiting for permissions...
EOF

deadline=$((SECONDS + WAIT_SECONDS))
while (( SECONDS < deadline )); do
  status="$(permission_status)"

  if [[ "${status}" == *'"accessibility_trusted" : true'* ]] \
    && [[ "${status}" == *'"screen_recording_trusted" : true'* ]]; then
    echo ""
    echo "✅ Aria Runtime permissions are ready."
    echo "Relaunching Aria Runtime once..."
    osascript -e 'quit app "Aria Runtime"' >/dev/null 2>&1 || true
    sleep 1
    open "${APP_PATH}" || true
    exit 0
  fi

  if [[ "${status}" != *'"screen_recording_trusted" : true'* ]]; then
    request_permissions
  fi
  printf '.'
  sleep 3
done

echo ""
echo "Still waiting or not accepted yet."
echo "Check manually with:"
echo "  \"${CLI_PATH}\" setup status"
echo ""
echo "If the toggles were enabled, quit and reopen Aria Runtime:"
echo "  osascript -e 'quit app \"Aria Runtime\"'"
echo "  open \"${APP_PATH}\""
