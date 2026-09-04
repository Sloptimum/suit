import Cocoa

extension DiffPaneContent {
    // MARK: - Loading

    // Shows the working tree's uncommitted changes (vs HEAD, so staged and
    // unstaged both appear) for the repo at `root`.
    func loadGitDiff(root: String) {
        let name = (root as NSString).lastPathComponent
        load(title: "diff: \(name)", status: name, root: root) {
            runProcess(Git.executable, ["-C", root, "diff", "HEAD"]) ?? ""
        }
    }

    // Feeds a diff the caller already holds (a restored tab, a review set).
    // `reload` is what Refresh re-runs — on a worker, like every load.
    func loadDiffText(_ diff: String, title: String, root: String?, reload: (() -> String)? = nil) {
        loadGeneration += 1
        gitRoot = root
        self.reload = reload
        loadStatus = title
        setDiff(diff, status: title)
        tab?.contentTitleDidChange(title)
    }

    // The load every git- or gh-backed diff goes through. The producer spawns
    // a process whose output can run to megabytes — a whole commit, a branch's
    // divergence, every worktree since a mark — so it runs on a worker while a
    // placeholder holds the tab. Nothing that spawns git runs on the main
    // thread here: a slow repo or a network volume must never beachball the
    // window. `status` is the status field's prefix when it should differ from
    // the tab title; `reviewingPR` is what Submit Review posts to, nil for git.
    func load(title: String, status: String? = nil, root: String?,
              reviewingPR: ReviewingPR? = nil, producer: @escaping () -> String) {
        let generation = beginLoad(title: title, status: status, root: root, reviewingPR: reviewingPR, reload: producer)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let diff = producer()
            DispatchQueue.main.async { self?.finishLoad(generation, diff: diff) }
        }
    }

    // The two halves of `load`, for a caller whose producer yields more than
    // the text (the catch-up diff learns its title's totals from the composed
    // set). Puts up the placeholder and returns the generation that
    // `finishLoad` must present.
    func beginLoad(title: String, status: String? = nil, root: String?,
                   reviewingPR: ReviewingPR? = nil, reload: @escaping () -> String) -> Int {
        loadGeneration += 1
        self.reviewingPR = reviewingPR
        gitRoot = root
        self.reload = reload
        loadStatus = status ?? title
        setDiff("Loading \(title)…", status: loadStatus)
        statusLabel.stringValue = "\(loadStatus) — loading…"
        tab?.contentTitleDidChange(title)
        return loadGeneration
    }

    // Applies a finished load — unless a newer load or refresh started since,
    // in which case this one is stale and dropped. `title` is for a load that
    // only knows its title once the text is in hand.
    func finishLoad(_ generation: Int, diff: String, title: String? = nil) {
        guard generation == loadGeneration else { return }
        if let title {
            loadStatus = title
            tab?.contentTitleDidChange(title)
        }
        setDiff(diff, status: loadStatus)
    }

    // Re-runs the producer on a worker and swaps the text in when it lands;
    // the current text stays up meanwhile rather than flashing a placeholder.
    // (Rebuilding the status from `loadStatus` also ends the old habit of
    // feeding the whole label back in as the prefix, which doubled the
    // "— N files" suffix on every click.)
    @objc func refresh(_ sender: Any?) {
        guard let reload else { return }
        loadGeneration += 1
        let generation = loadGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let diff = reload()
            DispatchQueue.main.async { self?.finishLoad(generation, diff: diff) }
        }
    }

    private func setDiff(_ diff: String, status: String) {
        diffLines = diff.isEmpty ? [] : UnifiedDiffParser.parse(diff)
        changedFilePaths = UnifiedDiffParser.changedPaths(diff)
        if diffLines.isEmpty {
            statusLabel.stringValue = "\(status) — no changes"
        } else {
            let files = changedFilePaths.count
            statusLabel.stringValue = "\(status) — \(files) file\(files == 1 ? "" : "s") · n/p walk, o open, c comment"
        }
        render()
        updateReviewButton()
    }

    // Reflects the draft's comment count into the header button (hidden when
    // empty), then relays out so the status field reclaims the freed width.
    private func updateReviewButton() {
        let count = reviewDraft.count
        reviewButton.isHidden = count == 0
        reviewButton.title = "Review (\(count))"
        layoutContents()
    }

    // Re-run after any draft mutation from outside (a send that cleared it).
    func reviewChanged() {
        render()
        updateReviewButton()
    }

    // Loads comments restored from a SavedTab into the draft.
    func restoreComments(_ comments: [DiffReviewComment]?) {
        guard let comments, !comments.isEmpty else { return }
        for c in comments {
            reviewDraft.set(text: c.text, file: c.file, side: c.side, line: c.line, lineText: c.lineText)
        }
        reviewChanged()
    }

    // The human-readable name of what's under review, for the prompt header.
    var reviewRef: String {
        if let gitRoot { return (gitRoot as NSString).lastPathComponent }
        return statusLabel.stringValue.components(separatedBy: " — ").first ?? "these changes"
    }

    @objc func modeChanged(_ sender: Any?) {
        updateModeVisibility()
        if let window = containerView.window, window.firstResponder === unifiedText || window.firstResponder === leftText {
            window.makeFirstResponder(focusTarget)
        }
    }

    func updateModeVisibility() {
        let unified = modePicker.selectedSegment == 0
        unifiedScroll.isHidden = !unified
        leftScroll.isHidden = unified
        rightScroll.isHidden = unified
    }
}
