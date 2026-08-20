import Cocoa

// The window's activity bar: a fixed-width, full-height strip pinned to the far
// left edge, outside the sidebar split (WindowRootView lays it out beside the
// body). It holds the tab icons — Files / Search / Sessions / SSH / Notes,
// in SidebarView.Tab.railOrder — that used to sit as a horizontal row inside the
// sidebar's own top edge. Moving them out is the point: the tabs stay on screen
// and clickable while the sidebar itself is collapsed with Cmd-B, so the bar is
// how you bring a collapsed sidebar back on the tab you want.
//
// Deliberately dumb — it owns no tab state. SidebarView stays the model (the
// enum, the rail order, the persisted selection); this view renders whatever
// `selectedTab` it is handed and reports clicks through `onSelect`. A selected
// tab with no icon here is legal and expected: Git and Bookmarks are
// palette-only, absent from railOrder, and simply leave every icon unselected.
final class ActivityBarView: NSView {
    static let width: CGFloat = 48

    var onSelect: ((SidebarView.Tab) -> Void)?

    var selectedTab: SidebarView.Tab = .files {
        didSet {
            for icon in icons { icon.isSelected = icon.tab == selectedTab }
        }
    }

    private var icons: [RailIconView] = []
    private let backdrop = ChromeBackdropView(frame: .zero)
    // No right-edge rule any more. The rule existed because bar and panel once
    // shared one flush frosted ground and needed a drawn seam; since the
    // sidebar became a floating card the well itself shows between the strip
    // and the card (and between the strip and the pane tree when the sidebar
    // is collapsed), and a hairline beside that gutter read as a double edge.

    // A count in the corner of one tab's icon — the Source Control tab's
    // changed-file count, so a dirty tree is visible with the sidebar
    // collapsed. A tab with no icon here (Bookmarks) silently ignores it.
    func setBadge(_ count: Int, for tab: SidebarView.Tab) {
        icons.first { $0.tab == tab }?.badgeCount = count
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // The same frosted material as the sidebar card beside it, but flush:
        // the strip is fixed window chrome, so it runs edge to edge while the
        // card floats — chrome is pinned, surfaces float.
        addSubview(backdrop)

        for tab in SidebarView.Tab.railOrder {
            let icon = RailIconView(tab: tab)
            icon.onClick = { [weak self] tab in self?.onSelect?(tab) }
            icons.append(icon)
            addSubview(icon)
        }
        layoutContents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Live theme switch: the backdrop's wash and each icon's tint are baked in
    // at init, so neither is reached by the controller's recursive needsDisplay
    // sweep — that only repaints draw()-based chrome. Called explicitly from
    // applyTheme(), exactly like SidebarView.reapplyTheme().
    func reapplyTheme() {
        backdrop.reapplyTheme()
        for icon in icons { icon.reapplyTheme() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContents()
        needsDisplay = true
    }

    // Manual layout, consistent with the rest of the window's chrome (Auto
    // Layout and NSSplitView's frame management don't mix here).
    private func layoutContents() {
        backdrop.frame = bounds
        let size = RailIconView.size
        // The sidebar card's well margin plus its interior top inset, so the
        // first icon and the tab content inside the card still start on one
        // line — the icon's 40pt cell brackets the 28pt title band next to it.
        let topPadding = Theme.Metrics.wellInset + SidebarView.topInset
        let gap: CGFloat = 4
        // Unflipped coords: start at the top edge and walk down.
        var y = bounds.height - topPadding - size
        for icon in icons {
            icon.frame = NSRect(x: (bounds.width - size) / 2, y: y, width: size, height: size)
            y -= size + gap
        }
    }
}
