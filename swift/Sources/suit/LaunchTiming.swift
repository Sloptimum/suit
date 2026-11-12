import Foundation

// Launch milestones, measured from the moment the kernel started the process.
//
// Why from the kernel's clock and not from the top of main.swift: the time the
// user waits includes dyld, the Swift runtime and every static initializer that
// runs before the first line of main — a number taken inside the process hides
// exactly the part nobody is looking at.
//
// Off unless SUIT_LAUNCH_TRACE is set, and then it is one line on stderr per
// milestone, so a normal launch pays for one environment lookup. Setting it to
// "exit" also ends the process at the last milestone (the shell's first byte, or
// the first idle run loop when no shell arrives within the grace period), which
// is what lets a script launch the app N times and read N sets of numbers
// without a person closing windows. That exit skips applicationWillTerminate on
// purpose: a measurement run must not overwrite the saved layout.
//
// Foundation only, so a harness can compile it alone.
enum LaunchTiming {
    enum Milestone: String {
        case mainEntered = "main"
        case didFinishLaunchingBegan = "didFinishLaunching.begin"
        case settingsLoaded = "settings+menu"
        case firstWindowOrdered = "window.ordered"
        case didFinishLaunchingEnded = "didFinishLaunching.end"
        case firstIdle = "runloop.firstIdle"
        case shellFirstByte = "shell.firstByte"
    }

    private static let mode = ProcessInfo.processInfo.environment["SUIT_LAUNCH_TRACE"]
    static let isEnabled = mode != nil
    private static let exitsWhenDone = mode == "exit"

    // How long after the first idle a run waits for a shell before it gives up
    // and exits anyway (a restored layout whose front tab is a file has none).
    private static let shellGrace: TimeInterval = 5

    private static var seen = Set<String>()
    // Subprocesses the main thread waited on before the first idle. A hard
    // count, because milliseconds on a machine that is also running the user's
    // own Suit are noise and a count is not.
    private static var blockingSpawns: [String] = []
    private static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let tv = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }()

    // Main thread only. Each milestone is reported once: the second window, the
    // second shell and the thousandth pty read are not launch.
    static func mark(_ milestone: Milestone) {
        guard isEnabled, seen.insert(milestone.rawValue).inserted else { return }
        let ms = Date().timeIntervalSince(processStart) * 1000
        FileHandle.standardError.write(
            Data(String(format: "launch %8.1f ms  %@\n", ms, milestone.rawValue).utf8)
        )
        if milestone == .shellFirstByte, seen.contains(Milestone.firstIdle.rawValue) {
            finish()
        }
    }

    // A free-form step inside launch (a window's construction phases, one
    // restored tab). Unlike a milestone it repeats, and it stops at the first
    // idle: after that the same code is ordinary use, not launch.
    static func note(_ label: @autoclosure () -> String) {
        guard isEnabled, !seen.contains(Milestone.firstIdle.rawValue) else { return }
        let ms = Date().timeIntervalSince(processStart) * 1000
        FileHandle.standardError.write(Data(String(format: "launch %8.1f ms    . %@\n", ms, label()).utf8))
    }

    // Called by the one process runner for every spawn it blocks on.
    static func noteBlockingSpawn(_ label: @autoclosure () -> String) {
        guard isEnabled, Thread.isMainThread, !seen.contains(Milestone.firstIdle.rawValue) else { return }
        blockingSpawns.append(label())
    }

    // "The window is on screen and the app is waiting for the user": the first
    // time the main run loop has nothing left to do after launch. Everything
    // that launch queued with DispatchQueue.main.async has run by then, so work
    // that was merely postponed by one turn still counts against this number.
    static func markFirstIdle() {
        guard isEnabled else { return }
        var observer: CFRunLoopObserver?
        observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0
        ) { _, _ in
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            mark(.firstIdle)
            let spawns = "launch main-thread spawns before idle: \(blockingSpawns.count)\n"
                + blockingSpawns.map { "launch   spawn \($0)\n" }.joined()
            FileHandle.standardError.write(Data(spawns.utf8))
            if seen.contains(Milestone.shellFirstByte.rawValue) {
                finish()
            } else if exitsWhenDone {
                DispatchQueue.main.asyncAfter(deadline: .now() + shellGrace) { finish() }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func finish() {
        guard exitsWhenDone else { return }
        exit(0)
    }
}
