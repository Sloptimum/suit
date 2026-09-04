#!/bin/bash
# Transcript parsing test: compiles the UI-free parser
# (swift/Sources/suit/TranscriptParsing.swift, Foundation-only, no app deps)
# with scripts/transcript-parsing-test/main.swift and runs its assertions — the
# JSONL line → entries rules the transcript pane and cross-transcript search
# both depend on (prompts kept, tool-result plumbing and sidechains dropped,
# tool calls collapsed to their most useful field) and the file:line reference
# resolver behind Cmd-click. Mirrors the FeedbackRouting standalone pattern.
#
# Usage: scripts/transcript-parsing-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DRIVER="$(mktemp -t transcript-parsing-test)"
trap 'rm -f "$DRIVER"' EXIT

echo "==> Compiling transcript parsing test"
if ! swiftc -O \
    "$ROOT/swift/Sources/suit/TranscriptParsing.swift" \
    "$ROOT/scripts/transcript-parsing-test/main.swift" \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running"
"$DRIVER"
