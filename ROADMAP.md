# Roadmap -- working file

What is left to do, decide, test and watch. Decisions and their reasons are in
[design.md](design.md), the contract in [CLAUDE.md](CLAUDE.md), how the code
behaves in [docs/behaviour.md](docs/behaviour.md), credits in
[PRIOR_ART.md](PRIOR_ART.md). An id (Q2, C17) is stable, so "Q2 yes, Q5 no"
works in chat. A check confirmed on screen moves to
[docs/seen-working.md](docs/seen-working.md); delete it here once ticked.

## 1. Do first

Things only the owner can do, and that other checks depend on.

- [ ] **Give Hammerspoon Full Disk Access.** Since October 7 macOS refuses
  Hammerspoon opening Brave's files ("Operation not permitted"), so Brave's
  bookmarks, history and maybe tabs are missing; Show Problems says so.
  How: System Settings ▸ Privacy & Security ▸ Full Disk Access (or App
  Data), allow Hammerspoon, reload: the problem is gone, bookmarks are rows.
- [ ] **Add the scripts folder in Raycast**, so the dummy script command can
  run. How: Raycast ▸ Settings ▸ Extensions ▸ Script Commands ▸ Add
  Directories ▸ `~/.hammerspoon/commandlayer/scripts`.
- [ ] **Commit the dotfiles.** Uncommitted there: the config folder moved
  from `.config/commandlayer` to `.hammerspoon/commandlayer`, the
  `init.lua` changes (addExtension, mediacontrol on the media Mac only), the
  dummy script, `raycast.scriptDirectories` and `wezterm.enabled`.
- [ ] **Delete the old config folder** once all is well:
  `~/.config/commandlayer.backup-2026-10-10`.

## 2. Open questions

- **Q1 Push main?** Everything since October 10 is committed but not pushed.
- **Q2 SpoonInstall:** `scripts/spoon-release.sh <folder>` writes
  `Spoons/CommandLayer.spoon.zip` and `docs/docs.json`. Publish it as a
  `spoons` branch -- by hand per release, or a GitHub Action -- and add the
  SpoonInstall lines to the README? Recommended: a GitHub Action on each tag.
- **Q3 Settings per machine:** settings.json is now in shared dotfiles, so a
  setting for one Mac only needs a way to differ. Today init.lua checks the
  Mac's name (mediacontrol). Keep that, or support something like
  `settings.<machine name>.json` applied on top? Recommended: keep init.lua's
  way until a second setting needs it.
- **Q4 Instant Send's key:** which global chord runs `selection.showActions`?
  Suggested: `alt+shift+space`, added to your keybindings.json.
- **Q5 HSKeybindings `mapping`:** drop it, or find out first what
  HSKeybindings reads from a Spoon? Recommended: drop.
- **Q7 A promotion post for Reddit.** Write one introducing Command Layer --
  what it is (a keyboard launcher on Hammerspoon, shaped like VS Code's
  palette), what sets it apart (one context model every extension shares;
  everything is plain-text settings and Lua; it routes to the tools you have
  rather than replacing them), a short screen recording, and how to install.
  Where: r/hammerspoon first, then r/macapps. When: after Q1 and Q2, so the
  post can point at a public repository with a one-line install. An agent can
  draft it; the recording is yours.
- **Q6 The old app history** (`commandlayer.appMRU` in hs.settings) is no
  longer read since J21. Delete it, or leave it? Recommended: leave; it is
  harmless.

## 3. To test on screen

Each needs a reload of Hammerspoon first (cmd+alt+ctrl+R).

### The picker

- [ ] **Picker chords keep what you typed.** Type "pull", press cmd+o: the
  field reads `>pull` and the Git commands are listed at once; cmd+p then
  reads `files pull`.
- [ ] **Rerun** (J19). Run Git: Checkout… and pick a branch, then `>` "rerun
  last": the same checkout runs without asking. `>` "rerun a recent" lists
  what ran, with its arguments below.
- [ ] **"Search Text in…" opens at once** (N6). `>` "search text in", enter:
  the folders are listed without a pause; no second enter needed.

### Files and selection

- [ ] **Several Finder files at once** (N7). Select three files in Finder,
  open the launcher: `cmd+.` lists "3 selected"; Copy path copies three
  lines, Reveal in Finder selects all three, Open with… opens all three.
- [ ] **Selected text** is a subject. Select a word in TextEdit, open the
  launcher: a row for it; `cmd+.` offers Look Up, Search the web and Copy.
- [ ] **No selection** where there should be none: a password field, Brave, VS
  Code; and no `slow: capture.selection` line in the console.
- [ ] **Instant Send** (J2), once Q4 has a key: select a word in TextEdit,
  press the key: Look Up, Search the web and Copy, for that word.

### Apps, windows and system

- [ ] **Recent apps from macOS** (J21). Quit an app, open `recent `: it is
  listed under the running apps, which come front to back.
- [ ] **Processes** (J11). Type `processes `: busiest first, the CPU figures
  change while you watch; cmd+k offers Quit and Force quit (asks first).
- [ ] **Spoons and hotkeys** (J17). Type `spoons ` then "f13": picking Hotkey
  F13 does what the remote's Home key does.
- [ ] **Secure Input.** In a password field, Paste and Emoji & Symbols alert
  that Secure Input is on, naming the app, and type nothing.

### Browser

Needs Full Disk Access (section 1).

- [ ] **Site icons** (J18). A few minutes after a reload, `recent ` with Brave
  in front: tabs carry their sites' icons. `"browser.favicons": false`
  removes them.
- [ ] **Brave: Command palette** (J20). With Brave in front, `cmd+.` then
  "command palette": Brave's own palette opens. If nothing happens,
  `ctrl+space` is not Brave's chord: set `browser.bravePaletteKeys` to the
  one Brave shows.

