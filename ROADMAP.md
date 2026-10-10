# Roadmap -- working file

What is still to check on screen, and what is still to build. Decisions
and their reasons are in [design.md](design.md), the contract in
[CLAUDE.md](CLAUDE.md), how the code behaves in
[docs/behaviour.md](docs/behaviour.md), and credits in
[PRIOR_ART.md](PRIOR_ART.md). An id (D9, C4) is stable, so "C4 yes, E5
no" works in chat.

## Owner checks

What only the owner can see or do; tick when done, delete once ticked. An
agent's live check is a reload, the console and `problems`; what a check
confirmed moves to [docs/seen-working.md](docs/seen-working.md).

### Performance

- [ ] No slow `open root` line naming systemsettings any more (the panes are
  seen listed after the change). None in the console from the reload at
  12:47 to 13:26 on October 10; the old cost came hourly, so a day is the
  test.
  How: over the next hours, the console has no `open root … systemsettings`
  warning. (One `slow: timer.systemsettings` line two seconds after a reload
  is expected: that is the single scan.)

### The picker

- [ ] Switching pickers by chord keeps what you typed: "pull" in the root,
  then cmd+o, reads `>pull`; cmd+p from there reads `files pull`.
  How: open the launcher, type "pull", press cmd+o: the field reads ">pull"
  and the Git commands are listed. Press cmd+p: "files pull".

### Search, files and selection

- [ ] Text selected in TextEdit, Notes or Xcode is a subject in the root and
  `cmd+.`, with Look Up (Dictionary), Search the web and Copy.
  How: select a word in TextEdit, open the launcher: a row for the selected
  text; cmd+. offers Look Up, Search the web and Copy.
- [ ] No selection in a password field, Brave or VS Code, and no `slow:
  capture.selection` line. If Brave or VS Code get slower (reading their
  focused element can switch on accessibility mode), they should be skipped.
  How: select text on a Brave page and in VS Code, open the launcher: no
  selection row. The console has no "slow: capture.selection" line.

### Apps, windows and system

- [ ] In a password field, Paste, Emoji & Symbols and a YouTube key alert
  that Secure Input is on, naming the app, and the key presses nothing.
  How: click into a password field (e.g. a login page in Safari), open the
  launcher, pick Paste or Emoji & Symbols: an alert names Safari and says
  Secure Input is on; nothing is typed.

### Browser, projects and remote

- [ ] Your ssh hosts in the root, changing without a reload when
  `~/.ssh/config` is edited; Connect in terminal opens `ssh <host>`; Connect
  in editor opens a remote VS Code window.
  How, against this Mac: add `Host test-box`, `HostName 127.0.0.1`,
  `User simonniederberger` to ~/.ssh/config; "test-box" in the root shows
  "SSH: test-box" without a reload. Picking it runs `ssh test-box` in
  Terminal ("Connection refused" until Remote Login is on, which is enough to
  see it sent). With System Settings ▸ General ▸ Sharing ▸ Remote Login on
  (your user only), it connects; cmd+k ▸ Connect in editor opens a remote VS
  Code window. Deleting the block takes the row away without a reload.
- [ ] A remote recent reads "Project on <host>" in the root and `recent `,
  opens remotely, and cmd+k offers Connect in terminal.
  How: in the remote window from the check above, File ▸ Open Folder… ~/Git,
  close it; "Git" in the root shows "Project on test-box -- …/Git", enter
  opens it remotely. Afterwards: Remote Login off, the block removed.
- [ ] VS Code's menu commands find their item: Command Palette, Go to File,
  Run Task and Toggle Terminal (whose menu titles read "…" and carry a
  shortcut) select it instead of alerting "has no menu item".
  How: `>` "command palette", enter: VS Code comes forward with its palette
  open. Likewise "run task", "go to file" and "toggle terminal".
- [ ] The VS Code bridge's alerts when a bridge row runs: with VS Code quit or
  removed, with the extension not installed, and (no alert) installed from
  location.
  How: quit VS Code, pick VS Code: Run command…: an alert says so.
- [ ] `open "hammerspoon://commandlayer?command=<id>"` runs an id in
  `urlhandler.allowedCommands` and refuses one that is not.
  How: add `"urlhandler.allowedCommands": [ "developer.showLogs" ]`, then in
  a terminal `open "hammerspoon://commandlayer?command=developer.showLogs"`:
  the console opens. With `developer.showPerformance` instead: an alert
  refuses it.

### Terminal

- [ ] A task from `tasks.json` (beside settings.json) runs in its
  `options.cwd`; a bad task is in Show Problems; "Tasks: Open User Tasks"
  creates the file.
  How (terminal on): `>` "user tasks" > Tasks: Open User Tasks creates the
  file. Put in
  `{ "version": "2.0.0", "tasks": [ { "label": "where am I", "type": "shell", "command": "pwd", "options": { "cwd": "~/Git" } } ] }`
  and save: "where am I" in the root runs in Terminal and prints ~/Git. A
  task without "command" is listed in Show Problems.

