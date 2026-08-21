import Foundation

// The first launch of Suit opens a short guide tab (Resources/guide.md) beside
// the fresh shell: the tab/pane model is the one part of the app a new user
// cannot discover by poking at a terminal, and the guide is where ⌘D / ⇧⌘D /
// ⌘T earn their keeps before Settings ▸ Shortcuts is ever opened.
//
// The guide is a real markdown file, not a bespoke welcome window, on purpose:
// MarkdownPaneContent already renders it themed, the one-tab-per-path rule
// makes reopening idempotent, and state restoration treats it like any other
// tab — left open at quit it comes back, closed it stays gone. The only new
// machinery is the decision below and a path lookup.
//
// Two rules the truth table in scripts/first-run-guide-test must keep honest:
// - "First launch" means *no saved state*, not "the latch is unset". An
//   existing install that upgrades onto this feature has saved state and an
//   unset latch; greeting a veteran with a tutorial would be wrong, so the
//   caller latches `shownDefaultsKey` on every launch, not just when showing.
// - A wiped defaults domain looks like a fresh install and gets the guide
//   again. That is acceptable on a personal machine and beats persisting a
//   flag file into ~/.suit/ for a single boolean.
//
// Foundation-only (no AppKit, no app types) so the harness can compile this
// file standalone; the AppDelegate owns UserDefaults and the tab opening.
enum FirstRunGuide {
    static let fileName = "guide.md"

    // The UserDefaults latch. Same shape as ActivityRecorder.lastDigestDayKey:
    // a tiny app-level flag lives in defaults, not in a ~/.suit/ store.
    static let shownDefaultsKey = "firstRunGuideShown"

    // Whether this launch should open the guide tab. `hasSavedState` is
    // "SavedAppState.load() found windows to restore" — the app's only memory
    // that predates the latch.
    static func shouldShow(hasSavedState: Bool, alreadyShown: Bool) -> Bool {
        !hasSavedState && !alreadyShown
    }

    // The guide, wherever this binary can find it: the app bundle's Resources
    // when running as Suit.app, else the checkout this file was compiled from —
    // the same dual path as BundledFonts.fontURLs, and for the same reason (the
    // bare `swiftc` dev loop has no bundle).
    static func guideURL(resourceURL: URL?) -> URL? {
        let candidates = [
            resourceURL?.appendingPathComponent(fileName),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // suit/
                .deletingLastPathComponent()   // Sources/
                .deletingLastPathComponent()   // swift/
                .deletingLastPathComponent()   // repo root
                .appendingPathComponent("Resources/\(fileName)"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
