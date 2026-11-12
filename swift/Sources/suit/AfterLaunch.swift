import Foundation

// Work that launch can do without, until the first frame is on screen.
//
// Why this and not DispatchQueue.main.async: the main queue drains *before* the
// run loop's first Core Animation commit, so work "postponed" that way still
// stands between the user and the window. This holds it until the run loop has
// gone idle once — the window has been drawn and the app is waiting for input —
// and then runs it in the order it was asked for.
//
// Outside launch it is transparent: the work runs immediately, synchronously,
// exactly as if it had been called directly. That covers ordinary use after
// the first frame, and every entry point that never runs
// applicationDidFinishLaunching (the offscreen render drivers, the harnesses),
// where there is no first frame to wait for. So a call site does not have to
// know whether it is being reached during launch.
//
// Main thread only.
enum AfterLaunch {
    private static var pending: [() -> Void]?

    // Called once, at the top of applicationDidFinishLaunching.
    static func begin() {
        guard pending == nil else { return }
        pending = []
        var observer: CFRunLoopObserver?
        // After every other observer of this activity — Core Animation's
        // commit is one of them, and it is the thing being waited for.
        observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
        ) { _, _ in
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            flush()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        // A launch that never goes idle (a restored tab flooding the main
        // queue) must not hold this work forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { flush() }
    }

    static func run(_ work: @escaping () -> Void) {
        if pending != nil {
            pending?.append(work)
        } else {
            work()
        }
    }

    private static func flush() {
        // Emptied one at a time rather than swapped out, so work that asks for
        // more work during the flush keeps its place in line instead of
        // running ahead of what was queued before it.
        while let next = pending?.first {
            pending?.removeFirst()
            next()
        }
        pending = nil
    }
}
