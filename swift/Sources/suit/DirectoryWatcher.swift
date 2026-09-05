import Foundation

// Watches directories for entries being written and calls back on the main
// queue once the writing goes quiet. The session monitor and the task monitor
// both watch a ~/.suit subdirectory whose files are small and rewritten
// atomically (mv), so a .write event on the directory is the reliable signal
// and the files themselves need no watching. Both kept the same source setup
// and the same 0.2 s debounce; this is those lines once.
//
// One watcher can cover several directories with one debounce: the statusline
// script rewrites a session file and claude-status.json in the same run, and
// the monitor wants one reload for the pair, not two.
final class DirectoryWatcher {
    // A burst of writes (a hook updating three session files, suit-bg dropping
    // a record and its first status) collapses into one callback this long
    // after the last of them.
    static let quietInterval: TimeInterval = 0.2

    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounce: DispatchWorkItem?

    // A path that can't be opened is skipped rather than failing the watcher;
    // callers create their directories before constructing one.
    init(paths: [String], onChange: @escaping () -> Void) {
        self.onChange = onChange
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in self?.schedule() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        debounce?.cancel()
        for source in sources { source.cancel() }
    }

    private func schedule() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.quietInterval, execute: work)
    }
}
