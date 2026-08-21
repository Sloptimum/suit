# Welcome to Suit

Suit opens as a terminal, but the whole app rests on two ideas — **tabs** and
**panes** — and a handful of keys that drive them. This tab is the five-minute
tour. Close it like any tab (⌘W); reopen it any time from the command palette
(⌘K → *Open the Guide*).

## Tabs are the unit

Every piece of work — a terminal, a file, a diff, a Claude transcript — is a
tab, exactly like a web browser. A tab in the background keeps its process
running, so switching away from a build never interrupts it.

| Key | Action |
| --- | --- |
| ⌘T | New tab — a fresh shell in the focused pane's directory |
| ⌘W | Close the tab (a busy tab asks first) |
| ⇧⌘T | Reopen the last closed tab |
| ⇧⌘] / ⇧⌘[ | Next / previous tab |
| ⌃Tab | Most-recently-used switcher — hold ⌃ to pick, quick tap to toggle the last two |
| ⌘1…⌘8 | Go to tab 1–8 |
| ⌘9 | Go to the last tab |

## Panes are viewports

A split does not create a second app — it creates a new **viewport** beside the
one you are in, and every pane shows one tab at a time with its own tab bar.
Think "two browser windows side by side", not "a terminal grid".

| Key | Action |
| --- | --- |
| ⌘D | Split the screen with a new terminal — the direction fits the pane's shape (wide splits side-by-side, tall stacks) |
| ⇧⌘D | Split horizontally — one pane above the other |
| ⌥⌘W | Remove the split but keep the tab — it folds back into a neighbor |
| ⌃⌘M | Remove all the splits |
| ⌥⌘← → ↑ ↓ | Move the focus to the pane on that side |

Moving a tab between panes is a **drag**: grab its chip from the tab bar and
drop it on another pane to show it there, on a pane's edge to split it out, or
clear of every window to tear it off into a window of its own. A right-click on
a tab offers Split Screen too.

## Finding your way

| Key | Action |
| --- | --- |
| ⌘K | Command palette — every command in the app, reachable by typing |
| ⌘P | Open a file quickly (a fuzzy search of the names) |
| ⌘B | Show or hide the sidebar |
| ⇧⌘F | Search in the project |
| ⌘, | Settings |

The full list of shortcuts lives in **Settings (⌘,) ▸ Shortcuts**. Quitting
saves your windows, tabs and splits; the next launch puts them back.
