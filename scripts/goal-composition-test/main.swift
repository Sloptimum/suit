import Foundation

// Standalone assertions for GoalComposition — the text "Set as Goal" sends.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

typealias Goal = GoalComposition

print("== composeGoalText ==")
check(Goal.composeGoalText(selection: "   \n ", file: "a.swift", startLine: 1, endLine: 1, includeProvenance: true) == nil,
      "a whitespace-only selection composes nothing")
check(Goal.composeGoalText(selection: "  fix this  ", file: nil, startLine: nil, endLine: nil, includeProvenance: true) == "/goal fix this",
      "trimmed and /goal-prefixed; no provenance without a file")
check(Goal.composeGoalText(selection: "x", file: "/repo/src/Foo.swift", startLine: 12, endLine: 12, includeProvenance: true) == "/goal From Foo.swift:12:\nx",
      "single-line provenance names the file's basename and one line")
check(Goal.composeGoalText(selection: "x", file: "/repo/src/Foo.swift", startLine: 12, endLine: 20, includeProvenance: true) == "/goal From Foo.swift:12-20:\nx",
      "a span is start-end")
check(Goal.composeGoalText(selection: "x", file: "/repo/src/Foo.swift", startLine: 12, endLine: nil, includeProvenance: true) == "/goal From Foo.swift:12:\nx",
      "a missing end line reads as a single line")
check(Goal.composeGoalText(selection: "x", file: "/repo/src/Foo.swift", startLine: 12, endLine: 20, includeProvenance: false) == "/goal x",
      "provenance off omits the From line")
check(Goal.composeGoalText(selection: "x", file: "/a.swift", startLine: nil, endLine: nil, includeProvenance: true) == "/goal x",
      "provenance needs a start line")
check(Goal.composeGoalText(selection: "line one\nline two", file: nil, startLine: nil, endLine: nil, includeProvenance: false) == "/goal line one\nline two",
      "inner newlines are kept")

print("== bracketedPaste ==")
check(Goal.bracketedPaste("a\nb") == "\u{1b}[200~a\nb\u{1b}[201~",
      "the payload is wrapped in the terminal's bracketed-paste markers")
check(Goal.pasteStart == "\u{1b}[200~" && Goal.pasteEnd == "\u{1b}[201~",
      "the markers are the xterm ones SessionControl.send uses")

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
