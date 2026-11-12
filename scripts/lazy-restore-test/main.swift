import Cocoa

// Drives the real AppDelegate offscreen through a restore (see
// scripts/lazy-restore-test.sh for what is under test and why it is slow).

let repo = CommandLine.arguments[1]
var failures = 0

func check(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
    let extra = detail()
    print((ok ? "ok: " : "FAIL: ") + what + (extra.isEmpty ? "" : " (\(extra))"))
    if !ok { failures += 1 }
}

func pump(_ seconds: TimeInterval) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}

_ = NSApplication.shared

// An unbundled binary's UserDefaults resolve against the real home whatever
// $HOME says, so this run steers with keys of its own and clears what a
// previous run left.
let defaults = UserDefaults.standard
for key in ["savedAppStateV2", "savedAppState", DefaultsKey.sidebarPinnedRoot] {
    defaults.removeObject(forKey: key)
}
defaults.set(true, forKey: DefaultsKey.sidebarVisible)
defaults.set(repo, forKey: DefaultsKey.lastWorkingDirectory)
defaults.set(true, forKey: FirstRunGuide.shownDefaultsKey)

// Four shells, three files, one document, one more file; the tree shows shell 0 beside file 4.
var saved: [SavedTab] = (0..<4).map { _ in SavedTab(kind: .terminal, cwd: repo) }
saved.append(SavedTab(kind: .viewer, filePath: repo + "/src/one.swift", firstVisibleLine: 40))
saved.append(SavedTab(kind: .viewer, filePath: repo + "/src/two.swift", firstVisibleLine: 300))
saved.append(SavedTab(kind: .viewer, filePath: repo + "/src/three.swift", firstVisibleLine: 1))
saved.append(SavedTab(kind: .markdown, filePath: repo + "/notes.md", scrollFraction: 0.5))
saved.append(SavedTab(kind: .viewer, filePath: repo + "/src/four.swift", firstVisibleLine: 200))
let tree = SavedNode.split(
    vertical: true, fraction: 0.3,
    first: .pane(tabIndex: 0, fontSize: nil), second: .pane(tabIndex: 4, fontSize: nil)
)
let frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
SavedAppState(windows: [
    SavedWindow(frame: frame, tabs: saved, tree: tree, mru: [0, 4, 1, 2, 3, 5, 6, 7, 8], activeTabIndex: 0),
]).save()

let delegate = AppDelegate()
NSApp.delegate = delegate
delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
pump(2.0)

guard let controller = delegate.windowControllers.first else {
    print("FAIL: no window restored")
    exit(1)
}
let tabs = controller.store.tabs
guard tabs.count == 9 else {
    print("FAIL: expected 9 restored tabs, got \(tabs.count)")
    exit(1)
}
let terminals = tabs.compactMap { $0.content as? TerminalPaneContent }
let viewers = tabs.compactMap { $0.content as? FileViewerPaneContent }
let markdown = tabs[7].content as! MarkdownPaneContent
func started() -> Int { terminals.filter { $0.shellPid > 0 }.count }

// --- at launch: only what is on screen -------------------------------------
check(controller.window.frame.size == frame.size, "window restored at its saved size", "\(controller.window.frame.size)")
check(started() == 1, "one shell forked at launch", "\(started()) of \(terminals.count)")
check(terminals.allSatisfy { $0.workingDirectory != nil }, "every terminal knows its directory")
check(viewers[0].textView.string.count > 1000, "the visible file is loaded")
check(viewers[1].textView.string.isEmpty && viewers[2].textView.string.isEmpty, "background files are unread")
check(tabs[4...].map(\.title) == ["one.swift", "two.swift", "three.swift", "notes.md", "four.swift"],
      "file tabs carry their file names", "\(tabs.map(\.title))")
if let split = controller.paneTreeRoot as? NSSplitView, split.frame.width > 0 {
    let fraction = split.arrangedSubviews[0].frame.width / split.frame.width
    check(abs(fraction - 0.3) < 0.02, "divider at its saved fraction", "\(fraction)")
} else {
    check(false, "split tree restored")
}

// --- a quit right now saves what was restored -------------------------------
let recaptured = controller.captureState()
check(recaptured.tabs.count == 9, "snapshot keeps every tab", "\(recaptured.tabs.count)")
if recaptured.tabs.count == 9 {
    check(recaptured.tabs[5].firstVisibleLine == 300, "an unread file keeps its saved line",
          "\(String(describing: recaptured.tabs[5].firstVisibleLine))")
    check(recaptured.tabs[7].scrollFraction == 0.5, "an unread document keeps its saved position")
    check(recaptured.tabs[1].cwd == saved[1].cwd, "an unstarted shell keeps its directory")
}