### VS Code

- [ ] **Menu commands find their item.** `>` "command palette", enter: VS
  Code comes forward with its palette open. Likewise "run task", "go to
  file", "toggle terminal".
- [ ] **The bridge's alert.** Quit VS Code, pick VS Code: Run command…: an
  alert says VS Code is not running, and nothing else happens.

### SSH and remote

- [ ] **ssh hosts change without a reload**; Connect in terminal and in
  editor. Add `Host test-box`, `HostName 127.0.0.1`, `User
  simonniederberger` to ~/.ssh/config: "test-box" in the root shows "SSH:
  test-box" without a reload. Picking it runs `ssh test-box` in Terminal
  ("Connection refused" until Remote Login is on, which is enough). With
  System Settings ▸ General ▸ Sharing ▸ Remote Login on (your user only), it
  connects; cmd+k ▸ Connect in editor opens a remote VS Code window.
  Deleting the block removes the row without a reload.
- [ ] **A remote recent.** In that remote window, File ▸ Open Folder… ~/Git,
  close it: "Git" in the root shows "Project on test-box -- …/Git", enter
  opens it remotely, cmd+k offers Connect in terminal. Afterwards: Remote
  Login off, the block removed.

### Terminal and scripts

- [ ] **Scripts** (J4), after section 1's Raycast step. Type `scripts `
  "hello": Hello from Command Layer runs, and Raycast shows its greeting.
- [ ] **WezTerm panes** (J22). With WezTerm running and two tabs, type part of
  a tab's title: "WezTerm pane" rows; picking one brings WezTerm forward on
  that pane.
- [ ] **tasks.json.** `>` "user tasks" ▸ Tasks: Open User Tasks makes the
  file. Put in `{ "version": "2.0.0", "tasks": [ { "label": "where am I",
  "type": "shell", "command": "pwd", "options": { "cwd": "~/Git" } } ] }`
  and save: "where am I" in the root runs in the terminal and prints ~/Git; a
  task without "command" is in Show Problems.

### URL handler

- [ ] **Only allowed commands run.** Add `"urlhandler.allowedCommands": [
  "developer.showLogs" ]`, then in a terminal `open
  "hammerspoon://commandlayer?command=developer.showLogs"`: the console
  opens. With `developer.showPerformance` instead: an alert refuses it.

## 4. To watch over the next days

Read from the console (or tell an agent to read it).

- **No slow opens from System Settings or windows** (N8, systemsettings): no
  `open root … systemsettings`, `slow: gather.windows` or `windows: reading
  the … list` warning on an open. One `slow: timer.systemsettings` line two
  seconds after a reload is expected: that is the single scan.
- **Slow extensions in Show Problems** (C16): if one is named, it holds up
  opens often enough to be worth switching off or looking at.
- **Slow results as notifications** (C15): a Git: Fetch that takes over 5 s
  shows up in Notification Center rather than as a fading alert.
- **Crashes:** Hammerspoon went away twice on September 15 (one SIGPIPE,
  fixed in ed37df6; one on a reload, more likely a hang). Note it here if it
  happens again.

## 5. Not planned

- **C17** Draw the fast rows first, the slow extensions' rows a turn later.
  The answer for a blocking source if one shows up again in section 4.
- **C18** Streaming `items`, answering through `done` as `search` does. A
  contract change; worth it once an extension needs it.
- **Window focus order:** the lists are z-order, not focus history; a source
  that watches focus is still to be judged worth its cost.

## 6. Done on October 10

| Item | Commit | What changed |
|---|---|---|
| User folder | 7d014b5 | `~/.hammerspoon/commandlayer` by default |
| addExtension | 518b1f3 | Extensions handed over from init.lua; replaced L6 |
| Picker chords | 8e55074, f93f5ef, 172b83b | Keep what was typed; fzf's late answer no longer lost |
| N6 | 188a216 | A question gathers only extensions that can answer it (`viewItems`): 147 ms to 64 ms |
| N8 | 60556d8, 0cf7862 | The window list opens from the last read and rereads after drawing; `windows.reuseLastList` |
| C16 | 00ea3b0 | An extension slow in 1 of 10 opens is named in Show Problems |
| N7 | 2fb4f9e | Verbs on every file selected in Finder |
| G2 | a494f3b | `layer.rows(view)` for an hs.menubar or a menu of your own |
| J19 | 49c1ee7 | Rerun last command, Rerun a recent command… |
| C11 | de1118c | Typing on searches only the last query's matches |
| C15 | 4f393b3 | A background result taking 5 s or more is a notification (`notifyAfterSeconds`) |
| J20 | 0ec3439 | Brave: Command palette (`browser.bravePaletteKeys`) |
| J2 | de5caba | Instant Send, `selection.showActions` |
| J18 | 4516721 | Site icons on tab, bookmark and history rows (`browser.favicons`) |
| J17 | ac91938 | `spoons `: other Spoons' methods and every hotkey |
| J21 | 6c0460f | Recent apps from macOS; the layer's own record gone |
| J11 | 6b18366 | `processes `, a live picker |
| J4 | 9f1ba55 | `scripts `: Shortcuts, tasks and Raycast script commands |
| J22 | 903c553 | `wezterm` and `yabai` extensions, off as shipped |
| L5 | f20ea17 | The README's table of extensions, generated |
| L4 | 3a70953 | `obj.homepage`, `logger`, `scripts/spoon-release.sh` |
| Brave access | 6ea21aa | A refused Bookmarks file is a problem saying where to allow it |

Declined the same day, with the reasons: design.md, "Declined, and why" (I2,
M1, C14, Docker and mas, a script runner and a menu bar of our own).
