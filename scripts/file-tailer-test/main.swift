import Foundation

// Standalone assertions for FileTailer: the pure read first, then the tailer
// against a real file and a real run loop. Each scenario writes the file the
// way something in the real world writes it — a hook appending a JSONL line,
// a job flushing half a line, `>` truncating a log, an editor's atomic save —
// pumps the run loop, and asserts on what the callbacks saw.
//
// The waits are wall-clock, set well past what a vnode event needs.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

let dir = NSTemporaryDirectory() + "file-tailer-test-\(ProcessInfo.processInfo.processIdentifier)"
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let path = dir + "/log.txt"

func append(_ text: String) {
    let handle = FileHandle(forWritingAtPath: path)!
    handle.seekToEndOfFile()
    handle.write(Data(text.utf8))
    try! handle.close()
}
func pump(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

// MARK: - The pure read

print("== readAppended ==")
do {
    try! "line1\nline2\n".write(toFile: path, atomically: true, encoding: .utf8)
    guard let first = FileTailer.readAppended(path: path, from: 0) else {
        check(false, "initial read"); exit(1)
    }
    check(first.lines == ["line1", "line2"], "reads the first two lines")
    check(!first.restarted, "a first read is not a restart")

    append("line3\npartial")
    guard let second = FileTailer.readAppended(path: path, from: first.newOffset) else {
        check(false, "append read"); exit(1)
    }
    check(second.lines == ["line3"], "reads only the new complete line")
    let size = try! FileManager.default.attributesOfItem(atPath: path)[.size] as! UInt64
    check(second.newOffset < size, "holds back the partial line")

    append("-done\n")
    let third = FileTailer.readAppended(path: path, from: second.newOffset)
    check(third?.lines == ["partial-done"], "completes the held-back line")

    try! "fresh\n".write(toFile: path, atomically: true, encoding: .utf8)
    let after = FileTailer.readAppended(path: path, from: 9999)
    check(after?.lines == ["fresh"], "truncation re-reads from the start")
    check(after?.restarted == true, "…and reports the restart")

    check(FileTailer.readAppended(path: dir + "/missing.txt", from: 0) == nil, "a missing file reads as nil")
}

// MARK: - The live tail

print("== live tail ==")
do {
    var batches: [[String]] = []
    var resets = 0
    try! "a\nb\n".write(toFile: path, atomically: true, encoding: .utf8)
    let tailer = FileTailer(path: path, onReset: { resets += 1 }, onLines: { batches.append($0) })
    tailer.start()
    check(batches == [["a", "b"]], "start delivers what is already there")
    check(resets == 0, "…without a reset")

    append("c\npar")
    pump(0.3)
    check(batches.last == ["c"], "an append delivers the complete line and holds the fragment")

    append("tial\n")
    pump(0.3)
    check(batches.last == ["partial"], "the fragment arrives whole once its newline lands")

    // `>` on a log: truncated in place, then written again.
    let handle = FileHandle(forWritingAtPath: path)!
    try! handle.truncate(atOffset: 0)
    handle.write(Data("new\n".utf8))
    try! handle.close()
    pump(0.3)
    check(resets == 1, "a file truncated in place resets the owner")
    check(batches.last == ["new"], "…then delivers what was written after")

    // Data.write(.atomic): a temp file renamed over the path. The inode we
    // held is gone; a naive tail is deaf from here on.
    try! Data("replaced\n".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    pump(0.5)
    check(resets == 2, "an atomic replace resets the owner")
    check(batches.last == ["replaced"], "…and delivers the new file's content")

    append("more\n")
    pump(0.3)
    check(batches.last == ["more"], "the re-armed tail keeps following the new inode")

    tailer.stop()
    append("after stop\n")
    pump(0.3)
    check(batches.last == ["more"], "a stopped tailer delivers nothing")
    tailer.stop()
    check(true, "stop is idempotent")
}

try? FileManager.default.removeItem(atPath: dir)

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
