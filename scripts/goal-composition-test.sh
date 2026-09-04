#!/bin/bash
# Goal composition test: compiles the UI-free core
# (swift/Sources/suit/GoalComposition.swift, Foundation-only, no app deps) with
# scripts/goal-composition-test/main.swift and runs its assertions — the
# `/goal` payload "Set as Goal" sends into a session (trim, the From
# file:lines provenance line, when it is omitted) and the bracketed-paste
# framing that keeps a multi-line goal one input-box unit. Mirrors the
# FeedbackRouting standalone pattern.
#
# Usage: scripts/goal-composition-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t goal-composition-test)"
trap 'rm -f "$DRIVER"' EXIT

echo "==> Compiling goal composition test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/GoalComposition.swift" \
    "$ROOT/scripts/goal-composition-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running"
"$DRIVER"
