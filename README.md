<p align="center">
  <img src="design/app-icon.png" width="128" alt="Suit app icon">
</p>

<h1 align="center">Suit</h1>

<p align="center">
  <strong>Stop Using IDE Terminal.</strong><br>
  A native macOS terminal for engineers who direct coding agents instead of typing every line.
</p>

<p align="center">
  <a href="https://github.com/Sloptimum/suit/actions/workflows/swift.yml"><img src="https://github.com/Sloptimum/suit/actions/workflows/swift.yml/badge.svg?branch=main" alt="CI status"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-000000?logo=apple&logoColor=white" alt="Platform: macOS 14+">
  <img src="https://img.shields.io/badge/language-Swift%20%2F%20AppKit-F05138?logo=swift&logoColor=white" alt="Language: Swift / AppKit">
  <img src="https://img.shields.io/badge/UI-100%25%20native%20%C2%B7%20no%20Electron-1f6feb" alt="UI: native AppKit, no Electron">
  <img src="https://img.shields.io/badge/build-swiftc%20(no%20SwiftPM)-important" alt="Build: swiftc">
  <img src="https://img.shields.io/badge/status-active%20development-3fb950" alt="Status: active development">
</p>

<p align="center">
  <img src="design/tabs-drag.gif" alt="A tab dragged from one pane to another. Dropping it on a pane edge splits out a new pane; dropping it on the center shows it in that pane. A highlight previews where the tab will land.">
  <br>
  <em>Drag a tab to the <strong>edge</strong> of a pane to split it out into a pane of its own. Drop it on the <strong>center</strong> to show it there instead. The highlight previews where it lands.</em>
</p>

Suit is a native macOS app bundle — its own Dock icon, its own bundle identifier, its own TCC
permissions. Every window is a split tree of panes, and every pane holds browser-style tabs:
terminals, file viewers, diffs, Claude transcripts, dashboards. The shells are real ptys driven by
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) with your login shell and your dotfiles.
Everything above them — tabs, splits, the file tree, project search, the git surface, code
navigation, session state — is AppKit, in one signed binary. No Electron, no web view, no
extension host.

## Table of contents

