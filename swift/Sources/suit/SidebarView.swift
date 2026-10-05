import Cocoa

// The window's left panel, toggled with Cmd-B: Files / Search / Source Control
// / Sessions / SSH Hosts / Notes / Background (in that order — see `railOrder`),
// picked with the segmented control across its top. This view owns the tab
// model: the enum, the order, the persisted selection.
//
// The panel draws no ground of its own. It is the view of the window's system
// sidebar item (WindowSplitViewController), so the material behind it — Liquid
// Glass on macOS 26 and later, edge to edge on 27 — is AppKit's, and follows
// the window's appearance. Everything inside is laid out on a clear ground.
// It used to be a hand-made frosted card floating on a painted well beside a
// VS Code-style icon strip; both were drawings of what the system sidebar
// already is.
//
// The picker is the Xcode navigator's answer to "which panel": a row of icon
// segments at the top of the panel itself. It goes away with the panel on ⌘B,
// which the strip was built to avoid — the toolbar's Source Control badge now
// carries the one signal that has to survive a collapse, and the palette and
// the shortcuts bring back any tab.
//
// The Files tab is the FileBrowserView, whole;
// Search is the SearchView (project-wide find and replace), which used to be an
// overlay over that tree and is now its own tab directly below it. Source
// Control is the GitView (changes, staging, commit, sync, branches). Sessions
// hosts the SessionsView (the open-tabs overview), SSH the SSHHostsView, and
// Notes the NotesView. Bookmarks has no segment; its BookmarksView is reached
// on demand through the palette (see `railOrder`).
final class SidebarView: NSView {
    static let defaultWidth: CGFloat = 240
    static let minWidth: CGFloat = 180
    static let maxWidth: CGFloat = 420

    // The picker row under the title bar, and the gap between it and the
    // tab's own title band below.
    static let pickerHeight: CGFloat = 24
    static let pickerMargin: CGFloat = 8

    enum Tab: Int, CaseIterable {
        case files
        case notes
        // Appended (not declared in rail order) so persisted rawValues from
        // earlier builds keep meaning the same tab; railOrder places them.
        case git
        case ssh
        case bookmarks
        case sessions
        case search
        case ops

        // The picker's left-to-right segment order, independent of rawValue.
        // Files leads (the primary surface) with Search directly under it — the
        // two halves of one job, and where the eye goes when the tree isn't
        // enough — then Source Control (staging and committing what those two
        // just changed, and the surface that carries a change-count badge), then
        // Sessions (the open-tabs list, the replacement for the removed top tab
        // strip), SSH, Notes. Files / Search / Source Control in that order is
        // also where a VS Code hand expects them.
        // Bookmarks is deliberately absent: the marks themselves live in the
        // viewer gutter where they are made, so the list is a palette
        // destination ("Show Bookmarks" / showBookmarks()) rather than a
        // permanent icon.
        // Background is last: it is the only tab that shows the *app's* work
        // rather than the user's, so it belongs at the end of the row — a
        // place you go to ask a question, not one you work out of.
        static let railOrder: [Tab] = [.files, .search, .git, .sessions, .ssh, .notes, .ops]

        // Tooltip / accessibility label; the picker shows only the icon.
        var label: String {
            switch self {
            case .files: return "Files"
            case .search: return "Search"
            case .notes: return "Notes"
            case .git: return "Source Control"
            case .ssh: return "SSH Hosts"
            case .bookmarks: return "Bookmarks"
            case .sessions: return "Sessions"
            case .ops: return "Background"
            }
        }

        var symbolName: String {
            switch self {
            case .files: return "folder"
            case .search: return "magnifyingglass"
            case .notes: return "square.and.pencil"
            case .git: return "arrow.triangle.branch"
            case .ssh: return "server.rack"
            case .bookmarks: return "bookmark"
            case .sessions: return "rectangle.stack"
            case .ops: return "waveform.path.ecg"
            }
        }

        var icon: NSImage {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
            image?.isTemplate = true
            return image ?? NSImage()
        }
    }

    // The restore in init sets this directly rather than through select(tab:).
    private(set) var selectedTab: Tab = .files

