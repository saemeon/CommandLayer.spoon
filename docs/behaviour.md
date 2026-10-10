# How it behaves

The detailed behaviour of the kernel and the shipped extensions, moved out
of CLAUDE.md so that file can stay the contract. Read the section for the
area you are changing; field lists are in the generated
[reference](api.md), the reasons in [design.md](../design.md).

## Running a thing

There are no backends: how a thing runs is a command, as VS Code's
`vscode.open` and `revealFileInOS` are, contributed by an extension with
`menus = {}` and switched off with it. The kernel runs none of its own.

    system.open        target: a URL or path, through /usr/bin/open; bundle
                       (open -b) or app (open -a) to choose the app, a
                       bundle alone opening that app
    system.reveal      target: a path, shown in Finder
    apps.open          id (bundle id), target (path or name)
    editor.open        target, in the editor installed; line, where it takes one
                       (code --goto path:line, zed and subl path:line); remote,
                       VS Code's authority (code --remote ssh-remote+host path),
                       which only code and cursor take
    terminal.open      target, a folder, in terminal.application
    terminal.run       cmd, as shell.run's, in the folder target; keepOpen
    webview.open       target, or html or file; width, height; css, js
    shell.run          cmd
    applescript.run    script, through osascript in a task; done(ok, output)
    spoon.call         spoon, method or chooser, fallback
    shortcuts.run      name

A row runs `command` with `args`, or a `run(ctx)` of its own. A command
runs Lua, or another command with args of its own, which is how a search
is data: `command = "system.open", args = { target =
"https://duckduckgo.com/?q=${query}" }`. The command that finally runs
fills its args' templates from the context, where the answers already
are; a chain that comes back to itself stops and is logged. The thing a
command acts on is `target`.

`shell.run` takes `cmd` two ways. As a list -- `{ "git", "-C", "${path}",
"pull" }` -- each element is resolved on its own and run with `hs.task`,
no shell: an absolute program as given, a registered tool's path, else
through `/usr/bin/env`. As a string it goes to `zsh -c`, and every value
substituted into it is single-quoted first, so `${clipboard}` can never
become shell code.

`webview.open` is a destination, as `system.open` is sent a URL: one
titled window, replacing any it opened before; escape closes it and focus
goes back to where you were. `css` and `js` are injected into every page it
loads through `hs.webview.usercontent` -- the style before the page draws,
the script once it is there, each value filled into `js` a string literal.

**A process's input** (`tools.run`'s `opts.input`: fzf's rows, bc's sum) is
never written into its stdin. A pipe written after its reader has gone -- a
task terminated for a newer query -- raises SIGPIPE, which Hammerspoon does
not ignore, so the whole app dies; that took Hammerspoon down while typing.
The input goes to a file in `$TMPDIR/commandlayer/`, and `/bin/sh` redirects
it into the program, the file, program and arguments each a positional
parameter, never script. The file is removed when the task exits or is
terminated. The harness fails on any `setInput` or `closeInput` in the
layer, and runs the argv in a real shell.

`applescript.run` never waits: the script runs in `/usr/bin/osascript`, and
a Lua caller that needs what it returned passes `done(ok, output, stderr)`.
"Open with…" (`system.openWith`, on a file, folder, project or link) lists
the apps Launch Services offers -- NSWorkspace through JavaScript for
Automation in a task, kept five minutes per extension, folder or scheme --
and runs `system.open` with the one chosen.

**The terminal.** `terminal.application` names one terminal, Terminal.app by
default, and nothing else is used in its place: one not installed is said
so. `terminal.run` builds `cmd` as `shell.run` does, every word or
substituted value single-quoted. In Terminal.app it is `do script`, typed
into a new window's own shell after a `cd`, through `osascript` in a task --
never `applescript.run`, which would fill templates in the built script a
second time, unquoted. That needs Hammerspoon allowed under Automation; a
refusal (-1743, -1744) is one alert saying where, and a log line, with no
other way tried. WezTerm, kitty and Alacritty run `$SHELL -lc` (or
`terminal.shell`), then `exec` a login shell so the window stays; `keepOpen =
false` is for interactive programs. WezTerm, judged running by bundle id
(`com.github.wez.wezterm`), gets `wezterm cli spawn --cwd <dir> [-- <shell> -lc
<line>]` and is brought to the front once that succeeds, since cli spawn does
not activate it; not running, cli spawn has no socket to reach, so it is
started through LaunchServices, `/usr/bin/open -na WezTerm --args start --cwd
<dir> [-- <shell> -lc <line>]` -- never `wezterm start` in a task, which would
make the GUI the task's child, ended when the extension stops.

**In the terminal.** What prints more than a line, or may ask something, is
handed to `terminal.run` by id, each extension requiring `terminal` and gone
with it. A command of an extension that does not require it -- Open in
terminal (`files.lua`), SSH: Connect in terminal -- has `when =
"terminalAvailable"`, a key the terminal extension sets while it is loaded, so
with it off that command is no row and no cmd+k verb, and an SSH host row
connects in the editor instead. `lazygit.lua`: Open in lazygit on a project or folder,
`keepOpen = false`, since lazygit is left by quitting it. `brew.lua`: the category is
Brew -- Brew: Update, Upgrade, Outdated, Doctor and Cleanup, as data (`command =
"terminal.run"`), and Install, Search and Info as text commands with the
prefixes `brew install `, `brew search ` and `brew info `, what was typed one
quoted word. Being text commands, they are among the root's fallbacks too.
Nothing lists formulae: `brew list` takes a second. `tasks.lua` reads
`tasks.json` beside the active profile's settings.json
(`cl.profileFile("tasks.json")`) in VS Code's shape -- `label`, `type`
`shell` or `process`, `command`, `args` (strings, or `{ value }`),
`options.cwd` with `~` expanded -- through `cl.readJSONC`, decoded again only
when its modification time or size moves, so an open costs a stat. Each task
is a root row running `tasks.runTask` with `{ task = label }`, as VS Code's
Run Task takes a label, so a keybinding can name one. A shell task is its
command as written with each argument single-quoted after it; a process task
is words alone. Another type, no label or command, or a label used twice is a
problem naming the file, and the task is left out. VS Code's own tasks.json
files are not read. "Tasks: Open User Tasks" makes the file and opens it in
the editor.

**URLs.** `extensions/urlhandler.lua` binds
`hammerspoon://commandlayer?command=<id>&args=<JSON object>` and runs the
command by id only when `urlhandler.allowedCommands` lists it, empty as
shipped: any web page can open such a URL. An id not listed, or args that
are not an object, is an alert and a log line naming the id.

**Secure Input.** While a password field holds it, macOS drops the keys
Hammerspoon presses. `extensions/secureinput.lua` sets `secureInput` in the
context while it is on (`hs.eventtap.isSecureInputEnabled`, in-process),
asks `ioreg` in a task which app holds it, and exports `warn(what, ctx)`:
`system.paste`, Emoji & Symbols, the screen captures and a site's keys
(`browser.keys`) call it before pressing, and alert naming the app. The media
keys are pressed anyway after
the warning: they are system-defined events, not keystrokes, and may well get
through. `system.paste` is the system extension's own -- the clipboard, then
cmd+v a tenth of a second later on a timer it holds -- and the kernel pastes
nothing.

**Screenshots, sound and media**, each the system's own route:

- **Screenshots** (`system.lua`): "Screenshot: Show toolbar" opens
  Screenshot.app by bundle id (`com.apple.screenshot.launcher`, which has
  lived in two folders); the captures press macOS's shortcuts --
  cmd+shift+3 and 4, with ctrl to copy -- a tenth of a second after the
  launcher closes, so the picker is not in the picture. Never `screencapture`:
  run from Hammerspoon it needs Screen Recording. The harness checks no plugin
  names it.
- **Audio** (`audio.lua`): switch the output or input device, keyed by UID,
  from lists read at start and again on `hs.audiodevice.watcher`, so a prompt
  reads no device. That watcher is one callback for all of Hammerspoon: a
  config setting its own replaces this one. "Toggle microphone mute" mutes
  every input device while any is on; `muted` in args says which way.
- **Media** (`media.lua`): play/pause, next and previous track as the media
  keys (`hs.eventtap.event.newSystemKeyEvent`, down then up), which macOS
  hands to whatever holds Now Playing; no player is scripted. In the root
  and the palette and nowhere else: the keys reach the player wherever you
  are, so they are not about the page in front, and in `cmd+.` on every page
  they were noise. They are how a video is controlled all the same -- the
  shipped YouTube site has no play / pause of its own, since pressing `k`
  into the page did nothing.
