import Foundation

// Standalone assertions for WorktreeTasks against a real fixture repo (built
// by the wrapper): the slug rules, then the whole "New Claude Task" →
// "Finish Task" life cycle, merged and discarded.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: harness <repo> <not-a-repo>")
    exit(2)
}
// git reports paths with symlinks resolved (/private/var/…), so compare on
// resolved paths throughout.
let repo = (arguments[1] as NSString).resolvingSymlinksInPath
let notARepo = arguments[2]
let fm = FileManager.default

func git(_ root: String, _ args: [String]) -> String {
    if case .success(let out) = WorktreeTasks.runGit(root, args) {
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return "<failed>"
}

print("== slug ==")
do {
    check(WorktreeTasks.slug(from: "Fix Login Bug!") == "fix-login-bug", "lowercased, punctuation and spaces become dashes")
    check(WorktreeTasks.slug(from: "  --a--  ") == "a", "runs of separators collapse and trim")
    check(WorktreeTasks.slug(from: "keep.this_one-ok") == "keep.this_one-ok", "dots, underscores and dashes survive")
    check(WorktreeTasks.slug(from: "!!!") == "", "nothing usable is an empty slug")
    check(WorktreeTasks.slug(from: String(repeating: "x", count: 60)).count == 48, "capped at 48 characters")
}

print("== isTaskWorktree ==")
do {
    check(WorktreeTasks.isTaskWorktree("/r/.claude/worktrees/x"), "a path under .claude/worktrees is a task worktree")
    check(!WorktreeTasks.isTaskWorktree("/r/x") && !WorktreeTasks.isTaskWorktree(nil), "anything else is not")
}

print("== createTask ==")
var taskPath = ""
do {
    switch WorktreeTasks.createTask(projectRoot: repo, name: "My Task") {
    case .success(let path): taskPath = path
    case .failure(let error): check(false, "createTask: \(error.message)"); exit(1)
    }
    check(taskPath == repo + "/.claude/worktrees/my-task", "the worktree lives under .claude/worktrees/<slug>: \(taskPath)")
    check(fm.fileExists(atPath: taskPath + "/README.md"), "…and is a checked-out worktree")
    check(WorktreeTasks.currentBranch(taskPath) == "task/my-task", "on branch task/<slug>")
    check(WorktreeTasks.mainRoot(ofWorktree: taskPath).map { ($0 as NSString).resolvingSymlinksInPath } == repo,
          "mainRoot finds the main checkout from inside the worktree")
    check(WorktreeTasks.isTaskWorktree(taskPath), "the created path is recognized as a task worktree")
    check(!WorktreeTasks.hasUncommittedChanges(taskPath), "a fresh worktree is clean")

    try! "work\n".write(toFile: taskPath + "/work.txt", atomically: true, encoding: .utf8)
    check(WorktreeTasks.hasUncommittedChanges(taskPath), "an untracked file counts as uncommitted")
    check(WorktreeTasks.finish(worktreePath: taskPath, merge: true) != nil, "finish refuses to merge uncommitted work")
    _ = git(taskPath, ["add", "-A"])
    _ = git(taskPath, ["commit", "-q", "-m", "task work"])
    check(!WorktreeTasks.hasUncommittedChanges(taskPath), "clean again after the commit")

    if case .failure(let error) = WorktreeTasks.createTask(projectRoot: repo, name: "my task") {
        check(error.message.contains("already exists"), "the same slug twice is refused: \(error.message)")
    } else { check(false, "the same slug twice is refused") }
    if case .failure(let error) = WorktreeTasks.createTask(projectRoot: repo, name: "!!!") {
        check(error.message.contains("empty"), "an unusable name is refused: \(error.message)")
    } else { check(false, "an unusable name is refused") }
    if case .failure(let error) = WorktreeTasks.createTask(projectRoot: notARepo, name: "x") {
        check(error.message.contains("not a git repository"), "a plain directory is refused: \(error.message)")
    } else { check(false, "a plain directory is refused") }
}

print("== finish: merge & remove ==")
do {
    check(WorktreeTasks.finish(worktreePath: taskPath, merge: true) == nil, "merge & remove succeeds")
    check(!fm.fileExists(atPath: taskPath), "the worktree directory is gone")
    check(git(repo, ["log", "--oneline", "-1"]).contains("Merge task/my-task"), "main has the merge commit")
    check(fm.fileExists(atPath: repo + "/work.txt"), "the task's file landed on main")
    check(git(repo, ["branch", "--list", "task/my-task"]).isEmpty, "the task branch is deleted")
}

print("== finish: discard & remove ==")
do {
    guard case .success(let path) = WorktreeTasks.createTask(projectRoot: repo, name: "Throwaway") else {
        check(false, "second createTask"); exit(1)
    }
    try! "junk\n".write(toFile: path + "/junk.txt", atomically: true, encoding: .utf8)
    check(WorktreeTasks.finish(worktreePath: path, merge: false) == nil, "discard & remove succeeds despite uncommitted work")
    check(!fm.fileExists(atPath: path), "the worktree directory is gone")
    check(!fm.fileExists(atPath: repo + "/junk.txt"), "nothing from it reached main")
    check(git(repo, ["branch", "--list", "task/throwaway"]).isEmpty, "the task branch is deleted")
}

print("== edges ==")
do {
    check(WorktreeTasks.finish(worktreePath: repo, merge: true) != nil, "the main checkout is not a task worktree")
    check(WorktreeTasks.reconcileMainWithUpstream(repo) != nil, "no upstream is reported, not silently ignored")
    check(WorktreeTasks.mainRoot(ofWorktree: notARepo) == nil, "mainRoot outside a repo is nil")
    check(WorktreeTasks.currentBranch(repo) == "main", "currentBranch on the main checkout")
}

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
