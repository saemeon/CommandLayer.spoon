# Roadmap -- working file

What is left to do, test and watch: a reference for the owner. Tick a box
when done; a check confirmed on screen moves to
[docs/seen-working.md](docs/seen-working.md) and is deleted here. What was
built is in git's history; decisions and their reasons are in
[design.md](design.md).

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
  `init.lua` changes (addExtension; mediacontrol only on a Mac whose name
  holds "Air"), the dummy script, `raycast.scriptDirectories` and
  `wezterm.enabled`.
- [ ] **On the MacBook Air, once:** remove the old app history the layer no
  longer reads -- in the Hammerspoon console,
  `hs.settings.clear("commandlayer.appMRU")`. Done on the MacBook Pro.
- [ ] **Delete the old config folder** once all is well:
  `~/.config/commandlayer.backup-2026-10-10`.

## 2. Later

- **A promotion post for Reddit.** Introduce Command Layer -- a keyboard
  launcher on Hammerspoon shaped like VS Code's palette; one context model
  every extension shares; plain-text settings and Lua; routing to the tools
  you have rather than replacing them -- with a short screen recording and
  the SpoonInstall lines. r/hammerspoon first, then r/macapps. Nothing to do
  yet.
- **Instant Send's key:** `selection.showActions` is installed with no key;
  bind one in keybindings.json when wanted, e.g. `{ "key":
  "alt+shift+space", "command": "selection.showActions", "global": true }`.

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
- [ ] **Instant Send** (J2), once it has a key (section 2): select a word in
  TextEdit, press the key: Look Up, Search the web and Copy, for that word.

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

### SpoonInstall

- [ ] **The spoons branch installs.** After a version tag (or Actions ▸
  Publish for SpoonInstall ▸ Run workflow), the `spoons` branch holds
  `docs/docs.json` and `Spoons/CommandLayer.spoon.zip`, and the README's
  SpoonInstall lines install it into a fresh `~/.hammerspoon/Spoons/`.

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
