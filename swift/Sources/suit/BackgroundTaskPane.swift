import Cocoa

// The background-task monitor pane: lists the background
// processes launched from a pane's shell — command, status (running /
// done / failed), listening port when detectable — over a live tail of the
// selected task's captured output. Read-only, like the transcript/diff panes;
// discovered by BackgroundTaskStore from the ~/.suit/tasks records the suit-bg
// wrapper writes, filtered to this pane's shell subtree.
//
// A task flipping to `failed` pulses this pane's strip item (the bell route,
// via tab?.wantsAttention) and folds a "N failed" suffix into the header title,
// so a dev server that fell over is noticed without scrolling any shell.
final class BackgroundTaskPaneContent: NSObject, PaneContent, NSTableViewDataSource, NSTableViewDelegate {
    weak var pane: Pane?
    weak var tab: Tab?

    // The shell whose background jobs this pane shows; 0 = every tracked task
    // (the palette's window-wide entry, when no terminal pane is focused). Read
    // by the window controller to decide reuse vs. rebind on re-open.
    let rootShellPid: Int32
    private let paneTitle: String

    private let splitView = SuitSplitView(frame: .zero)
    private let tableScroll = NSScrollView(frame: .zero)
    private let table = NSTableView(frame: .zero)
    private let logScroll = NSScrollView(frame: .zero)
    private let logView = NSTextView(frame: .zero)

    private(set) var displayedTasks: [BackgroundTask] = []
    // The task whose log is currently tailed (by id, so it survives reloads).
    private var selectedTaskId: String?
    // Last title pushed to the strip, so the heartbeat only republishes on change.
    private var lastPublishedTitle: String?

    // The selected task's log and its live tail (nil while none is shown).
    private var logPath: String?
    private var logTailer: FileTailer?

    private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    var view: NSView { splitView }
    var focusTarget: NSView { table }
    var defaultTitle: String { paneTitle }

