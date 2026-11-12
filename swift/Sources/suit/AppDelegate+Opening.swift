import Cocoa

// The ways a Mac hands an app something to open, none of which Suit answered
// before: File ▸ Open… (⌘O), a folder or file dropped on the Dock icon, "Open
// With" in Finder, and `open -a Suit <path>` from a shell. They all arrive
// here and mean the same two things — a folder becomes a window on that
// project, a file becomes a tab — plus the Dock menu and the placement of a
// new window, which belong to the same "be a normal Mac app" family.
extension AppDelegate {

    // MARK: - Opening folders and files

    // Finder, the Dock and `open` deliver here. On a cold launch that can be
    // before applicationDidFinishLaunching has restored anything, so the
    // request is held until the windows exist (see finishPendingOpens).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard launchFinished else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        open(urls)
    }

    // File ▸ Open… — one panel for both kinds, like the Dock drop.
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if let directory = activeWindowController()?.activeTabWorkingDirectory() {
            panel.directoryURL = URL(fileURLWithPath: directory)
        }
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            self?.open(panel.urls)
        }
        // A sheet on the window it is for; app-modal only when there is none.
        if let window = activeWindowController()?.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func open(_ urls: [URL]) {
        var files: [String] = []
        for url in urls where url.isFileURL {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                openProjectWindow(at: url.path)
            } else {
                files.append(url.path)
            }
        }
        guard !files.isEmpty else { return }
        // Files go to the window in use; with none open, to a new one rooted
        // where the first file lives, so its sidebar shows the file's project.
        let controller = activeWindowController() ?? windowControllers.first ?? {
            let controller = openWindow(startDirectory: (files[0] as NSString).deletingLastPathComponent)
            placeNewWindow(controller.window, relativeTo: nil)
            return controller
        }()
        controller.window.makeKeyAndOrderFront(nil)
        for path in files {
            controller.openFile(atPath: path, line: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // A folder: the window already showing that project comes forward;
    // otherwise a new window opens with its shell and sidebar there.
    private func openProjectWindow(at path: String) {
        let root = FileIndex.gitRoot(of: path) ?? path
        if let existing = windowControllers.first(where: { $0.projectIndex.root == root }) {
            existing.window.makeKeyAndOrderFront(nil)
        } else {
            let anchor = activeWindowController()?.window
            let controller = openWindow(startDirectory: path)
            placeNewWindow(controller.window, relativeTo: anchor)
            controller.window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // What a cold launch was asked to open, once the launch has its windows.
    func finishPendingOpens() {
        launchFinished = true
        let urls = pendingOpenURLs
        pendingOpenURLs = []
        if !urls.isEmpty { open(urls) }
    }

    // MARK: - New window placement

    // A new window takes the size of the one it was opened from and steps down
    // and right from it, the way every document app cascades. Every window
    // used to open centred at one fixed size — exactly on top of the last.
    func placeNewWindow(_ window: NSWindow, relativeTo anchor: NSWindow?) {
        guard let anchor, anchor.isVisible, !anchor.styleMask.contains(.fullScreen) else { return }
        window.setFrame(anchor.frame, display: false)
        // With .zero the anchor stays put and answers where the next goes.
        let next = anchor.cascadeTopLeft(from: .zero)
        _ = window.cascadeTopLeft(from: next)
    }

    // MARK: - Dock menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newWindowItem = menu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "")
        newWindowItem.target = self
        return menu
    }

    // MARK: - Help

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        settingsWindowController.show(category: "Shortcuts")
    }
}
