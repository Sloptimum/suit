import Foundation

// Standalone assertions for WorktreeSwitcher's parsers — the one place the
// app reads `git worktree list --porcelain` and `for-each-ref` output.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

print("== worktree list --porcelain ==")
do {
    // Verbatim shape of git's output: blank-line-separated blocks, the main
    // checkout first, a linked worktree on a branch, and a detached one.
    let porcelain = """
    worktree /repo
    HEAD 1111111111111111111111111111111111111111
    branch refs/heads/main

    worktree /repo/.claude/worktrees/feature
    HEAD 2222222222222222222222222222222222222222
    branch refs/heads/feature/x

    worktree /repo/.claude/worktrees/spike
    HEAD 3333333333333333333333333333333333333333
    detached

    """
    let entries = WorktreeSwitcher.parseWorktrees(porcelain)
    check(entries.count == 3, "three blocks parse to three entries")
    check(entries.first == WorktreeEntry(
        path: "/repo", branch: "main", head: "1111111111111111111111111111111111111111"
    ), "the main checkout comes first, with its branch and HEAD")
    check(entries[1].path == "/repo/.claude/worktrees/feature" && entries[1].branch == "feature/x",
          "a branch with a slash keeps its full name")
    check(entries[2].branch == nil, "a detached worktree has no branch")
    check(entries[2].head == "3333333333333333333333333333333333333333", "…but still has a HEAD")

    check(WorktreeSwitcher.parseWorktrees("").isEmpty, "empty output parses to no entries")
    check(WorktreeSwitcher.parseWorktrees("branch refs/heads/orphan\n").isEmpty,
          "a branch line before any worktree line is ignored")
}

print("== for-each-ref ==")
do {
    check(WorktreeSwitcher.parseBranches("main\nfeature/x\n") == ["main", "feature/x"],
          "one branch per line, in git's order")
    check(WorktreeSwitcher.parseBranches("").isEmpty, "empty output parses to no branches")
    check(WorktreeSwitcher.parseBranches("\n\nmain\n\n") == ["main"], "blank lines are dropped")
}

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
