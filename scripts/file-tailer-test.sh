#!/bin/bash
# FileTailer test: compiles the Foundation-only tailer
# (swift/Sources/suit/FileTailer.swift) with scripts/file-tailer-test/main.swift
# and runs its assertions — the pure incremental read (whole lines only, a
# held-back fragment, truncation restarts) and the live tail against a real run
# loop and a real file (an append, a truncate, an atomic replace, stop). The
# descriptor-lifecycle failures are invisible to a pure test, so the live half
# is where a tail that goes deaf after a replace is actually caught. Mirrors
# the file-watch live harness.
#
# Usage: scripts/file-tailer-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t file-tailer-test)"
trap 'rm -f "$DRIVER"' EXIT

echo "==> Compiling FileTailer test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/FileTailer.swift" \
    "$ROOT/scripts/file-tailer-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running"
"$DRIVER"
