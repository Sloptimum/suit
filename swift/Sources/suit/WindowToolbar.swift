import Cocoa

// The window's unified toolbar: the sidebar toggle over the sidebar, then the
// window title, then a short row of the verbs a mouse user reaches for most —
// Source Control (with the changed-file count as a system badge), split, new
// tab and the command palette.
//
// Every item is a plain NSToolbarItem with a nil target, so its action walks
// the responder chain to the same AppDelegate method the menu bar calls: one
// implementation per verb, and AppKit validates the button exactly as it
// validates the menu item. The toolbar owns no state but the badge count.
//
// The Source Control badge is what took over from the old icon strip's corner
// count: it is the one signal that has to stay on screen while the sidebar is
// collapsed (a dirty tree you can't see is the reason the count exists), and
// the toolbar is the chrome that survives ⌘B.
final class WindowToolbar: NSObject, NSToolbarDelegate {
    private static let sourceControl = NSToolbarItem.Identifier("suit.sourceControl")
    private static let split = NSToolbarItem.Identifier("suit.split")
    private static let newTab = NSToolbarItem.Identifier("suit.newTab")
    private static let palette = NSToolbarItem.Identifier("suit.palette")

    let toolbar = NSToolbar(identifier: "suit.window")
    private var sourceControlItem: NSToolbarItem?

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    // The Source Control tab's changed-file count; zero clears the badge.
    func setChangeCount(_ count: Int) {
        sourceControlItem?.badge = count > 0 ? .count(count) : nil
        sourceControlItem?.toolTip = count > 0
            ? "Source Control — \(count) changed file\(count == 1 ? "" : "s")"
            : "Source Control"
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace,
         Self.sourceControl, Self.split, Self.newTab, Self.palette]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Self.sourceControl:
            let item = makeItem(identifier, label: "Source Control", symbol: "arrow.triangle.branch",
                                action: #selector(AppDelegate.showGit(_:)))
            sourceControlItem = item
            return item
        case Self.split:
            return makeItem(identifier, label: "Split Screen", symbol: "rectangle.split.2x1",
                            action: #selector(AppDelegate.splitScreen(_:)))
        case Self.newTab:
            return makeItem(identifier, label: "New Tab", symbol: "plus",
                            action: #selector(AppDelegate.newTab(_:)))
        case Self.palette:
            return makeItem(identifier, label: "Command Palette", symbol: "command",
                            action: #selector(AppDelegate.showCommandPalette(_:)))
        default:
            return nil
        }
    }

    private func makeItem(_ identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.action = action
        item.target = nil
        return item
    }
}
