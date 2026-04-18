# Contributing

Thanks for contributing to Aria Runtime Codex.

## What is useful right now

The highest-value contributions are:

- macOS runtime reliability fixes
- onboarding and permission-flow improvements
- stronger screenshot verification for computer use
- Codex integration fixes
- packaging and install improvements
- tests around MCP behavior and local runtime behavior

## Development workflow

Build:

```bash
swift build
```

Run tests:

```bash
swift test
```

Run smoke tests:

```bash
./.build/debug/aria smoke mcp
./.build/debug/aria smoke codex
./.build/debug/aria-runtime-daemon &
./.build/debug/aria smoke runtime
kill %1
```

## Scope

Please keep the project aligned with these principles:

- Codex is the planner
- Aria is the local execution layer
- no remote Aria brain dependency
- local-first MCP integration
- visual tasks should stay in the screenshot/action loop

## Pull requests

When possible:

- keep PRs focused
- explain the user-visible impact
- mention any permission or packaging implications
- include smoke-test output when relevant

## License

By contributing, you agree that your contributions are licensed under the Apache License 2.0 used by this repository.