- [Why Suit exists](#why-suit-exists)
- [What Suit replaces](#what-suit-replaces)
  - [Your terminal emulator](#your-terminal-emulator) ·
    [Most of your IDE](#most-of-your-ide) ·
    [What Suit is not](#what-suit-is-not)
- [Highlights](#highlights)
- [Features](#features)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Install & build](#install--build)
- [Requirements](#requirements)
- [Development and contribution](#development-and-contribution)
- [License](#license)

## Why Suit exists

The shape of the work changed before the tools did.

An IDE is built around one human cursor: one project window, one checked-out branch, one file you
are personally authoring. That was the right model when the bottleneck was typing. It is the wrong
model when three Claude Code sessions are running in three worktrees on three branches, each
producing diffs you have to read, each occasionally stopping to ask you a question. Now the
bottleneck is *attention* — knowing which session needs you, what changed while you were away, and
whether the change is any good.

Agents live in terminals, so that is where the work drifted. But a terminal emulator has nothing to
say about what is inside its panes. Every tab is an identical rectangle of text; the only index is
your memory. You end up running two apps that each solve half the problem badly — an IDE demoted to
a file viewer with a chat panel bolted on, and a terminal multiplexer you navigate by recall.

Suit collapses that into one app built for the actual shape of the work. Underneath, it is an
honest terminal: `zsh -l -i` on a true pty, your prompt, your `.zshrc`, your Powerlevel10k. Around
it sits the surface an IDE would have given you — a file tree, fuzzy open, ripgrep search,
go-to-definition, a full local git workflow, diff review — plus the surface neither tool gives you:
live state for every agent session, aggregated across every window, with the controls to steer them
without typing into each pane by hand.

## What Suit replaces

### Your terminal emulator

iTerm2, Ghostty, Warp and Terminal.app all draw text extremely well, and the best of them model
shells and commands. None of them model the thing above the shell: a long-running agent session,
the worktree and branch it is working in, and the review that has to happen afterwards. Suit does,
and builds the window around it:

- **Panes report their state.** A pane running a Claude session shows a live status dot — busy,
  pulsing needs-input, done — plus context fill and cost. A shell that exits non-zero keeps its tab
  open with a red dot and the signal reason instead of vanishing.
- **A tab is not only a shell.** Terminals, editable file viewers, diffs, transcripts, Markdown,
  images, PDFs and dashboards are all tabs in the same strip, with the same drag, split, dedupe and
  restore behavior. Cmd-click a path in terminal output and it opens as a real tab at the right
  line.
- **One cross-window fleet view.** ⇧⌘O lists every live session across every window — status, task,
  project · worktree · branch, context %, cost — sorted needs-you-first, with Focus / Interrupt /
  Continue / Stop on each row and a Kanban board toggle. Subagent worktrees nest under their
  parent.
- **You steer sessions from the UI.** Send a prompt into any session's pty, broadcast one
  instruction to a selected set, dispatch a slash command from a menu of Claude's built-ins and
  your own, switch permission mode without guessing how many Shift+Tabs it takes, or review a
  proposed plan with Approve / Edit / Discard buttons.
- **Attention is routed, not polled.** A session that blocks while Suit is in the background posts
  a notification, badges the Dock, and plays a sound you chose — and stays silent when Suit is
  already frontmost. Spend ceilings per session and per worktree fire once on crossing, and can
  send Esc to halt the run.
- **Background jobs stop being invisible.** Launch a dev server or test watcher through the bundled
  `suit-bg` wrapper and a monitor pane tracks it — command, running/done/failed, listening port,
  and a live tail of its captured output.
- **State survives.** Quitting snapshots every window's tabs, split tree and scroll positions;
  launch puts them back, restarting shells in their old working directories. Named layouts do the
  same on demand.

### Most of your IDE

The parts of VS Code you actually touch during agent-driven work are reading, searching, navigating
and reviewing code. Suit ships those natively, with nothing to install:

| What you open VS Code for | In Suit |
| --- | --- |
| File tree, fuzzy open | Sidebar Files tab with git status tints and sub-project badges; ⌘P over a live project index |
| Project-wide search & replace | ⇧⌘F ripgrep panel — case / whole-word / regex, glob and scope filters, streaming results, preserve-case Replace All, and matches washed into every open viewer |
| Syntax highlighting | Bundled scanner, ~40 languages, no language server and no download |
| Go to definition, find references | ⌃⌘J / ⌃⌘R, ⌥⌘J peek, ⌃⌘O symbol outline, clickable breadcrumbs, browser-style jump history — all off one ctags index |
| Editing | Editable buffers with autosave and undo, smart indent, auto-closing pairs, ⌘/ comment toggle, code folding, multi-selection, column select |
| Find & replace in file | ⌘F / ⌥⌘F bar with the same three toggles, regex capture groups, and Replace All as one undo step |
| Source control view | Stage / unstage per file or in bulk, commit box with amend and commit-and-push, fetch / pull / rebase / push / stash, branch and worktree switcher, PR creation |
| Blame & history | ⌃⌘B blame gutter, file history, a Time Travel scrubber over every revision, and a clickable commit-graph DAG |
| Diff review | Unified or side-by-side, `n`/`p`/`o` review walk, and `c` to leave a line comment |
| Pull request review | PR inbox of everything that involves you, `gh pr diff` into the diff pane, line comments, and Approve / Request Changes / Comment submitted with `gh pr review` |
| Markdown, image, PDF preview | Rendered Markdown in a reading column, images over a checkerboard, PDFs with a thumbnail rail — all ordinary tabs |
| Themes & settings | 26 color tokens across chrome, text, status, syntax and diff; 14 built-in themes; live switching; `.suittheme` import/export |

Two capabilities have no counterpart in a conventional IDE, because they only make sense once
agents are doing the writing:

- **"What changed while I was away."** Drop a marker (⚑) across a repo, walk away, and come back to
  one aggregate diff of every worktree's commits, staged, unstaged and new files since that mark —
  with a per-worktree summary of files touched and `+/−` counts, attributed to the session that did
  it.
- **Review comments that go somewhere.** Line comments left in a diff collect into a draft, then
  **Send Review to Session…** pipes the batch into a chosen Claude session as one structured
  prompt. The Feedback inbox does the same for CI failures, PR review comments and merge conflicts,
  each routed back to the session whose worktree caused it.

### What Suit is not

This is a deliberate scope, not a roadmap gap:

- **No language server, no debugger, no extension marketplace.** Navigation is ctags-backed and
  degrades to whole-word ripgrep when ctags is absent. There is no completion engine, no refactoring
  engine, no breakpoint UI.
- **Editing is a bounded slice.** The viewer edits well enough to fix a line, adjust a config, or
  write a note — autosave, undo, find and replace, folding, multi-selection. It is not trying to be
  the place you write a thousand lines by hand, because in this workflow you don't.
- **macOS only, and personal software.** One platform, one engineer's daily driver, MIT licensed.

If you write most of your code yourself, VS Code is a better editor and this is an honest thing to
say. If you spend your day directing agents and reviewing what they produce, the editor was never
the part you needed.

## Highlights

- **Browser-style tabs and splits** for terminals, files, diffs and transcripts — dragged between
  panes, torn off into windows, deduped by path, and restored at the next launch.
- **A sidebar that covers the loop** — file tree, ripgrep search with project-wide replace, a full
  Source Control tab (staging, commits, branches, worktrees, pull requests), sessions, SSH hosts,
  notes, bookmarks, and a background-activity log. A live file index keeps it honest about your
  gitignore rules.
- **A cockpit for Claude Code** — per-pane session state and context fill, the cross-window fleet
  dashboard, broadcast, talk-back, slash commands, plan review, checkpoint timelines, transcript
  search, worktree tasks, recipes and spend guardrails.
- **Native and honest** — one ad-hoc-signed bundle, true ptys, login shells, on-device dictation,
  passwords only in the Keychain, and OSC 52 clipboard *reads* refused outright. [Hack](https://sourcefoundry.org/hack)
  ships inside the bundle, so a fresh install looks right before you install anything else.

## Features

**[docs/features.md](docs/features.md)** is the complete reference — every behavior, shortcut and
setting:

- [Tabs & panes — the browser model](docs/features.md#tabs--panes--tabs-live-on-the-pane)
- [Files, search & navigation](docs/features.md#files-search--navigation)
- [Claude Code cockpit](docs/features.md#claude-code-cockpit)
- [Appearance & settings](docs/features.md#appearance--settings)
- [Themes](docs/features.md#themes)
- [Safety](docs/features.md#safety)

## Keyboard shortcuts

The app also shows the full list in **Settings (⌘,) ▸ Shortcuts**.

<details>
<summary><strong>Show all shortcuts</strong></summary>

### Tabs

| Shortcut | Action |
| --- | --- |
| ⌘T | New tab |
| ⌘W | Close the tab |
| ⇧⌘T | Open the last closed tab again |
| ⇧⌘] | Next tab |
| ⇧⌘[ | Previous tab |
| ⌃Tab | Go through the recent tabs |
| ⌃⇧Tab | Go through the recent tabs, in the opposite sequence |
| ⌘1…⌘8 | Go to tab 1 to tab 8 |
| ⌘9 | Go to the last tab |

### Screens & splits

| Shortcut | Action |
| --- | --- |
| ⌘D | Split the screen and put a new terminal in the new pane |
| ⇧⌘D | Split the screen horizontally (one pane above the other) |
| ⌥⌘W | Remove the split, but keep the tab |
| ⌃⌘M | Remove all the splits |
| ⌥⌘← / → / ↑ / ↓ | Move the focus to the pane at the left, the right, above or below |

Save a window's tab list and split tree under a name and reopen it any time — **Save Layout As…**
and **Open Layout…** in the Screen menu. The command palette does both, and adds **Rename Layout…**
and **Delete Layout…**.

### Files, search & navigation

| Shortcut | Action |
| --- | --- |
| ⌘N | New file (Untitled-1, in a new pane, ready to type) |
| ⌘S | Save the file (a new file asks where it goes) |
| ⌘P | Open a file quickly (a fuzzy search of the names) |
| ⌘K | Command palette |
| ⌃R | Search the history of the commands (Enter runs · ⇧Enter edits first) |
| ⌘B | Show or hide the sidebar |
| ⇧⌘F | Search in the project |
| ⌘F | Find in the pane |
| ⌥⌘F | Find and replace (file viewer) |
| ⌘G | Find the next result |
| ⇧⌘G | Find the previous result |
| ⌘E | Use the selection for the find function |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘X / ⌘C / ⌘V | Cut / copy / paste |
| ⌘A | Select all |
| Home / End | Go to the start / end of the line (⇧ extends the selection, ⌘ goes to the ends of the file) |
| ⌘S | Save the file that you edited (file viewer) |
| ⌘L | Go to a line (file viewer) |
| ⇧⌘L | Add or remove a bookmark on this line (file viewer) |
| ⌃⌘J | Go to the definition (file viewer; a click with ⌘ does the same) |
| ⌥⌘J | Show the definition in the same pane (file viewer; a click with ⌥⌘ does the same) |
| ⌃⌘R | Find the references (file viewer) |
| ⌃⌘O | Go to a symbol in this file (file viewer) |
| ⌃- / ⌃⇧- | Go back / forward through your jumps |
| ⌘/ | Add or remove a comment (file viewer) |
| ⌃⌘] / ⌃⌘[ | Increase / decrease the indent (file viewer) |
| ⌃⌘E / ⌃⌘G | Select the next / all the occurrences (multi-selection) |
| ⌥⌘[ / ⌥⌘] | Fold / unfold the block (file viewer) |
| ⌥⌘0 / ⇧⌥⌘0 | Fold / unfold all the blocks (file viewer) |

### Git & Claude

| Shortcut | Action |
| --- | --- |
| ⌃⌘G | Show Source Control (⌘↩ in the message box makes the commit) |
| ⌃⌘D | Show the git diff |
| ⌃⌘B | Show or hide the blame gutter (file viewer) |
| ⌃⌘H | Move through the history of the file (file viewer) |
| ⌃⌘C | New Claude session |
| ⌃⌘T | New Claude task |
| ⌃⌘F | Search the transcripts |
| ⌃⌘/ | Menu of the slash commands |
| ⌃⌘K | Compact the focused session (/compact) |
| ⇧⌘O | Show the fleet dashboard |

**Show File History** (in the palette, or right-click in the viewer) lists the open file's commits
in the Source Control tab.

In a focused diff pane, `n` and `p` walk the changed files, `o` opens the file under review, and
`c` leaves a review comment on the line at the caret. **Send Review to Session…** collects the
whole batch and sends it into a Claude session as one structured prompt.

The Source Control tab's Feedback section surfaces CI failures, pull-request review comments and
merge conflicts, each attributed to the session whose worktree caused it. Click a row, or use
**Show Feedback Inbox** and **Route Feedback to Session…** in the palette.

The PR Review Inbox lists the open pull requests that involve you. Click one — or use **Show PR
Review Inbox** — to pull its diff into the diff pane; **Submit as PR Review…** then posts an
Approve, Request Changes or Comment verdict with `gh pr review`.

### Appearance

| Shortcut | Action |
| --- | --- |
| ⌘= / ⌘- | Increase / decrease the size of the font |
| ⇧⌘= / ⇧⌘- | Increase / decrease the size of the font (all the panes) |

### App & windows

| Shortcut | Action |
| --- | --- |
| ⇧⌘N | New window |
| ⌘, | Settings |
| ⌘C / ⌘V | Copy / paste |
| ⌘Q | Quit Suit |

</details>

## Install & build

```sh
git clone https://github.com/Sloptimum/suit.git
cd suit
./build.sh                 # compiles swift/, assembles build/Suit.app (ad-hoc code signed)
open build/Suit.app        # launch it like any other Mac app
```

There is no Xcode project and no SwiftPM package: `build.sh` compiles every source file directly
with `swiftc` and assembles the bundle. **[docs/development.md](docs/development.md)** covers the
development loop, the test harnesses, integration setup and the project layout.

## Requirements

- **macOS 14+**
- **Xcode Command Line Tools** (`swiftc`) — the full Xcode and SwiftPM are not needed
- **`gh`** (optional) — pull request creation and the Source Control tab's PR actions
- **`universal-ctags`** (optional, build time) — `build.sh` copies it into the bundle when it finds
  one, powering the symbol index behind go-to-definition; without it, navigation falls back to a
  whole-word ripgrep search
- **Claude Code** (optional) — everything in the cockpit

## Development and contribution

This is personal software, but the process is written down. Start with
**[docs/development.md](docs/development.md)** for the build loop, the test harnesses, integration
setup, the project layout and how to contribute. `CLAUDE.md` holds the architecture and the working
rules for coding agents, and is written in ASD-STE100 Simplified Technical English.

## License

[MIT](LICENSE) — © 2026 Sloptimum. Use it, copy it, change it and distribute it; keep the
copyright and permission notices.
