import Foundation

// Branch / PR overview: the shipping end of the review
// workflow. `GitBranchList` reads the repo's local branches with their
// ahead/behind vs upstream, which worktree (if any) has them checked out, and
// whether that worktree is dirty — all from plumbing git, off the main thread.
// `GitHubCLI` layers optional `gh` actions on top (PR status, create, open on
// web), degrading to a no-op when `gh` isn't installed. This file spawns; the
// reading of what git and gh print is GitOutputParsing, which has a harness.

enum GitBranchList {

    // The repo's local branches, current first, then alphabetical. Ahead/behind
    // come from `%(upstream:track)` in one for-each-ref pass rather than a
    // rev-list per branch; dirtiness is one `git status` per *worktree* (few),
    // cached so branches sharing a worktree don't re-run it.
    static func compute(root: String, currentBranch: String?) -> [GitBranchInfo] {
        guard let output = runProcess(Git.executable, [
            "-C", root, "for-each-ref",
            "--format=%(refname:short)%09%(upstream:short)%09%(upstream:track,nobracket)",
            "refs/heads",
        ]) else { return [] }

        let worktrees = worktreeBranchMap(root: root)
        let remotes = remoteRefs(root: root)
        var dirtyByPath: [String: Bool] = [:]
        return GitOutputParsing.branchListing(
            output, currentBranch: currentBranch, worktreeByBranch: worktrees, remoteRefs: remotes
        ) { path in
            if let cached = dirtyByPath[path] { return cached }
            let dirty = WorktreeTasks.hasUncommittedChanges(path)
            dirtyByPath[path] = dirty
            return dirty
        }
    }

