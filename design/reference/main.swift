import Cocoa

// The design-reference scenario (Phase 15 drift harness): pinned terminal +
// second terminal + a file viewer split beside it — rendered offscreen to
// the path given as argv[1]. Regenerate design/phase15-window.png with
// design/render-reference.sh whenever chrome changes, so visual drift shows
// up in review diffs instead of user reports.

_ = NSApplication.shared
// applicationDidFinishLaunching doesn't run here; set the appearance the app
// would pick for the default (dark) theme.
NSApp.appearance = NSAppearance(named: .darkAqua)
let delegate = AppDelegate()

let fixture = NSTemporaryDirectory() + "suit-design-reference"
try? FileManager.default.createDirectory(atPath: fixture, withIntermediateDirectories: true)
let sample = fixture + "/Sample.swift"
try? """
import Cocoa

func hello() {
    print("hello")
}
""".write(toFile: sample, atomically: true, encoding: .utf8)

func pump(_ s: TimeInterval) {
    let end = Date().addingTimeInterval(s)
    while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}

// The sidebar is part of the chrome under review, so it is shown — pinned to
// the fixture folder below, and with render-reference.sh running this under a
// sandboxed $HOME, so the render never carries the machine's real files,
// account name or recent folders. Set here, not left to the defaults domain,
// so every run draws the same panel.
UserDefaults.standard.set(true, forKey: DefaultsKey.sidebarVisible)
UserDefaults.standard.set(Double(SidebarView.defaultWidth), forKey: DefaultsKey.sidebarWidth)
UserDefaults.standard.set(SidebarView.Tab.files.rawValue, forKey: DefaultsKey.sidebarTab)
UserDefaults.standard.removeObject(forKey: DefaultsKey.sidebarPinnedRoot)

delegate.newWindow(nil)
guard let c = NSApp.windows.compactMap({ $0.delegate as? TerminalWindowController }).first else {
    FileHandle.standardError.write(Data("no window controller\n".utf8))
    exit(1)
}
c.window.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 800), display: true)
pump(1.5)
c.pinSidebar(toDirectory: fixture)
// The window opened on NSHomeDirectory(), which ignores the sandboxed $HOME,
// and noted it as a recent folder; drop it so the account name stays out.
FavoritesStore.shared.removeRecentFolder(NSHomeDirectory())
pump(0.5)

// Pinned terminal, a second shell, the sample file split beside it.
if let first = c.store.tabs.first {
    c.store.setPinned(true, for: first)
}
c.newTerminalTab()
pump(0.5)
c.openFile(atPath: sample, line: nil)
pump(0.5)
if let shell = c.store.tabs.first(where: { !($0.content is FileViewerPaneContent) && $0.pane == nil }) {
    c.splitScreen(with: shell)
}
pump(1.0)

// The live shells title themselves user@host — pin a neutral title so the
// committed render never carries the machine's real username.
for tab in c.store.tabs where tab.content is TerminalPaneContent {
    tab.customTitle = "user@mac:~"
    c.tabDidChange(tab)
}
pump(0.3)

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/phase15-window.png"
// The theme frame, not the content view: the toolbar and the traffic lights
// are part of the chrome under review, and they live in the frame.
if let view = c.window.contentView?.superview {
    view.layoutSubtreeIfNeeded()
    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
    }
}
for tab in c.store.tabs { tab.content.teardown() }
print("wrote \(out)")
exit(0)
