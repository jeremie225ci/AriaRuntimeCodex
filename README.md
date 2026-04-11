# Aria Runtime Codex

Aria Runtime Codex is a standalone macOS product that gives Codex local machine powers without shipping the legacy Linux monorepo or a remote Aria brain.

## Product Shape

- `Codex` remains the only brain.
- `Aria` provides the control loop, local runtime, MCP surface, and install flow.
- `aria-runtime-daemon` exposes local machine capabilities over a Unix socket.
- `aria` is the operator-facing CLI and MCP bridge.
- `Aria Runtime.app` is the menu bar shell that installs and supervises the local daemon.
- end users receive packaged binaries only, not the source repository

## Public MCP Surface

- `aria_bootstrap`
- `computer_snapshot`
- `computer_action`
- `system_open_application`
- `system_open_url`
- `runtime_health`
- `runtime_permissions`

The Aria control loop is strict:

1. `aria_bootstrap` once per visual task
2. enter app/site if needed
3. `computer_snapshot`
4. exactly one `computer_action`
5. inspect returned screenshot
6. repeat until visually verified

For visual tasks, Aria is designed to steer Codex away from DOM-first strategies and toward screenshot-driven computer use.

## Build

```bash
swift build
swift test
./.build/debug/aria smoke mcp
./.build/debug/aria smoke codex
./.build/debug/aria-runtime-daemon &
./.build/debug/aria smoke runtime
kill %1
./scripts/build_app_bundle.sh
./scripts/build_pkg.sh
```

The universal build targets both `x86_64` and `arm64` in one pass.

## Local Install

For a no-admin local install in one command:

```bash
./scripts/install_local.sh
```

This installs `Aria Runtime.app` into `~/Applications`, links `aria` into `~/.local/bin/aria`, starts the background runtime, requests macOS permissions, and registers the MCP server for Codex when the `codex` CLI is available.

The install surface is binary-first. End users should use the packaged app or pkg and should not need this repository at all.

For the packaged app or any existing install, the canonical onboarding command is:

```bash
aria setup
```

Useful follow-ups:

```bash
aria setup status
aria setup test-prompt
```

By default, repeated local installs reuse the existing `dist/Aria Runtime.app` bundle so macOS permissions are not reset on every test. To rebuild before installing:

```bash
ARIA_RUNTIME_REBUILD=1 ./scripts/install_local.sh
```

From the repo root, the shortest install path is:

```bash
cd path/to/AriaRuntimeCodex
./install_aria_runtime.sh
```

## Smoke Tests

The CLI exposes non-destructive smoke tests for the three critical paths:

```bash
./.build/debug/aria smoke mcp
./.build/debug/aria smoke codex
./.build/debug/aria-runtime-daemon &
./.build/debug/aria smoke runtime
kill %1
```

- `aria smoke mcp` validates the stdio MCP bridge, Aria control instructions, and screenshot-based tools.
- `aria smoke codex` validates JSONL MCP framing plus resources and prompts used to steer Codex.
- `aria smoke runtime` validates the live daemon, Aria bootstrap instructions, and screenshot capture when permission exists.

## Codex Setup

```bash
./dist/Aria\ Runtime.app/Contents/MacOS/aria codex install
./dist/Aria\ Runtime.app/Contents/MacOS/aria codex status
```

This registers `aria-runtime` as a local MCP server for Codex using the shipped app bundle binary.

Once installed, Codex should discover Aria as a local MCP server and receive Aria's control instructions through:

- MCP initialize instructions
- MCP prompt `aria_computer_use`
- MCP resources under `aria://...`
- the canonical tools `aria_bootstrap`, `computer_snapshot`, and `computer_action`

`aria setup` also prints a ready-to-run visual smoke prompt for Codex.

## Versioned Build

```bash
ARIA_RUNTIME_VERSION=1.2.0 ARIA_RUNTIME_BUILD=42 ./scripts/build_pkg.sh
```

## Signed Release

```bash
ARIA_RUNTIME_VERSION=1.2.0 \
ARIA_RUNTIME_BUILD=42 \
ARIA_CODESIGN_APP_IDENTITY="Developer ID Application: Your Company" \
ARIA_CODESIGN_INSTALLER_IDENTITY="Developer ID Installer: Your Company" \
./scripts/build_signed_pkg.sh
```

## Notarization

Create a notary profile once with `xcrun notarytool store-credentials`, then run:

```bash
ARIA_NOTARY_PROFILE=aria-runtime ./scripts/notarize_pkg.sh
```

## Install Surface

- app bundle path: `dist/Aria Runtime.app`
- unsigned package path: `dist/AriaRuntime.pkg`
- signed package path: `dist/AriaRuntime-signed.pkg`

After installation, the postinstall script links `aria` into `/usr/local/bin/aria`.
