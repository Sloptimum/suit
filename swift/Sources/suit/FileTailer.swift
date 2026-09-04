import Foundation

// Tails one growing file — a Claude transcript, the checkpoint log, a task's
// captured output — and hands back each batch of complete lines as they land.
// Generalised from the three copies the transcript pane, the checkpoint
// timeline and the task monitor each kept of the same DispatchSource + offset
// + remainder dance (the FileWatcher story, one file type later).
//
// Two rules a naive tail gets wrong:
//  * **A line arrives in pieces.** A writer can flush mid-line. Only whole
//    lines are delivered; the fragment waits for the next event, by rewinding
//    the offset to just past the last newline so it is re-read with its ending.
//  * **The file can start over.** Truncated in place (its size drops below the
//    offset) or replaced (a delete/rename event on the inode) — either way what
//    the owner built from the old bytes is void. `onReset` says so before the
//    first lines of the new content arrive; after a replace the path is
//    re-opened if something is there again (a resumed session recreates its
//    transcript).
//
// Callbacks fire on the main queue. The owner retains the tailer, so the
// callbacks must capture the owner weakly. The pure read is a static so the
// harness asserts the line splitting without a run loop.
final class FileTailer {
    let path: String
    private let onReset: () -> Void
    private let onLines: ([String]) -> Void

    private var offset: UInt64 = 0
    private var source: DispatchSourceFileSystemObject?
    private var stopped = false

    init(path: String, onReset: @escaping () -> Void = {}, onLines: @escaping ([String]) -> Void) {
        self.path = path
        self.onReset = onReset
        self.onLines = onLines
    }

    deinit { stop() }

    // Reads what is there now, delivers it, then watches for more.
    func start() {
        guard !stopped else { return }
        readMore()
        watch()
    }

    // Idempotent and terminal: a stopped tailer stays stopped, so pointing a
    // pane at a different file means dropping this one and making a new
    // tailer (the FileWatcher contract; teardown() may call it twice).
    func stop() {
        stopped = true
        // The cancel handler closes the descriptor.
        source?.cancel()
        source = nil
    }

    // MARK: - The pure read

    // Everything past `offset`, as whole lines, plus where the next read should
    // start. nil if the file can't be opened. A file that shrank below `offset`
    // (truncated in place) is re-read from the start, and `restarted` says so.
    static func readAppended(path: String, from offset: UInt64)
        -> (lines: [String], newOffset: UInt64, restarted: Bool)? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var start = offset
        var restarted = false
        if size < start {
            start = 0
            restarted = true
        }
        guard size > start else { return ([], size, restarted) }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return ([], size, restarted) }

        // Only whole lines; a final fragment (no trailing newline) is left for
        // the next read by rewinding the offset to just after the last newline.
        var consumed = start
        var lines: [String] = []
        var lineStart = data.startIndex
        var idx = data.startIndex
        while idx < data.endIndex {
            if data[idx] == UInt8(ascii: "\n") {
                let lineData = data[lineStart..<idx]
                lines.append(String(decoding: lineData, as: UTF8.self))
                consumed += UInt64(data.distance(from: lineStart, to: idx)) + 1
                lineStart = data.index(after: idx)
            }
            idx = data.index(after: idx)
        }
        return (lines, consumed, restarted)
    }

    // MARK: - Watching

    private func readMore() {
        guard let read = Self.readAppended(path: path, from: offset) else { return }
        offset = read.newOffset
        if read.restarted { onReset() }
        if !read.lines.isEmpty { onLines(read.lines) }
    }

    private func watch() {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source, !self.stopped else { return }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                // The inode we hold is gone from the name. Start over on
                // whatever is at the path now, if anything.
                self.source?.cancel()
                self.source = nil
                self.offset = 0
                self.onReset()
                if FileManager.default.fileExists(atPath: self.path) {
                    self.start()
                }
                return
            }
            self.readMore()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }
}