    // Fired when a tab switch would have stranded the caret inside the tab that
    // just went away; the controller hands focus back to a pane. See
    // moveFocusOutOfHiddenTabs().
    var onFocusEscaped: (() -> Void)?
    let fileBrowser = FileBrowserView(frame: .zero)
    let searchView = SearchView(frame: .zero)
    let notesView = NotesView(frame: .zero)
    let gitView = GitView(frame: .zero)
    let sshHostsView = SSHHostsView(frame: .zero)
    let bookmarksView = BookmarksView(frame: .zero)
    let sessionsView = SessionsView(frame: .zero)
    let opsLogView = OpsLogView(frame: .zero)
    let recentFolders = RecentFoldersView(frame: .zero)
    let usageFooter = ClaudeUsageFooterView(frame: .zero)
    private let picker = NSSegmentedControl(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        picker.segmentCount = Tab.railOrder.count
        picker.trackingMode = .selectOne
        picker.segmentDistribution = .fillEqually
        picker.controlSize = .regular
        for (index, tab) in Tab.railOrder.enumerated() {
            picker.setImage(tab.icon, forSegment: index)
            picker.setToolTip(tab.label, forSegment: index)
            picker.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        picker.target = self
        picker.action = #selector(pickerChanged)
        addSubview(picker)

        // A stale persisted value (e.g. from a build with more tabs) falls
        // back to Files rather than landing on a tab with no segment in the
        // picker to switch back from.
        let saved = UserDefaults.standard.integer(forKey: DefaultsKey.sidebarTab)
        let restored = Tab(rawValue: saved) ?? .files
        selectedTab = Tab.railOrder.contains(restored) ? restored : .files

        // The tree and search are siblings now, one tab each. The browser
        // header's magnifier is a second way onto the Search tab (⌘⇧F is the
        // other), and Escape on an empty search field walks back to the tree.
        fileBrowser.onSearch = { [weak self] in self?.showSearch() }
        searchView.onDismiss = { [weak self] in self?.select(tab: .files) }
        addSubview(fileBrowser)
        addSubview(searchView)
        addSubview(notesView)
        addSubview(gitView)
        addSubview(sshHostsView)
        addSubview(bookmarksView)
        addSubview(sessionsView)
        addSubview(opsLogView)

        // The project switcher sits below the tab content, on every tab, and
        // the Claude Code usage footer sits at the very bottom below it.
        addSubview(recentFolders)
        recentFolders.onHeightChange = { [weak self] in self?.layoutContents() }
        addSubview(usageFooter)
        usageFooter.onHeightChange = { [weak self] in self?.layoutContents() }

        updateTabContent()
    }

    // Switches to the Search tab and focuses its pattern field (Cmd-Shift-F, the
    // Files header's magnifier); the caller unhides the sidebar first if needed.
    func showSearch() {
        select(tab: .search)
        searchView.focusSearchField()
    }

    func select(tab: Tab) {
        selectedTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: DefaultsKey.sidebarTab)
        updateTabContent()
    }

    @objc private func pickerChanged() {
        guard Tab.railOrder.indices.contains(picker.selectedSegment) else { return }
        select(tab: Tab.railOrder[picker.selectedSegment])
    }

    // Live theme switch: the sidebar's draw-based chrome is repainted by the
    // controller's recursive needsDisplay sweep, and the picker and the
    // material are AppKit's, following the window's appearance. The Search
    // tab's controls carry tints set at init, so they are re-read here.
    func reapplyTheme() {
        searchView.reapplyTheme()
        // Same reason: the Source Control tab's header tints and the commit
        // box's layer ground are baked in at init.
        gitView.reapplyTheme()
        // And the Sessions rows, whose tints are baked in by configure().
        sessionsView.reapplyTheme()
        // Same for the Background tab's rows and its header controls.
        opsLogView.reapplyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContents()
    }

    // The safe area's top is the title bar and toolbar the sidebar runs under;
    // it changes without a resize (full screen, a toolbar that appears), so the
    // layout runs again whenever it does.
    override func layout() {
        super.layout()
        layoutContents()
    }