- **Keep awake** (`keepawake.lua`): macOS's own `caffeinate`, run in a task
  the extension holds -- `-di`, or `-i` with `keepawake.display` off, and
  `-t` for Keep awake for…, whose minutes are `keepawake.durations`. One at a
  time: a new request replaces the one running. `keepAwake` is in the
  context while it runs, so Keep awake and Allow sleep each show only when
  they mean something; switching the extension off or a reload ends it with
  everything else it held. "What is keeping it awake" reads `pmset -g
  assertions` and names each process holding a Prevent… assertion, once.
- **App: Toggle** (`apps.toggle`, on an app's cmd+k, meant for a key with
  `"args": { "app": { "id": "<bundle id>" } }`): hides the app that was in
  front as the layer opened, focuses it when running behind, launches it
  when not running.

## Profiles and settings

Settings are VS Code's arrangement; there is no Lua configuration.
`config/defaults.jsonc` and `config/defaultKeybindings.jsonc` ship; a
profile is a folder whose `settings.json` and `keybindings.json` go over
them. Both are JSONC, read by `core/jsonc.lua` (hs.json reads neither
comments nor trailing commas, and the harness has no hs.json).

- **Which profile:** `spoon.CommandLayer.profile`, else
  `~/.hammerspoon/commandlayer/profile.json`'s `profile`, else `default`. A
  name is the Spoon's `config/profiles/<name>/` then the user's
  `profiles/<name>/`; `default` is the user folder itself; a path is that
  folder.
- **Switching, not stacking:** only the active profile's files apply over
  the defaults, as VS Code's profiles do -- unless the profile says
  `"useDefaultProfile": { "keybindings": true }`, VS Code's "Use Default
  Profile" for keyboard shortcuts: then the default profile's
  keybindings.json comes after the shipped defaults and before the
  profile's own, which still win. Such an entry's origin is
  `defaultProfile`, so removing it from the keybindings picker appends a
  `-` entry to the active profile's file rather than editing the default's.
- **Merging:** objects merge key by key, lists and values replace, an
  empty list clears a list. `views` merge by name -- an entry changes the
  fields it names, and a new name adds a picker -- and
  `"enabled": false` removes one; removing the picker `defaultView` or
  `actionsView` names is a problem. Keybindings: the defaults', then the
  profile's, a `-` entry removing earlier ones.
- A picker's `placeholder` and `empty` are templates filled from the
  context.

`default` is shaped like VS Code's quick open. `raycast` has one picker and
no picker chords, and keeps the seam honest: a second profile has to be a
second opinion, not a patch to the first. `popup` is the default plus the
palette drawn as a native menu on `cmd+m`, the presenter seam as a profile.

`extensions/workbench.lua` reaches the files under VS Code's command ids,
so `"workbench.enabled": false` leaves them out. The active profile's own
files are made empty if missing. Default Settings is generated as VS Code
builds its own: `defaults.jsonc` with every extension's `<ext>.enabled`
and declared settings added inside the same object. Generated files go in
`$TMPDIR/commandlayer/` and are never read back. Switching profile lists
`default` and every folder with a settings or keybindings file under
either `profiles/`, writes `profile.json` and reloads. All four are
workbench's own (`M.defaultSettingsText`, `M.defaultKeybindingsText`,
`M.writeGenerated`, `M.switchProfile` on its module): the kernel gives it the
shipped files' paths (`cl.shippedFile`), each extension's declared menus
(`menus` on `cl.getSettingOwners()`) and `cl.encodeJSON`, and writes nothing.
Default Keyboard Shortcuts is the shipped file's entries, read again.

**Reloading.** `cl.reload()` (`M.reload`, at the end of `core/lifecycle.lua`)
stops the layer, undoes what setup made -- every extension unregistered with
what it registered (`M.unloadPlugins`), the keybindings, problems, prefix
aliases and the modal's hotkeys -- and starts it again, so every file is
read anew; `hs.reload` would restart the whole Hammerspoon config. The
profile chosen and what `hs.settings` records stay. Workbench watches the
active profile's folder and, once changes settle, calls
`cl.reload({ ifChanged = true })`, which reloads only when settings.json or
keybindings.json says something other than what the layer last read or
wrote, and returns whether it did. Compared by decoded
value, so a comment, a space or an extension's own write -- told to the layer
through `cl.settingsWritten()` or `cl.keybindingsWritten()`, which read the
file again and remember it -- is no change. A file that does not parse is a
problem, and nothing reloads until it parses. `workbench.autoReload: false` switches it off, read when a change
settles. Switching profile uses `hs.reload`.

`appearance` holds only what every picker shares; a key defaults.jsonc
does not have is a problem. A presenter's or ranker's own options are
settings it declares, under its name (`"chooser.screen"`), listed and
checked like an extension's.

