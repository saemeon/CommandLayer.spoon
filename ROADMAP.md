# Roadmap -- working file

What is still to check on screen, and what is still to build. Decisions
and their reasons are in
[design.md](hammerspoon/CommandLayer.spoon/design.md), how the code
behaves in [CLAUDE.md](CLAUDE.md), and credits in
[PRIOR_ART.md](PRIOR_ART.md). An id (D9, C4) is stable, so "C4 yes, E5
no" works in chat.

## Owner checks

What only the owner can see or do; tick when done, delete once ticked. An
agent's live check is a reload, the console and `problems`; what a check
confirmed moves to CLAUDE.md's "Seen working".

### Your own config

- [ ] Optional: `"$schema"` pointing at the Spoon's
  `config/settings.schema.json` in settings.json completes and underlines in
  VS Code.
  How: as the first key in settings.json add
  `"$schema": "file:///Users/simonniederberger/.hammerspoon/Spoons/CommandLayer.spoon/config/settings.schema.json",`
  then type `"brow` in VS Code: it offers the browser settings, and a typo
  like `"browser.tabOrdr"` is underlined.

### The picker

- [x] Built, to be seen: why a key did what it did (D11).
  How: in the console run `spoon.CommandLayer.layer.setLogLevel("debug")`,
  open the launcher and press a chord you have two entries for (or cmd+k):
  the console has a line `key cmd+k -> quickOpen.showActions: …` naming each
  entry on that chord and why it did not run. `setLogLevel("warning")` after.

- [x] Built, to be seen: Keep awake (I18).
  How: type "keep awake" > Keep Awake: Keep awake -- an alert says so, and
  `pmset -g assertions` in a terminal lists caffeinate. Type "allow sleep":
  it ends. Keep awake for… offers 15 minutes, 1 hour, 2 hours. "What is
  keeping it awake" names what holds the Mac awake right now.

- [x] Built, to be seen: a site's commands on a tab row (I22).
  How: have a YouTube video in a Brave tab, then look at another page. Open
  `recent `, highlight the YouTube tab, cmd+k: "YouTube: Full screen" and the
  others are offered. Pick one: Brave brings that tab forward and presses the
  key (Vimium permitting, N9).

- [i only see finderSelected. but this has no agcions oar cmd+k  actions. i.e. i dont know what to use for.] Look again (N7): several files selected in Finder reach
  `finderSelectedFiles`. The capture reads every item; what hid it was
  Inspect Context Keys showing only `activeView` (N4, fixed) and a list as
  "table, 3 entries". A list of paths now reads as "3: one.txt, two.txt, …".
  How: select three files in Finder, open the launcher, `>` "context keys":
  finderSelectedFiles reads "3:" and their names.

### Search, files and selection

- [ ] zoxide's folders in `files ` before and while typing, cmd+k on one; a
  folder opened here reaches `zoxide query` (writes your real database;
  `zoxide.learn` off stops it).
  How: cmd+p: folders from zoxide are listed; open one. In a terminal,
  `zoxide query` lists it near the top. `"zoxide.learn": false` stops that.
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

- [x] The window providers other than raycast (rectangle, yabai, aerospace),
  whose action names and flags were written from memory. Raycast's are seen
  working.
  How, for a tool you have: set `"windows.provider"`, save, quit the tool and
  run Window: Left half -- nothing should move, since a move goes to that
  provider and nowhere else. Start it again and run it: the window moves.
- [ ] In a password field, Paste, Emoji & Symbols and a YouTube key alert
  that Secure Input is on, naming the app, and the key presses nothing.
  How: click into a password field (e.g. a login page in Safari), open the
  launcher, pick Paste or Emoji & Symbols: an alert names Safari and says
  Secure Input is on; nothing is typed.

### Browser, projects and remote

- [ ] An ssh host row reading "SSH: <name>", as a command row reads
  "Category: Title", and the Homebrew commands reading "Brew: Update" and so
  on -- both asked for after the last round.
  How: type "ssh" in the root: the rows read "SSH: <host>". Type "brew"
  (terminal on): "Brew: Update", "Brew: Upgrade"…
- [x] Show Problems lists nothing for the shipped sites; YouTube's commands
  show on a video page; a mistake in your own site file is listed.
  How: create `~/.config/commandlayer/sites/mine.json` holding
  `{ "name": "Mine", "match": "[", "commands": [] }`, save settings.json to
  reload: Show Problems names mine.json and the bad match. Delete the file.
- [ ] Your ssh hosts in the root, changing without a reload when
  `~/.ssh/config` is edited; Connect in terminal opens `ssh <host>`; Connect
  in editor opens a remote VS Code window.
  How: add `Host test-box` with a `HostName` to ~/.ssh/config: typing
  "test-box" in the root shows it without a reload. Picking it connects (in
  the editor while terminal is off); cmd+k offers Connect in editor.
- [ ] A remote recent reads "Project on <host>" in the root and `recent `,
  opens remotely, and cmd+k offers Connect in terminal.
  How: open a folder over Remote - SSH in VS Code once, then type the
  folder's name: "Project on <host> -- <path>"; enter opens it remotely.