    // Manual layout, consistent with the pane tree around it (Auto Layout and
    // NSSplitView's frame management don't mix well — see SettingsWindowController).
    private func layoutContents() {
        let inner = bounds
        let top = inner.height - safeAreaInsets.top
        let margin = Self.pickerMargin
        picker.frame = NSRect(
            x: margin, y: top - Self.pickerHeight,
            width: max(0, inner.width - margin * 2), height: Self.pickerHeight
        )
        let usageHeight = usageFooter.desiredHeight
        usageFooter.frame = NSRect(x: 0, y: 0, width: inner.width, height: usageHeight)
        let foldersHeight = recentFolders.isHidden ? 0 : recentFolders.desiredHeight
        recentFolders.frame = NSRect(x: 0, y: usageHeight, width: inner.width, height: foldersHeight)
        let footerHeight = usageHeight + foldersHeight
        // Below the picker; the tab's own title band is the margin after it.
        let contentFrame = NSRect(
            x: 0,
            y: footerHeight,
            width: inner.width,
            height: max(0, picker.frame.minY - margin / 2 - footerHeight)
        )
        fileBrowser.frame = contentFrame
        searchView.frame = contentFrame
        notesView.frame = contentFrame
        gitView.frame = contentFrame
        sshHostsView.frame = contentFrame
        bookmarksView.frame = contentFrame
        sessionsView.frame = contentFrame
        opsLogView.frame = contentFrame
    }

    private func updateTabContent() {
        // Bookmarks has no segment: the picker shows no selection rather
        // than a wrong one.
        picker.selectedSegment = Tab.railOrder.firstIndex(of: selectedTab) ?? -1
        fileBrowser.isHidden = selectedTab != .files
        searchView.isHidden = selectedTab != .search
        notesView.isHidden = selectedTab != .notes
        gitView.isHidden = selectedTab != .git
        sshHostsView.isHidden = selectedTab != .ssh
        bookmarksView.isHidden = selectedTab != .bookmarks
        sessionsView.isHidden = selectedTab != .sessions
        opsLogView.isHidden = selectedTab != .ops
        // Notes and Bookmarks are keyboard-navigable lists: selecting the tab
        // should land on the list so ↑↓/Return work without a click. (Notes no
        // longer holds an editor — a note opens as its own file tab.)
        if selectedTab == .notes {
            window?.makeFirstResponder(notesView.focusTarget)
        } else if selectedTab == .bookmarks {
            window?.makeFirstResponder(bookmarksView.focusTarget)
        } else if selectedTab == .search {
            // Landing on Search with the caret anywhere else would mean clicking
            // the icon and then having to click the field as well.
            searchView.focusSearchField()
        }
        shownTabDidBecomeVisible()
        moveFocusOutOfHiddenTabs()
    }

    // The shown tab is now reachable — either it was just selected, or the
    // whole panel came back with ⌘B (which changes no selection, so the
    // controller calls this itself). Only Source Control cares today: it skips
    // the loads only it draws while hidden — its branch list, feedback gather
    // and gh passes all shell out — so becoming visible is what asks for them.
    // The ancestor check, not isHidden: a collapsed sidebar item hides the
    // split's arranged view, which may be a container AppKit puts around this one.
    func shownTabDidBecomeVisible() {
        guard !isHiddenOrHasHiddenAncestor, selectedTab == .git else { return }
        gitView.sidebarTabDidBecomeVisible()
    }

    // A hidden view keeps first responder, so a tab switch that leaves the caret
    // in the tab that just disappeared swallows every keystroke after it — which
    // is why the old search overlay moved focus as it closed, and matters more now
    // that the Search tab's fields are permanent rather than summoned. Notes and
    // Bookmarks have already claimed the caret by here, so this only fires for the
    // tabs that don't want it, and it asks the controller (which owns focus) where
    // it should go rather than deciding for itself.
    private func moveFocusOutOfHiddenTabs() {
        guard let window else { return }
        guard let responder = window.firstResponder as? NSView else {
            // Hiding a field mid-edit ends the edit and drops first responder to
            // the *window*: nothing swallows the keystrokes, but nothing receives
            // them either — the terminal stays dead until you click it.
            onFocusEscaped?()
            return
        }
        guard responder.isDescendant(of: self), responder.isHiddenOrHasHiddenAncestor else { return }
        onFocusEscaped?()
    }
}
