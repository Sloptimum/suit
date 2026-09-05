#!/bin/bash
# WorktreeSwitcher test: compiles the Foundation-only parsers
# (swift/Sources/suit/WorktreeSwitcher.swift) with
# scripts/worktree-switcher-test/main.swift and runs its assertions — the
# `git worktree list --porcelain` and `for-each-ref` parsing that the switcher
# menus, the marker catch-up, the Fleet tree and the task finisher all share.
# Mirrors the FeedbackRouting / DiffParser standalone-test pattern.
#
# Usage: scripts/worktree-switcher-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t worktree-switcher-test)"
trap 'rm -f "$DRIVER"' EXIT

echo "==> Compiling WorktreeSwitcher test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/WorktreeSwitcher.swift" \
    "$ROOT/scripts/worktree-switcher-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running"
"$DRIVER"
