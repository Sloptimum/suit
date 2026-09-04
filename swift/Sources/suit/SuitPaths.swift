import Foundation

// Where Suit keeps its data, decided once.
//
// $HOME rather than NSHomeDirectory(): the Claude Code hooks, the statusline
// script and the suit-bg wrapper all resolve ~ from the environment, and
// NSHomeDirectory() ignores an overridden $HOME on macOS. A harness that points
// $HOME at a scratch directory therefore sandboxes the scripts' side of the
// exchange, and only this rule sandboxes the app's side to match. Every store
// used to carry its own copy of the line, each with the same explanation; one
// place means one place to get it wrong. Computed, not stored, so a harness
// that re-points $HOME between cases is honored.
enum SuitPaths {
    static var home: String {
        ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }

    // ~/.suit — favorites, notes, recipes, layouts, sessions, tasks, markers,
    // ssh hosts and themes (see CLAUDE.md §4).
    static var directory: String { home + "/.suit" }

    // ~/.claude — Claude Code's own directory: settings, projects, commands,
    // file history. Read here, written only by the integration installer.
    static var claudeDirectory: String { home + "/.claude" }
}