A write from the picker is the settings extension's: `update(name, key,
value)` in its exports, which workbench's Reset Setting reaches through an
optional dependency -- with settings off it says it cannot write, rather than
failing silently. It changes one value in the file's text, as VS Code's
settings editor does, then tells the layer (`cl.settingsWritten()`), so a
setting reads what was written: `editJSONC` replaces a value where it stands, or
adds a missing key after the object's last entry with its indentation --
past a comment ending that line, inline in a one-line object, objects made
along the path -- so comments, order and layout survive. The parser that
decodes is the one that records where each value is. Settings are written
flat (`"browser.tabOrder"`). The file is read from disk at the moment of
writing, so a hand edit since setup is kept. Writing nothing removes the key, as VS Code's
`update(key, undefined)` does -- every entry for it, with its lines, a
comment ending its last line, and the comma before a last entry -- so the
setting reads its default; a key not there, or no file, changes nothing. A
file that does not parse is refused with an alert, never rewritten. `M.encodeJSON` writes whole
generated files, two-space indented with sorted keys.

**Problems.** Setup collects what is wrong in `M.problems` (`{ file,
message }`, once each); `start()` shows them in one alert naming the first
three, and logs every one. The settings still apply around a problem, as
VS Code reads the rest of a file it underlines; the harness asserts the
shipped defaults and profiles have none. A problem is: a file that does
not parse; a key that is not a setting (an extension switched off or
dropped still declares its keys, `K.declaredExtensions`); a value of the
wrong type or outside its `enum`; a prefix, `defaultView` or `actionsView`
naming no picker; a ranker, matcher or presenter not loaded; a section
naming nothing, or sections leading back to their own picker (opening
those stops rather than recursing); a keybinding with no or an unknown
command (removals too), an unreadable key, a `when` that does not parse, a
`key` on a view, or a `quickOpen` picker that does not exist -- checked
after removals, since a profile removes a picker and its chord together.

Every spec is checked against one schema too (`core/schema.lua`,
`M.checkSpecs` after settings are read): a field the kind cannot have, a
wrong type or value, a missing required field, a `when` that does not
parse, a declaration whose default breaks it, and a `command`, `parent`,
`presenter` or section naming nothing, and a picker's `command` naming no
command that takes text. So are a plugin or site file that does not load,
and a Lua file in the user folder's `views/`, which is never run: a picker
is declared in settings. Rows are checked only by the harness (`M.checkRow`): they
are made too late for a problem to be shown. "View: Show Problems" lists
them, and picking one opens its file.

## Keybindings and controls

A **control** is what the picker does to itself, as against what a row
does to the world: the `quickOpen.*` commands, `quickOpen.hide` closing
every level at once where escape and `quickOpen.back` leave one. Keys reach
them, and any other command, through keybindings shaped like VS Code's
`keybindings.json`.

The kernel binds no chord of its own (`M.keybindings` starts empty).
`defaultKeybindings.jsonc` ships the entry chord, the pickers' chords and
`cmd+k`, which every launcher has; moving and opening (`cmd+e`/`cmd+d`,
`tab`, `cmd+w`) are a person's preference, since arrows, return and escape
work unbound. A
profile's entries are appended, not replacing. A command starting with `-`
removes the entries before it for that command -- only that `key` when it
names one -- which is how `raycast` drops the picker chords and keeps
`cmd+k`. `M.effectiveKeybindings()` is the list after removals, and what
`setup()` binds. A keybinding that is a problem is not bound.

Keys resolve as VS Code's do. `setup()` binds each chord once, however
many entries share it (`M.chordId`); a press (`M.pressKeybinding`) walks
that chord's entries newest first, so a profile's beats a default, and runs
the first whose `when` holds and whose command's `enablement` holds
(`M.resolveKeybinding`). So one key can mean different things per picker
or row. With `"logLevel": "debug"` each press writes one line saying so --
VS Code's keyboard shortcuts troubleshooting: the chord, the command that
ran or "nothing", and each entry on the chord before it, newest first, with
its file and why it did not run (`when is false: …`, `not enabled: …`, `not
global, and the layer is closed`, `not bound: a problem`). Below debug
nothing is formatted. Two entries on one key in one file with the same `when` are a
problem, since the earlier can never run; a later file's entry on an
earlier file's key is an override, not a collision. A key the search field
needs to edit text -- typed characters, space, the delete keys, left,
right, home and end, `cmd+a/c/v/x/z` (`M.editsText`) -- is a problem and
not bound, since the modal takes a key before the field sees it; tab,
arrows up and down and the ctrl chords stay free. `"repeat": true` runs
the command again while the key is held (the hotkey's repeat function);
the moves repeat unless their entry says `false`. `hyper` in a chord is
cmd+alt+ctrl+shift, spelled out by `M.chord`, since hs.hotkey has no such
modifier.

**Global keys.** `"global": true` binds the key with `hs.hotkey` in every
app, in `start()` and given back in `stop()`, rather than in the modal; the
rest work only while the layer is open. The entry chord is one: `{ "key":
"alt+space", "command": "quickOpen", "global": true }` -- Raycast's default
chord; VS Code's Quick
Open with no args opening the default picker, and from a closed layer
entering through the modal so the layer's own keys are live. Setup reports
a problem when no global `quickOpen` is left, and a global key macOS holds
is a problem at start. A global press walks only the global entries on its
key; while the layer is open, the modal's key on a shared chord shadows it
(hs.hotkey enables the later key over the earlier) and walks every entry.
Closed, the context is made only when an entry has a `when` or its command
an `enablement`, and the command runs in it -- a view it opens too
(`session.outsideContext`) -- so entering captures once. A global entry on a
text-editing key is a problem, and so is one after a non-global entry on its
key with the same `when`; the reverse is not, since the global one still
runs while the layer is closed. `bindHotkeys({ enter = chord })`, SPOONS.md's
convention, appends a removal of each entry chord so far and a global
entry of its own after every file, and rebinds at once after start. A
`hotkeys` key in a settings file is a problem naming that keybinding.

A view has no key of its own: `quickOpen` opens a view with a query
already typed, so the prefix machinery applies and `"files "` lands in
Files, and `-quickOpen` removes such an entry. `M.runKeybinding(entry)`
runs one entry, for the harness as for `setup()`; nothing else in the
kernel chooses a key. `defaultView` says which picker entering opens, so
the kernel holds no view name of its own.

**Writing a keybinding** is VS Code's keyboard shortcuts editor's, and the
keybindings extension's own: into the active profile's own keybindings.json,
in its text (`cl.removeJSONCElement` and `cl.appendJSONCElement`, the list
counterparts of `editJSONC`), read from disk at the moment of writing and
refused with an alert while it does not parse. `M.keybindingOrigin(entry)`
says where an entry came from -- `default`, `user` (that file), `profile` (a
shipped profile's) or `bindHotkeys` -- and is a copy's `source`, so a copy
from `getKeybindings` is all a write needs. The extension's
`removeKeybinding(entry)` deletes the person's own element and takes out
any other by appending `{ "key": …, "command": "-<command>" }`; init.lua's
cannot be. `changeKeybinding(entry, key)` is that removal, then the same
entry on the new key after it; a key that does not read, or that the search
field needs (`cl.editsText`), is refused. `cl.keybindingsWritten()`
(`M.keybindingsWritten`) then reads every
keybindings file again and binds the modal's and the global keys again --
the modal's enabled at once while the layer is open -- forgetting what those
files were a problem for. Reading remembers what each file says, so the
reload watching the profile's folder takes the write for no change.
`M.chordText(flags, key)` writes a pressed chord in VS Code's modifier
order, `hyper` for all four, fn left out.

**The Keyboard Shortcuts picker** is `keybindings `, declared in
`defaults.jsonc` on the `keybindings` menu, which `extensions/keybindings.lua`
feeds from `cl.getKeybindings()`: a row per effective keybinding -- its
command's title with category (the id when nothing registered it), key,
source and `when` -- which runs the command when picked, its subject `{ kind =
"keybinding", key, command, when, source, entry, view }`, `entry` the copy
handed out and its source part of the subject's id, so the same chord in two
files is two rows. Switched off, the picker has no rows and its `empty` says
how to switch it back on. On cmd+k the same extension offers VS Code's
Remove Keybinding (back to the list, drawn again) and Change Keybinding….
Change closes the layer first, since the modal takes a bound chord before an
event tap sees it, then takes one chord from an `hs.eventtap` key-down tap
held through `watch` -- escape, or `M.captureSeconds` unanswered, ends it --
writes it a turn later, as a tap's callback must not keep macOS waiting, and
opens the list again. "Preferences: Open Keyboard Shortcuts" is workbench's.

No overlay of chord hints: it was removed as noise. `?` lists every picker
and how to reach it, and a command's row shows its chord.

Escape is the exception, deliberately: `hs.chooser` reports its own
dismissal, so escape always steps back and cannot be rebound. Binding it
as well is how it once closed the whole layer instead of one level.

## Commands

The registry holds verbs with a stable id, as VS Code's does. Registering
an id again replaces it; `menus = {}` is no row, which is what controls and
`quickOpen` are. An extension's commands are registered at setup, never at
load; an id outside its namespace is a problem and skipped. A command row
comes after the extensions' items and carries the subject `{ kind =
"command", id }`, which frecency keys on, so a new title keeps its history.

`M.executeCommand(id, args, ctx)` runs one straight away when `args`
answers every input, otherwise through the argument views, entering the
layer first if closed. It returns `true` and what `run` returned, or
`false` for no such command. A `run` that throws is one alert, "Could not
run ...", however it was reached. Without `ctx` it uses the open layer's,
building one only when the layer is closed. It ignores `when` and
`enablement`, as VS Code's does.

A command says what the picker does once it has run, as data: `after =
"close"` (when absent, VS Code's quick pick), `"keepOpen"` -- redrawn where
it was picked, in the context it had, the argument prompts above that level
gone -- or `"back"`, a level up from there, closing from the top. It holds
picked, run by id while the layer is open, and after answers. A row's own
`keepOpen` is the same for a row that runs Lua. A pick closes the picker it
was made in -- `hs.chooser` hides itself before it reports, and the popup's
menu goes with the click -- so the kernel draws that level again, keeping
what was typed, the prefix it was reached by and the row picked. A pick that
changes nothing puts the same rows back: a row marked unavailable, the busy
row of a search still running, an answer refused by `pattern` or `validate`. A picked row is copied
before answers are written into it, so a picker left open never offers a
row already answered.

A destructive verb names what it acts on: `targetName`, a template over
the context and the answers -- `${input:window.app}` reads a field of a
subject -- or a function of them, counting what a `preferCurrent` input would
take, reads `Window: Close -- Notes`, and nothing while it fills empty.
`confirm`, filled the same way, asks yes or no once every input is answered,
also run by id; a function returning nil runs without asking, which is how
`git.confirmPush` and `apps.confirmQuit` switch it off. No steps back, as
escape does.

**Running one again** (`rerun.lua`, through its `picked` hook): every
command row picked is kept with the arguments it ran with, latest first, the
same command with the same arguments once, twenty at most, in memory only --
an argument may be a window or an app object nothing outside the layer can
keep, so a reload empties it. The picker's own controls (`quickOpen*`) and
rerun's commands are not kept. "Rerun last command" runs the latest again;
"Rerun a recent command…" lists them, the arguments as the second line.

Dynamic rows -- menu items, apps, tabs, files -- stay plain rows with no
id, as VS Code's quick pick items do, and reach the registry through a
parameterised command: a menu row runs `appmenus.select` with `{ app, path
}`, keeping its `menu` subject and history, and a key bound to that command
with args selects one item.

A command row reads `Category: Title`, and the category is matched, so
"git" finds every Git command. Its subtitle is the extension's display
name, then its first chord in the effective keybindings, so a row is where
a shortcut is learned and a rebind shows at once. The chords are mapped by
command once per keybindings list (`M.firstChords`), not looked up per row. `recentlyUsed = n`
puts the n rows picked most lately first, the latest first -- VS Code's
MRU, by when rather than how often, as the rankers in use say
(`lastUsed`) -- marked "Recently used" on copies. Typing keeps them first
among what matched, after the rows made from the text.

**Sections** open a view, with nothing typed, on a few rows from each
source, then everything else ranked. A section's rows keep the order the
extension gave -- for `recent`, recency, which ranking would reorder by
pick count -- and its first row carries the title in its subtitle:
`hs.chooser` has no header rows, and a fake one would be selectable.
Gather tags every row with `source`, which a section selects on. A section
naming a `view` takes that view's opening rows, ranked, with its own
sections applied. A row shown in a section is not repeated below, matched
by command id or subject; `exclude` applies before the limit. Typing drops
the sections but not what they showed: those rows stay searchable -- a
`view` section's rows, another picker's, included -- and first among what
matches, behind a typed alias. Worked out when the sections are
(`rememberSections`), never per keystroke.

The shipped pickers: **root** opens on the top four of context without the
window commands (in every context, and root rows already), five recent
projects, five recent windows -- so in a browser the tabs you were just on
lead; **context** on three recent tabs while a browser is in front;
**recent** on three each of projects, tabs, windows and apps -- the apps
extension gives `recent` the apps you used, never its catalogue. Why these
pickers ship and no others is in design.md, "Which pickers ship".

- **Menus with their own `when`**, as VS Code's `contributes.menus`.
- **`enablement`** keeps the command a row, marked "Unavailable", faded
  by the chooser and disabled by the popup, refused when picked with the
  layer left open; a row's `enabled = false` is the same. `when` hides;
  `enablement` greys.
- **Separators** label the row after them, in the subtitle. Ranking moves
  positions, so it drops separators; sections are how a ranked picker
  groups, and emit separators after ranking.
- **`setContext`** keys go on every context built afterwards; a capture
  still wins over them.
- **Icons.** `$(name)` on a command or row, or leading a label, is VS
  Code's ThemeIcon syntax; modifiers like `~spin` are ignored. The `$(…)`
  always leaves the label; the image comes from the extension registered
  as theme icon provider. `codicons.lua` draws the codicon font (`brew
  install --cask font-codicon`), one cached image per name, from the table
  in `extensions/codicons/` (the loader reads only top-level `*.lua`).
  Without the font nothing is drawn, and installing it needs no reload.

### Commands that take a thing

An input takes a thing when its picker names a `when` over a row: `viewItem`
is the row's subject kind, as VS Code names a tree item's contextValue, and
the subject's fields and the context are readable too. One declaration,
two ways in: picked from search, the command lists every row from the
picker's `menus` the clause holds for, plus the picker's `options` such as a
"Choose…" dialog, and the answer is the row's subject; on cmd+k, every row
the clause holds for offers the command with that row given -- VS Code's
`view/item/context` menu, generated rather than written. A
`view/item/context` entry in `menus` narrows it with a `when` over the same
row and is in no picker unless the command also names one.

Asked from search, such a question gathers only what could answer it. An
extension may declare `viewItems`, every subject kind its rows carry (windows
`window`, apps `app`, the browser `url`, app menus `menu`, System Settings
`systemsettings`); a question whose clause names its kinds plainly --
alternatives each requiring `viewItem == '<kind>'` (`M.acceptedViewItems`) --
does not gather one declaring none of them, nor the command rows, which no
such clause takes. A clause it cannot be sure of -- a negation, parentheses,
an alternative naming no kind -- gathers everything, and so does an extension
declaring nothing. "Search Text in…" spent 104 of its 147 ms gathering
windows and apps it then threw away, before this.

Which verbs are rows too: a verb that repeats what picking the row already
does -- Launch or focus on an app, Open in browser on a bookmark, Toggle --
has the `view/item/context` entry alone. Any other is also a palette row
that asks for its thing, preferring what is in front, and in `cmd+.` where
that is the point: App: Quit and Hide take the app you were in
(`frontmostAppID`, never Hammerspoon) and ask among running apps
(`appRunning`, an item context key reading the running apps once per
context); Reveal in Finder asks for an app with a path; Browser: Copy URL
takes the page in front (`url`) and asks from `recent` otherwise; Go to tab
and Open in new tab ask for a tab. A question whose `menus` is `recent` alone
lists what `recent` would -- every running browser's tabs -- from whichever
picker it was asked.

Run by id -- a chord, a call -- an input's `current(ctx)` answers with
what is in front instead of asking; with `preferCurrent`, picking the row
does too, asking only when nothing is in front, and cmd+k on a row is how
to choose instead. A clause may ask for a key the row does not carry,
worked out once per row when asked (`itemContextKey`).

A prompt of several says where it stands, `Clone into (2/2)`, counted at the
first question, so what was given or taken from what is in front is no step.
An input's `pattern` (a Lua pattern, as a setting's) and `validate(value,
ctx, args)` refuse an answer: the reason is the typed row's second line, and
picking it alerts the reason and keeps the prompt open. Typed text that will
not do is not taken as a text command's answer, so picking asks.

- **Windows:** all but Focus prefer the window you were in -- "Window:
  Left half" plus enter moves it, cmd+k lists windows -- and are in `cmd+.`
  while there is one. Focus always asks, since focusing the window you
  were in does nothing. The moves -- layouts, other screens, full screen --
  go to `windows.provider`: `hs.window` by default, or Raycast's deeplinks,
  Rectangle's URL scheme, `yabai -m window` or `aerospace`, each a table in
  `M.providers` from a move's name to the tool's own action. A move the tool
  has no action for is no command, and a tool not installed at start is a
  problem and offers none; nothing is done another way. Focus, close,
  minimise and the list itself stay `hs.window`'s. The list is read as a
  picker lists windows, never at start and never watched: `windows.source`
  names `all` -- every window on screen, whatever its app, and every window of
  the apps in the Dock (`kind() == 1`), minimised or on another Space; never
  `hs.window.allWindows()`, which also asks every background service, and
  Karabiner's core service answers it only after its 1.5 s accessibility
  timeout while a picker is on screen -- `orderedWindows()` (the default) or
  `visibleWindows()`, and `windows.sourceByPicker`
  another per picker by `activeView` (`{ "root": "ordered" }`; a value not a
  source is a problem at setup). `all` and `visible` are sorted front to back
  by `hs.window._orderedwinids()`, private to Hammerspoon and so pcalled, a
  window not in it (minimised, another Space) after the rest; `ordered` keeps
  its own order. Each source is read once per open -- kept until a turn later,
  since every section gathers through a context of its own -- and the window
  objects of the last listing are what focus and close act on. An open shows
  the list the last one read, and reads it again a turn later, once the picker
  is on screen, redrawing only if a window came, went or was renamed: a
  listing waits on every app, and an app woken from App Nap -- Script Editor,
  Mail -- held opens for up to a second, where every app answers in a few
  milliseconds once awake. The first list is read two seconds after start. `windows.reuseLastList: false`
  reads the windows as an open opens, as before.
  The order is z-order, not focus history: nothing watches focus.
- **Paths** (`files.lua`): Open in terminal, Open in editor, Reveal in
  Finder, Copy path, on a file, folder or project, preferring Finder's
  selection. No other extension writes its own copy; the harness counts.
  With several items selected in Finder, the subject taken from it -- and the
  selection row in `cmd+.`, reading "3 selected" -- carries them all as
  `paths`: Copy path copies one per line, Reveal in Finder and Open with…
  are one `open` of them all (`system.open`'s `target` may be a list), Open
  in editor opens each, and Open in terminal opens the first one's folder.
- **Git:** the repository commands take a project or folder that is a
  `gitRepository`. Pull, Push and Checkout… run `git` in the terminal, in the
  repository (`terminalCommand`), so a conflict or a credential prompt is seen
  and answered; Fetch, Stash and Pop latest stash run in a task
  (`repositoryCommand`), showing the last line git printed. VS Code's other
  Git commands are there too, in the palette alone -- the five above are the
  ones reached for, and fifteen more would fill a list you open on: Pull
  (rebase), Sync (`git pull --rebase && git push`, one line so the shell
  reads the `&&`), Publish branch, Fetch (prune), Fetch from all remotes,
  Stash (include untracked), Merge branch…, Rebase branch…, Create branch…,
  Rename branch…, Delete branch…, Pop stash…, Apply stash…, Drop stash… and
  Undo last commit (`reset --soft HEAD~1`, so nothing written is lost). A
  branch is chosen from git's own list (`searchBranches`), a stash from
  `git stash list --format=%gd\t%gs`, and a typed branch name must be one
  git takes (`^[%w%._/%-]+$`). Delete branch and Drop stash name what they
  act on and ask first, unless `git.confirmDestructive` is off. Checkout's branches come from `git branch
  --list --ignore-case '*typed*'` in a task per keystroke, the older ended,
  what was typed offered as a name too (`alwaysShow`). Init takes `!gitRepository` and asks, the thing in
  front rarely being a folder. Clone asks for the repository from your own, in
  a search picker:
  `gh repo list`, read the first time the prompt opens (the busy row covers
  that read) and kept with `cached` for `M.OWN_REPOS_SECONDS` (300), asked
  again in the background after. They are narrowed by the matcher as you type,
  and GitHub's `gh search repos <text>` follows them as `alwaysShow` rows,
  gh having matched those itself, one already yours not repeated; the busy
  row stays after your matches until GitHub answers. A newer query ends the
  older search, and a redraw for the same query -- your list landing -- keeps
  the search running rather than starting it again. Without gh, what was typed
  is the URL, `alwaysShow`. It runs `gh repo clone`, or `git clone`
  for a full URL gh does not take or without gh, into a folder of
  `git.cloneRoots` or one chosen; owner/name is never made into a URL here.
  Cloning into VS Code opens `vscode://vscode.git/clone`, which VS Code's
  own Git extension answers.
