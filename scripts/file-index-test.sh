#!/bin/bash
# FileIndex logic test: compiles the UI-free scanner
# (swift/Sources/suit/FileIndex.swift, Foundation-only, no app deps) with
# scripts/file-index-test/main.swift and runs its assertions — the non-git-repo
# fallback scan behind the Files sidebar: hidden directories (.claude, .github)
# and dotfiles are indexed, while .git / node_modules / .Trash and Finder
# droppings (.DS_Store, ._*) are pruned.
# Mirrors the FeedbackRouting / DiffParser / Recipes standalone-test pattern.
#
# ProcessUtil.swift joins the compile because FileIndex spawns git through
# runProcess (which lives there), and OpsLog.swift because runProcess records
# every spawn to the operations log; both are Foundation-only, so the harness
# stays app-free.
#
# Usage: scripts/file-index-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t file-index-test)"
trap 'rm -f "$DRIVER"' EXIT

echo "==> Compiling FileIndex logic test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/FileIndex.swift" \
    "$ROOT/swift/Sources/suit/ProcessUtil.swift" \
    "$ROOT/swift/Sources/suit/OpsLog.swift" \
    "$ROOT/scripts/file-index-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running"
"$DRIVER"
