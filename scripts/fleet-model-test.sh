#!/bin/bash
# Fleet model test: compiles the UI-free projection
# (swift/Sources/suit/FleetModel.swift) with the session model it projects
# (ClaudeSessions.swift and what that needs — all Foundation-only) and
# scripts/fleet-model-test/main.swift, then runs its assertions — the
# needs-you-first row order, project/worktree naming, the display-name
# precedence, the subagent tree woven into the rows, and the Kanban columns.
# Mirrors the FeedbackRouting standalone pattern.
#
# Usage: scripts/fleet-model-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t fleet-model-test)"
SCRATCH="$(mktemp -d -t fleet-model-home)"
trap 'rm -f "$DRIVER"; rm -rf "$SCRATCH"' EXIT

echo "==> Compiling fleet model test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/FleetModel.swift" \
    "$ROOT/swift/Sources/suit/SubagentTree.swift" \
    "$ROOT/swift/Sources/suit/ClaudeSessions.swift" \
    "$ROOT/swift/Sources/suit/ClaudeMode.swift" \
    "$ROOT/swift/Sources/suit/DirectoryWatcher.swift" \
    "$ROOT/swift/Sources/suit/SuitPaths.swift" \
    "$ROOT/swift/Sources/suit/ProcessUtil.swift" \
    "$ROOT/swift/Sources/suit/OpsLog.swift" \
    "$ROOT/scripts/fleet-model-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running (scratch HOME=$SCRATCH)"
HOME="$SCRATCH" "$DRIVER"
