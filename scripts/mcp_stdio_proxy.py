#!/usr/bin/env python3
import os
import subprocess
import sys
import threading
from pathlib import Path


def pump(reader, writer, log_path, label):
    with open(log_path, "ab", buffering=0) as log_file:
        while True:
            chunk = reader.read(4096)
            if not chunk:
                try:
                    writer.flush()
                except Exception:
                    pass
                try:
                    writer.close()
                except Exception:
                    pass
                return
            log_file.write(b"\n=== " + label.encode("utf-8") + b" ===\n")
            log_file.write(chunk)
            writer.write(chunk)
            writer.flush()


def main():
    if len(sys.argv) < 2:
        print("usage: mcp_stdio_proxy.py <aria-binary> [args...]", file=sys.stderr)
        sys.exit(2)

    target = sys.argv[1:]
    log_dir = Path("/tmp/aria-runtime-mcp-debug")
    log_dir.mkdir(parents=True, exist_ok=True)
    inbound_log = log_dir / "codex-to-aria.log"
    outbound_log = log_dir / "aria-to-codex.log"
    stderr_log = log_dir / "aria-stderr.log"

    env = os.environ.copy()
    process = subprocess.Popen(
        target,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )

    threads = [
        threading.Thread(
            target=pump,
            args=(sys.stdin.buffer, process.stdin, inbound_log, "stdin"),
            daemon=True,
        ),
        threading.Thread(
            target=pump,
            args=(process.stdout, sys.stdout.buffer, outbound_log, "stdout"),
            daemon=True,
        ),
        threading.Thread(
            target=pump,
            args=(process.stderr, sys.stderr.buffer, stderr_log, "stderr"),
            daemon=True,
        ),
    ]

    for thread in threads:
        thread.start()

    exit_code = process.wait()
    for thread in threads:
        thread.join(timeout=1)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
