import Cocoa

// The pane tree's host inside the sidebar split: sizes its one subview (the
// tree's root — a PaneContainerView or the outermost NSSplitView) to its
// bounds, minus the well margin.
//
// `contentInset` is the frame of the floating-card look: the window ground
// behind this host is the darker well (Theme.well), and the inset is what lets
// it show around the tree so the rounded cards read as surfaces sitting *on*
// something instead of tiles cut out of the window. The pane splits' widened
// gutter dividers (SuitSplitView.isPaneGutter) paint the same well color, so
// margin and gutters form one continuous ground.
final class RootContainerView: NSView {
    var contentInset: CGFloat = 0 {
        didSet { layoutParts() }
    }

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
            subview.frame = bounds.insetBy(dx: contentInset, dy: contentInset)
        }
    }
}
