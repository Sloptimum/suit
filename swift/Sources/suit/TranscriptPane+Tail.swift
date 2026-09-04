import Cocoa

// Live-tail / file-watching for the transcript pane: a FileTailer follows the
// JSONL file and hands over each batch of complete lines, which are parsed
// into entries and appended to the view.

extension TranscriptPaneContent {
    func watch(path: String) {
        let tailer = FileTailer(
            path: path,
            onReset: { [weak self] in
                // Truncated or recreated (a resumed session): start over.
                guard let self else { return }
                self.resetEntries()
                self.render()
            },
            onLines: { [weak self] lines in self?.consume(lines: lines) }
        )
        self.tailer = tailer
        tailer.start()
    }

    func stopWatching() {
        tailer?.stop()
        tailer = nil
    }

    // Parses a batch of complete lines and appends the new entries.
    func consume(lines: [String]) {
        var newEntries: [TranscriptEntry] = []
        var newSourceLines: [Int] = []
        for line in lines {
            lineCounter += 1
            let parsed = parseTranscriptLine(line)
            newEntries.append(contentsOf: parsed)
            newSourceLines.append(contentsOf: Array(repeating: lineCounter, count: parsed.count))
        }

        guard !newEntries.isEmpty else { return }
        entries.append(contentsOf: newEntries)
        entrySourceLines.append(contentsOf: newSourceLines)
        // Trimming means rebuilding the whole document (the dropped prefix's
        // character length isn't tracked), so it is done in one big bite rather
        // than one entry at a time. Trimming at exactly maxEntries meant that
        // every subsequent append — and Claude Code appends constantly — paid a
        // full re-render of 4000 entries, which is why a long-running session's
        // transcript pane got slower the longer it ran. Overshooting by `slack`
        // makes that cost land once per `slack` entries instead of once per
        // entry: the same ceiling, ~1000× less work.
        if entries.count > Self.maxEntries + Self.trimSlack {
            let drop = entries.count - Self.maxEntries
            entries.removeFirst(drop)
            entrySourceLines.removeFirst(drop)
            render()
        } else {
            append(attributed: attributedString(for: newEntries))
        }
    }
}
