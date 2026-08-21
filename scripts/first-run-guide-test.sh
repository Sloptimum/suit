#!/bin/bash
# First-launch-guide logic test: compiles the UI-free core
# (swift/Sources/suit/FirstRunGuide.swift, Foundation only, no app deps) with
# scripts/first-run-guide-test/main.swift and runs its assertions — the
# show-the-guide-once truth table (a veteran with saved state is never
# greeted), guide discovery in both the bundle and the checkout, and that the
# guide document still teaches the keys it exists for. Mirrors the
# BundledFonts pattern.
#
# Usage: scripts/first-run-guide-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t first-run-guide-test)"
trap 'rm -f "$DRIVER"' EXIT

echo "==> Compiling first-run-guide logic test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/FirstRunGuide.swift" \
    "$ROOT/scripts/first-run-guide-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running"
"$DRIVER"
