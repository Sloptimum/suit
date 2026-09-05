import Foundation

// Standalone assertions for SlashCommandCatalog against a scratch $HOME (set
// by the wrapper): the catalog is built from real files laid out the way
// Claude Code lays them out.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok: \(message)")
    } else {
        print("  FAIL: \(message)")
        failures += 1
    }
}

let home = ProcessInfo.processInfo.environment["HOME"]!
func write(_ path: String, _ text: String) {
    try! FileManager.default.createDirectory(
        atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
    )
    try! text.write(toFile: path, atomically: true, encoding: .utf8)
}

// User level: commands, skills, and a few things that must not count.
write(home + "/.claude/commands/deploy.md", "---\ndescription: \"Ship it\"\n---\n# Deploy\nbody")
write(home + "/.claude/commands/notes.md", "\n## Notes helper\n\nbody")
write(home + "/.claude/commands/compact.md", "Shadows a built-in")
write(home + "/.claude/commands/README.txt", "not a command")
write(home + "/.claude/commands/verbose.md", "---\ndescription: " + String(repeating: "d", count: 100) + "\n---\n")
write(home + "/.claude/skills/graphify/SKILL.md", "---\nname: graphify\ndescription: Any input to a knowledge graph\n---\n")
write(home + "/.claude/skills/deploy/SKILL.md", "---\ndescription: skill deploy\n---\n")
write(home + "/.claude/skills/loose.md", "a file, not a skill folder")
// A project with its own .claude, and a cwd two levels below it.
let project = home + "/proj"
write(project + "/.claude/commands/proj-only.md", "Project command")
write(project + "/.claude/commands/deploy.md", "---\ndescription: project deploy\n---\n")
try! FileManager.default.createDirectory(atPath: project + "/src/deep", withIntermediateDirectories: true)

let builtins = SlashCommandCatalog.builtins

print("== user-level catalog ==")
do {
    let catalog = SlashCommandCatalog.forSession(cwd: nil)
    check(Array(catalog.prefix(builtins.count)) == builtins, "built-ins come first, in their curated order")
    let discovered = Array(catalog.dropFirst(builtins.count))
    check(discovered.map(\.name) == ["/deploy", "/graphify", "/notes", "/verbose"],
          "discovered entries follow, alphabetical: \(discovered.map(\.name))")
    let deploy = discovered.first { $0.name == "/deploy" }
    check(deploy?.source == .custom && deploy?.detail == "Ship it", "a frontmatter description, quotes stripped")
    check(discovered.first { $0.name == "/notes" }?.detail == "Notes helper", "else the first non-blank line, heading marks stripped")
    let graphify = discovered.first { $0.name == "/graphify" }
    check(graphify?.source == .skill && graphify?.detail == "Any input to a knowledge graph", "a skill folder's SKILL.md description")
    let verbose = discovered.first { $0.name == "/verbose" }?.detail ?? ""
    check(verbose.count == 80 && verbose.hasSuffix("…"), "a long description is capped at 80 characters")
    check(!catalog.contains { $0.name == "/compact" && $0.source != .builtin }, "a custom file can't shadow a built-in")
    check(!catalog.contains { $0.name == "/loose" }, "a loose .md in the skills dir is not a skill")
    check(!catalog.contains { $0.name == "/README" }, "only .md files are commands")
    check(catalog.filter { $0.name == "/deploy" }.count == 1 && deploy?.source == .custom, "a command beats a same-named skill")
}

print("== inside a project ==")
do {
    let catalog = SlashCommandCatalog.forSession(cwd: project + "/src/deep")
    check(catalog.contains { $0.name == "/proj-only" && $0.detail == "Project command" },
          "the nearest .claude ancestor's commands join in")
    check(catalog.first { $0.name == "/deploy" }?.detail == "Ship it", "the user-level root wins a name collision")
    let outside = SlashCommandCatalog.forSession(cwd: home + "/elsewhere")
    check(outside.map(\.name) == SlashCommandCatalog.forSession(cwd: nil).map(\.name),
          "a cwd whose nearest .claude is $HOME itself adds nothing twice")
}

print("== edges ==")
do {
    check(SlashCommandCatalog.discover(commandDirs: ["/nonexistent"], skillDirs: ["/nope"]) == builtins,
          "missing directories are skipped")
    check(SlashCommand(name: "/x", source: .custom, detail: nil).menuTitle == "/x", "a row without a detail is just the name")
    check(SlashCommand(name: "/x", source: .custom, detail: "d").menuTitle == "/x — d", "…with the detail after a dash")
}

if failures == 0 {
    print("\nALL PASS")
    exit(0)
} else {
    print("\n\(failures) FAILURE(S)")
    exit(1)
}
