import Foundation
import Darwin

// Claude session awareness. Claude Code hooks + the
// statusline script (scripts/claude/) write one JSON file per session into
// ~/.suit/sessions/; this monitor watches that directory and publishes the
// parsed sessions, and the assigner maps them onto terminal panes by pid
// ancestry (the claude process is a descendant of the pane's shell) with cwd
// as the fallback.

enum ClaudeSessionState: String {
    case working
    case needsInput = "needs-input"
    case done

    // Sessions tab ordering: "needs you first."
    var sortRank: Int {
        switch self {
        case .needsInput: return 0
        case .working: return 1
        case .done: return 2
        }
    }

    var label: String {
        switch self {
        case .working: return "busy"
        case .needsInput: return "needs input"
        case .done: return "done"
        }
    }

    // The state's dot color lives UI-side (Theme.swift) so this file stays
    // Foundation-only and standalone-compilable.
}

struct ClaudeSession {
    let id: String
    let state: ClaudeSessionState
    let cwd: String?
    let summary: String?
    let model: String?
    let pid: pid_t?
    let updatedAt: Date
    let transcriptPath: String?
    let sessionName: String?
    let contextPct: Double?
    let costUSD: Double?
    // Best-effort mode readback: the permission mode from the
    // session JSON when Claude Code exposes it, mapped onto Ask/Plan/Agent. nil
    // when absent — the mode control then reflects the last mode Suit sent.
    let permissionMode: ClaudeMode?

    var displayName: String {
        if let sessionName, !sessionName.isEmpty {
            return sessionName
        }
        if let summary, !summary.isEmpty {
            return summary
        }
        if let cwd {
            return (cwd as NSString).lastPathComponent
        }
        return String(id.prefix(8))
    }
}

// Claude Code's global rate-limit usage, written by the statusline script to
// ~/.suit/claude-status.json regardless of which session is active.
struct ClaudeUsage {
    let fiveHourPct: Double?
    let sevenDayPct: Double?
    // When each window rolls over, from rate_limits.*.resets_at — the
    // statusline mirrors Claude Code's JSON verbatim, so the value is parsed
    // defensively (epoch seconds or an ISO8601 string). Nil when absent.
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
    // Model-scoped weekly limits beyond the all-models one: every other
    // rate_limits key shaped `seven_day_<model>` (e.g. seven_day_fable →
    // "Fable"), so new per-model limits show up without a parser change.
    let modelWeeklies: [(name: String, pct: Double)]
    let capturedAt: Date
}

final class ClaudeSessionMonitor {
    static let shared = ClaudeSessionMonitor()
    static let didUpdate = Notification.Name("ClaudeSessionMonitorDidUpdate")

    // Sessions younger than this are shown; "done" ages out faster since a
    // finished session stops being actionable.
    private static let maxAge: TimeInterval = 12 * 60 * 60
    private static let maxDoneAge: TimeInterval = 2 * 60 * 60
    // Files older than this are deleted on scan so the directory can't grow forever.
    private static let pruneAge: TimeInterval = 7 * 24 * 60 * 60

    private(set) var sessions: [ClaudeSession] = []
    private(set) var usage: ClaudeUsage?

    // Where the hook/statusline scripts write ("$HOME/.suit", see SuitPaths).
    private let sessionsDirectory = SuitPaths.directory + "/sessions"
    private let statusFile = SuitPaths.directory + "/claude-status.json"

    private var watcher: DirectoryWatcher?

    private init() {
        try? FileManager.default.createDirectory(atPath: sessionsDirectory, withIntermediateDirectories: true)
        watch()
        // Deferred: reload() posts didUpdate, and an observer calling back into
        // `.shared` while this initializer is still inside dispatch_once traps.
        DispatchQueue.main.async { [weak self] in
            self?.reload()
        }
    }

    // The sessions directory plus ~/.suit itself, where claude-status.json
    // lives — one debounce for the pair, since the statusline script rewrites
    // both in the same run (DirectoryWatcher).
    private func watch() {
        watcher = DirectoryWatcher(
            paths: [sessionsDirectory, (statusFile as NSString).deletingLastPathComponent]
        ) { [weak self] in self?.reload() }
    }

    // Re-reads every session file and the global usage snapshot. Called on
    // watcher events and by the app's periodic refresh (process trees change
    // without any file event).
    func reload() {
        let fm = FileManager.default
        var loaded: [ClaudeSession] = []
        let now = Date()

        for name in (try? fm.contentsOfDirectory(atPath: sessionsDirectory)) ?? [] where name.hasSuffix(".json") {
            let path = sessionsDirectory + "/" + name
            guard let data = fm.contents(atPath: path), let session = Self.parseSession(data) else { continue }

            let age = now.timeIntervalSince(session.updatedAt)
            if age > Self.pruneAge {
                try? fm.removeItem(atPath: path)
                continue
            }
            if age > Self.maxAge || (session.state == .done && age > Self.maxDoneAge) {
                continue
            }
            loaded.append(session)
        }

        sessions = loaded.sorted {
            ($0.state.sortRank, $1.updatedAt.timeIntervalSince1970) < ($1.state.sortRank, $0.updatedAt.timeIntervalSince1970)
        }
        usage = Self.readUsage(path: statusFile)
        NotificationCenter.default.post(name: Self.didUpdate, object: self)
    }

