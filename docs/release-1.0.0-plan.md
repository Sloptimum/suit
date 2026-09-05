# Release 1.0.0 — code-health plan

The working plan for the `1.0.0` branch. It exists so a later session can pick the work up
where the last one stopped: each step below is one commit, done in order, with its status kept
current in this file. Tick a box in the same commit that finishes the step.

## Where the work lives

- Branch `1.0.0`, cut from `main` at `329e680` on 2026-09-05. The branch carries the name of the
  version it ships (tags use a `v` prefix, so `v1.0.0` stays free for the release tag).
- Worktree `.claude/worktrees/1.0.0`.
- Version bumped from 0.2.3 to 1.0.0 (`CFBundleVersion` 3 → 4) in `Resources/Info.plist`.
- Merge target: `main`, by pull request, after the whole list is done and the advisor review
  (CLAUDE.md §7) has run. Nothing merges before then.
- The in-flight `integrate/code-health` branch already covers the unlisted-harness gap, shared file
  limits, a shell-quote helper, and CI pins. None of that is redone here, though both branches
  remove the same "(ROADMAP Phase N)" comments from seventeen scripts (identical text, so git
  merges them). Expect conflicts in `scripts/test.sh` (both add harness entries: keep all),
  `ProcessUtil.swift` (both additive), `AppDelegate+SettingsPersistence.swift` (keep code-health's
  textColorA fallback, spelled with `DefaultsKey`), `CLAUDE.md`, `build.sh`,
  `scripts/claude/suit-session-state.sh`, and one comment line each in `GoalComposition.swift` and
  `StateRestoration.swift`.

## How to resume

1. `git -C .claude/worktrees/1.0.0 log --oneline main..1.0.0` shows what landed.
2. Find the first unticked step below and continue from it.
3. After each step: `scripts/test.sh` in the worktree, and `./build.sh` when the change touches
   anything the harnesses do not compile. Commit with the step's title.

## Steps

### Phase 0 — setup
- [x] Cut the branch, bump the version, write this plan.

### Phase 1 — correctness
- [x] **1. One process runner.** Move the spawn into `ProcessUtil.swift`: stdout and stderr drained
      concurrently so a chatty child can never wedge the app, optional stdin, optional cwd, every
      call recorded in the ops log. Replace the eight bespoke spawns (FileIndex, GitBranches,
      WorktreeTasks, FleetDashboard ×2, BackgroundTaskStore, SymbolIndex ×2) and the 39
      `/usr/bin/git` literals with one constant. Fixes the stdout-then-stderr deadlock in
      `GitBranches.spawn` and `WorktreeTasks.runGit`, and makes Fleet's and WorktreeTasks' git
      calls visible in the ops log.
- [x] **2. Quarantine unreadable stores.** `Layouts.load` and `ThemeStore.loadSelection` go
      through `StoreFile.load`, so a corrupt file is moved aside instead of overwritten on the
      next save.
- [x] **3. One home-directory resolver.** `SuitPaths.home` / `SuitPaths.directory` replace the
      `$HOME ?? NSHomeDirectory()` line copied into ~18 files. `CheckpointTimeline.openSnapshot`
      switches from `NSHomeDirectory()` to it, so a sandboxed `$HOME` sandboxes the file-history
      read too. Harness compile lists gain `SuitPaths.swift` where a store is compiled standalone.
- [x] **4. No git on the main thread.** `DiffPaneContent.loadGitDiff` / `refresh`,
      `openCommitDiff` (both forms), the "since mark" composer in `+OpenTabs`, and
      `followWorktreeInTerminals` load with the placeholder-then-fill shape `openUpstreamDiff`
      already uses. The two `openSwitcherMenu`s read worktrees and branches from the repo shape
      `GitStatusMonitor` already caches instead of spawning git twice per click.

### Phase 2 — duplication
- [x] **5. One tail reader, one directory watcher, one process-table walker.** A Foundation-only
      `FileTailer` (watch a path, hand back appended lines, restart on truncate or replace)
      replaces the copies in `TranscriptPane+Tail`, `CheckpointTimeline` and
      `BackgroundTaskPane`; a `DirectoryWatcher` replaces the two in `ClaudeSessions` and
      `BackgroundTaskStore`; `processParentMap` lives once in `ProcessUtil`; the four
      `git worktree list --porcelain` parsers (WorktreeSwitcher, Markers, FleetDashboard,
      WorktreeTasks) become one. Harness for the tailer and the parsers.
- [x] **6. Typed defaults keys.** A `Defaults.Key` enum replaces the 35 hand-typed UserDefaults
      strings across 14 files, so a typo is a compile error. The load/save ledger in
      `AppDelegate+SettingsPersistence` keeps its shape but reads keys from the enum.
- [x] **7. Harnesses for the uncovered cores.** `TranscriptParsing`, `SlashCommands`,
      `GoalComposition`, `FleetModel` get harnesses directly; the parse functions in
      `GitBranches`, `WorktreeTasks` and `ClaudeSessions` move to Foundation-only cores first,
      then get theirs. Each is added to `HARNESSES` in `scripts/test.sh`.

### Phase 3 — hygiene
- [x] **8. Theme-token colors.** `ImagePane`'s checkerboard derives from theme tokens;
      `Pane.screensaverFontColors` uses `Theme.rgb` like the backgrounds beside it. No new
      tokens (that would change the theme file format).
- [x] **9. Docs.** File counts in `CLAUDE.md`, `build.sh` and `docs/development.md` corrected;
      the "ROADMAP Phase N" references in ten scripts and the hook script dropped;
      `design/roadmap-playground.html` removed; `docs/features.md` notes the loading placeholder
      on diff tabs.
- [x] **10. Split the two wiring giants.** `AppDelegate.buildMenu` (419 lines) split by menu;
      `TerminalWindowController.init` (343 lines) split by sidebar tab. Pure moves, no behavior
      change. Last, because it is the least valuable and the most conflict-prone.

### Phase 4 — close
- [x] `scripts/test.sh --all` green (43 of 43), `./build.sh` green, and the app rendered offscreen
      with a sandboxed `$HOME` (the design-reference scenario plus a diff tab on a fixture repo,
      so the split initializer and the async diff load ran for real). The bundle itself was not
      launched: it would share the live `~/.suit` and defaults with a running Suit.
- [x] Advisor review of the full diff (CLAUDE.md §7). Verdict: merge with fixes. Applied: the
      stdin write in `ProcessUtil.spawn` sets `F_SETNOSIGPIPE` (a ctags that exits mid-list used
      to kill the app with SIGPIPE — a hazard older than this branch); `lsof` gets `-a` so a
      task's port can no longer be another process's; `symbolic-ref` is a probe (a detached HEAD
      no longer logs red); the dead `loadDiffText`, `branchCount`, `worktreeCount` are gone; the
      feedback inbox uses the one porcelain parser. Noted by the advisor, left alone:
      `Activity.swift` bare-reads its `.jsonl` (per-line tolerant) and the switcher menus are
      empty until the monitor's first pass lands.
- [x] `main` had not moved (nothing to merge); pushed and opened PR #105 against `main`.