// --- shown for the first time ----------------------------------------------
controller.activate(tabs[5]); pump(1.0)
check(viewers[1].textView.string.count > 1000, "a background file loads when shown")
check(abs(viewers[1].firstVisibleLine - 300) <= 1, "and returns to its saved line", "\(viewers[1].firstVisibleLine)")
controller.activate(tabs[7]); pump(1.0)
check(abs(markdown.scrollFraction - 0.5) < 0.05, "a background document returns to its saved position",
      "\(markdown.scrollFraction)")
controller.activate(tabs[1]); pump(1.5)
check(terminals[1].shellPid > 0 && started() == 2, "a background shell starts when shown, and only it", "\(started())")

// Input for a shell nobody has looked at starts it instead of vanishing.
terminals[2].terminalView.send(txt: "echo deferred-ok\n"); pump(2.5)
let screen = String(decoding: terminals[2].terminalView.getTerminal().getBufferAsData(), as: UTF8.self)
check(terminals[2].shellPid > 0 && screen.contains("deferred-ok"), "input starts a deferred shell and reaches it")

// The file tree's click on a tab that was never shown is that tab's deferred
// load, saved line included — not a fresh load at the top.
check(viewers[3].textView.string.isEmpty, "fourth file still unread")
controller.openFile(atPath: repo + "/src/four.swift", line: nil); pump(1.0)
check(viewers[3].textView.string.count > 1000 && abs(viewers[3].firstVisibleLine - 200) <= 1,
      "opening a never-shown file by path keeps its saved line", "\(viewers[3].firstVisibleLine)")

// --- a never-shown file tab torn off into its own window --------------------
// Its pane is built before the new window has a sidebar; the load it triggers
// reports a title change into a half-built window.
check(viewers[2].textView.string.isEmpty, "third file still unread before tear-off")
delegate.tearOffTab(withId: tabs[6].id, at: NSPoint(x: 200, y: 700)); pump(1.0)
check(delegate.windowControllers.count == 2, "tear-off made a second window", "\(delegate.windowControllers.count)")
check(viewers[2].textView.string.count > 1000, "and the torn-off file loaded there")

// --- a snapshot with no split tree whose first tab is a file ----------------
// (The window's only pane was showing something that cannot be saved.)
let treeless = SavedWindow(
    frame: frame,
    tabs: [
        SavedTab(kind: .viewer, filePath: repo + "/src/one.swift", firstVisibleLine: 120),
        SavedTab(kind: .markdown, filePath: repo + "/notes.md", scrollFraction: 0.25),
        SavedTab(kind: .terminal, cwd: repo),
    ],
    tree: nil
)
let second = TerminalWindowController(appDelegate: delegate, startDirectory: repo, restoring: treeless)
delegate.windowControllers.append(second)
second.window.makeKeyAndOrderFront(nil); pump(1.0)
check(second.store.tabs.count == 3, "tree-less snapshot restores its tabs", "\(second.store.tabs.count)")
check(second.panes.first?.tab === second.store.tabs.first, "and shows the first one")
check((second.store.tabs.first?.content as? FileViewerPaneContent)?.textView.string.isEmpty == false,
      "which is loaded")

// A tree that names only tabs that cannot come back collapses the same way,
// and then the tab it falls back to was restored deferred.
let collapsed = SavedWindow(
    frame: frame,
    tabs: [
        SavedTab(kind: .viewer, filePath: repo + "/src/gone.swift", firstVisibleLine: 1),
        SavedTab(kind: .markdown, filePath: repo + "/notes.md", scrollFraction: 0.25),
    ],
    tree: .pane(tabIndex: 0, fontSize: nil)
)
let third = TerminalWindowController(appDelegate: delegate, startDirectory: repo, restoring: collapsed)
delegate.windowControllers.append(third)
third.window.makeKeyAndOrderFront(nil); pump(1.0)
check(third.store.tabs.count == 1 && third.panes.first?.tab === third.store.tabs.first,
      "a collapsed tree falls back to a deferred tab without crashing")

for controller in delegate.windowControllers {
    for tab in controller.store.tabs { tab.content.teardown() }
}
print(failures == 0 ? "\nALL PASS" : "\n\(failures) assertion(s) failed")
exit(failures == 0 ? 0 : 1)
