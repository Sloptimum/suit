#!/bin/bash
# Git/gh output parsing test: compiles the UI-free parsers
# (swift/Sources/suit/GitOutputParsing.swift + GitBranchOps.swift, both
# Foundation-only, no app deps) with scripts/git-output-parsing-test/main.swift
# and runs its assertions — the branch listing's order and flags, which PR a
# branch keeps, the check-rollup traffic light, PR detail, the failed run to
# fetch, the capped log, and the created-PR URL. No git, no gh, no network.
# Mirrors the GitBranchOps standalone pattern.
#
# Usage: scripts/git-output-parsing-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t git-output-parsing-test)"
trap 'rm -f "$DRIVER"' EXIT

echo "==> Compiling git/gh output parsing test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/GitOutputParsing.swift" \
    "$ROOT/swift/Sources/suit/GitBranchOps.swift" \
    "$ROOT/scripts/git-output-parsing-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running"
"$DRIVER"
