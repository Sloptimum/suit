import Cocoa

// The two row kinds in the Search tab's results outline.
//
// Both compute their hover state inside layout(), from the window's current
// mouse location, rather than latching it in mouseEntered/mouseExited. Rows are
// recycled constantly while rg streams results in, and a latched flag follows
// the *view* to whichever file it is reused for — leaving the replace and
// dismiss buttons showing on a row the pointer is nowhere near. The tracking
// area's only job here is to ask for a re-layout when the pointer moves.

// A file header row: type icon, name, grayed parent directory, and — on hover —
// the per-file replace and dismiss actions in place of the match count.
final class SearchFileRowView: NSTableCellView {
    // Called by the outline delegate on every configure; a recycled row still
    // holds the previous file's closures until it is rebound. Both nil means the
    // row has no actions to reveal — which is how the references pane, the other
    // user of these views, keeps its plain match-count rows.
    var onReplace: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let iconView = NSImageView(frame: .zero)
    private let nameLabel = NSTextField(labelWithString: "")
    private let directoryLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let replaceButton = NSButton(frame: .zero)
    private let dismissButton = NSButton(frame: .zero)

    private var isHovered = false
    // Text widths measured from the strings in configure().
    // NSTextField.intrinsicContentSize is not usable here: on a label that
    // truncates, it reports the width the label *currently* has, so laying the
    // row out from it ratchets the name narrower every pass until the middle of
    // every filename is an ellipsis.
    private var nameWidth: CGFloat = 0
    private var directoryWidth: CGFloat = 0
    // When the row is too narrow for both, the directory shrinks first — but
    // only down to this floor. Head-truncated, "…/Store" still answers "where
    // is this from", which is the question the row exists for; an invisible
    // directory answers nothing, and that was exactly the old failure at
    // sidebar widths. 44pt fits an innermost directory name at 10pt; when the
    // name must also give ground, its middle-truncation keeps the prefix and
    // the extension, and the directory beside it does the disambiguating.
    private static let directoryFloor: CGFloat = 44

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        // Regular, not medium: this row sits one tab over from the Files tree
        // (system 12 regular) and should read as the same species of row.
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)

        directoryLabel.font = .systemFont(ofSize: 10)
        directoryLabel.lineBreakMode = .byTruncatingHead
        addSubview(directoryLabel)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        countLabel.alignment = .center
        countLabel.wantsLayer = true
        addSubview(countLabel)

        configure(action: replaceButton, symbol: "arrow.left.arrow.right",
                  tooltip: "Replace All in File", selector: #selector(replaceClicked))
        configure(action: dismissButton, symbol: "xmark",
                  tooltip: "Dismiss from results", selector: #selector(dismissClicked))

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(action button: NSButton, symbol: String, tooltip: String, selector: Selector) {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        button.toolTip = tooltip
        button.target = self
        button.action = selector
        button.refusesFirstResponder = true
        button.isHidden = true
        addSubview(button)
    }

    @objc private func replaceClicked() { onReplace?() }
    @objc private func dismissClicked() { onDismiss?() }

    override func mouseEntered(with event: NSEvent) { needsLayout = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsLayout = true; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered else { return }
        Theme.hover.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
    }

    override func layout() {
        super.layout()
        isHovered = hovered(in: self)

        let icon: CGFloat = 13
        iconView.frame = NSRect(x: 2, y: (bounds.height - icon) / 2, width: icon, height: icon)

        var right = bounds.width - 4
        let showsActions = isHovered && (onReplace != nil || onDismiss != nil)
        replaceButton.isHidden = !showsActions
        dismissButton.isHidden = !showsActions
        countLabel.isHidden = showsActions
        if showsActions {
            for button in [dismissButton, replaceButton] {
                right -= 18
                button.frame = NSRect(x: right, y: (bounds.height - 16) / 2, width: 18, height: 16)
            }
            right -= 4
        } else {
            let countHeight: CGFloat = 15
            let countWidth = max(countHeight, countLabel.intrinsicContentSize.width + 10)
            right -= countWidth
            countLabel.frame = NSRect(x: right, y: (bounds.height - countHeight) / 2,
                                      width: countWidth, height: countHeight)
            // Half the height, so any count from "3" to "1400" sits in a pill.
            countLabel.layer?.cornerRadius = countHeight / 2
            right -= 6
        }

        let left = iconView.frame.maxX + 6
        let available = max(0, right - left)
        // The name yields to the directory's floor and nothing else: a filename
        // is worth more characters than a path, but a path squeezed to zero
        // width strips the row of its provenance, which matters more than the
        // tail of a long name.
        let reserved = directoryWidth == 0 ? 0 : min(directoryWidth, Self.directoryFloor) + 6
        let shownName = min(nameWidth, max(0, available - reserved))
        nameLabel.frame = NSRect(x: left, y: (bounds.height - 16) / 2, width: shownName, height: 16)
        let directoryX = nameLabel.frame.maxX + 6
        directoryLabel.frame = NSRect(
            x: directoryX, y: (bounds.height - 14) / 2,
            width: max(0, min(directoryWidth, right - directoryX)), height: 14
        )
    }

    func configure(with group: SearchFileGroup) {
        let name = (group.relativePath as NSString).lastPathComponent
        nameLabel.stringValue = name
        nameLabel.textColor = Theme.textPrimary
        // +6 for the cell's own inset: a label handed exactly its text width
        // still draws an ellipsis, which is the difference between "SearchView.swift"
        // and "Search…w.swift".
        nameWidth = ceil((name as NSString).size(withAttributes: [.font: nameLabel.font as Any]).width) + 6
        let directory = (group.relativePath as NSString).deletingLastPathComponent
        directoryLabel.stringValue = directory
        directoryLabel.textColor = Theme.textFaint
        directoryWidth = directory.isEmpty ? 0
            : ceil((directory as NSString).size(withAttributes: [.font: directoryLabel.font as Any]).width) + 6
        countLabel.stringValue = "\(group.matches.count)"
        countLabel.textColor = Theme.textDim
        countLabel.layer?.backgroundColor = Theme.hover.cgColor
        for button in [replaceButton, dismissButton] {
            button.contentTintColor = Theme.textDim
        }
        // The Files tree's per-extension icon, so a result set is scannable by
        // the same colors the tree taught you.
        let (image, tint) = FileTreeIcon.image(for: FileNode(name: name, relativePath: group.relativePath,
                                                             isDirectory: false))
        iconView.image = image
        iconView.contentTintColor = tint
        toolTip = group.relativePath
        needsLayout = true
    }
}

// A match row: the line's text with the matched ranges washed in the same
// searchHit amber the open panes use for this pattern, and an indent guide
// running down the left so a long run of hits reads as belonging to one file.
// No line number — the row's job is "which hit is this", the click answers
// "where exactly", and the tooltip still carries path:line for the curious.
// In list mode the file name leads the row instead of the guide, because there
// is no header row above it to have named the file.
final class SearchMatchRowView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    private var isHovered = false
    private var drawsGuide = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        addSubview(label)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseEntered(with event: NSEvent) { needsLayout = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsLayout = true; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            Theme.hover.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        guard drawsGuide else { return }
        // Full-bleed vertically so consecutive matches join into one line rather
        // than a dashed column of stubs.
        Theme.hairline.setFill()
        NSRect(x: 1, y: 0, width: 1, height: bounds.height).fill()
    }

    override func layout() {
        super.layout()
        isHovered = hovered(in: self)
        let left: CGFloat = drawsGuide ? 10 : 4
        label.frame = NSRect(x: left, y: (bounds.height - 16) / 2,
                             width: max(0, bounds.width - 6 - left), height: 16)
    }

    func configure(with node: SearchMatchNode, showsFile: Bool = false) {
        let match = node.match
        drawsGuide = !showsFile

        // Trim leading indentation so deeply-nested code doesn't push the
        // match itself out of the truncated row.
        let trimmed = match.lineText.drop(while: { $0 == " " || $0 == "\t" })
        let trimOffset = match.lineText.utf16.count - trimmed.utf16.count
        let snippet = String(trimmed.prefix(300))

        // An attributed value carries its own wrapping and ignores the field's:
        // without this paragraph style the rows wrap to a second line the 22pt
        // row height then clips, which is how the results list once turned to
        // visual rubble.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let text = NSMutableAttributedString()
        if showsFile {
            text.append(NSAttributedString(
                string: (match.relativePath as NSString).lastPathComponent + "  ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: Theme.textFaint,
                ]
            ))
        }
        let snippetStart = text.length
        text.append(NSAttributedString(
            string: snippet,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: Theme.textDim,
            ]
        ))
        let snippetLength = (snippet as NSString).length
        for range in match.matchRanges {
            let shifted = NSRange(location: range.location - trimOffset + snippetStart, length: range.length)
            guard shifted.location >= snippetStart,
                  shifted.location + shifted.length <= snippetStart + snippetLength else { continue }
            // searchHit, not selection: the same wash the open panes put behind
            // this pattern, so the list and the panes visibly agree about what
            // "a hit" is. Weight stays regular — in a monospaced run a medium
            // face changes no widths but does make the wash look like a smear.
            text.addAttributes([
                .foregroundColor: Theme.textPrimary,
                .backgroundColor: Theme.searchHit,
            ], range: shifted)
        }
        text.addAttribute(.paragraphStyle, value: paragraph,
                          range: NSRange(location: 0, length: text.length))
        label.attributedStringValue = text
        toolTip = "\(match.relativePath):\(match.lineNumber)"
        needsLayout = true
        needsDisplay = true
    }
}

// Whether the pointer is currently inside this row. Read at layout time rather
// than tracked, for the reuse reason at the top of this file; outside a window
// (offscreen renders, the design harness) nothing is hovered.
private func hovered(in view: NSView) -> Bool {
    guard let window = view.window, window.isKeyWindow else { return false }
    let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    return view.bounds.contains(point)
}
