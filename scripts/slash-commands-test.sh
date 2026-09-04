#!/bin/bash
# Slash-command catalog test: compiles the UI-free discovery
# (swift/Sources/suit/SlashCommands.swift + SuitPaths.swift, Foundation-only,
# no app deps) with scripts/slash-commands-test/main.swift and runs its
# assertions against a scratch $HOME — built-ins first, custom commands and
# skills discovered from ~/.claude and the nearest project .claude, the
# name-collision rules, and the one-line descriptions. Mirrors the Recipes
# standalone pattern.
#
# Usage: scripts/slash-commands-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t slash-commands-test)"
SCRATCH="$(mktemp -d -t slash-commands-home)"
trap 'rm -f "$DRIVER"; rm -rf "$SCRATCH"' EXIT

echo "==> Compiling slash-command catalog test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/SlashCommands.swift" \
    "$ROOT/swift/Sources/suit/SuitPaths.swift" \
    "$ROOT/scripts/slash-commands-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running (scratch HOME=$SCRATCH)"
HOME="$SCRATCH" "$DRIVER"
