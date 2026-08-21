import Foundation

// Assertions for FirstRunGuide: the show-the-guide-once decision, the guide
// file lookup in both the bundle and the checkout, and a drift guard that the
// guide document still teaches the keys it exists to teach. Compiled by
// scripts/first-run-guide-test.sh against swift/Sources/suit/FirstRunGuide.swift
// alone — no app, no AppKit, no UserDefaults (the truth table takes the flag
// as a parameter precisely so this driver never touches the shared defaults).

var failures = 0

func check(_ label: String, _ condition: Bool) {
    if condition {
        print("ok: \(label)")
    } else {
        print("FAIL: \(label)")
        failures += 1
    }
}

// --- shouldShow: the full truth table -----------------------------------
// The case that matters is the veteran upgrade: saved state exists, the latch
// is unset (the feature is newer than the install) — no tutorial.
check("fresh install shows the guide",
      FirstRunGuide.shouldShow(hasSavedState: false, alreadyShown: false))
check("veteran upgrading (saved state, latch unset) is not greeted",
      !FirstRunGuide.shouldShow(hasSavedState: true, alreadyShown: false))
check("second launch (latch set) shows nothing",
      !FirstRunGuide.shouldShow(hasSavedState: false, alreadyShown: true))
check("saved state and latch set shows nothing",
      !FirstRunGuide.shouldShow(hasSavedState: true, alreadyShown: true))

// --- guideURL -----------------------------------------------------------
// No bundle resource dir (the bare `swiftc` dev binary) still finds the guide
// via the #filePath fallback into the checkout this file came from.
let devURL = FirstRunGuide.guideURL(resourceURL: nil)
check("dev fallback finds the guide", devURL != nil)
check("dev fallback resolves \(FirstRunGuide.fileName)",
      devURL?.lastPathComponent == FirstRunGuide.fileName)

// A resource dir without the guide falls through to the checkout rather than
// returning a path that does not exist.
let absent = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("suit-guide-absent")
check("missing bundle guide falls back to the checkout",
      FirstRunGuide.guideURL(resourceURL: absent) != nil)

// A bundle whose Resources/ holds the guide wins over the checkout.
let staged = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("suit-guide-test-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
try? Data("# staged".utf8).write(to: staged.appendingPathComponent(FirstRunGuide.fileName))
check("bundle Resources wins over the checkout",
      FirstRunGuide.guideURL(resourceURL: staged)?.path.hasPrefix(staged.path) == true)
try? FileManager.default.removeItem(at: staged)

// --- the guide document itself ------------------------------------------
// The guide exists to teach the tab/pane keys; a rewrite that drops one of
// them (or a key change that forgets the guide) should fail here, not ship.
if let devURL, let text = try? String(contentsOf: devURL, encoding: .utf8) {
    check("guide is not empty", !text.isEmpty)
    for key in ["⌘T", "⌘W", "⇧⌘T", "⌘D", "⇧⌘D", "⌥⌘W", "⌃⌘M", "⌘K", "⌘P", "⌘B"] {
        check("guide teaches \(key)", text.contains(key))
    }
    check("guide names the palette entry that reopens it",
          text.contains("Open the Guide"))
} else {
    check("guide file is readable", false)
}

if failures > 0 {
    print("\n\(failures) assertion(s) failed")
    exit(1)
}
print("\nall first-run-guide assertions passed")