    // One session file (the JSON scripts/claude/suit-session-state.sh and the
    // statusline merge) as a session. nil without a session_id; an unknown
    // state reads as working, since a hook that wrote anything is a session
    // doing something. Pure, so the harness feeds it JSON directly.
    static func parseSession(_ data: Data) -> ClaudeSession? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["session_id"] as? String else { return nil }
        return ClaudeSession(
            id: id,
            state: (object["state"] as? String).flatMap(ClaudeSessionState.init(rawValue:)) ?? .working,
            cwd: object["cwd"] as? String,
            summary: object["summary"] as? String,
            model: object["model"] as? String,
            pid: (object["pid"] as? Int).map(pid_t.init),
            updatedAt: Date(timeIntervalSince1970: (object["updated_at"] as? Double) ?? 0),
            transcriptPath: object["transcript_path"] as? String,
            sessionName: object["session_name"] as? String,
            contextPct: (object["context_pct"] as? NSNumber)?.doubleValue,
            costUSD: (object["cost_usd"] as? NSNumber)?.doubleValue,
            permissionMode: ClaudeMode.fromRawMode(object["permission_mode"] as? String)
        )
    }

    private static func readUsage(path: String) -> ClaudeUsage? {
        guard let usage = parseUsage(path: path) else { return nil }
        // A snapshot from a long-dead session shouldn't show as live usage.
        guard Date().timeIntervalSince(usage.capturedAt) < 30 * 60 else { return nil }
        return usage
    }

    // The ungated reader: a caller that applies its own staleness policy (a
    // stale snapshot still carries resets_at, which tells it *when* the window
    // rolls over) reads the raw values + capturedAt and decides for itself.
    // The UI keeps the gated `usage`.
    func readUsageSnapshot() -> ClaudeUsage? {
        Self.parseUsage(path: statusFile)
    }

    private static func parseUsage(path: String) -> ClaudeUsage? {
        FileManager.default.contents(atPath: path).flatMap(parseUsage(data:))
    }

    // The statusline's claude-status.json (Claude Code's own JSON, mirrored
    // verbatim under rate_limits). Pure, so the harness feeds it directly.
    static func parseUsage(data: Data) -> ClaudeUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let limits = object["rate_limits"] as? [String: Any]
        func pct(_ key: String) -> Double? {
            (limits?[key] as? [String: Any])?["used_percentage"] as? Double
        }
        func resetsAt(_ key: String) -> Date? {
            parseResetsAt((limits?[key] as? [String: Any])?["resets_at"])
        }
        let captured = Date(timeIntervalSince1970: (object["captured_at"] as? Double) ?? 0)
        var modelWeeklies: [(name: String, pct: Double)] = []
        for key in (limits ?? [:]).keys where key.hasPrefix("seven_day_") {
            guard let value = pct(key) else { continue }
            let name = key.dropFirst("seven_day_".count)
                .replacingOccurrences(of: "_", with: " ").capitalized
            modelWeeklies.append((name, value))
        }
        modelWeeklies.sort { $0.name < $1.name }
        return ClaudeUsage(
            fiveHourPct: pct("five_hour"), sevenDayPct: pct("seven_day"),
            fiveHourResetsAt: resetsAt("five_hour"), sevenDayResetsAt: resetsAt("seven_day"),
            modelWeeklies: modelWeeklies, capturedAt: captured
        )
    }

    // resets_at is upstream's field, not ours — accept whatever shape it
    // arrives in: epoch seconds (number or numeric string) or an ISO8601
    // timestamp, with or without fractional seconds.
    static func parseResetsAt(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespaces),
              !string.isEmpty else { return nil }
        if let epoch = Double(string) {
            return Date(timeIntervalSince1970: epoch)
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: string)
    }

    // Snapshot of pane→session mapping state; build once per refresh pass so
    // the process table is read once, not once per pane.
    func makeAssigner() -> ClaudeSessionAssigner {
        ClaudeSessionAssigner(sessions: sessions)
    }
}

// Maps a pane (its shell pid + cwd) to the session running inside it.
final class ClaudeSessionAssigner {
    private let sessions: [ClaudeSession]
    private let parentMap: [pid_t: pid_t]

    init(sessions: [ClaudeSession]) {
        self.sessions = sessions
        self.parentMap = sessions.contains(where: { $0.pid != nil }) ? processParentMap() : [:]
    }

    func session(forShellPid shellPid: pid_t, cwd: String?) -> ClaudeSession? {
        // pid ancestry is authoritative: the claude process the hooks reported
        // sits somewhere under the pane's shell.
        for session in sessions {
            guard let pid = session.pid else { continue }
            if isDescendant(pid, of: shellPid) {
                return session
            }
        }
        // Fallback: same working directory, newest wins. Catches sessions whose
        // pid discovery failed (or that outlived their process — "done").
        guard let cwd else { return nil }
        return sessions
            .filter { $0.cwd == cwd }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func isDescendant(_ pid: pid_t, of ancestor: pid_t) -> Bool {
        guard pid > 0, ancestor > 0 else { return false }
        var current = pid
        var hops = 0
        while current > 1, hops < 64 {
            if current == ancestor { return true }
            guard let parent = parentMap[current] else { return false }
            current = parent
            hops += 1
        }
        return false
    }

}
