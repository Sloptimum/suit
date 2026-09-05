import Darwin
import Foundation

// SwiftTerm's LocalProcess hands back the raw `waitpid` status word as `exitCode`
// (see LocalProcess.swift's `processTerminated()`), not a decoded exit code — so
// this reimplements the <sys/wait.h> WIFEXITED/WEXITSTATUS/WIFSIGNALED/WTERMSIG
// macros, which the Swift importer doesn't expose on Darwin.
enum ProcessExitStatus: Equatable {
    case exited(code: Int32)
    case signaled(signal: Int32)

    init(waitStatus status: Int32) {
        let stopSignal = status & 0x7f
        if stopSignal == 0 {
            self = .exited(code: (status >> 8) & 0xff)
        } else {
            self = .signaled(signal: stopSignal)
        }
    }

    var isClean: Bool {
        self == .exited(code: 0)
    }

    // strsignal already renders human text for the case that matters most here
    // (SIGPIPE -> "Broken pipe"), so there's no need for a hand-rolled signal table.
    var shortLabel: String {
        switch self {
        case .exited(let code):
            return code == 0 ? "done" : "exit \(code)"
        case .signaled(let signal):
            return String(cString: strsignal(signal)).lowercased()
        }
    }
}

// A pane counts as "running code" when the pty's foreground process group is no
// longer the shell's own — i.e. the user launched something (claude, vim, a
// build…) that currently controls the terminal. Background helpers that prompt
// frameworks spawn (e.g. Powerlevel10k's gitstatusd) live in their own
// non-foreground group, so they don't trip this. Returns the foreground
// process's name, or nil when the shell is sitting idle at a prompt.
func foregroundProcessName(ptyFd: Int32, shellPid: pid_t) -> String? {
    guard ptyFd >= 0, shellPid > 0 else { return nil }
    let foregroundGroup = tcgetpgrp(ptyFd)
    guard foregroundGroup > 0, foregroundGroup != shellPid else { return nil }
    // The group leader's pid is the pgid itself; it can be gone already if the
    // job is mid-exit, in which case the pane is still busy — just nameless.
    var buffer = [CChar](repeating: 0, count: 256)
    let length = proc_name(foregroundGroup, &buffer, UInt32(buffer.count))
    return length > 0 ? String(cString: buffer) : "a process"
}

// Reads a running process's current working directory straight from the kernel
// (the same information `lsof`/`ps` show), so a new split pane can start in
// wherever the shell it was split from actually is right now — independent of
// whether that shell's prompt/config reports its cwd via any escape sequence.
func currentWorkingDirectory(ofProcess pid: pid_t) -> String? {
    var info = proc_vnodepathinfo()
    let size = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
    guard size == Int32(MemoryLayout<proc_vnodepathinfo>.size) else { return nil }

    return withUnsafePointer(to: &info.pvi_cdir.vip_path) { pathPtr in
        pathPtr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cString in
            String(cString: cString)
        }
    }
}

// MARK: - Spawning child processes

// Where git lives. /usr/bin/git is the Xcode Command Line Tools shim, present
// on every Mac that can build this app; one constant so the path is decided
// once rather than typed at forty call sites.
enum Git {
    static let executable = "/usr/bin/git"
}

