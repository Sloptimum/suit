import Cocoa

// The window's top-level content view: the activity bar takes a fixed strip at
// the far left and the body (sidebar split + pane tree) fills what's left. The
// old window-level tab strip is gone — tabs now live on each pane's own in-pane
// tab bar, and the sidebar's Sessions tab is the cross-pane overview. Terminal
// transparency is a behind-window frost hosted per pane (see PaneContainerView),
// not a single view behind the whole window.
//
// The bar sits here rather than inside sidebarSplit on purpose: it must outlive
// a Cmd-B collapse of the sidebar, and the split's delegate special-cases
// (min/max width, sidebarWidth persistence) key off a single divider and would
// misread a second one. Offsetting the split's frame keeps that whole path
// untouched — it works in the split's own coordinate space.
final class WindowRootView: NSView {
    weak var activityBar: NSView?
    weak var body: NSView?

    // The well — the ground the pane cards float on — is painted here, not
    // left to window.backgroundColor: offscreen renders capture the content
    // view alone, and an unpainted region composites to black there (invisible
    // on the dark themes, a black moat on the light ones). draw() re-reads the
    // token live, so the theme sweep repaints it for free.
    override func draw(_ dirtyRect: NSRect) {
        Theme.well.setFill()
        dirtyRect.fill()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutParts()
    }

    func layoutParts() {
        guard let activityBar, !activityBar.isHidden else {
            body?.frame = bounds
            return
        }
        let barWidth = ActivityBarView.width
        activityBar.frame = NSRect(x: 0, y: 0, width: barWidth, height: bounds.height)
        body?.frame = NSRect(
            x: barWidth, y: 0,
            width: max(0, bounds.width - barWidth), height: bounds.height
        )
    }
}
