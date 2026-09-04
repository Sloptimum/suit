import Foundation

// Standalone assertions for FleetModel: sessions in, dashboard rows out.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

func session(
    _ id: String, _ state: ClaudeSessionState, cwd: String?, at: TimeInterval,
    name: String? = nil, summary: String? = nil, cost: Double? = nil
) -> ClaudeSession {
    ClaudeSession(
        id: id, state: state, cwd: cwd, summary: summary, model: nil, pid: nil,
        updatedAt: Date(timeIntervalSince1970: at), transcriptPath: nil, sessionName: name,
        contextPct: nil, costUSD: cost, permissionMode: nil
    )
}

print("== rows ==")
do {
    let sessions = [
        session("done", .done, cwd: "/r/a", at: 3),
        session("w1", .working, cwd: "/r/b", at: 1),
        session("ask", .needsInput, cwd: "/r/c", at: 2),
        session("w5", .working, cwd: "/r/d", at: 5, cost: 1.5),
    ]
    let rows = FleetModel.rows(sessions: sessions, hostedIds: ["w1"], branch: { $0 == "/r/b" ? "feature" : nil })
    check(rows.map(\.id) == ["ask", "w5", "w1", "done"], "needs-you first, then most recently updated: \(rows.map(\.id))")
    check(rows[2].hosted && !rows[0].hosted, "hosted marks the sessions a pane holds")
    check(rows[2].branch == "feature" && rows[0].branch == nil, "the branch resolver is asked per cwd")
    check(rows[0].project == "c" && rows[0].worktree == nil, "a plain cwd is its own project, no worktree")
    check(rows[1].costUSD == 1.5 && rows[1].depth == 0 && !rows[1].isBareWorktree, "cost carries over; a flat row has depth 0")
}

print("== projectAndWorktree ==")
do {
    let place = FleetModel.projectAndWorktree(cwd: "/Users/me/repo/.claude/worktrees/feat/src")
    check(place.project == "repo" && place.worktree == "feat", "a task worktree names the repo and the worktree")
    let plain = FleetModel.projectAndWorktree(cwd: "/Users/me/repo")
    check(plain.project == "repo" && plain.worktree == nil, "a plain checkout is its basename")
    check(FleetModel.projectAndWorktree(cwd: nil).project == "—", "no cwd is an em dash")
    check(FleetModel.projectAndWorktree(cwd: "").project == "—", "…and so is an empty one")
}

print("== displayName ==")
do {
    check(session("s", .working, cwd: "/r/x", at: 0, name: "Named", summary: "Sum").displayName == "Named", "the session name first")
    check(session("s", .working, cwd: "/r/x", at: 0, summary: "Sum").displayName == "Sum", "then the summary")
    check(session("s", .working, cwd: "/r/x", at: 0).displayName == "x", "then the cwd basename")
    check(session("0123456789", .working, cwd: nil, at: 0).displayName == "01234567", "then the id prefix")
}

print("== tree ==")
do {
    let parent = session("parent", .working, cwd: "/repo", at: 2)
    let sub = session("sub", .needsInput, cwd: "/repo/.claude/worktrees/sub", at: 1)
    let orphan = session("orphan", .working, cwd: nil, at: 0)
    let roots = SubagentTree.build(
        sessions: [
            SubagentTreeSession(id: "parent", cwd: "/repo", state: "working"),
            SubagentTreeSession(id: "sub", cwd: "/repo/.claude/worktrees/sub", state: "needs-input"),
        ],
        worktrees: [
            SubagentTreeWorktree(path: "/repo", branch: "main"),
            SubagentTreeWorktree(path: "/repo/.claude/worktrees/sub", branch: "task/sub"),
            SubagentTreeWorktree(path: "/repo/.claude/worktrees/bare", branch: "task/bare"),
        ]
    )
    let sessionRows = FleetModel.rows(sessions: [parent, sub, orphan], hostedIds: [])
    check(sessionRows.map(\.id) == ["sub", "parent", "orphan"], "flat rows still sort needs-you first")

    let tree = FleetModel.tree(sessionRows: sessionRows, roots: roots)
    check(tree.map(\.id) == ["parent", "/repo/.claude/worktrees/bare", "sub", "orphan"],
          "the parent leads, its subagents follow by name, a session outside the tree stays a root: \(tree.map(\.id))")
    check(tree.map(\.depth) == [0, 1, 1, 0], "depths mark the nesting: \(tree.map(\.depth))")
    let bare = tree[1]
    check(bare.isBareWorktree && bare.title == "bare" && bare.branch == "task/bare" && bare.worktree == "bare"
              && bare.project == "repo" && bare.state == .done && !bare.hosted,
          "a subagent worktree with no session is a muted bare row")
    check(!tree[2].isBareWorktree && tree[2].state == .needsInput, "a subagent with a session keeps that session's row")
    check(tree.filter { $0.id == "sub" }.count == 1, "a nested session is not repeated at the top level")
}

print("== kanban ==")
do {
    check(FleetColumn.column(for: .working) == .running, "working → Running")
    check(FleetColumn.column(for: .needsInput) == .needsYou, "needs-input → Needs you")
    check(FleetColumn.column(for: .done) == .done, "done → Done")
    check(FleetColumn.allCases.map(\.title) == ["To-do", "Running", "Needs you", "Done"], "the four columns, in board order")
}

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
