import Cocoa

// The window's two worlds as AppKit's own sidebar split: the SidebarView in a
// sidebar item, the pane tree in the content item.
//
// This replaced a hand-built arrangement — an icon strip, a frosted card and a
// plain NSSplitView whose delegate pinned the sidebar's width — that drew its
// own version of every surface the system already provides. A sidebar item is
// what makes the window read as a Mac app rather than a port of one: it gets
// the system's Liquid Glass sidebar (edge to edge on macOS 27), the traffic
// lights over it, the toolbar's tracking separator and the collapse
// animation, all with no drawing code here. The window is
// full-size-content, so the sidebar runs under the title bar; the content item
// keeps the pane tree below it through its safe area (see PaneTreeHostView).
//
// The sidebar item's holding priority is above the content's, so a window
// resize goes to the pane tree and the sidebar keeps the width it was dragged
// to — the same contract the old split delegate enforced by hand.
//
// Policy stays in the window controller. AppKit's toggleSidebar(_:) reaches
// this object through the responder chain (the toolbar's sidebar button); it
// hands the gesture to `onToggleSidebar`. A collapse or an expand from *any*
// source — that button, ⌘B, a reveal, or a drag of the divider past the
// sidebar's minimum, which AppKit turns into a collapse — is reported once
// through `onCollapsedChange`, so persistence and the "don't strand the caret
// in a collapsing panel" rule live in one place.
final class WindowSplitViewController: NSSplitViewController {
    let sidebarItem: NSSplitViewItem
    let contentItem: NSSplitViewItem

    var onToggleSidebar: (() -> Void)?
    // The sidebar's width after a user drag (never while collapsed), so the
    // controller can persist it. Fired only when it changes: the split reports
    // every frame of an animation and every window resize.
    var onSidebarWidthChange: ((CGFloat) -> Void)?
    // The sidebar collapsed (true) or came back (false).
    var onCollapsedChange: ((Bool) -> Void)?

    private var lastReportedWidth: CGFloat = 0
    private var lastCollapsed = false

    init(sidebar: NSView, content: NSView) {
        let sidebarController = NSViewController()
        sidebarController.view = sidebar
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = SidebarView.minWidth
        sidebarItem.maximumThickness = SidebarView.maxWidth
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue + 10)

        let contentController = NSViewController()
        contentController.view = content
        contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.holdingPriority = .defaultLow

        super.init(nibName: nil, bundle: nil)
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var sidebarWidth: CGFloat {
        sidebarItem.viewController.view.frame.width
    }

    // Puts the divider where a restored width says, once the split has a real
    // frame to measure against.
    func setSidebarWidth(_ width: CGFloat) {
        let clamped = min(max(width, SidebarView.minWidth), SidebarView.maxWidth)
        splitView.setPosition(clamped, ofDividerAt: 0)
    }

    // Sets the collapsed state the window opens with, without reporting it as
    // a change.
    func setInitialCollapsed(_ collapsed: Bool) {
        sidebarItem.isCollapsed = collapsed
        lastCollapsed = collapsed
    }

    override func toggleSidebar(_ sender: Any?) {
        onToggleSidebar?()
    }

    // Every collapse path ends in a resize of the split — an animated one
    // included, on its frames — so this is the one place that sees all of them.
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        let collapsed = sidebarItem.isCollapsed
        if collapsed != lastCollapsed {
            lastCollapsed = collapsed
            onCollapsedChange?(collapsed)
        }
        guard !collapsed, sidebarWidth >= SidebarView.minWidth, sidebarWidth != lastReportedWidth else { return }
        lastReportedWidth = sidebarWidth
        onSidebarWidthChange?(sidebarWidth)
    }
}

// The content item's view: holds the pane-tree host and keeps it out from under
// the toolbar. The window is full-size-content (the sidebar has to run up behind
// the traffic lights), so this view starts at the window's top edge; pinning
// the host to the safe area is what keeps the first row of a terminal visible.
// Auto Layout does that one job here — it follows a toolbar that appears,
// changes size or enters full screen without a frame calculation of our own —
// and stops at the host: the tree inside it keeps its manual layout.
final class PaneTreeHostView: NSView {
    init(host: NSView) {
        super.init(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // The band under the toolbar, above the first pane: painted as the panes'
    // own header chrome, so the toolbar reads as the top of the pane column
    // rather than a strip of a different material. Read live so a theme switch
    // repaints it with the rest of the chrome.
    override func draw(_ dirtyRect: NSRect) {
        Theme.barChrome.setFill()
        dirtyRect.fill()
    }
}
