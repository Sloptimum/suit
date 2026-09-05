import Foundation

// Standalone assertions for TranscriptParsing: the JSONL line → entries rules
// and the file:line reference resolver. Each JSON line below is the shape
// Claude Code writes, trimmed to the fields the parser reads.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

print("== parseTranscriptLine ==")
do {
    check(parseTranscriptLine(#"{"type":"user","message":{"content":"  Fix the bug  "}}"#) == [.user("Fix the bug")],
          "a user prompt trims to one .user entry")
    check(parseTranscriptLine(#"{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}"#).isEmpty,
          "array user content is tool-result plumbing, dropped")
    check(parseTranscriptLine(#"{"type":"user","message":{"content":"<command-name>/compact</command-name>"}}"#).isEmpty,
          "a synthetic <command-name> prompt is dropped")
    check(parseTranscriptLine(#"{"type":"user","message":{"content":"   "}}"#).isEmpty,
          "a blank prompt is dropped")
    check(parseTranscriptLine(#"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"sub"}]}}"#).isEmpty,
          "sidechain (subagent) traffic is dropped")

    let assistant = #"{"type":"assistant","message":{"content":["# +
        #"{"type":"thinking","thinking":"hmm"},"# +
        #"{"type":"text","text":" Sure. "},"# +
        #"{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/a.swift"}},"# +
        #"{"type":"tool_use","name":"Bash","input":{"command":"ls\n-la","description":"list"}},"# +
        #"{"type":"tool_use","name":"Mystery","input":{"other":1}}"# +
        #"]}}"#
    let entries = parseTranscriptLine(assistant)
    check(entries == [
        .assistantText("Sure."),
        .toolUse(name: "Read", summary: "/tmp/a.swift"),
        .toolUse(name: "Bash", summary: "ls -la"),
        .toolUse(name: "Mystery", summary: ""),
    ], "assistant blocks: thinking dropped, text trimmed, tool calls summarized by the most useful field: \(entries)")

    let long = String(repeating: "x", count: 200)
    let capped = parseTranscriptLine(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"\#(long)"}}]}}"#)
    if case .toolUse(_, let summary)? = capped.first {
        check(summary.count == 121 && summary.hasSuffix("…"), "a long summary is capped at 120 characters plus an ellipsis")
    } else {
        check(false, "a long summary still parses")
    }

    check(parseTranscriptLine(#"{"type":"file-history-snapshot","messageId":"x"}"#).isEmpty, "bookkeeping entries are dropped")
    check(parseTranscriptLine(#"{"type":"assistant"}"#).isEmpty, "an assistant line without a message is dropped")
    check(parseTranscriptLine("not json").isEmpty, "garbage is dropped")
    check(parseTranscriptLine("").isEmpty, "an empty line is dropped")

    check(TranscriptEntry.toolUse(name: "Read", summary: "").plainText == "Read", "plainText of a bare tool call is its name")
    check(TranscriptEntry.toolUse(name: "Read", summary: "/a").plainText == "Read — /a", "…with the summary when there is one")
    check(TranscriptEntry.user("hi").plainText == "hi", "plainText of a prompt is the prompt")
}

print("== resolveFileReference ==")
do {
    let dir = NSTemporaryDirectory() + "transcript-parsing-test-\(ProcessInfo.processInfo.processIdentifier)"
    try! FileManager.default.createDirectory(atPath: dir + "/sub", withIntermediateDirectories: true)
    try! "let x = 1\n".write(toFile: dir + "/main.swift", atomically: true, encoding: .utf8)

    let relative = resolveFileReference("main.swift:12:3", relativeTo: dir)
    check(relative?.path.hasSuffix("/main.swift") == true && relative?.line == 12,
          "a cwd-relative path:line:col resolves and keeps the line")
    let absolute = resolveFileReference(dir + "/main.swift", relativeTo: nil)
    check(absolute?.path.hasSuffix("/main.swift") == true && absolute?.line == nil,
          "an absolute path resolves without a cwd, no line")
    check(resolveFileReference("main.swift:0", relativeTo: dir)?.line == nil, "a zero line number is not a line")
    check(resolveFileReference("sub", relativeTo: dir)?.path == nil, "a directory is not a file reference")
    check(resolveFileReference("https://example.com/a.swift", relativeTo: dir)?.path == nil, "a URL is never a file reference")
    check(resolveFileReference("mailto:a@b.c", relativeTo: dir)?.path == nil, "…nor a mailto link")
    check(resolveFileReference("missing.swift", relativeTo: dir)?.path == nil, "a path that doesn't exist is nil")
    check(resolveFileReference("main.swift", relativeTo: nil)?.path == nil, "a relative path with no cwd is nil")

    try? FileManager.default.removeItem(atPath: dir)
}

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