- **Selection** (`selection.lua`): the app in front's selected text is the
  context's `selection` and a `selection` subject, with Look Up (`dict://`
  through `system.open`), Search the web (`browser.searchWeb` by id) and
  Copy. It is read with `hs.axuielement` from the focused element only,
  each element given a `M.timeoutSeconds` (0.1) messaging timeout, and not
  at all while `secureInput` is set, from a secure text field, from
  Hammerspoon itself, or past `M.maxLength` (1000). No cmd+c fallback: it
  would overwrite the clipboard, so an app without `AXSelectedText`
  (Electron, browsers) has no selection. Its cost is `capture.selection`.
  Instant Send is `selection.showActions` ("Selection: Show actions"): bound
  to a global key, it opens the actions panel -- the declared picker of kind
  `item`, `actions` as shipped -- on the selected text, skipping the picker
  in between; nothing selected, it says so. No chord ships for it.
- **Typed URLs** (`url.lua`): a query that reads as an address (a scheme's
  `://`, `www.`, or a host with a path) is a row opening it, carrying a
  `url` subject, so cmd+k offers the link verbs other extensions own --
  Open with…, Copy URL, Open in browser, Clone repository. A cheap gate
  runs first, since it is every keystroke's (`query.url`).
- **SSH hosts** (`ssh.lua`): each concrete `Host` in `~/.ssh/config` is a
  root row reading "SSH: <name>", as a command row reads "Category: Title",
  an `sshHost` subject, matched by "ssh" and by the address it stands for --
  both keywords, since a subtitle is never matched. The file is read at start and when a
  change in `~/.ssh` names it and it was written since, never per open;
  patterns, `Match` blocks and names starting with `-` are left out, the
  first `HostName` and `User` count, and `Include` is not followed. "SSH:
  Connect in terminal" runs `ssh <host>` through `terminal.run` (so
  Terminal.app needs Automation) and also takes a remote project's host;
  "SSH: Connect in editor" runs `editor.open` with `remote =
  "ssh-remote+<host>"`, which VS Code's Remote - SSH answers.