## What is left

### Found on screen

- **N6** "Search Text in…" takes long enough to open that a second enter --
  pressed because nothing had happened yet -- lands on the first folder and
  opens it. The question gathers every extension feeding `files` and
  `recent` -- tabs, apps and windows included -- and its clause keeps only
  files, folders and projects. Not yet measured: open it, then "Developer:
  Show Performance"; the `gather.<extension>` names say who. If it is the
  discarded rows, an extension would have to say which subject kinds it
  contributes, so a question gathers only what could answer it -- a contract
  change, so a proposal first.
- **N8** Listing windows is the root's largest cost again: after the reload
  on October 10, opens spent 1083 ms (the first) and 184 ms in
  `gather.windows`, on the default `ordered` source
  (`hs.window.orderedWindows()`), where it had been about 25 ms that
  morning. Worth a look at which app answers slowly -- the windows extension
  names the slowest window when a read is slow -- and whether C17 (draw the
  rest first) is the answer, since the call blocks and cannot be streamed.
- **N7** Finder's multiple selection is captured (`finderSelectedFiles`) and
  shown in Inspect Context Keys, but no command reads it, so it does nothing
  you can see. Either verbs that take several files (Open with…, Reveal in
  Finder, Copy paths, Open in editor), or the key goes.

### Slow extensions

Read from the console on October 10: the root's slow opens were
systemsettings (about 200 ms, its hourly re-scan) and windows (about 200 ms
on October 7, 25 ms that morning, 184-1083 ms after a reload that
afternoon: N8). systemsettings now scans once per start, and
`cached` no longer refreshes inside an open. Hammerspoon has one Lua thread,
so a hook stuck in a blocking call cannot be interrupted; what remains is
how the picker copes with one.

- **C16** Slow extensions named as a problem: an extension whose
  `gather.<name>` p90 stays over a budget is listed in Show Problems with
  its time, switching it off the way out. The spans exist; only the report
  is missing.
- **C17** Draw the fast rows first: gather the extensions known to be fast,
  draw, then gather the slow ones a turn later and redraw, keeping the
  highlight. Kernel only. Rows arriving late below the highlighted one, so
  enter never lands on a row that just moved.
- **C18** Streaming `items`: a hook may return a function (how to stop)
  instead of rows and answer through `done`, as `search` does. Per-extension
  row slots, so a late answer still wins dedupe in extension order; a stale
  answer dropped once its level is left. Only helps an extension that moves
  its slow part into a task. A contract change, so a proposal first; worth
  it once an extension needs it.

### Later

- **C11** Narrow the previous results when the query extends the last one.
- **C14** Safer paste: focus the captured window first; apps where only
  copying makes sense.
- **C15** Notifications for results that land after the picker closed.
- **G2** A menu bar icon whose menu is a picker's rows, through the popup.
- **I2** appmenus: a path with alternatives (Play or Pause), so one key
  toggles. The menu says which of the two is there now, and the row clicks
  that one; nothing is remembered between presses.
- **J2** Instant Send: a global chord that opens the cmd+k panel straight on
  the selected text (Look Up, Search the web, Copy), skipping the picker in
  between -- Raycast's Instant Send, Alfred's Universal Actions. Needs only a
  keybinding running `quickOpen` with the actions picker and the selection as
  subject. Worth it only if you act on selected text often.
- **J4** Script commands in any language: a folder of executables that
  become rows, each saying in a comment block at its top what it is called
  and what it takes, as Raycast's Script Commands do. Run through
  `shell.run` or `terminal.run` by its mode; a verb without writing Lua.
- **J11** Live pickers, whose rows keep changing while open -- running
  processes with Quit on cmd+k, or CPU, memory and battery. The extension
  starts a timer when its picker opens and calls `refresh()`; the `left` hook
  stops it.
- **J17** Loaded Spoons: their hotkeys and the commands they expose.
- **J18** Favicons for tabs and bookmarks from Chromium's local database.
- **J19** Replay a recent command with its arguments.
- **L4** Installable with SpoonInstall.
- **L5** A README table per extension: what return does, what cmd+k offers.
- **L6** Installing extensions from a repository, pinned by commit.
- **M1** Share `tasks.json` with the zsh palette, which stays for Windows.
- App-usage history: try `lsappinfo`'s front-to-back order plus Spotlight's
  last-used date in its place.
- Window focus order: the lists are z-order, not focus history. Nothing
  watches focus; a source that does is still to be judged worth its cost.
- Ideas: a hand-off to Brave's own command palette (`ctrl+space`); `yabai`,
  `wezterm cli`, `mas`, `docker` as sources of rows.


### Yours to decide

- Before publishing: `obj.homepage` once the repository is public, and
  whether init.lua should offer a `logger` and an HSKeybindings `mapping`.
