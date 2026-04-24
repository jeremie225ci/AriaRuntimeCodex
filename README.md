# Aria Runtime Codex computer use 

Aria Runtime Codex is a **local-first macOS runtime** that gives **Codex** controlled computer-use powers on a real Mac.

The core idea is simple:

- **Codex is the brain**
- **Aria is the local execution layer**
- **There is no remote Aria brain, no Hetzner dependency, and no Aria decision server**

This repository is intended to be **open source**, **self-hosted**, and **auditable**.

## Why this project exists

The earlier Aria direction depended heavily on a Linux VM and a remote brain/server split. That model made experimentation possible, but it added too much friction for everyday developer use.

This repository takes the opposite direction:

- install quickly on a local Mac
- expose local desktop/browser/app powers through an MCP server
- let **Codex** make the decisions
- keep Aria focused on **control loop, permissions, screenshots, and action execution**

That direction now aligns much more closely with OpenAI's current Codex computer-use direction:

- official Codex computer-use docs: <https://developers.openai.com/codex/app/computer-use>
- official Codex config reference: <https://developers.openai.com/codex/config-reference>
- public Codex repository: <https://github.com/openai/codex>

## Project status

This repo is designed as a **standalone local runtime** for macOS:

- no remote Aria server required
- no remote Aria planner required
- no Aria-owned OpenAI key required to decide actions
- all planning stays in Codex
- Aria only provides local machine powers plus a strict visual control loop

## Design principles

1. **Local-first**
   - The runtime lives on the user's Mac.
   - The daemon communicates over a local Unix socket.
   - No hosted Aria control plane is required.

2. **Codex-native**
   - Aria integrates through a local MCP server.
   - Codex keeps code reasoning, repo understanding, planning, and bug fixing.
   - Aria contributes machine execution primitives and visual-task discipline.

3. **Strict computer-use loop**
   - For visual tasks, the flow is intentionally narrow:
     1. `aria_bootstrap`
     2. `system_open_application` or `system_open_url`
     3. `computer_snapshot`
     4. one `computer_action`
     5. inspect screenshot
     6. repeat
   - This mirrors the screenshot-driven approach recommended for computer use.

4. **Open and auditable**
   - The codebase is small enough to inspect.
   - The local control logic is readable.
   - The install flow is reproducible from source.

## Architecture

### High-level shape

- **Codex**
  - the only decision engine
  - decides what to do
  - uses Aria through MCP

- **`aria`**
  - CLI entrypoint
  - MCP bridge
  - setup/install helper for Codex integration

- **`aria-runtime-daemon`**
  - long-running local daemon
  - exposes machine/runtime services through a Unix socket

- **`Aria Runtime.app`**
  - menu bar shell for macOS
  - supervises the local daemon
  - helps with installation and permissions

- **`AriaRuntimeMacOS`**
  - macOS-specific desktop/runtime implementation
  - screenshots, keyboard, mouse, app launching, permissions checks

- **`AriaRuntimeShared`**
  - shared protocol/config/control-plane logic

### Local-only communication

This project is already architected around a **local Unix socket runtime**, not a remote hosted service.

What that means in practice:

- Aria does **not** need a cloud gateway to execute actions
- Aria does **not** need a remote planner to decide actions
- the runtime speaks locally to:
  - the daemon
  - macOS APIs
  - the Codex MCP integration

## Public MCP surface

The visual-task surface intentionally stays small:

- `aria_bootstrap`
- `runtime_health`
- `runtime_permissions`
- `system_open_application`
- `system_open_url`
- `computer_snapshot`
- `computer_action`

For visual tasks, Aria locks Codex into a canonical loop instead of letting it drift into:

- DOM inspection
- AppleScript DOM scraping
- out-of-band browsing
- clipboard/window helper shortcuts as a substitute for computer use

## How this relates to official Codex computer use

From the official OpenAI Codex computer-use docs:

- computer use in the Codex app is available on macOS
- it is for tasks that require a graphical UI
- it depends on macOS permissions such as **Screen Recording** and **Accessibility**
- Codex can view screen content, take screenshots, and interact with desktop apps
- approvals and sandboxing still matter for file edits and shell commands

That maps well to this repository's direction:

- Aria should stay focused on **desktop execution**
- Codex should remain the **planner**
- visual tasks should be based on **screenshots and one action at a time**
- permissions should be explicit and user-controlled

Also important: the public OpenAI Codex repository confirms that **Codex CLI runs locally on your computer**, while Codex Web is the cloud-based agent. This repository is intentionally aligned with the **local** model, not the hosted one.

## Build from source

Requirements:

- macOS 13+
- Xcode / Swift toolchain with Swift 6.2 support
- Codex CLI installed if you want the full Codex integration

Build and test:

```bash
swift build
swift test
./.build/debug/aria smoke mcp
./.build/debug/aria smoke codex
./.build/debug/aria-runtime-daemon &
./.build/debug/aria smoke runtime
kill %1
```

Universal app build:

```bash
./scripts/build_app_bundle.sh
```

Package build:

```bash
./scripts/build_pkg.sh
```

The packaged build targets both:

- `x86_64`
- `arm64` / Apple Silicon

## Local install

Fast local install:

```bash
./scripts/install_local.sh
```

This installs:

- `Aria Runtime.app` into `~/Applications`
- `aria` into `~/.local/bin/aria`
- the background runtime
- the Codex MCP integration when Codex is available

## Codex integration

For the packaged app or an existing install:

```bash
aria setup
aria setup status
```

Aria configures Codex using the official-style config surface:

- `model_instructions_file`
- `web_search = "disabled"` for the Aria profile
- MCP `enabled_tools` allowlisting for the Aria server

The goal is:

- normal coding stays flexible in Codex
- visual tasks are forced back into the Aria loop

## Permissions

Computer use on macOS depends on system permissions.

You should expect to grant:

- **Accessibility**
- **Screen Recording**

Useful status check:

```bash
aria setup status
```

To start the macOS permission prompts and open the right Privacy & Security
panes:

```bash
./scripts/request_permissions.sh
```

If you need to clear stale denials first:

```bash
./scripts/request_permissions.sh --reset
```

macOS still requires the user to manually enable **Accessibility** and
**Screen Recording** for **Aria Runtime**; scripts can request and open the
panes, but cannot click those toggles for the user.

## Smoke tests

The CLI includes non-destructive smoke tests:

```bash
./.build/debug/aria smoke mcp
./.build/debug/aria smoke codex
./.build/debug/aria-runtime-daemon &
./.build/debug/aria smoke runtime
kill %1
```

What they validate:

- `aria smoke mcp`
  - MCP transport
  - Aria policy enforcement
  - screenshot-driven tool flow

- `aria smoke codex`
  - Codex-facing MCP framing/resources/prompts

- `aria smoke runtime`
  - daemon health
  - local screenshot/runtime path

## Release outputs

- app bundle: `dist/Aria Runtime.app`
- unsigned package: `dist/AriaRuntime.pkg`
- signed package: `dist/AriaRuntime-signed.pkg`

Signed release:

```bash
ARIA_RUNTIME_VERSION=1.2.0 \
ARIA_RUNTIME_BUILD=42 \
ARIA_CODESIGN_APP_IDENTITY="Developer ID Application: Your Company" \
ARIA_CODESIGN_INSTALLER_IDENTITY="Developer ID Installer: Your Company" \
./scripts/build_signed_pkg.sh
```

Notarization:

```bash
ARIA_NOTARY_PROFILE=aria-runtime ./scripts/notarize_pkg.sh
```

## Open-source scope

This repository is meant to contain the **local runtime product**:

- local daemon
- macOS runtime implementation
- Codex MCP integration
- packaging and install scripts
- local control-plane logic

This repository does **not** depend on shipping:

- a remote Aria planner
- a hosted gateway
- a VM-only execution model

## Relationship to OpenAI / Codex

This project integrates with Codex, but it is **not** the official OpenAI Codex repository.

If you want the official Codex codebase or docs:

- Codex repo: <https://github.com/openai/codex>
- Codex docs: <https://developers.openai.com/codex>
- Codex computer use docs: <https://developers.openai.com/codex/app/computer-use>

## Contributing

Contributions are welcome. For now, the most useful contributions are:

- macOS runtime fixes
- permission/onboarding improvements
- stronger visual verification
- packaging and installation polish
- tests around Codex integration behavior

## License

Licensed under the **Apache License 2.0**. See [LICENSE](./LICENSE).