    // Every remote-tracking ref in short form ("origin/main"), from the same
    // cheap for-each-ref plumbing as the branch pass. This is a *local* view of
    // the remote — refs go stale until the next `fetch --prune`, exactly as
    // git's own "gone" marker does.
    private static func remoteRefs(root: String) -> Set<String> {
        guard let output = runProcess(Git.executable, [
            "-C", root, "for-each-ref", "--format=%(refname:short)", "refs/remotes",
        ]) else { return [] }
        return Set(output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
    }

    // branch name → the worktree path it's checked out in, from
    // `git worktree list --porcelain` (WorktreeSwitcher parses it).
    private static func worktreeBranchMap(root: String) -> [String: String] {
        guard let output = runProcess(Git.executable, ["-C", root, "worktree", "list", "--porcelain"]) else {
            return [:]
        }
        return Dictionary(
            WorktreeSwitcher.parseWorktrees(output).compactMap { entry in entry.branch.map { ($0, entry.path) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

// The optional GitHub layer. Every entry point is a no-op / graceful failure
// when `gh` isn't installed, so the Git tab works identically without it.
enum GitHubCLI {
    // gh lives in Homebrew's bin, which isn't on a GUI app's minimal PATH — so
    // probe the known install locations directly rather than trusting $PATH.
    // SUIT_GH_PATH overrides for tests/dev runs (mirrors SUIT_RG_PATH).
    // Resolved once (nil = not installed); the result is stable for a session.
    private static let resolvedPath: String? = {
        var candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh", "/run/current-system/sw/bin/gh"]
        if let envPath = ProcessInfo.processInfo.environment["SUIT_GH_PATH"], !envPath.isEmpty {
            candidates.insert(envPath, at: 0)
        }
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        // Last resort: let the login shell resolve it.
        if let found = runProcess("/bin/zsh", ["-l", "-c", "command -v gh"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !found.isEmpty,
           FileManager.default.isExecutableFile(atPath: found) {
            return found
        }
        return nil
    }()

    static var isAvailable: Bool { resolvedPath != nil }

    // All PRs (any state) for the repo, keyed by their branch (headRefName). A
    // branch with several PRs keeps its open one, else the most recent. Returns
    // empty on any failure (gh missing, no remote, not authed, offline) — the
    // caller just shows branches without PR badges.
    static func pullRequests(root: String) -> [String: GitPRInfo] {
        guard let gh = resolvedPath,
              case .success(let output) = run(gh, cwd: root, [
                  "pr", "list", "--state", "all", "--limit", "100",
                  "--json", "number,headRefName,state,url,statusCheckRollup",
              ]),
              let data = output.data(using: .utf8)
        else { return [:] }
        return GitOutputParsing.pullRequests(json: data)
    }

    // The repo's default branch ("main"/"master"), from origin/HEAD when set.
    static func defaultBranch(root: String) -> String? {
        // Both of these are probes — an unset origin/HEAD and a repo with no
        // `main` are ordinary answers, so they don't log as failures.
        if let head = runProcess(
            Git.executable, ["-C", root, "symbolic-ref", "--short", "-q", "refs/remotes/origin/HEAD"],
            probe: true
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty {
            return (head as NSString).lastPathComponent
        }
        for candidate in ["main", "master"] {
            if runProcess(Git.executable, ["-C", root, "rev-parse", "--verify", "-q", candidate], probe: true) != nil {
                return candidate
            }
        }
        return nil
    }

    // A best-effort PR body: the branch's commit subjects that aren't on the
    // default branch, one bullet each (empty when the base can't be resolved).
    static func commitBody(root: String, branch: String) -> String {
        guard let base = defaultBranch(root: root), base != branch,
              let log = runProcess(Git.executable, ["-C", root, "log", "--format=%s", "\(base)..\(branch)"])
        else { return "" }
        let subjects = log.split(separator: "\n", omittingEmptySubsequences: true).map { "- \($0)" }
        return subjects.joined(separator: "\n")
    }

    // `gh pr create` for the branch. Returns the new PR's URL (gh prints it on
    // the last stdout line) or gh's own error text — shown verbatim so an
    // unpushed branch / missing auth explains itself.
    static func createPR(root: String, branch: String, title: String, body: String) -> Result<String, WorktreeTaskError> {
        guard let gh = resolvedPath else { return .failure(WorktreeTaskError(message: "The gh CLI isn’t installed.")) }
        let result = run(gh, cwd: root, ["pr", "create", "--head", branch, "--title", title, "--body", body])
        switch result {
        case .success(let out):
            return .success(GitOutputParsing.createdPRURL(from: out))
        case .failure(let error):
            return .failure(error)
        }
    }

    // `gh pr merge <n> --merge` for the PR. Deliberately *not* `--delete-branch`:
    // the branch is checked out in a task worktree, so gh's local delete would
    // fail — worktree + branch cleanup is the caller's job (WorktreeTasks).
    // Success carries gh's stdout; failure gh's own error text (branch
    // protection, "not mergeable", …) verbatim so the caller can react to it.
    static func mergePR(root: String, number: Int) -> Result<String, WorktreeTaskError> {
        guard let gh = resolvedPath else { return .failure(WorktreeTaskError(message: "The gh CLI isn’t installed.")) }
        return run(gh, cwd: root, ["pr", "merge", "\(number)", "--merge"])
    }

    // One PR's current state/mergedAt/body from `gh pr view` — used to confirm
    // a merge actually landed (state == MERGED), to adopt an in-flight run on
    // relaunch, and to read trailer lines out of the body.
    static func prState(root: String, number: Int) -> Result<GitPRDetail, WorktreeTaskError> {
        guard let gh = resolvedPath else { return .failure(WorktreeTaskError(message: "The gh CLI isn’t installed.")) }
        switch run(gh, cwd: root, ["pr", "view", "\(number)", "--json", "state,mergedAt,body"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let output):
            guard let data = output.data(using: .utf8),
                  let detail = GitOutputParsing.prDetail(json: data)
            else { return .failure(WorktreeTaskError(message: "Couldn’t parse gh pr view output.")) }
            return .success(detail)
        }
    }

    // The reviewer feedback on a PR: review summaries + conversation
    // comments from `gh pr view <n> --json reviews,comments`, parsed by the
    // UI-free `FeedbackRouting`. Nil on any failure (gh missing / not authed /
    // offline) so the feedback inbox just skips that PR.
    static func prFeedback(root: String, number: Int) -> FeedbackRouting.PRFeedback? {
        guard let gh = resolvedPath,
              case .success(let output) = run(gh, cwd: root, ["pr", "view", "\(number)", "--json", "reviews,comments"]),
              let data = output.data(using: .utf8)
        else { return nil }
        return FeedbackRouting.parsePRFeedback(json: data)
    }

    // The failing checks on a PR: the per-check detail behind the
    // `pr list` traffic light, from `gh pr view <n> --json statusCheckRollup`.
    static func failingChecks(root: String, number: Int) -> [FeedbackRouting.CheckFailure] {
        guard let gh = resolvedPath,
              case .success(let output) = run(gh, cwd: root, ["pr", "view", "\(number)", "--json", "statusCheckRollup"]),
              let data = output.data(using: .utf8)
        else { return [] }
        return FeedbackRouting.parseFailingChecks(json: data)
    }

    // A best-effort tail of the failed CI run's log for the branch:
    // find the newest failed run (`gh run list`) and pull only its failed steps
    // (`gh run view --log-failed`), capped so a huge log can't blow up the
    // routed prompt. Empty when gh can't surface it (Actions off, no failed run,
    // permissions) — the routed prompt then leans on the failing-check names.
    static func failedRunLog(root: String, branch: String, maxBytes: Int = 6000) -> String {
        guard let gh = resolvedPath,
              case .success(let listing) = run(gh, cwd: root, [
                  "run", "list", "--branch", branch, "--limit", "20",
                  "--json", "databaseId,conclusion",
              ]),
              let data = listing.data(using: .utf8),
              let failedId = GitOutputParsing.newestFailedRunId(json: data),
              case .success(let log) = run(gh, cwd: root, ["run", "view", "\(failedId)", "--log-failed"])
        else { return "" }
        return GitOutputParsing.cappedRunLog(log, maxBytes: maxBytes)
    }

    // Whether gh has credentials for the repo's host (`gh auth status` exits 0).
    // False when gh isn't installed.
    static func isAuthenticated(root: String) -> Bool {
        guard let gh = resolvedPath else { return false }
        if case .success = run(gh, cwd: root, ["auth", "status"]) { return true }
        return false
    }

    // Opens the branch on GitHub: the PR page when one exists, otherwise the
    // "create PR" compare page — both in the browser (gh handles auth). Runs
    // detached; failures are silent (best-effort convenience action).
    static func openWeb(root: String, branch: String, hasPR: Bool) {
        guard let gh = resolvedPath else { return }
        let args = hasPR
            ? ["pr", "view", branch, "--web"]
            : ["pr", "create", "--head", branch, "--web"]
        DispatchQueue.global(qos: .userInitiated).async { _ = run(gh, cwd: root, args) }
    }

    // MARK: - PR review inbox

    // Open PRs that involve me — authored, assigned, or review-requested — as a
    // review inbox (`PRReviewInbox`). Two `gh pr list --search` passes (involves
    // covers authored/assigned/commented; review-requested is its own qualifier)
    // are unioned and deduped by number. Empty on any failure (gh missing / not
    // authed / offline), so the inbox section just stays hidden.
    static func reviewInbox(root: String) -> [PRReviewItem] {
        guard let gh = resolvedPath else { return [] }
        let fields = "number,title,author,headRefName,url,statusCheckRollup"
        var byNumber: [Int: PRReviewItem] = [:]
        for query in ["is:open involves:@me", "is:open review-requested:@me"] {
            guard case .success(let output) = run(gh, cwd: root, [
                "pr", "list", "--search", query, "--limit", "50", "--json", fields,
            ]) else { continue }
            for item in PRReviewInbox.parseList(output) where byNumber[item.number] == nil {
                byNumber[item.number] = item
            }
        }
        return byNumber.values.sorted { $0.number > $1.number }
    }

    // A PR's unified diff (`gh pr diff <n>`), fed straight into a DiffPaneContent.
    // Empty on failure so the caller shows an empty diff rather than erroring.
    static func prDiff(root: String, number: Int) -> String {
        guard let gh = resolvedPath,
              case .success(let output) = run(gh, cwd: root, ["pr", "diff", "\(number)"])
        else { return "" }
        return output
    }

    // Submit a review on a PR (`gh pr review <n> --approve|--request-changes|
    // --comment [--body …]`). The argv is composed by the UI-free
    // `PRReviewComposer`. Success carries gh's stdout; failure its error text
    // (already-reviewed, can't-approve-own-PR, not authed) verbatim.
    static func prReview(root: String, number: Int, decision: PRReviewDecision, body: String) -> Result<String, WorktreeTaskError> {
        guard let gh = resolvedPath else { return .failure(WorktreeTaskError(message: "The gh CLI isn’t installed.")) }
        return run(gh, cwd: root, PRReviewComposer.reviewArguments(number: number, decision: decision, body: body))
    }

    // gh with stdout/stderr captured; stderr's first line is the error message.
    // gh has no `-C` flag (that's a git-ism) — it's pointed at a repo by its
    // working directory instead, which is also what the ops-log row names,
    // since argv carries no repo.
    private static func run(_ executable: String, cwd: String, _ arguments: [String]) -> Result<String, WorktreeTaskError> {
        let result: ProcessResult
        do {
            result = try runProcessCapturing(
                executable, arguments, cwd: cwd, detail: (cwd as NSString).lastPathComponent
            )
        } catch {
            return .failure(WorktreeTaskError(message: error.localizedDescription))
        }
        if result.succeeded { return .success(result.stdout) }
        return .failure(WorktreeTaskError(message: result.firstStderrLine ?? "gh exited \(result.status)"))
    }
}