- **The VS Code bridge** (`vscodebridge.lua`): switching it on
  (`vscodebridge.enabled`, shipped off) says the VS Code side is installed,
  so its four commands are always rows, looking for nothing on an open: Find
  in files and Go to file (text commands), Run task… and Run command…. Each
  runs `vscodebridge.run`, which fills its args' templates and opens
  `vscode://saemeon.command-layer?command=<id>&args0=<JSON>&args1=<JSON>` --
  each argument's JSON percent-encoded twice, as VS Code decodes the query
  once -- or
  `workbench.action.tasks.runTask` with the label as `args0` for Run task, through
  `system.open`, whose failing exit is its "Could not open" alert. Only as it runs does it look, and send nothing but an alert
  when a link would reach nothing: VS Code not installed (by bundle id), or
  the extension in neither `~/.vscode/extensions/extensions.json` (an entry
  whose `identifier.id` is `saemeon.command-layer`, as "Developer: Install
  Extension from Location…" writes it without copying a folder) nor a
  `saemeon.command-layer*` folder there. A list that is not JSON names nothing
  and is no problem; the harness points `extensionsPath` at fixtures. The extension checks nothing --
  any command a link names runs, after VS Code's own prompt; nothing else in the launcher needs it, and the
  harness checks no other extension names it. Its install is one symlink,
  described in that extension's own README; it is not in this repository.

## When clauses

`when` is VS Code's syntax for "only in this situation", on a command, a
row, a `view/item/context` entry or a keybinding:

    when = "frontmostApp == 'Brave Browser' && url =~ /youtube%.com%/watch/"

`==`, `!=`, `=~ /pattern/`, `!`, `&&`, `||`, parentheses, and a bare key
meaning "is set" (not nil, false or ""); `true`/`false` as a bare word
compares whether a key is set. `a in b` asks whether key a's value is an
element, or a key, of what key b holds (`not in` the opposite); `<`, `<=`,
`>`, `>=` compare numbers, and a non-number compares false. `=~` takes a
Lua pattern: `%.` for a dot, `%/` for a slash inside it.

A key is a context field, so what can be asked is whatever extensions
capture (`frontmostApp`, `clipboard`, `finderSelection`, `focusedWindow`,
`screenCount`, `url`, `pageTitle`, `secureInput`, `selection`, `hostname`,
`online`); one no extension captured is unset, so
a clause about something not installed is false, not an error. `hostname`
(`hs.host.localizedName`, the name in Sharing settings) is read once, a turn
after start, since NSHost may wait on the network; `online` is kept by an
`hs.network.reachability` watcher -- reachable with no connection to bring
up first -- so no open asks the network, and `!online` holds while offline. The kernel
adds `activeView`, the picker whose rows are being built or searched, so a
row or an extension can differ by picker.

`config.<ext>.<key>` is a setting, as VS Code's `config.` keys are
(`config.browser.tabOrder == 'recent'`), read through `M.setting`. It is
answered once per context -- on the context a scoped copy reads through --
so a gather does not read settings per row; `settings.lua` registers the
namespace on `when.lua` (`M.registerWhenNamespace`), as it registers
`${config:…}` on templates.

Each clause is parsed once and cached by text. One that does not parse is
logged once and is false: showing a command in the situation it was
written to avoid is the worse mistake. A keybinding's clause is checked
when the chord is pressed, against the picker on screen, with three keys
only a press knows, worked out once per press and never per keystroke:
`activeView`, `hasQuery` (text in the field after any prefix, so `cmd+o`'s
bare `>` is none) and `viewItem`, the highlighted row's subject kind.

## Browser

**Sites** are commands that exist only while a page is in front, as data:

    { name = "YouTube", match = "youtube%.com/watch",
      commands = { { title = "Full screen", keys = "f" },
                   { title = "Copy title",  js = "document.title" } } }

Each becomes `browser.site.<site>.<title>`, category the site's name, in
root, context and palette while the page in front matches (each menu's
`when = "url =~ /<match>/"`, a slash escaped). It is about a page, not about
whichever page is in front, so it takes a tab: on a tab row whose URL
matches it is a cmd+k verb for that tab (`value =~ /<match>/`, the row's own
URL -- `url` would be the page in front), and run from a picker it takes the
page in front and asks nothing (`preferCurrent`). The condition is on each
menu and on the tab, never on the command, whose `when` would hide it from a
tab row while another page is in front. Given a tab that is not in front,
`browser.keys` and `browser.js` bring it forward first through the same
Apple Events a tab row uses, and act once it is; a tab gone since says so. `keys` bring the browser forward and press the site's own
shortcut a tenth of a second later, once the picker is gone. `js` runs
AppleScript in its own process -- `execute ... javascript` for Chromium,
`do JavaScript` for Safari -- which needs "Allow JavaScript from Apple
Events" and says where when refused. Keys are preferred: no permission,
and what the site itself supports; while Secure Input is on they are not
pressed, and `secureinput`'s `warn` says so. Being the page's own shortcuts,
they reach whatever in the page takes keys first: a keyboard extension such
as Vimium swallows YouTube's, and the command does nothing though the key
was sent. The ways out are the person's: exclude the site in that
extension's options, or write the command with `js` instead.

Sites are data, never Lua, which would run whatever a file holds: the
shipped ones are `extensions/browser/sites.jsonc`, a person's are `*.json`
or `*.jsonc` files in `~/.hammerspoon/commandlayer/sites/`, each one site or a
list, read with `readJSONC`. Each is checked as it is read -- a field a site
or command cannot have, a name or title without a letter or digit, a `match`
that is not a Lua pattern, `commands` not a list, a command with neither or
both of `keys` and `js`, `keys` that do not read as a chord -- each a
problem under `extension browser` naming the file, the site and the command.
A mistake leaves out only the site or command it is in; an unknown field,
neither. A `.lua` file there is a problem, and not run.

A tab row finds its tab by URL when picked -- tabs move and close between
list and pick -- and selects it through Apple Events (`M.switchScript`, `set
active tab index` for Chromium and `set current tab` for Safari) in
osascript, then brings its window forward. A tab closed since, a browser
that refuses Automation (-1743, one alert saying where to allow it) or a row
from something that is not a browser opens the URL instead. That is the only
automation the browser does beyond a site's `js`: nothing is typed into a
page and no form is filled.

A running Chromium browser's tabs come from its session file,
`<profile>/Sessions/Session_*`, read by `extensions/browser/session.lua` in
Chromium's own record layout, unknown records skipped. The header's format
version is checked first: 1 and 3 (the same records, with a marker) are
read; any other -- 2 and 4 are encrypted -- is not guessed at, is one problem
naming the browser and the version, and leaves the browser asked as one
without a file is. It is read at start,
when its Sessions folder changes (an `hs.pathwatcher`, left a second for a
burst of writes to settle) and with history, as a net for a folder made
since -- each time parsed only where the newest file was written since. A
picker lists the tabs last read and never touches the file. Bookmarks are
decoded again only when a Bookmarks file was written since, and bookmark
and history rows are made once per read, only their `ctx` set per open. No Automation permission, and recency is
Chromium's own: `tabOrder` "recent" sorts by the file's last-active times,
a few seconds behind; the launcher keeps no recency of its own. A browser
is judged running by bundle id,
never by name, and a stopped one's file is ignored, since its tabs are
gone. The harness points the reader at no folder, so the machine's own
tabs never reach a check.

A browser without a session file (Safari) is asked through AppleScript,
front tab first because it is current to the moment, and only the browser
in front, only on becoming frontmost and on being left, since the tab then
is the one you were on. Others keep their last answer until they quit;
their tabs are in the browser's own order. Asking a browser Hammerspoon
may not control brings up macOS's permission prompt, which takes focus and
closes the launcher. An unchanged answer does not redraw the picker, which
would lose its selection.

Alt-tab order: with a browser in front, the tab you are on goes last among
its recent tabs, so the first is the one before; windows, front to back,
likewise list the window you were in last. The root lists the front browser's tabs, `recent`
every running browser's (by `activeView`); context gets
tabs, bookmarks and history only while a browser is in front.

**Brave's own command palette** (`browser.bravePalette`, "Brave: Command
palette"), offered in `cmd+.` and the palette while Brave is in front: Brave
brought forward and `browser.bravePaletteKeys` (`ctrl+space`) pressed a tenth
of a second later, warned rather than pressed under Secure Input. Its settings,
Shields and tab groups are Brave's to list.

## Projects

VS Code's recent projects are its Open Recent list,
`lastKnownMenubarData` in `User/globalStorage/storage.json`, which VS Code
rewrites whenever a folder opens. It is read at start and when a change in
its folder names storage.json and the file was written since; a picker
reads the list kept, never the file.
`workspaceStorage/*/workspace.json` is written once, at first open, so it
orders by first open; it remains the fallback. The editor's list is merged
each time rather than cached with the scan. After it: zoxide's git
folders in its order, the older `~/.z` database, then `find` for `.git`
under the project roots.

A recent folder on an SSH host (`vscode-remote://ssh-remote+<host>`) keeps
its authority, and is a row of its own in VS Code's order -- a
`remoteProject` subject with its `host`, "Project on <host> -- <path>" --
opening through `editor.open` with `remote`, whatever `projects.opensWith`
says, since that is given a local path. Remote - SSH writes a host holding
a user as hex-encoded JSON; `vscode.remoteHost` reads it as `user@host`.
The same path on two hosts is two projects. The `projects` export stays
local, and `projects.remoteProjects` off leaves the rows out.

## Commands that take text

An input with `fromQuery`, its picker `typed`, is answered by what was
typed, so a search runs straight from the field. `${query}` in the title
shows the text, or `…` while there is none. With text the input arrives
answered -- encoded as collecting it would have been -- and picking runs at
once; without, it asks. An input is VS Code's `tasks.json` input without
its `type`: `picker` says how it is asked, `command` is tasks.json's command
input, and `default` and the template variables keep its names.

A question is a picker of its own, which the input names: `{ options, menus,
when, kind, search, typed }` and nothing else, pushed as a spec rather than a
name (`M.pickerOfInput` adds the input's default and prompt, `M.push(spec, {
placeholder, args, answering })`) -- its `options`; the rows its `when` holds
for from its `menus`, then its options; `kind = "search"` with an inline
`search`; or `typed`. An input with neither `picker` nor `command`, or both,
is a problem, and so is one still writing `type`, `options`, `when`, `from`
or `search` on itself, each saying where it went; the harness checks no
extension or check writes an old type. Picking there answers the command
that asked -- the row's `value`,
else its subject -- and never runs the row, whatever command or `keepOpen` it
carries; typing in a question switches on no prefix. The confirm prompt is
such a picker of Yes and No.
`${command:id}` is what that command returns; one asking for itself gets
nothing.

Three ways in, and no default command bound to a chord:

- **`?` with text**: the `help` picker has `"textCommands": "first"` --
  while text is typed, every text command with the text filled in (leading
  spaces trimmed), ranked with no query, so by use, then its own rows
  matching the text; bare `?` is its own rows alone, the pickers that
  `extensions/help.lua` lists. With help switched off, `? text` still offers
  the text commands.
- **A command's own `prefix`** registers a picker holding that command,
  named by its id and declared `"command": "<id>"` -- its one row, what is
  typed filled in -- so aliases, `?` and the prefix machinery treat it as
  any picker. A picker in settings may hold a text command the same way.
- **Fallbacks:** in a picker with `"textCommands": "fallback"` -- the root,
  as shipped -- nothing matching offers the text commands. Only there: in
  `files ` or the palette, nothing matching means nothing matching. Both
  are `defaultQuery` in `core/stack.lua`; a picker's old `fallbacks` is a
  problem naming `textCommands`.

A quicklink with `${query}` in its URL is a text command too; one without
is a bookmark row. `quicklinks.links` is read once, at setup, for both, so
the rows never list links the commands do not have.

## Prefixes, menus and views

VS Code's Quick Open is one widget whose mode is chosen by what the text
starts with, and Cmd+Shift+P only opens it with `>` typed. A view's
`prefix` is the same:

- Typing a view's prefix opens that view over the current one, the prefix
  left in the field; what follows is searched. The longest prefix wins. A
  symbol switches at once (`>`); a word carries its space (`files `), so
  `files` alone still searches.
- Editing the prefix away goes back to the view underneath with the text
  as it now stands, which may open another prefix's view; editing into
  another prefix of the same view keeps the view.
- A chord bound to a view with a prefix opens the entry picker with the
  prefix typed, so `cmd+o` is the root with `>`, and deleting it leaves
  you searching everything. From an open picker, what was being searched
  for comes along after the new prefix: "pull" then `cmd+o` is `>pull`, and
  `cmd+p` from there `files pull`. Not out of a question, the cmd+k panel
  or a text command's picker, whose text is an answer or a verb.
- Only declared pickers switch; in the cmd+k panel and argument prompts
  `>` is text. A view reached by its prefix always watches for its
  deletion.
- A profile's `prefixes` add aliases and never replace a view's own, so a
  shipped prefix works wherever an alias is set.
- Shipped prefixes are whole words or VS Code's symbols, because a short
  one like `w ` would catch a search for "w lan". Short ones are a user's
  to choose.
- A view reached by prefix with nothing to show says so once and leaves
  you where you were. With nothing typed after the prefix (`cmd+.` types
  `context `) the field is cleared, so the view underneath opens on its
  own rows rather than searching for the word.
- `?` is built from the declarations: `extensions/help.lua` reads
  `cl.getViews()` and `cl.getKeybindings()` and lists every picker with a
  chord, prefix or parent and how to reach it, a title-less one by its
  placeholder filled from the context -- and, with text, the text commands
  first, so `?` doubles as choosing which engine to search with.
- With `pickerRows` (the root) every picker with a prefix is also a row,
  typing its prefix when picked; a text command's own prefix view is left
  out, the command being a row already. Rank 0.05, so they come up when
  matched.

A view with a `parent` is a row there reading `Title ▸`, and a row with
`submenu` does the same: picking opens the view *over* the current one,
escape comes back, and it is recorded like a pick, so a menu used often
rises. Its rows are built when that level opens, never before, so a tree
is declarations all the way down. The breadcrumb reads `Menu ▸ Recent`.

**A picker is data.** A picker is what VS Code calls a quick access
provider, declared rather than written: how it is reached (a prefix, a
chord, a parent), where its rows come from (menus, or one text command) and
a few flags; no field of it is code. Every picker but the
root is a mode of it, reached by prefix or by a chord that types it, so
there is one model, not prefix modes beside pickers of their own.

A picker may be given a subject, and picking hands a subject back: one
symmetric rule, with no field saying what a picker is about.
`M.push(name, { subject, label })` -- and `quickOpen` with `args.subject` --
puts it in that level's context as `subject`, the row's label as
`subjectLabel`, so its rows are built with it and `${subject:label}` or
`${subject:path}` fills its placeholder and empty text; a command's question
hands the picked row's subject back as its answer. The cmd+k panel is a
declared picker given the highlighted row's subject: `actions` in
defaults.jsonc, `"kind": "item"` (the verbs `itemActions` offers on the
subject; given nothing, nothing), `compact`, and `answers = false` so typing
there neither calculates nor switches on a keyword; a profile's `actionsView`
points cmd+k elsewhere. A verb there reads as its title alone, without
the category a palette row carries, but the category is matched as a keyword,
so typing "git" on a repository keeps Pull and Fetch rather than emptying the
panel. A verb there carries the kind of
row it is offered on (`subject.viewItem`), and `rowKey` keys it with that,
so its order is learned per kind: "Reveal in Finder" picked on files does
not reorder the verbs on tabs, nor lift the command's own palette row.
History recorded before, keyed without a kind, stays with the palette row.
A row picked before offers "Remove from Recently Used" (workbench).

A pushed level keeps the context the layer was entered with; a fresh one
would find Hammerspoon in front. A chord *replaces* the stack: pickers
reached by chord are siblings, pickers reached from a row are children.

An extension's `left(ctx)` is called when a level its rows feed comes off
the stack -- escape, a prefix deleted, a command's `after`, a chord
replacing the stack, the layer closing -- never when a level opens over it,
so an extension feeding a live picker can own a timer. Those told are the
extensions on the menus the level's picker lists, `<ext>.menus` included
(`M.onOwnMenu`), with `activeView` in `ctx` naming the picker left; a level
with no menus -- cmd+k's verbs, a text command's own picker -- tells none.
One that throws is logged as an error naming it, and the rest still hear.

## User config

Everything personal lives in `~/.hammerspoon/commandlayer/` (`hs.configdir`'s;
`userDir` before `start()`),
found in `setup()`, never at load. Every folder the Spoon loads --
`extensions/`, `presenters/`, `matchers/`, `rankers/` -- is read from there
too, after the Spoon's, and a file named like a shipped one
replaces it, so a changed copy never runs beside the original. An extension
can also be handed over from init.lua, kept wherever Hammerspoon loads it:
`spoon.CommandLayer:addExtension("mediacontrol", require("media_control"))`
(`M.addExtension`, kept in `M.addedExtensions` across reloads). It is built
with the folders' at setup, replacing a file of the same name, which is then
never loaded; the name is the one given, a letter then letters, digits or
`_`, and a spec naming another, or a name it cannot be, is a problem. Given
after start, it reloads the layer. Its
`settings.json` and `keybindings.json` are the default profile's;
`"<ext>.enabled": false` drops an extension, and then anything requiring
it. `"<ext>.menus"` moves its rows and commands between pickers, as VS Code
leaves a contribution's placement to the extension and a person overrides it:
a menu's name to `true`, added though the extension does not declare it, or
`false`, taken out; a menu not named keeps the declaration, and a declared
menu's own `when` still decides (`M.onOwnMenu`, read once per gather). A
command with `menus = {}` is no row anywhere and never becomes one. A menu no
picker lists, or a value not true or false, is a problem; Default Settings
writes each extension's declared menus beside its switch. What needs a tool not everyone has -- raycast, maccy, github,
vscodebridge -- ships switched off in `defaults.jsonc`, so everything on by
default makes sense to have; `"maccy.enabled": true` switches one on. Default
Settings writes each switch once, in its extension's part, with the shipped
value.

Settings are read at the moment of asking, so a switch applies without a
reload; the browser does not ask for tabs at all while `tabs` is off. The
kernel's `M.setting` returns where a value came from -- `"settings.json"`,
`"profile"` (defaults or a shipped profile) or `"default"` (the
declaration); a plugin gets that through `inspectSetting`. A write refuses
while the file on disk does not parse.

`settings ` (declared in `defaults.jsonc`, its rows from
`extensions/settings.lua` through `cl.getSettingOwners()`) lists every
extension, on or off -- the settings extension too, so it can be switched off
from there; while it is off its rows are gone, the picker's `empty` says so,
and settings.json is the way back -- and every setting, marked "(default)"
when settings.json has not set it.
Picking flips it and the picker stays open, redrawn (`keepOpen`). An
`enum` steps to the next value, past the last back to the first. A row's
subject is `{ kind = "setting", id, name, key, modified }`, `modified` while
settings.json sets it -- VS Code's word -- and cmd+k on a modified row
offers "Reset Setting" (`workbench.action.resetSetting`), which removes the
key; like any cmd+k verb it closes the layer.
Switching an extension off applies on reload, since its hooks and watchers
are in use; it stays listed so it can be switched back on.

Recents and frecency stay in `hs.settings`: what the launcher records, not
what a person configures. The harness points every layer at a folder that
does not exist, so a real `~/.hammerspoon/commandlayer` cannot change a check.

## Matching and ordering

The kernel matches no text. A matcher's `match(items, query, callback)`
calls back with the rows it keeps, best first, and optionally a grade per
row -- `callback(rows, scores)`, `scores[i]` 0..1 for `rows[i]` -- or
returns `false` to decline (an empty query, a tool not installed).
`matchers` is the whole set in the order tried; the first to take a query
decides, one not named does not run, `[]` matches nothing, and when none
takes it every row stays. `fzf` declines without the binary; `substring`
needs nothing and answers when fzf cannot.

A row's `keywords` (a list of strings: a tab's URL, an app's other names
and bundle id) are matched beside its label, never its subtitle, cut at
160 characters. fzf is sent `index<TAB>label<TAB>keywords` with
`--nth=2..` and its answer mapped back by index. Both matchers grade what
they keep the same way: exact 1, prefix 0.85, word start 0.7, anywhere
0.5, fzf's letters in order 0.3, found only by keywords 0.15. fzf prints
no scores, so its grade is a Lua check of the label per kept row, term by
term, and its order decides within a grade. Each matcher lowers or builds
a row's text once per row table, in a weak table, since a view's rows stay
the same tables while you type.

Typing on searches only what the last query kept (`narrowed` in
`core/stack.lua`): whatever matches "pul" matched "pu", fuzzily or as a
substring, word by word. Deleting, a query holding fzf's `|` (which can
widen), or a list built again (a refresh) searches every row. No setting: the
rows are the same, only fewer are handed to the matcher.

A row's `alwaysShow` is VS Code's QuickPickItem field: no matcher drops it.
`rankItems` does not send it to a matcher or rank it either. Whoever marked
it placed it -- a status line such as grep's "No results", or another
source's own matches such as GitHub's in Clone -- so with text typed it
follows the ranked rows in the order given, whether or not it would have
matched. With nothing typed nothing is narrowed, and it ranks with the rest.

Rankers score a row 0..1 and are weighted into a sum, so a weight is the
whole of how much one counts and two weights are comparable. Matching is a
ranker like the others: `relevance` scores a graded row 0.8 by its grade
and 0.2 by its place in the matcher's order, halving by the tenth place --
so the 50th of 2000 matches no longer scores near 1 -- and a row from a
matcher that grades nothing by its place in the order alone;
With nothing typed it scores every row alike: nothing matched, and the order
a picker was given is not a judgement -- scoring by it froze cmd+k's verbs,
where the first scored 1 and the second 0 and no history could lift one.
`specificity` a row's `rank`, held within 0..1 (the harness asserts the
range, including for a rank declared above 1); `frecency` picks;
`alphabetical` the naive order. A ranker reads the list as a whole from its
context (`count`, `matched`, `position`, `quality` -- the matcher's grades,
by position -- and `alphabetical`); `alphabetical` is
sorted when first read, so at weight 0 nothing pays for it. The kernel tells every ranker in use of a
pick (`picked`), asks when a row was last picked (`lastUsed`, a time, 0 for
never), and tells them to forget a row's key (`forget`) or everything
(`reset`); one at weight 0 is not in use, records nothing and hears
nothing. Extensions reach the last three as `lastUsed`,
`removeRecentlyUsed` and `clearRecentlyUsed`, which workbench's "Remove
from Recently Used" and "Clear Command History"
(`workbench.action.clearCommandHistory`, confirmed first) run.

Frecency is zoxide's, copied: a run adds 1, scored x4 within the hour, x2
the day, x0.5 the week, x0.25 after -- each step a setting, as Albert has
them (`frecency.hourWeight`, `dayWeight`, `weekWeight`, `olderWeight`);
past `frecency.maxAge` all ranks scale to 90% of it and any below 1 is
forgotten. `relevance.exactMatchBoost` (0..1, 0 as shipped) is Albert's
exact-match boost: that share of relevance's score goes to a row whose label
is exactly what was typed, so an exact match can climb over a prefix match
the matcher put first. Counts from before runs had
times read as old runs.

`rank` is what makes cloning the repository you are looking at beat an
app whose name contains "clone". Ambient context verbs and site commands
are 1, the browser 0.86, recents 0.57, git and windows 0.43, tabs 0.34,
apps, shortcuts, tasks and Hammerspoon 0.29, GitHub 0.23, quicklinks, snippets, Maccy, VS Code and prefix rows 0.14, bookmarks 0.11,
history and Raycast 0.06, System Settings panes, menu items and zoxide 0.
Bookmarks and history are lowest because hundreds of them would fill the
root before anything is typed; the root opens on its sections instead.

Additive rather than tiered on purpose: tiers would mean a context verb
*always* beats an app, so typing an app's exact name would bury it. A
strong text match has to be able to win.

**Aliases are the one exception.** `"aliases": { "windows.leftHalf": "lh" }`
in settings (a string or a list, by command id) is a person naming a
command, as Raycast's aliases are: when the whole query is an alias,
ignoring case and surrounding spaces, that command's row goes first,
matched or not, ahead of the rankers' sum and of "Recently used" -- rankItems
tells its caller how many rows it put there. Only command rows, only where
the command is a row. An alias for no command, or one that is not text, is
a problem.

## Search pickers

`search` runs in a picker with `"kind": "search"`, which asks rather than narrowing a list: nothing
typed shows its menus' rows; once you type, those of them that match stay,
first -- recent files beside the files found -- but for `alwaysShow` rows,
which speak for the empty field. Fewer than `minQuery` characters ask
nothing; otherwise the hooks run once typing pauses for `debounce`, the
matching own rows and the busy row shown until a first answer, and a found
row that is the same thing as an own row is not repeated. A hook
answers through `done` and returns a function that stops it; the kernel
stops every running search when a newer query arrives, and merges and
ranks each answer with the earlier ones. File search is exactly that --
`files.lua` runs `mdfind` in its hook -- so the `files` picker is a
declaration with `"kind": "search"` and nothing more. Every
word typed must be in the name, and each tool does the AND itself: one
`kMDItemFSName == "*word*"cd` clause per word joined by `&&` (one word
stays `-name`), fd's `--and`, find's several `-iname`. mdfind finds nothing
rather than failing on a malformed predicate, so the harness checks its
exact text. Text search (the `grep` picker in `defaults.jsonc`, over `grep.lua`) is the same
shape: `rg --fixed-strings --smart-case --max-count 5 --max-columns 200` in
one place, from three characters, a hit opening in `editor.open` at its
line. The picker has no prefix: "Search Text in…" (`grep.searchIn`) is the
entry, taking a file, folder or project row -- cmd+k on one, Finder's
selection, or asked: `grep.roots`, Finder's folder, five of VS Code's local
folders, the rows, and Choose… (`hs.dialog`, files allowed) -- and opens
the picker given the place as its subject (`quickOpen` with `subject`), so it
is in that level's context alone and closing the layer ends it. A file
searches that file alone. The search never picks a place itself, and says
what it is doing in disabled rows: where it searches, "Choose a place",
"No results in <place>", or rg's first stderr line on an exit other than
0 or 1, also logged at warning. rg has no overall limit, so it runs under
zsh with `head` (`M.CAPPED`): the listing ends at `grep.maxResults`, the
TERM a newer query sends zsh is passed on to rg, and rg's exit comes back
unless a signal ended it, which is the cut. Such a row is `alwaysShow`, or
the matcher would drop it. Each icon
is an image made on the main thread, so one list of files loads at most
`files.iconRows`, and a file type's icon is shared and kept.

## Context from the world

The kernel knows nothing about the world and seeds no context field. The
frontmost app, the clipboard, `hostname` and `online` come from
`extensions/ambient.lua`, which
runs before `finder.lua` because that reads `frontmostApp`; a clipboard an
app marked concealed or transient (nspasteboard.org's types) is left out
of the context, so it never reaches a `when` or a template. Finder's
selection is read in a task, never on the main thread: the context starts
from the last answer, and a new one updates and redraws the open picker.
`finderSelection` is its first item and `finderSelectedFiles` every item, a
list, unset rather than empty when nothing is selected, and one path on a
file row. So a reader of `ctx` treats every field as possibly absent: a profile may
ship without the extension that captures it.

## Presenters

A presenter returns `{ create = function(opts) ... end }`. `opts` carries
`onPick(picker, item, reason)` -- `item` nil for a dismissal, `reason`
`"away"` when focus went to another app, which closes the layer instead
of stepping back -- `onQuery(picker, query)`, `width`/`rows` hints, and
`expand(item)`, the rows behind a `submenu` row without opening it, for a
presenter that draws a whole tree. `create` returns a picker:

    show(state)             open with state.placeholder, state.items, state.query
    setItems(items, query)  replace what is shown; query, typed after any
                            prefix, is for highlighting and may be ignored
    hide(closing)           hide it; closing is true when the layer is closing
                            rather than switching to another picker
    selected(), move(delta), accept()   optional
    select(i)               optional: highlight row i

A presenter shows exactly the rows it is given and filters none; matching
and ranking stay in the kernel. An unknown presenter name falls back to
the default with a log line.

The kernel keeps the highlight across a redraw: when the same query is drawn
again -- a refresh, rows landing late -- the row highlighted is found by
`rowKey` among the new rows and handed to `select`. Typing starts from the
top, and so does a highlight on the first row, so better rows arriving take
it.

While a searching picker searches a query nothing has been drawn for yet, the
kernel presents one row, `{ label = "Searching…", enabled = false }`: VS
Code's busy indicator, as a row because `hs.chooser` shows its placeholder
only while the field is empty, and a search always has text in it. The
chooser draws it faded; picking it does nothing, not even the "not available"
alert. Rows replace it as they land. No hook says when it has finished, so
`searchExtensions` passes `done(rows, first)` and returns how many hooks
started: once every one has answered with nothing, nothing is shown. The row
is drawn without ending the search trace, which still waits for answers, and
a refresh keeps the rows already drawn for the query while it asks again.

A question's search picker (`picker = { kind = "search", search =
function(query, ctx, args, callback) }`) is shown the same
way, through the same row (`M.busyRow`, `M.showBusy` in `core/stack.lua`):
until its callback answers for the query on screen, the busy row alone. An
answer for an older query is dropped before it is matched. What it answers
goes through `rankItems` against what was typed, so rows narrow as you type
and `alwaysShow` rows stay; with nothing typed it is shown as given.
`callback(rows, true)` says more is coming -- `busy`, as VS Code's QuickPick
has it -- and the busy row follows the rows. A refresh asks an argument
prompt's search again, so a `cached` answer landing redraws it. An input's
search therefore answers every row it has, whatever was typed, unless its
tool matches for it (git's branch pattern, `gh search`): Open with… answers
every app.

The kernel keeps these promises so no presenter has to: only the picker on
screen may report a pick or a dismissal, and the outgoing picker stops
being active before it is hidden, so a presenter that reports its own
hide, as `hs.chooser` does, cannot close the layer while switching. What a
presenter reports while being shown is dropped, and the kernel runs the
query itself once the picker is up: `hs.chooser` fires its query callback
inside `show()`, and switching pickers from there -- a chord typing a
prefix -- let the outgoing picker come back on top and dismiss the new
one. The harness has a presenter that does the same; otherwise it drives
the layer through a recording presenter, and asserts no `core/` file
mentions it.

Two ship, and the set is closed on purpose:

- `chooser` (`hs.chooser`, the default). With more than one display it
  opens on the main one, placed by hand since `hs.chooser` centres on the
  focused window's display. Fonts, row height and background are fixed by
  its layout file, but a row's text may be `hs.styledtext`: the matched
  part bold and tinted (the query as one run where it appears, else its
  characters in order), subtitles smaller, made once and cached. Only the
  first `chooser.styledRows` are styled, since each is an Objective-C
  object made again per keystroke. Hammerspoon's default
  `hs.chooser.globalCallback` focuses, on every hide, the window in front
  when that chooser opened, so switching pickers would hand focus to the app
  you were in between two of them. The chooser installs its own instead, kept
  on `hs.chooser._commandLayer` and made once so a reload does not wrap it:
  the layer's choosers remember the window in front as the first opens over
  another app (one opening while Hammerspoon is in front is a switch), and
  hand focus back once, in `hide(true)`, before a picked command runs, so
  what it focuses wins; a dismissal read as "away" forgets it, leaving focus
  where you clicked. Every other chooser is passed to the callback that was
  there before. The tenth-of-a-second waits before keys are pressed (paste,
  a site's keys, captures, Maccy, the web view) stay: they wait for macOS to
  finish an activation, which no callback shortens.
- `popup` (`hs.menubar:popupMenu`): no search field, menu type-select
  instead; views with a `parent` become real submenus through `expand`. It
  opens a turn after `show`, because `popupMenu` blocks and a pick made
  while it blocked would re-enter the kernel mid-switch.

**Pickers are the chooser or the popup, and nothing else.** No preview
pane, no webview picker. VS Code draws the same line: its quick pick is a
fixed widget extensions only feed, and a webview is something a command
*opens*. The presenter seam stays because it keeps the chooser's quirks in
one file, lets the harness drive the kernel with no `hs.chooser` behind
it, and carries the popup.
