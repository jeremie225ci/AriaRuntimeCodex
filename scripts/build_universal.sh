#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build-universal"
OUTPUT_DIR="${ROOT_DIR}/dist"

rm -rf "${BUILD_DIR}" "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

swift build \
  -c release \
  --arch arm64 \
  --arch x86_64 \
  --scratch-path "${BUILD_DIR}"

copy_product() {
  local product="$1"

  local candidate="${BUILD_DIR}/apple/Products/Release/${product}"
  if [[ ! -x "${candidate}" ]]; then
    echo "Expected binary not found: ${candidate}" >&2
    exit 1
  fi

  cp "${candidate}" "${OUTPUT_DIR}/"
  file "${OUTPUT_DIR}/${product}"
}

copy_product "aria"
copy_product "aria-runtime-daemon"
copy_product "AriaRuntimeApp"

echo
echo "Universal binaries copied to ${OUTPUT_DIR}"
