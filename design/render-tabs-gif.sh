#!/bin/bash
# Regenerates design/tabs-drag.gif — the README animation of tab drag & drop
# (chip → edge split / center show, with the live drop-zone preview). Rendered
# offscreen from the real app, same harness pattern as render-reference.sh.
# Re-run and commit the GIF after any tab/pane chrome or drag behavior change.
set -euo pipefail
cd "$(dirname "$0")/.."
# -j: swiftc runs its per-file frontend jobs serially by default — see build.sh.
swiftc -O -j "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" $(ls swift/Sources/suit/*.swift | grep -v '/main.swift$') \
  design/tabs-demo/main.swift \
  $(find swift/Vendor/SwiftTerm -name '*.swift') \
  -o /tmp/suit-tabs-demo
# A sandboxed $HOME, as render-reference.sh: no real ~/.suit or ~/.claude.
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
# The shells are real login shells: without a prompt of our own, zsh's
# default prints user@host into the picture.
echo "PROMPT='%# '" > "$sandbox/.zshrc"
HOME="$sandbox" /tmp/suit-tabs-demo design/tabs-drag.gif
