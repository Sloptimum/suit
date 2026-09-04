import Foundation

// The pure half of GitBranches: what git and gh print, turned into the structs
// the Git tab shows. GitBranches spawns the processes; this file only reads
// their output, so scripts/git-output-parsing-test.sh can assert the rules —
// which PR a branch keeps, when a check rollup is red, which run's log to
// fetch, how the branch list sorts — without git, gh, or a network.

// One local branch, as the Git tab lists it.
struct GitBranchInfo {
    let name: String
    let upstream: String?        // "origin/foo" or nil when no upstream is set
    let ahead: Int               // commits on this branch not on its upstream
    let behind: Int              // commits on its upstream not on this branch
    let isCurrent: Bool          // the shown root's checked-out branch
    let worktreePath: String?    // the worktree this branch is checked out in
    let isDirty: Bool            // that worktree has uncommitted changes
    let remote: GitBranchOps.RemoteState  // published / local-only / upstream gone

    // git will only delete a branch no worktree holds — the checked-out one
    // included (the shown root is itself a worktree, so `isCurrent` is implied
    // by `worktreePath`, but say both: a detached-HEAD root leaves neither set).
    var isDeletable: Bool { !isCurrent && worktreePath == nil }
}

// A pull request for a branch, from `gh pr list`.
struct GitPRInfo {
    enum State: String {
        case open = "OPEN"
        case merged = "MERGED"
        case closed = "CLOSED"
    }
    enum Checks {
        case passing, failing, pending
    }
    let number: Int
    let state: State
    let url: String
    let checks: Checks?
}

// One PR's detail from `gh pr view` (see GitHubCLI.prState): its state plus
// the merge timestamp and body.
struct GitPRDetail {
    let state: GitPRInfo.State
    let mergedAt: Date?
    let body: String
}

enum GitOutputParsing {
    // MARK: - git

    // `for-each-ref --format=%(refname:short)%09%(upstream:short)%09%(upstream:track,nobracket) refs/heads`
    // (one branch per line) into the Git tab's list: current first, then
    // alphabetical. `worktreeByBranch` says where each checked-out branch
    // lives, and `isDirty` answers for a worktree path — a closure so the
    // caller can run one `git status` per worktree and cache it.
    static func branchListing(
        _ output: String, currentBranch: String?, worktreeByBranch: [String: String],
        remoteRefs: Set<String>, isDirty: (String) -> Bool
    ) -> [GitBranchInfo] {
        var result: [GitBranchInfo] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.components(separatedBy: "\t")
            guard let name = cols.first, !name.isEmpty else { continue }
            let upstream = cols.count > 1 && !cols[1].isEmpty ? cols[1] : nil
            // "ahead 2, behind 1" / "gone" / "" → counts. The parse itself
            // lives in GitBranchOps, which the Files-tab branch row reads the
            // same field through.
            let track = GitBranchOps.parseTrack(cols.count > 2 ? cols[2] : "")
            let worktreePath = worktreeByBranch[name]
            result.append(GitBranchInfo(
                name: name, upstream: upstream, ahead: track.ahead, behind: track.behind,
                isCurrent: name == currentBranch, worktreePath: worktreePath,
                isDirty: worktreePath.map(isDirty) ?? false,
                remote: GitBranchOps.remoteState(branch: name, upstream: upstream, remoteRefs: remoteRefs)
            ))
        }
        result.sort { a, b in
            if a.isCurrent != b.isCurrent { return a.isCurrent }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return result
    }

    // MARK: - gh

    // `gh pr list --json number,headRefName,state,url,statusCheckRollup`,
    // keyed by branch. A branch with several PRs keeps its open one, else the
    // most recent (gh lists newest first).
    static func pullRequests(json: Data) -> [String: GitPRInfo] {
        guard let array = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return [:] }
        var result: [String: GitPRInfo] = [:]
        for entry in array {
            guard let branch = entry["headRefName"] as? String,
                  let number = entry["number"] as? Int,
                  let stateRaw = entry["state"] as? String,
                  let state = GitPRInfo.State(rawValue: stateRaw),
                  let url = entry["url"] as? String
            else { continue }
            let checks = summarizeChecks(entry["statusCheckRollup"] as? [[String: Any]])
            let pr = GitPRInfo(number: number, state: state, url: url, checks: checks)
            // Prefer an open PR over a stale merged/closed one for the branch.
            if let existing = result[branch], existing.state == .open, state != .open { continue }
            result[branch] = pr
        }
        return result
    }

    // statusCheckRollup mixes CheckRun (status/conclusion) and StatusContext
    // (state) entries; collapse to one traffic light. nil when there are no
    // checks at all.
    static func summarizeChecks(_ rollup: [[String: Any]]?) -> GitPRInfo.Checks? {
        guard let rollup, !rollup.isEmpty else { return nil }
        var anyPending = false
        for check in rollup {
            let conclusion = (check["conclusion"] as? String)?.uppercased() ?? ""
            let state = (check["state"] as? String)?.uppercased() ?? ""
            let status = (check["status"] as? String)?.uppercased() ?? ""
            if ["FAILURE", "TIMED_OUT", "CANCELLED", "ERROR", "ACTION_REQUIRED"].contains(conclusion)
                || ["FAILURE", "ERROR"].contains(state) {
                return .failing
            }
            if (status != "COMPLETED" && !status.isEmpty) || state == "PENDING"
                || (conclusion.isEmpty && state.isEmpty && status.isEmpty) {
                anyPending = true
            }
        }
        return anyPending ? .pending : .passing
    }

    // `gh pr view <n> --json state,mergedAt,body`. nil when the state is
    // missing or not one gh documents.
    static func prDetail(json: Data) -> GitPRDetail? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stateRaw = object["state"] as? String,
              let state = GitPRInfo.State(rawValue: stateRaw) else { return nil }
        let mergedAt = (object["mergedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return GitPRDetail(state: state, mergedAt: mergedAt, body: object["body"] as? String ?? "")
    }

    // `gh run list --json databaseId,conclusion` (newest first): the newest
    // run that failed, or nil when every run passed or is still going.
    static func newestFailedRunId(json: Data) -> Int? {
        guard let runs = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return nil }
        return runs.first(where: {
            let conclusion = ($0["conclusion"] as? String)?.uppercased() ?? ""
            return ["FAILURE", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE"].contains(conclusion)
        })?["databaseId"] as? Int
    }

    // A run log capped for a routed prompt, so a huge log can't blow it up.
    // Keeps the tail: the failure message is at the end of a build log.
    static func cappedRunLog(_ log: String, maxBytes: Int) -> String {
        let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.utf8.count <= maxBytes { return trimmed }
        let tail = String(decoding: Array(trimmed.utf8.suffix(maxBytes)), as: UTF8.self)
        return "…(truncated)\n" + tail
    }

    // `gh pr create` prints the new PR's URL on its last stdout line.
    static func createdPRURL(from output: String) -> String {
        (output.split(separator: "\n", omittingEmptySubsequences: true).last.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespaces)
    }
}
