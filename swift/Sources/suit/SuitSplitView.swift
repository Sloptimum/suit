import Cocoa

// Every split in the window — the sidebar divider and the whole pane tree —
// drawn with the palette's hairline instead of AppKit's system divider.
//
// The system divider color comes from the *appearance*, not from the theme, and
// the window pins .darkAqua: on the darker palettes it lands within a couple of
// levels of `barChrome`, so the boundary between the sidebar and the pane tree
// (or between two stacked panes) simply isn't there to see. `dividerColor` is
// the supported hook — NSSplitView asks for it on every divider draw, so a
// computed override follows a live theme switch for free, with nothing cached
// and nothing to reapply.
final class SuitSplitView: NSSplitView {
    // Pane-tree splits set this (the three creation sites in +Splitting,
    // +Panes and +State): their divider widens into a gutter painted the same
    // well color as the margin around the tree, so two cards read as floating
    // side by side rather than sharing an edge. The sidebar split leaves it
    // false — the frost wants a crisp 1px hairline against the pane world,
    // not a moat.
    var isPaneGutter = false

    override var dividerColor: NSColor { isPaneGutter ? Theme.well : Theme.hairline }

    override var dividerThickness: CGFloat { isPaneGutter ? 6 : super.dividerThickness }
}
