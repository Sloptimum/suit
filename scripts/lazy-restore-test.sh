#!/bin/bash
# Lazy state-restoration test: a saved layout comes back with only its visible
# tabs brought up — background terminals have no shell and background files
# are unread until they are shown — while every tab keeps the identity the
# next quit snapshot needs (title, path, working directory, scroll position).
# Also covers the shapes that restore differently: a snapshot with no split
# tree, and a never-shown file tab torn off into its own window, both of which
# build a pane before the window's sidebar exists.
#
# Slow (~40 s): like the source-control gate, this compiles the whole app and
# drives the real AppDelegate offscreen, because what is under test is the
# wiring between StateRestoration, TabStore, Pane and the pane contents.
#
# Sandboxed: a scratch $HOME (so ~/.suit is never touched) and a scratch repo.
# The driver binary has its own name so its UserDefaults domain is its own.
#
# Usage: scripts/lazy-restore-test.sh   (run from the repo root)
# Exit: 0 all pass, 1 an assertion failed, 64 compile failure.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
WORK="$(mktemp -d -t suit-lazyrestore)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
mkdir -p "$REPO/src" "$WORK/home"
# A prompt of our own: the default one prints user@host.
echo "PROMPT='%# '" > "$WORK/home/.zshrc"
for name in one two three four; do
    for i in $(seq 1 600); do
        printf 'let %s%d = %d\n' "$name" "$i" "$i"
    done > "$REPO/src/$name.swift"
done
for i in $(seq 1 400); do
    printf '## Section %d\n\nParagraph %d of the fixture document.\n\n' "$i" "$i"
done > "$REPO/notes.md"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name "Suit Test"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "initial"

DRIVER="$WORK/suit-lazy-restore-driver"

echo "==> Compiling lazy-restore test (whole app — slow)"
if ! swiftc -Onone -j "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
    $(ls "$ROOT"/swift/Sources/suit/*.swift | grep -v '/main.swift$') \
    "$ROOT/scripts/lazy-restore-test/main.swift" \
    $(find "$ROOT/swift/Vendor/SwiftTerm" -name '*.swift') \
    -o "$DRIVER"; then
    echo "COMPILE FAILED"
    exit 64
fi

echo "==> Running"
cd "$REPO"
HOME="$WORK/home" "$DRIVER" "$REPO"
