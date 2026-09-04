import Foundation

// Worktree and branch enumeration for the switcher menus. The Files-tab git
// footer (ProjectHeaderView) and the Git tab's header dropdown both build
// their switcher from the same lists, so the two never disagree about a repo's
// worktrees or branches.
//
// The lists come from GitStatusMonitor, which already runs `git worktree list`
// and `git for-each-ref` on every refresh and caches the result; the menus
// read that cache rather than spawning git twice per click on the main thread,
// which on a slow disk or a network volume stalled the window before the menu
// could open. What lives here is the pure parsing of the two plumbing outputs,
// so a harness can check it without git.
struct WorktreeEntry: Equatable {
    var path: String
    // nil for a detached HEAD.
    var branch: String?
}

enum WorktreeSwitcher {
    // `git worktree list --porcelain`: blocks of "worktree <path>" followed by
    // "branch refs/heads/<name>" or "detached".
    static func parseWorktrees(_ porcelain: String) -> [WorktreeEntry] {
        var result: [WorktreeEntry] = []
        for line in porcelain.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("worktree ") {
                result.append(WorktreeEntry(path: String(line.dropFirst("worktree ".count)), branch: nil))
            } else if line.hasPrefix("branch refs/heads/"), !result.isEmpty {
                result[result.count - 1].branch = String(line.dropFirst("branch refs/heads/".count))
            }
        }
        return result
    }

    // `git for-each-ref --format=%(refname:short) refs/heads`: one branch per line.
    static func parseBranches(_ output: String) -> [String] {
        output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
