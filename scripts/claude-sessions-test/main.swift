import Foundation

// Standalone assertions for the session monitor's parsers: the JSON the hooks
// and the statusline write, turned into sessions and usage.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

typealias Monitor = ClaudeSessionMonitor

print("== parseResetsAt ==")
do {
    let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    check(Monitor.parseResetsAt(NSNumber(value: 1_700_000_000)) == epoch, "epoch seconds as a number")
    check(Monitor.parseResetsAt("1700000000") == epoch, "epoch seconds as a numeric string")
    check(Monitor.parseResetsAt(" 1700000000 ") == epoch, "…with surrounding whitespace")
    check(Monitor.parseResetsAt("2026-01-02T03:04:05Z") == ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z"), "an ISO8601 timestamp")
    check(Monitor.parseResetsAt("2026-01-02T03:04:05.250Z") != nil, "ISO8601 with fractional seconds")
    check(Monitor.parseResetsAt("") == nil && Monitor.parseResetsAt(nil) == nil && Monitor.parseResetsAt("soon") == nil,
          "empty, absent and unparsable are nil")
}

print("== parseUsage ==")
do {
    let json = """
    {"captured_at": 1700000000, "rate_limits": {
      "five_hour": {"used_percentage": 42.5, "resets_at": 1700003600},
      "seven_day": {"used_percentage": 10},
      "seven_day_fable": {"used_percentage": 3},
      "seven_day_opus_4": {"used_percentage": 7}}}
    """
    guard let usage = Monitor.parseUsage(data: Data(json.utf8)) else {
        check(false, "usage parses"); exit(1)
    }
    check(usage.fiveHourPct == 42.5 && usage.sevenDayPct == 10, "the two all-model windows")
    check(usage.fiveHourResetsAt == Date(timeIntervalSince1970: 1_700_003_600) && usage.sevenDayResetsAt == nil,
          "resets_at per window, nil when absent")
    check(usage.modelWeeklies.map(\.name) == ["Fable", "Opus 4"] && usage.modelWeeklies.map(\.pct) == [3, 7],
          "per-model weeklies from seven_day_<model>, names humanized, sorted: \(usage.modelWeeklies)")
    check(usage.capturedAt == Date(timeIntervalSince1970: 1_700_000_000), "captured_at")
    let empty = Monitor.parseUsage(data: Data("{}".utf8))
    check(empty != nil && empty?.fiveHourPct == nil && empty?.modelWeeklies.isEmpty == true,
          "no rate_limits reads as empty usage, not as a parse failure")
    check(Monitor.parseUsage(data: Data("nope".utf8)) == nil, "garbage is nil")
}

print("== parseSession ==")
do {
    let json = """
    {"session_id": "abc", "state": "needs-input", "cwd": "/repo", "summary": "Fix", "model": "fable",
     "pid": 4242, "updated_at": 1700000000, "transcript_path": "/t.jsonl", "session_name": "Named",
     "context_pct": 37.5, "cost_usd": 1.25, "permission_mode": "plan"}
    """
    guard let s = Monitor.parseSession(Data(json.utf8)) else {
        check(false, "session parses"); exit(1)
    }
    check(s.id == "abc" && s.state == .needsInput && s.cwd == "/repo" && s.summary == "Fix" && s.model == "fable",
          "identity, state, cwd, summary, model")
    check(s.pid == 4242 && s.updatedAt == Date(timeIntervalSince1970: 1_700_000_000) && s.transcriptPath == "/t.jsonl",
          "pid, updated_at, transcript_path")
    check(s.sessionName == "Named" && s.contextPct == 37.5 && s.costUSD == 1.25 && s.permissionMode == .plan,
          "session_name, context_pct, cost_usd, permission_mode")
    check(s.displayName == "Named", "displayName prefers the session name")

    check(Monitor.parseSession(Data(#"{"session_id":"x","state":"weird"}"#.utf8))?.state == .working,
          "an unknown state reads as working")
    let sparse = Monitor.parseSession(Data(#"{"session_id":"x"}"#.utf8))
    check(sparse?.permissionMode == nil && sparse?.pid == nil && sparse?.cwd == nil && sparse?.updatedAt == Date(timeIntervalSince1970: 0),
          "absent fields are nil (updated_at falls back to the epoch)")
    check(Monitor.parseSession(Data(#"{"state":"done"}"#.utf8)) == nil, "no session_id is no session")
    check(Monitor.parseSession(Data("[]".utf8)) == nil, "a non-object is no session")
    check(Monitor.parseSession(Data(#"{"session_id":"x","permission_mode":"acceptEdits"}"#.utf8))?.permissionMode == .agent,
          "acceptEdits maps onto the Agent mode")
}

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
