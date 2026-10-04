import Cocoa

// Every split in the pane tree drawn with the palette's hairline instead of
// AppKit's system divider.
//
// The system divider color comes from the *appearance*, not from the theme: on
// the darker palettes it lands within a couple of levels of `barChrome`, so the
// boundary between two stacked panes simply isn't there to see. `dividerColor`
// is the supported hook — NSSplitView asks for it on every divider draw, so a
// computed override follows a live theme switch for free, with nothing cached
// and nothing to reapply.
final class SuitSplitView: NSSplitView {
    // Pane-tree splits set this (the three creation sites in +Splitting,
    // +Panes and +State). Panes are flush rectangles that share an edge, the
    // way Xcode's editors and Terminal's splits do, so the divider between them
    // is one thin hairline. Splits *inside* a pane (BackgroundTaskPane) leave it
    // off and keep the same hairline; the flag names the role for the callers
    // that measure room before a split exists.
    var isPaneGutter = false

    /// The pane divider's width. Public because callers that ask "is there room
    /// to split?" have to subtract it *before* the split exists — see
    /// paneRequestedFooter.
    static let gutterThickness: CGFloat = 1

    override var dividerColor: NSColor {
        Theme.hairline
    }

    override var dividerThickness: CGFloat {
        isPaneGutter ? Self.gutterThickness : super.dividerThickness
    }
}