// What a finished child left behind. Text rather than Data because every
// caller wants text; a byte that isn't UTF-8 becomes U+FFFD instead of turning
// the whole output into nil, so a diff with one Latin-1 comment still renders.
struct ProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String

    var succeeded: Bool { status == 0 }

    // The line a CLI puts its error on. git and gh both lead with it.
    var firstStderrLine: String? {
        stderr.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// Runs a process to completion and returns stdout, or nil on nonzero exit /
// launch failure. Used for git (the index, the diff pane, review tooling);
// never called on paths derived from file content.
//
// Every internal subprocess Suit spawns of its own accord goes through here or
// through runProcessCapturing below, which makes this file the one place worth
// instrumenting: the operations log (OpsLog) derives the row's name and kind
// from argv, so a `git` call added anywhere in the app shows up in the
// Background tab without its author writing a line of logging. `trigger` names
// *why* the call is being made — pass it at sites that know (the status monitor
// knows an FSEvents burst asked); anything else inherits the ambient trigger
// its caller scoped with OpsLog.withTrigger. `probe` marks a call whose *job*
// is to ask a yes/no question — "is this directory in a repo", "does this ref
// exist" — where a nonzero exit is the answer "no", not a fault. Without it
// those rows log red, and a log where the commonest routine call is red is a
// log whose red stops meaning anything. `detail` overrides the argv-derived
// detail for a call whose argv says nothing useful (ctags reads its file list
// from stdin).
func runProcess(
    _ executable: String, _ arguments: [String],
    trigger: String? = nil, probe: Bool = false, detail: String? = nil
) -> String? {
    let derived = OpsLabel.derive(executable: executable, arguments: arguments)
    let watch = OpsStopwatch()
    let result = try? spawn(executable, arguments, cwd: nil, stdin: nil, captureStderr: false)
    let output = result?.succeeded == true ? result?.stdout : nil
    OpsLog.shared.record(
        kind: derived.kind,
        label: derived.label,
        detail: detail ?? derived.detail,
        trigger: trigger ?? OpsLog.currentTrigger,
        startedAt: watch.startedAt,
        duration: watch.elapsed,
        // A command that ran fine and printed nothing (`git status` in a clean
        // tree) is `.empty`, not a failure.
        outcome: output.map { $0.isEmpty ? .empty : .ok } ?? (probe ? .empty : .failed)
    )
    return output
}

// The variant for a call whose failure text matters: stdout, stderr and the
// exit status all come back, so the caller can show git's or gh's own words.
// Throws only when the executable could not be launched at all. `cwd` is for
// tools without a `-C` flag (gh finds its repo by working directory); `stdin`
// feeds the child and is closed after, for `ctags -L -`.
func runProcessCapturing(
    _ executable: String, _ arguments: [String],
    cwd: String? = nil, stdin: Data? = nil, trigger: String? = nil, detail: String? = nil
) throws -> ProcessResult {
    let derived = OpsLabel.derive(executable: executable, arguments: arguments)
    let watch = OpsStopwatch()
    let outcome: OpsOutcome
    let result: ProcessResult
    do {
        result = try spawn(executable, arguments, cwd: cwd, stdin: stdin, captureStderr: true)
        outcome = result.succeeded ? (result.stdout.isEmpty ? .empty : .ok) : .failed
    } catch {
        OpsLog.shared.record(
            kind: derived.kind, label: derived.label, detail: detail ?? derived.detail,
            trigger: trigger ?? OpsLog.currentTrigger,
            startedAt: watch.startedAt, duration: watch.elapsed, outcome: .failed
        )
        throw error
    }
    OpsLog.shared.record(
        kind: derived.kind, label: derived.label, detail: detail ?? derived.detail,
        trigger: trigger ?? OpsLog.currentTrigger,
        startedAt: watch.startedAt, duration: watch.elapsed, outcome: outcome
    )
    return result
}

// The uninstrumented spawn, split out so the timing wrappers above read as one
// thing and the pipe plumbing as another.
//
// A pipe holds about 64 KB. A child that fills one Suit isn't reading blocks on
// its next write, never finishes, and never closes the *other* pipe — so a
// reader that drains stdout to EOF before touching stderr hangs forever the
// day a command has a lot to say on stderr (a fetch's progress, a flood of
// CRLF warnings, a merge's conflict listing). Both pipes are therefore drained
// at once — stdout here, stderr on a worker — and stdin, when there is one, is
// written on a worker too, so a file list longer than a pipe can't deadlock
// against output the child has already started producing. When stderr isn't
// wanted it goes to /dev/null rather than an unread pipe, for the same reason.
private func spawn(
    _ executable: String, _ arguments: [String],
    cwd: String?, stdin: Data?, captureStderr: Bool
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

    let stdoutPipe = Pipe()
    process.standardOutput = stdoutPipe
    let stderrPipe = captureStderr ? Pipe() : nil
    process.standardError = stderrPipe ?? FileHandle.nullDevice
    let stdinPipe = stdin == nil ? nil : Pipe()
    if let stdinPipe { process.standardInput = stdinPipe }

    try process.run()
    if let stdinPipe {
        // A child that exits before reading everything makes the write below a
        // broken pipe. By default that is delivered as SIGPIPE and kills *us*;
        // with the flag the write just fails with EPIPE, which is the child's
        // answer and not ours to crash on. (F_SETNOSIGPIPE is per descriptor,
        // so nothing else in the process changes its signal disposition.)
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    let workers = DispatchGroup()
    var stderrData = Data()
    if let stderrPipe {
        workers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            workers.leave()
        }
    }
    if let stdinPipe, let stdin {
        workers.enter()
        DispatchQueue.global(qos: .utility).async {
            // EPIPE (see the fcntl above) is swallowed on purpose.
            try? stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
            try? stdinPipe.fileHandleForWriting.close()
            workers.leave()
        }
    }
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    workers.wait()
    process.waitUntilExit()

    return ProcessResult(
        status: process.terminationStatus,
        stdout: String(decoding: stdoutData, as: UTF8.self),
        stderr: String(decoding: stderrData, as: UTF8.self)
    )
}

// MARK: - The process table

// One sysctl read of the whole process table → child pid → parent pid. The
// session assigner walks it to find which pane's shell a claude process sits
// under, and the task monitor to scope a pane's background jobs; each reads it
// once per pass rather than once per pane.
func processParentMap() -> [pid_t: pid_t] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [:] }
    // Headroom for processes spawned between the two calls.
    size += size / 8
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [:] }

    let count = size / MemoryLayout<kinfo_proc>.stride
    var map: [pid_t: pid_t] = [:]
    map.reserveCapacity(count)
    buffer.withUnsafeBytes { raw in
        let procs = raw.bindMemory(to: kinfo_proc.self)
        for i in 0..<count {
            let proc = procs[i]
            map[proc.kp_proc.p_pid] = proc.kp_eproc.e_ppid
        }
    }
    return map
}