- [ ] With the bridge installed, its four rows appear within a minute; Find
  in files and Go to file run once allowed, and are refused before; a task
  and a command id run by name.
  How: `"vscodebridge.enabled": true`, then `>` "find in files lofi": VS Code
  searches for lofi (once `workbench.action.findInFiles` is in the VS Code
  setting `commandLayer.uriHandler.allowedCommands`; refused before). 
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
  opens it. What the code says: the question lists the rows its clause holds
  for from two whole menus, `files` and `recent`, so opening it gathers
  every extension feeding either -- recent files, zoxide's folders, projects,
  and then the browser's tabs, the apps and the windows, whose rows the
  clause (`file`, `folder` or `project`) throws away. Windows alone was 130 ms
  of a root open before that list was narrowed.
  Two ways out, neither started:
  - Measure first: open it, then "Developer: Show Performance" -- the
    `gather.<extension>` names say who, and one slow name may be the whole
    story.
  - Then, if it is the discarded rows: an extension would have to say which
    subject kinds it contributes, so a question gathers only what could
    answer it. That widens the extension contract, so it is a proposal, not
    a tidy-up.

### In progress

- Hammerspoon went away twice on September 15. At 08:39 it was killed by
  SIGPIPE: the layer wrote a task's input into a pipe whose reader had gone.
  Fixed (ed37df6): input goes through a file, and a source check forbids
  writing a task's stdin. Once more on a reload, with no crash report, more
  likely a hang. Watch whether it happens again.

### Later

- **C11** Narrow the previous results when the query extends the last one.
- **C14** Safer paste: focus the captured window first; apps where only
  copying makes sense.
- **C15** Notifications for results that land after the picker closed.
- **G2** A menu bar icon whose menu is a picker's rows, through the popup.
- **I2** appmenus: a path with alternatives (Play or Pause), so one key
  toggles. Still dispatch: the menu says which of the two is there now, and
  the row clicks that one. Reading the menu is reading the environment, and
  nothing is remembered between presses.
- **J2** Instant Send: a global chord that opens the cmd+k panel straight on
  what is selected, skipping the picker in between -- Raycast's of the same
  name. Pressed in any app, it reads the selection (`selection.lua`), pushes
  the `actions` picker with that as its subject, and what you see is Look Up,
  Search the web, Copy and whatever else takes a selection. Nothing new is
  needed but the entry: a keybinding running `quickOpen` with the actions
  picker and a subject taken from the context.
  What it is for: acting on what you have selected without going looking for
  the verb. Today that is three steps -- select the text, open the launcher,
  find "Search the web" or "Look Up" among everything else. Instant Send is
  one key: the panel opens already about the selection, listing only what can
  be done with text (Look Up, Search the web, Copy, and whatever else takes a
  `selection`), and enter runs it. Alfred calls the same thing Universal
  Actions. It is worth building only if you select text and act on it often;
  if you mostly copy and paste yourself, it saves nothing, and that is the
  question to answer rather than the mechanism.
- **J4** Script commands in any language: a folder of executables that
  become rows, each saying in a comment block at its top what it is called
  and what it takes -- Raycast's Script Commands (`@raycast.title`,
  `@raycast.mode`, `@raycast.argument1`) or Alfred's Script Filter, which
  prints JSON rows instead. An extension would read the folder, make a
  command per file with its arguments as inputs, and run it through
  `shell.run` or `terminal.run` by its mode. It is how a person adds a verb
  without writing Lua, and it is dispatch: we run the file and show what it
  prints.
- **J11** Live pickers -- not VS Code's, kept because the owner wants it --
  a picker whose rows keep changing while it is open --
  running processes with Quit on cmd+k, or CPU, memory and battery as rows
  that tick. The extension feeding it starts a timer when its picker opens
  and calls `refresh()`; the `left` hook is what stops that timer when the
  level comes off the stack, so nothing ticks behind a closed launcher. That
  hook is why this is now possible.
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

- Browser automation: **decided, and minimal.** Going to a tab is Apple
  Events already (`browser.tab` selects the tab in its window, and a tab
  gone, a refusal or a non-browser opens the URL instead), and a site's `js`
  runs the same way. Nothing more is wanted: no typing into pages, no forms,
  no Raycast round trip, no browser extension of our own. Why the
  alternatives were turned down is in design.md.
  What stays and is worth keeping good: verbs that know what the URL *is* --
  Clone repository on a GitHub page, a site's own commands. Those lead the
  context picker now, since the page is a context inside the app's.
- Before publishing: `obj.homepage` once a repository is public, and whether
  init.lua should offer a `logger` and an HSKeybindings `mapping`.

## Progress

**81/81 built**, and everything agreed since is built too: E10, F7, I13,
I18, I21, I22, D11, and apps and menu items where they belong. Of the nine
found on screen, N6 is the one still open -- it needs a measurement only
the owner's machine can give (above). What remains is the owner checks,
Later, and what is yours to decide.
