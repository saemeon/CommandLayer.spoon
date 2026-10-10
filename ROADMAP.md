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

- [ ] Rerun last command and Rerun a recent command… (J19).
  How: run Git: Checkout… and pick a branch, then `>` "rerun last": the same
  checkout runs again without asking. `>` "rerun a recent" lists what ran,
  each with its arguments below it.
- [ ] Opening the launcher no longer waits on the window list (N8): no `slow:
  gather.windows` or `windows: reading the … list` warning on an open; the
  windows rows are there, and a window opened since appears a moment later.
  How: use it for a day, then look in the console for those lines. A reread
  that is slow may still log, after the picker is up.
- [ ] "Search Text in…" opens at once (N6): it no longer gathers windows,
  apps or tabs to throw them away.
  How: `>` "search text in", enter: the folders are listed without a pause,
  and a second enter is not needed. Before: 147 ms, 104 of it windows and apps.
- [ ] Switching pickers by chord keeps what you typed: "pull" in the root,
  then cmd+o, reads `>pull`; cmd+p from there reads `files pull`.
  How: open the launcher, type "pull", press cmd+o: the field reads ">pull"
  and the Git commands are listed at once, without typing another letter
  (fzf's answer once arrived after its exit and was dropped). Press cmd+p:
  "files pull".

### Search, files and selection

- [ ] Instant Send (J2): a global key opens the actions panel on selected text.
  How: bind `{ "key": "alt+shift+space", "command": "selection.showActions",
  "global": true }`, select a word in TextEdit, press it: Look Up, Search the
  web and Copy are listed for that word.
- [ ] Several files selected in Finder are acted on together (N7).
  How: select three files in Finder, open the launcher: `cmd+.` lists "3
  selected"; Copy path copies three lines, Reveal in Finder selects all three,
  Open with… opens all three in the app chosen.
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

- [ ] `processes ` lists running processes busiest first and updates while open
  (J11); cmd+k on one offers Quit and Force quit.
  How: type `processes `, watch the CPU figures change; leave it, and the
  console shows no more `ps` runs.
- [ ] Recent apps come from macOS (J21): `recent ` lists the running apps front
  to back and then apps you quit, most recently used first.
  How: quit an app, open `recent `: it is listed under the running ones.
- [ ] `spoons ` lists the Hammerspoon hotkeys, and picking one presses it
  (J17); another Spoon's methods are rows once one is loaded.
  How: type `spoons ` then "f13": picking Hotkey F13 does what the remote's
  Home key does.
- [ ] In a password field, Paste, Emoji & Symbols and a YouTube key alert
  that Secure Input is on, naming the app, and the key presses nothing.
  How: click into a password field (e.g. a login page in Safari), open the
  launcher, pick Paste or Emoji & Symbols: an alert names Safari and says
  Secure Input is on; nothing is typed.

### Browser, projects and remote

- [ ] Tab, bookmark and history rows show their site's icon (J18).
  How: a few minutes after a reload, `recent ` or `context ` with Brave in
  front: tabs carry their sites' icons. `"browser.favicons": false` removes them.
- [ ] Brave: Command palette opens Brave's own palette (J20). If nothing
  opens, the chord is not Brave's: set `browser.bravePaletteKeys` to the one
  Brave shows for its command palette.
  How: with Brave in front, `cmd+.` then "command palette".
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

- [ ] WezTerm's panes are rows in the root, focused when picked (J22).
  How: with WezTerm running and two tabs open, type part of a tab's title:
  "WezTerm pane" rows; picking one brings WezTerm forward on that pane.
- [ ] `scripts ` lists Shortcuts, tasks and Raycast script commands (J4), and
  the dummy script runs through Raycast.
  How: in Raycast's settings, Extensions ▸ Script Commands ▸ Add Directories,
  add `~/.hammerspoon/commandlayer/scripts`. Then type `scripts ` "hello":
  Hello from Command Layer runs, and Raycast shows its greeting.
- [ ] A task from `tasks.json` (beside settings.json) runs in its
  `options.cwd`; a bad task is in Show Problems; "Tasks: Open User Tasks"
  creates the file.
  How (terminal on): `>` "user tasks" > Tasks: Open User Tasks creates the
  file. Put in
  `{ "version": "2.0.0", "tasks": [ { "label": "where am I", "type": "shell", "command": "pwd", "options": { "cwd": "~/Git" } } ] }`
  and save: "where am I" in the root runs in Terminal and prints ~/Git. A
  task without "command" is listed in Show Problems.

## What is left

### The plan, agreed on October 10

In this order, one commit each, the harness green after each and every new
check shown to fail without its change. What an item leaves to be seen on
screen goes to the Owner checks above. Declined on the same day, with the
reasons: design.md, "Declined, and why".

**Progress: 15 of 18 done.**

| # | Item | State |
|---|---|---|
| 1 | **N6** "Search Text in…" slow to open | Done, 188a216 -- a question gathers only extensions that can answer it (`viewItems`); 147 ms to 64 ms |
| 2 | **N8** Window list slow (up to 1.3 s) | Done, 60556d8 -- apps woken from App Nap were the cause; an open shows the last list and rereads it after drawing |
| 3 | **C16** Slow extensions as problems | Done, 00ea3b0 -- slow at the 90th percentile of 5+ opens: named in Show Problems |
| 4 | **N7** Finder's multiple selection | Done, 2fb4f9e -- Copy path, Reveal, Open with…, Open in editor act on every selected file |
| 5 | **G2** Rows for Hammerspoon code | Done, a494f3b -- `layer.rows(view)`, e.g. for an `hs.menubar` |
| 6 | **J19** Run a recent command again with its arguments | Done, 49c1ee7 -- Rerun last command, Rerun a recent command… (`rerun.lua`) |
| 7 | **C11** Typing that extends the last query searches only what matched it | Done, de1118c -- the matcher is handed only the last query's matches |
| 8 | **C15** A notification when a result lands after its picker closed | Done, 4f393b3 -- a background result taking `notifyAfterSeconds` (5) or longer is a notification; Git's task commands, shell and AppleScript failures |
| 9 | **J20** A row handing over to Brave's own command palette (`ctrl+space`) | Done, 0ec3439 -- Brave: Command palette, chord in `browser.bravePaletteKeys` |
| 10 | **J2** Instant Send: a global key opening cmd+k on the selected text | Done, de5caba -- `selection.showActions` for a global key; no chord shipped |
| 11 | **J18** Favicons on tab and bookmark rows, from Chromium's database | Done, 4516721 -- site icons from Chromium's Favicons database; `browser.favicons` |
| 12 | **J17** The loaded Spoons: their hotkeys and the commands they expose | Done, ac91938 -- `spoons ` picker: other Spoons' methods and every hotkey |
| 13 | **J21** App history from macOS (`lsappinfo`, Spotlight's last-used date) in place of the launcher's own | Done, 6c0460f -- `lsappinfo` order and Spotlight's last-used date; the layer's own record is gone |
| 14 | **J11** A live picker: running processes with Quit, redrawn while open | Done, 6b18366 -- `processes ` updates every 2 s while open; Quit, Force quit |
| 15 | **J4** A Scripts picker fed by extensions (Shortcuts, tasks, Raycast script commands), tried with a dummy script | Done, 9f1ba55 -- `scripts ` picker; Raycast script commands from `raycast.scriptDirectories`; a dummy script in your dotfiles |
| 16 | **J22** yabai spaces and WezTerm panes as rows | |
| 17 | **L5** A README table, one row per extension | |
| 18 | **L4** SpoonInstall, `obj.homepage`, logger and hotkey mapping; needs the repository public | |

Done before the plan, the same day: the user folder moved to
`~/.hammerspoon/commandlayer` (7d014b5), extensions added from init.lua
(518b1f3), picker chords keeping what was typed (8e55074, f93f5ef).

### Not planned

- **C17** Draw the fast rows first: gather the extensions known to be fast,
  draw, then gather the slow ones a turn later and redraw, keeping the
  highlight. Kernel only. The answer for a blocking source if N8 finds no
  other.
- **C18** Streaming `items`: a hook may return a function (how to stop)
  instead of rows and answer through `done`, as `search` does. A contract
  change; worth it once an extension needs it.
- Window focus order: the lists are z-order, not focus history. Nothing
  watches focus; a source that does is still to be judged worth its cost.

### Watch

- Hammerspoon went away twice on September 15: once killed by SIGPIPE,
  fixed in ed37df6 (a task's input goes through a file, and the harness
  forbids writing stdin), and once on a reload with no crash report, more
  likely a hang. Note it here if it happens again.
