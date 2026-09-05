#!/bin/bash
# Claude session parsing test: compiles the session monitor's file
# (swift/Sources/suit/ClaudeSessions.swift, Foundation-only, plus what it
# needs) with scripts/claude-sessions-test/main.swift and runs its assertions
# — the hook's session JSON → ClaudeSession, the statusline's usage JSON →
# ClaudeUsage (per-model weeklies included), and the defensive resets_at
# parse. The monitor itself is never started. Mirrors the FeedbackRouting
# standalone pattern.
#
# Usage: scripts/claude-sessions-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t claude-sessions-test)"
SCRATCH="$(mktemp -d -t claude-sessions-home)"
trap 'rm -f "$DRIVER"; rm -rf "$SCRATCH"' EXIT

echo "==> Compiling Claude session parsing test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/ClaudeSessions.swift" \
    "$ROOT/swift/Sources/suit/ClaudeMode.swift" \
    "$ROOT/swift/Sources/suit/DirectoryWatcher.swift" \
    "$ROOT/swift/Sources/suit/SuitPaths.swift" \
    "$ROOT/swift/Sources/suit/ProcessUtil.swift" \
    "$ROOT/swift/Sources/suit/OpsLog.swift" \
    "$ROOT/scripts/claude-sessions-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running (scratch HOME=$SCRATCH)"
HOME="$SCRATCH" "$DRIVER"
