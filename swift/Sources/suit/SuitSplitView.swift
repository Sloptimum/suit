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
    // side by side rather than sharing an edge.
    var isPaneGutter = false

    // The sidebar split sets this instead: its divider stays thin (the drag
    // affordance between two independently-sized worlds) but paints the well,
    // so the hairline melts into the gutter between the sidebar card and the
    // pane cards instead of drawing a line across it. Splits *inside* a pane
    // (BackgroundTaskPane) set neither flag and keep the crisp hairline.
    var isWellSeam = false

    /// The gutter's width. Public because callers that ask "is there room to
    /// split?" have to subtract it *before* the split exists — see
    /// paneRequestedFooter.
    static let gutterThickness: CGFloat = 6

    override var dividerColor: NSColor {
        isPaneGutter || isWellSeam ? Theme.well : Theme.hairline
    }

    override var dividerThickness: CGFloat {
        isPaneGutter ? Self.gutterThickness : super.dividerThickness
    }
}
