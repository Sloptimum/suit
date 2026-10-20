import Cocoa

// The pane tree's host inside the window's content item: sizes its one subview
// (the tree's root — a PaneContainerView or the outermost NSSplitView) to its
// bounds. Panes run flush to the window edges and to the sidebar; the host
// itself is pinned below the toolbar by PaneTreeHostView.
final class RootContainerView: NSView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutParts()
    }

    // Tree surgery replaces the subview outside any resize; frame the newcomer
    // now rather than waiting for the next window resize to do it.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        layoutParts()
    }

    private func layoutParts() {
        for subview in subviews {
            subview.frame = bounds
        }
    }
}
