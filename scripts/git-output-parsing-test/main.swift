import Foundation

// Standalone assertions for GitOutputParsing — what git and gh print, read
// into the Git tab's structs.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

typealias Parsing = GitOutputParsing

print("== branchListing ==")
do {
    let output = "main\torigin/main\tahead 2, behind 1\nfeature\t\t\nold\torigin/old\tgone\nzeta\t\t\n"
    var asked: [String] = []
    let branches = Parsing.branchListing(
        output, currentBranch: "feature", worktreeByBranch: ["old": "/wt/old", "zeta": "/wt/zeta"],
        remoteRefs: ["origin/main", "origin/zeta"]
    ) { path in
        asked.append(path)
        return path == "/wt/old"
    }
    check(branches.map(\.name) == ["feature", "main", "old", "zeta"], "current first, then alphabetical: \(branches.map(\.name))")
    let main = branches[1]
    check(main.upstream == "origin/main" && main.ahead == 2 && main.behind == 1 && main.remote == .published,
          "upstream, ahead/behind and a published remote state")
    let feature = branches[0]
    check(feature.isCurrent && feature.upstream == nil && feature.remote == .localOnly && !feature.isDirty,
          "the current branch: no upstream, never pushed")
    let old = branches[2]
    check(old.worktreePath == "/wt/old" && old.isDirty && old.remote == .gone,
          "a branch another worktree holds: its dirtiness asked, its upstream gone")
    check(branches[3].remote == .published && branches[3].upstream == nil,
          "a remote ref with the branch's name counts as published even untracked")
    check(asked == ["/wt/old", "/wt/zeta"], "dirtiness is asked once per worktree path, only for held branches: \(asked)")
    check(!feature.isDeletable && !old.isDeletable && main.isDeletable, "only a branch no worktree holds is deletable")
    check(Parsing.branchListing("", currentBranch: nil, worktreeByBranch: [:], remoteRefs: []) { _ in false }.isEmpty,
          "no output is no branches")
}

print("== pullRequests ==")
do {
    let json = """
    [{"number": 12, "headRefName": "feat", "state": "MERGED", "url": "u12", "statusCheckRollup": []},
     {"number": 9, "headRefName": "feat", "state": "OPEN", "url": "u9",
      "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "SUCCESS"}]},
     {"number": 3, "headRefName": "fix", "state": "CLOSED", "url": "u3",
      "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "FAILURE"}]},
     {"number": 4, "headRefName": "wip", "state": "OPEN", "url": "u4",
      "statusCheckRollup": [{"status": "IN_PROGRESS", "conclusion": null}]},
     {"number": 5, "headRefName": "odd", "state": "WEIRD", "url": "u5"},
     {"number": 6, "state": "OPEN", "url": "u6"}]
    """
    let prs = Parsing.pullRequests(json: Data(json.utf8))
    check(Set(prs.keys) == ["feat", "fix", "wip"], "keyed by branch; unknown states and missing branches dropped: \(prs.keys.sorted())")
    check(prs["feat"]?.number == 9 && prs["feat"]?.state == .open, "a branch with an open PR keeps the open one over a merged one")
    check(prs["feat"]?.checks == .passing, "all-complete-success rollup is passing")
    check(prs["fix"]?.checks == .failing && prs["fix"]?.state == .closed, "a failed check is failing")
    check(prs["wip"]?.checks == .pending, "an in-progress check is pending")
    check(Parsing.pullRequests(json: Data("nope".utf8)).isEmpty, "garbage is empty")

    let newestWins = Parsing.pullRequests(json: Data("""
    [{"number": 20, "headRefName": "b", "state": "MERGED", "url": "u"},
     {"number": 10, "headRefName": "b", "state": "CLOSED", "url": "u"}]
    """.utf8))
    check(newestWins["b"]?.number == 10, "with no open PR the last listed (gh lists newest first, so the newest still overwrites) wins: \(String(describing: newestWins["b"]?.number))")
}

print("== summarizeChecks ==")
do {
    check(Parsing.summarizeChecks(nil) == nil && Parsing.summarizeChecks([]) == nil, "no checks is nil, not a verdict")
    check(Parsing.summarizeChecks([["state": "ERROR"]]) == .failing, "a StatusContext ERROR is failing")
    check(Parsing.summarizeChecks([["state": "PENDING"], ["status": "COMPLETED", "conclusion": "SUCCESS"]]) == .pending,
          "one pending context makes the rollup pending")
    check(Parsing.summarizeChecks([["conclusion": "TIMED_OUT"], ["state": "PENDING"]]) == .failing, "a failure outranks a pending")
    check(Parsing.summarizeChecks([[:]]) == .pending, "an entry that says nothing yet is pending")
    check(Parsing.summarizeChecks([["status": "completed", "conclusion": "success"]]) == .passing, "case-insensitive")
}

print("== prDetail ==")
do {
    let detail = Parsing.prDetail(json: Data(#"{"state":"MERGED","mergedAt":"2026-01-02T03:04:05Z","body":"Fixes #1"}"#.utf8))
    check(detail?.state == .merged && detail?.body == "Fixes #1", "state and body")
    check(detail?.mergedAt == ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z"), "mergedAt parsed as ISO8601")
    let open = Parsing.prDetail(json: Data(#"{"state":"OPEN","mergedAt":null}"#.utf8))
    check(open?.state == .open && open?.mergedAt == nil && open?.body == "", "an open PR: no mergedAt, empty body")
    check(Parsing.prDetail(json: Data(#"{"body":"x"}"#.utf8)) == nil, "no state is nil")
}

print("== newestFailedRunId ==")
do {
    let runs = #"[{"databaseId": 3, "conclusion": "success"}, {"databaseId": 2, "conclusion": "failure"}, {"databaseId": 1, "conclusion": "timed_out"}]"#
    check(Parsing.newestFailedRunId(json: Data(runs.utf8)) == 2, "the first failed run in gh's newest-first order")
    check(Parsing.newestFailedRunId(json: Data(#"[{"databaseId": 3, "conclusion": "success"}, {"databaseId": 4, "conclusion": null}]"#.utf8)) == nil,
          "no failure (a run still going is not one) is nil")
    check(Parsing.newestFailedRunId(json: Data("{}".utf8)) == nil, "the wrong shape is nil")
}

print("== cappedRunLog ==")
do {
    check(Parsing.cappedRunLog("  short log \n", maxBytes: 100) == "short log", "a short log is returned trimmed")
    let long = String(repeating: "a", count: 50) + "TAIL"
    let capped = Parsing.cappedRunLog(long, maxBytes: 10)
    check(capped == "…(truncated)\naaaaaaTAIL", "a long log keeps its last maxBytes behind a marker: \(capped)")
}

print("== createdPRURL ==")
do {
    check(Parsing.createdPRURL(from: "Creating pull request…\nhttps://github.com/o/r/pull/7 \n") == "https://github.com/o/r/pull/7",
          "the last non-empty line, trimmed")
    check(Parsing.createdPRURL(from: "") == "", "no output is an empty URL")
}

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
