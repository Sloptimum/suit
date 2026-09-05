#!/bin/bash
# Worktree tasks test: builds a throwaway git repo, then compiles the task
# orchestration (swift/Sources/suit/WorktreeTasks.swift, Foundation-only, with
# the git plumbing it calls through) against scripts/worktree-tasks-test/
# main.swift and runs it against that repo — the slug rules, "New Claude Task"
# creating a worktree on task/<slug>, the main-checkout lookup from inside it,
# the dirty check, and "Finish" both merging and discarding. Real git, no app,
# no UI; a scratch $HOME keeps the user's git config and hooks out of it.
#
# Usage: scripts/worktree-tasks-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- The fixture repo and a plain directory that is not one -----------------
REPO="$TMP/repo"
mkdir -p "$REPO" "$TMP/not-a-repo" "$TMP/home"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name tester
printf 'hello\n' > "$REPO/README.md"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "initial"

# --- Compile the core + driver, run ------------------------------------------
echo "==> Compiling worktree tasks test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/WorktreeTasks.swift" \
    "$ROOT/swift/Sources/suit/WorktreeSwitcher.swift" \
    "$ROOT/swift/Sources/suit/FileIndex.swift" \
    "$ROOT/swift/Sources/suit/ProcessUtil.swift" \
    "$ROOT/swift/Sources/suit/OpsLog.swift" \
    "$ROOT/scripts/worktree-tasks-test/main.swift" \
    -o "$TMP/harness"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running (scratch HOME=$TMP/home)"
HOME="$TMP/home" "$TMP/harness" "$REPO" "$TMP/not-a-repo"