    init(shellPid: Int32, title: String) {
        rootShellPid = shellPid
        paneTitle = title
        super.init()
        buildUI()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeDidUpdate), name: BackgroundTaskStore.didUpdate, object: nil
        )
        reload()
        // A monitor pane opening should show what's already tracked immediately
        // and pick up liveness; nudge the store to re-probe.
        BackgroundTaskStore.shared.reload()
    }

    private func buildUI() {
        splitView.isVertical = false          // stacked: task list over log tail
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // Task list.
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.selectionHighlightStyle = .regular
        table.usesAutomaticRowHeights = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.drawsBackground = false
        tableScroll.borderType = .noBorder

        // Log tail.
        logView.isEditable = false
        logView.isSelectable = true
        logView.isRichText = false
        logView.usesFindBar = true
        logView.isIncrementalSearchingEnabled = true
        logView.textContainerInset = NSSize(width: 8, height: 8)
        logView.font = font
        logView.textColor = Theme.textDim
        logView.drawsBackground = false
        logView.string = "No background task selected.\n\nRun a long-lived command through the suit-bg wrapper (e.g. `suit-bg npm run dev`) to track it here."
        logView.autoresizingMask = [.width]
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.textContainer?.widthTracksTextView = true
        logScroll.documentView = logView
        logScroll.hasVerticalScroller = true
        logScroll.drawsBackground = false
        logScroll.borderType = .noBorder

        splitView.addArrangedSubview(tableScroll)
        splitView.addArrangedSubview(logScroll)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
    }

    // MARK: - Store updates

    @objc private func storeDidUpdate() {
        reload()
    }

    private func reload() {
        let previous = displayedTasks
        let current = rootShellPid > 0
            ? BackgroundTaskStore.shared.tasks(underShell: rootShellPid)
            : BackgroundTaskStore.shared.tasks

        // Attention: a task that just flipped to failed pulses the strip item.
        let failed = BackgroundTasks.newlyFailed(previous: previous, current: current)
        if !failed.isEmpty { tab?.wantsAttention() }

        displayedTasks = current
        table.reloadData()

        // Header title reflects a running/failed summary so a backgrounded
        // monitor tab still advertises trouble.
        let failedCount = current.filter { $0.status == .failed }.count
        let runningCount = current.filter { $0.status == .running }.count
        var title = paneTitle
        if failedCount > 0 {
            title += " — \(failedCount) failed"
        } else if runningCount > 0 {
            title += " — \(runningCount) running"
        }
        // Only republish on a real change — the heartbeat calls this every 3 s
        // and each publish reloads the strip.
        if title != lastPublishedTitle {
            lastPublishedTitle = title
            tab?.contentTitleDidChange(title)
        }

        // Keep the tail pinned to the selected task; if it's gone, or none was
        // chosen yet, default to the most recent one.
        if let id = selectedTaskId, let idx = current.firstIndex(where: { $0.id == id }) {
            selectRow(idx)
        } else if selectedTaskId == nil, let first = current.first {
            selectedTaskId = first.id
            selectRow(0)
            tailLog(of: first)
        } else if let id = selectedTaskId, !current.contains(where: { $0.id == id }) {
            // The tailed task's record was cleared; drop the tail.
            stopTailing()
            selectedTaskId = nil
            logView.string = ""
        }
    }

    private func selectRow(_ idx: Int) {
        guard idx >= 0, idx < table.numberOfRows else { return }
        table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { displayedTasks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayedTasks.count else { return nil }
        let task = displayedTasks[row]
        let cell = BackgroundTaskRowView()
        cell.configure(with: task, font: font)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let idx = table.selectedRow
        guard idx >= 0, idx < displayedTasks.count else { return }
        let task = displayedTasks[idx]
        selectedTaskId = task.id
        tailLog(of: task)
    }

    // MARK: - Log tail (a FileTailer on the selected task's captured output)

    private func tailLog(of task: BackgroundTask) {
        // Idempotent: re-selecting the already-tailed task (which happens every
        // heartbeat, since reloadData drops and we restore the selection) must
        // not tear down the live tail and blank the view — leave it running.
        if task.logPath == logPath, logTailer != nil { return }
        stopTailing()
        logView.string = ""
        guard let path = task.logPath, FileManager.default.fileExists(atPath: path) else {
            logPath = nil
            logView.string = task.logPath == nil
                ? "This task has no captured log."
                : "Log file not found:\n\(task.logPath ?? "")"
            return
        }
        logPath = path
        watchLog(path: path)
        logView.scrollToEndOfDocument(nil)
    }

    private func watchLog(path: String) {
        let tailer = FileTailer(
            path: path,
            onReset: { [weak self] in self?.logView.string = "" },
            onLines: { [weak self] lines in self?.appendLog(lines: lines) }
        )
        logTailer = tailer
        tailer.start()
    }

    private func appendLog(lines: [String]) {
        let wasAtBottom = isLogAtBottom
        let text = lines.joined(separator: "\n") + "\n"
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: Theme.textDim,
        ])
        logView.textStorage?.append(attributed)
        if wasAtBottom { logView.scrollToEndOfDocument(nil) }
    }

    private var isLogAtBottom: Bool {
        let visible = logScroll.contentView.bounds
        return visible.maxY >= logView.frame.maxY - 40
    }

    private func stopTailing() {
        logTailer?.stop()
        logTailer = nil
    }

    // MARK: - Appearance

    func applyFont(_ newFont: NSFont) {
        font = newFont
        logView.font = newFont
        table.reloadData()
    }

    func applyBackground(_ color: NSColor) {
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = color.cgColor
    }

    func teardown() {
        stopTailing()
        NotificationCenter.default.removeObserver(self)
    }
}

// One row of the monitor: a colored status dot, the command, and a right-aligned
// "· :PORT · status" trailer. Plain drawing so it stays cheap during frequent
// reloads.
private final class BackgroundTaskRowView: NSView {
    private let dot = NSView()
    private let commandLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        addSubview(dot)
        commandLabel.lineBreakMode = .byTruncatingMiddle
        commandLabel.cell?.usesSingleLineMode = true
        addSubview(commandLabel)
        statusLabel.alignment = .right
        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        statusLabel.textColor = Theme.textFaint
        addSubview(statusLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with task: BackgroundTask, font: NSFont) {
        dot.layer?.backgroundColor = Self.color(for: task.status).cgColor
        commandLabel.stringValue = task.command
        commandLabel.font = NSFont.systemFont(ofSize: 11.5)
        commandLabel.textColor = task.status == .failed ? Theme.failed : Theme.textPrimary
        var trailer = task.status.label
        if let port = task.port { trailer = ":\(port) · " + trailer }
        statusLabel.stringValue = trailer
        needsLayout = true
    }

    private static func color(for status: BackgroundTaskStatus) -> NSColor {
        switch status {
        case .running: return Theme.sessionBusy
        case .exitedClean: return Theme.sessionDone
        case .failed: return Theme.failed
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        dot.frame = NSRect(x: 10, y: (h - 7) / 2, width: 7, height: 7)
        statusLabel.sizeToFit()
        let statusWidth = min(statusLabel.frame.width, bounds.width * 0.5)
        statusLabel.frame = NSRect(x: bounds.width - statusWidth - 10, y: (h - 16) / 2, width: statusWidth, height: 16)
        let cmdX: CGFloat = 26
        commandLabel.frame = NSRect(
            x: cmdX, y: (h - 16) / 2,
            width: max(0, statusLabel.frame.minX - cmdX - 8), height: 16
        )
    }
}
