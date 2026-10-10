# Command Layer

A launcher for macOS built on Hammerspoon. The repository root is the
Spoon itself. Design notes and rationale live in [design.md](design.md) —
read that before changing the architecture.

This file is the contract: the boundaries, how to verify, the shape and the
extension rules. How each part behaves in detail is in
[docs/behaviour.md](docs/behaviour.md); read its section before changing
that part.

Guiding rule: **don't fight the system, ride it.** The layer is a
dispatcher, not an implementation. If macOS, a Spoon, or a CLI already
does something, route to it instead of rebuilding it.

## Use case and boundaries

**Use case.** A keyboard launcher for macOS that runs the commands
belonging to whatever is in front of you -- an app, a window, a Finder
selection, a browser tab, a project -- without first going to where they
live. It collects them into one VS Code-shaped palette, fills in what a
command needs from the context, asks only for what is missing, and hands
the work to the tool that already does it. Scope is decided feature by
feature against that picture; there is no list of non-goals yet.

**Boundary rules.** Follow these in every change.

- The kernel (`core/`) owns the registries, the context model, `when`, the
  view stack and dispatch. It names no extension, backend, menu or subject
  field.
- An extension contributes through declared hooks and specs only. It
  reaches another extension through a declared dependency, never through
  `cl.modules`, and never writes a registry's tables.
- Every action is a command run by id, never a command's `run` called
  directly.
- Everything an extension registers, and every timer, watcher and task it
  starts, is held and undone on stop.
- Nothing blocks Hammerspoon's one thread on the picker path.
- A presenter draws exactly the rows it is given.
- One spelling per concept, VS Code's. While in development an old name
  is removed, not kept as an alias. A mistake in a spec or a file is a
  problem shown to the user, not a log line.
- Settings are in settings: anything a person might change is a declared
  setting or a key in `config/defaults.jsonc`, never a field in a Lua file.
- Everything beyond the kernel can be switched off: a feature is an
  extension (`"<ext>.enabled": false`) or a removable picker, not code in
  `core/`, so the core can be kept small.
- A feature needing more than this is a proposal to change the contract,
  never a way around it.

## The reference

[`docs/api.md`](docs/api.md)
is generated and lists every spec kind's fields (command, extension,
input, row, section, setting, view), the kernel's settings keys, every
declared setting, a keybinding's fields, the plugin API members per kind,
and every registered command. Look those up there. What a table cannot say
-- why, the constraints, and the behaviour between fields -- is in this
file and in docs/behaviour.md.

## Where the rest is

| Changing | Read first, in [docs/behaviour.md](docs/behaviour.md) |
|---|---|
| a command that runs something (`system.open`, `shell.run`, `terminal.run`, `webview.open`), Secure Input, screenshots, audio, media, keep awake | Running a thing |
| settings, profiles, merging, problems, reloading, writing settings.json | Profiles and settings |
| keybindings, controls, global keys, the Keyboard Shortcuts picker | Keybindings and controls |
| commands, `after`, `confirm`, sections, inputs that take a thing, windows, paths, Git, selection, URLs, SSH, the VS Code bridge | Commands |
| `when` clauses and `config.` keys | When clauses |
| sites, tabs, Chromium session files | Browser |
| VS Code's recents, zoxide, remote projects | Projects |
| text commands, `fromQuery`, question pickers | Commands that take text |
| prefixes, submenus, pickers as data, cmd+k, `left` | Prefixes, menus and views |
| `~/.config/commandlayer/`, `<ext>.enabled`, `<ext>.menus`, the settings picker | User config |
| matchers, rankers, frecency, aliases, `alwaysShow` | Matching and ordering |
| `search` hooks, file and text search | Search pickers |
| ambient context, Finder's selection | Context from the world |
| the presenter contract, the busy row, `chooser` and `popup` | Presenters |

[docs/seen-working.md](docs/seen-working.md) records what has been
confirmed on screen; ROADMAP.md's Owner checks move there once ticked.

## Verification

Run the harness before claiming a change works:

```bash
lua test.lua
```

`tests/harness.lua` stubs `hs.*`; every file in `tests/` is a suite of one
concern and every file in `tests/extensions/` one extension's checks, each
on a kernel of its own (`T.layer()`), so none sees what another left
behind. `T.layer(settings)` sets one up on a settings.json of its own --
`T.everyExtensionOn` switches on what ships off, as the reference is
generated. A shipped extension carries no checks of its own. They exercise
the pure logic — rows, verbs, templates, menus. Hooks and presenters are
pcalled, so a failing extension is a log line, not an error: the harness
keeps every `[commandlayer]` line and fails on any no check caused on
purpose (`expectedLogs` in `test.lua`). It also reads the source: every
timer started is held, nothing calls `hs.application.get`, nothing in
`core/` runs `os.execute`, nothing logs through `print`.

Checks come in groups (`group("name")`); a `stub(table, key, value)` is
put back when the next group starts, so one not restored by hand cannot
change what later groups see.

**Checks resolve no real tool and change no real file; the harness
refuses.** Every kernel a suite makes (`T.loadKernel`) resolves a tool a
plugin registers to `/fake/<name>`; a check that needs a real program --
`/usr/bin/open`, `osascript`, `ioreg` -- stubs `tools.paths[name]`, and
candidates a check writes itself resolve to nothing, as a tool not
installed. While test.lua runs the suites, `os.remove`, `os.rename`,
`hs.fs.mkdir` and `io.open` in a writing mode raise "a check tried to
change a real file: <path>" for a path outside `$TMPDIR` and the names
`os.tmpname()` handed out (a folder spelled `os.tmpname() .. "-suffix"` is
inside; a `..` is outside), and every refusal fails the run, since a
pcalled hook would swallow the error. A broken build of `tools.run` once
removed a real Homebrew link through a tool's real path. The guard is given
back at the end; `lua tests/reference.lua` never switches it on.

**Logging.** One `hs.logger`, `M.log` (`cl.log` in a plugin), so every
line carries a level: `e` for something that failed -- a hook or command
that threw, a process that exited non-zero -- and `w` for a mistake found
-- a problem in a file, an unknown name, a `when` that does not parse.
The harness stub prints every line whatever its level, so the trap still
sees them, and records which level wrote last.

**Performance.** `M.span(name, detail)` returns a stop function; spans are
named `group.part` (`gather.browser`, `match.fzf`, `draw.setItems`) and kept
per name (count, total, max, last, median, p90) and in a ring of the latest
`performance.keep`. An open, a keystroke, a search or a refresh is a trace,
from its start to its rows on screen (`core/performance.lua`), and writes
one line at `debug`, each group with its slowest parts:
`open root 412ms first: capture 38 (windows 20) · gather 290 (browser 180,
apps 70) · match 25 · rank 40 · draw 44 · 1480 rows`. `first` marks the
first open after setup, kept apart as `open.<view>.first`. A span or a
whole open over `performance.slowMilliseconds` (250) is a `warning` naming
it, every span a `trace` line; `0` records nothing. Work off the main thread
logs its slow line at `debug`, never `warning`: a span named `task.*` or
`cache.*` waits on another process and slows nothing on screen, so name
background work that way. Setup and start write
their line at `debug` only, since starting may take longer. "Developer: Show
Performance" lists the names slowest first, "Reset Performance" clears
them, and an extension reads them through `cl.performance()`. The harness
gives every kernel a still clock (`T.loadKernel`), so no timing line
reaches the trap; a check that measures stubs `clock`. It also holds rows
through gather, matching, ranking and drawing to a coarse budget, and fails
on any plugin calling `hs.execute`, `hs.osascript`, `io.popen` or
`os.execute` beyond the known debt listed in `tests/source.lua`.

`lua tests/luacheck.lua .` runs luacheck with `.luacheckrc` (undefined
globals, unused locals, shadowing, except in checks). The harness runs it
where luacheck is installed and fails on any warning. The launcher exists
because luacheck 1.2.0 does not load under Lua 5.5; it patches the one
loop that stops it, in memory, only when the file will not load as it is.

`lua tests/reference.lua` writes `docs/api.md` and
`config/settings.schema.json` / `config/keybindings.schema.json` from the
descriptions in `core/schema.lua` and `core/api.lua` and from the shipped
plugins. It is not a suite; `tests/generated.lua` is, and fails while a
generated file is stale or something has no description. Change the
description, then run it again. A settings.json may begin with `"$schema"`;
keybindings.json, a list, is reached through VS Code's `json.schemas`.

**docs.json.** init.lua is documented in hs.doc's docstring format, and
`tests/spoon.lua` holds it there: the metadata SPOONS.md asks for, a
docstring for every method and variable init.lua offers (a method's with
Parameters and Returns), none naming something it does not offer, and
`defaultHotkeys` equal to the shipped entry chord. Only init.lua carries
`---` docstrings. `docs.json` needs Hammerspoon, with `hs.ipc` loaded, so the
harness cannot write it; from the repository root:

```bash
hs -c "hs.doc.builder.genJSON(\"$(pwd)\")" | grep -v "^--" > docs.json
```

A silent harness means all files parse, which catches what takes the whole
config down at load and nothing more — nil-indexing, wrong `hs.*`
arguments and malformed Spotlight predicates still fail at runtime.
`hs.reload` remains the only real test. (Homebrew's `lua` is 5.5;
Hammerspoon embeds 5.4.) So `M.start()` guards each subsystem with
`pcall`: one that throws must degrade, never take `init.lua` down.

An agent's live check is a reload, the console, `problems` and harmless
commands; what has to be seen on screen goes in [ROADMAP.md](ROADMAP.md)'s
Owner checks. An agent never changes the owner's own files or state to
check something: a new picker is tried in a throwaway profile, never the
owner's keybindings.json; `~/.ssh/config` is read only through fixtures;
no Homebrew verb is run.

## Comments

Code comments explain the code — a constraint, a gotcha, why a
non-obvious line is written the way it is. They do **not** argue about
how the project is organised, or narrate how the design got here. That
belongs in this file or in design.md, where it can be revised in one
place instead of drifting across twenty.

Comments say **why**, never what — the code says what — and never how
the design got here.

Keep: "copied first, because the browser holds the database open".
Drop: "which is the same coupling the registration lines were".
Drop: "returns true if something still had to be asked" — read the code.

Interfaces are documented once. The extension contract's fields are in the
generated reference, its behaviour in this file, docs/behaviour.md and
README.md; repeating
it in a header means copies that drift.

## Shape

    commandlayer.lua   the loader: runs core/ in a fixed order
    core/              the kernel, one file per concern
      loading            the log, the clock, making folders
      performance        spans, traces per open and keystroke, what they add up to
      problems           what is wrong in a person's files, shown in one alert
      jsonc              reading JSON with comments, and writing it back
      profiles           which profile, where its files are, which profiles there are
      tools              resolving binaries, choosing providers
      chords             reading a written chord, the keybindings list after removals
      context            context keys, filling templates, template variables
      when               `when` clauses over the context
      session            the modal, the view stack, the picker on screen, the hooks
      disposables        what a plugin registered or started, undone together
      items              the row shape: icons, the second line
      commands           the command registry, command rows, running a command or a row
      extensions         the extension registry, capture, gather, search
      ranking            matching and ranking
      presenters         the presenter registry, appearance
      viewregistry       the declared views as data, prefixes
      sections           sections, separators, "Recently used"
      stack              the pick path, rendering, typing, refresh
      inputs             asking for a command's inputs, running a command by id
      views              opening a view, building its rows, the cmd+k panel
      controls           named controls: what the picker does to itself
      settings           merging and applying settings, reading one, taking in what a plugin wrote
      schema             one schema for every spec; checking specs, settings files, keybindings
      keybindings        the keybindings files, binding them, reading them again, running an entry
      api                what each kind of plugin is given
      plugins            loading the folders: presenters, extensions, matchers, rankers
      lifecycle          setup, start, stop, bindHotkeys, the public layer, reloading
    config/            defaults.jsonc, defaultKeybindings.jsonc, profiles/<name>/,
                       settings.schema.json and keybindings.schema.json (generated)
    extensions/        what there is to run, how it runs, and what can be done with it
    matchers/          which rows a query keeps, and in what order
    rankers/           what decides the order among those
    presenters/        how a picker is drawn
    docs/              api.md, the reference (generated); behaviour.md, how each
                       part behaves; seen-working.md, what was confirmed on screen
    test.lua           runs every suite, then the log trap
    tests/             harness.lua, a suite per concern, extensions/<name>.lua,
                       reference.lua, which writes docs/api.md and the JSON Schemas

A picker is a declaration and never sees a chooser: rows reach a presenter
only through `present(items)`, and the harness drives the kernel through a
recording presenter, because that seam decides whether the picker can ever
be swapped.

An extension's hooks (`items`, `subjects`, `query`, `search`, `capture`,
`scope`, `picked`, `left`) are optional fields of its spec; verbs are
commands. A `picked` or `left` hook that throws is logged; the others still
hear. How `search` behaves is in docs/behaviour.md, "Search pickers".

Loading `commandlayer.lua` defines things and touches nothing: it reads no
folder, claims no chord and consults no other file. `setup()` does all of
that and `start()` calls it, as SPOONS.md asks, so a caller can set
`profile` and `userDir` in between. The harness asserts nothing is
registered before `setup()` and counts `hs.settings` reads during the load.

Each `core/` file begins `local M = ...`: the kernel's one table, private
to it. A core file may alias from it as it loads, so the loader's order is
load order; the harness fails if a file in `core/` is not listed there.

**The load order is the dependency order.** A core file reads only what
files before it define, as it loads or when it runs, and the harness names
any read of a later file's definition. The one loop the design has --
opening a view can push another, running a command can ask for its inputs
-- goes through three hooks on `M.session` filled by later files:
`session.push` and `session.rowsOfView` (views), `session.collect`
(inputs). Anything else that seems to need a later file is in the wrong
file.

**Three things are given out, and none is the kernel** (`core/api.lua`):

- **The public layer** -- what `commandlayer.lua` returns and `hs -c`
  reaches as `spoon.CommandLayer.layer`: `start`, `stop`, `bindHotkeys`,
  `addExtension`, `executeCommand`, `setLogLevel`, `apiVersion`, a copy of
  `problems`, and `profile` and `userDir` to set before start. Anything else
  raises.
- **A plugin's API** -- one per extension, presenter, matcher and
  ranker, from an allowlist per kind (`M.pluginAPI(kind, name)`; members in
  the reference). A name outside it raises, naming the name and the kind.
- **The kernel, to the harness only**: `loadfile("commandlayer.lua")(t)`
  fills `t` with `M`. Hammerspoon passes nothing.

`apiVersion` is 0 while in development.

The kernel needs nothing installed: its binaries are `mdfind`, `find`,
`open` and `zsh`. Every third-party tool, fzf included, is registered by
the file that wants it and declines when it is missing.

## Extension separation

One file per extension in `extensions/`, owning its whole feature,
returning a module with `extension(cl)`. The folder is loaded and
registered automatically, so adding an extension is adding a file. Its
name is its file's; a `name` that differs is a problem and it is not
registered.

`extension(cl)` gets the extension's own API, never the kernel. As VS
Code's `context.subscriptions`, it records what the extension does through
it, each call returning a disposable `{ dispose }`:

- **Registered**, undone when switched off or dropped: theme icon
  providers, item context keys (a clash is a problem), context keys,
  `tools.register` (the binary stays while another plugin claims it) and
  `tools.provide`, and its commands with their prefix pickers.
- **Running**, undone on stop and started again by `start()`: `after`,
  `every`, `watch`, tasks from `tools.run`, and `cached` entries. A
  callback that throws is logged as an error naming the extension.

So `stop()` then `start()` works, and `"<ext>.enabled": false` leaves
nothing behind.

**The layer's own lists.** An extension building rows about the launcher
reads `cl.getViews()`, `cl.getKeybindings()` and `cl.getSettingOwners()`:
each call a fresh copy, every entry holding the fields `M.listShapes` in
`core/schema.lua` documents and no other (the reference's "Lists"), so
changing one changes nothing the layer holds and the shapes stay put while
the kernel changes. The kernel edits no file for a plugin -- `profileFile(name,
initial)` only makes one that is missing: the extension that changes one
edits its text with `cl.decodeJSONC`, `cl.editJSONC`,
`cl.removeJSONCElement` and `cl.appendJSONCElement`, pure functions over
text, and then tells the layer with `cl.settingsWritten()` or
`cl.keybindingsWritten()`. So settings.json is written by the settings
extension, keybindings.json by the keybindings extension from a copy whose
`source` says which file it came from, and profile.json and the generated
files by workbench.

`cl.extension(name)` is nil while that extension is off, and raises for
one not declared a dependency. `readJSONC(path)` reads a file of the
extension's own -- a site, a tasks.json -- as JSONC; one that does not parse
is a problem under the extension's name, naming the file, and nil. It
remembers nothing, unlike the kernel's, which tells a settings file's change. `cached` counts an empty answer as an
answer, and `done(nil)` as none: a call that did not work -- gh offline, a
token expired -- leaves the last good answer where it is and is asked again
on the next open, where an empty one would stand for the whole of `seconds`.
With an answer to show, a stale entry is refreshed a turn later, never inside
the call that found it stale, so an open never pays for a refresh that
happens to answer at once. An extension missing a required dependency is dropped with its
commands and logged, repeatedly until nothing changes; the rest start
after what they require and the optional ones present (`M.startOrder()`).
Capture, gather and search run in `before`/`after` order -- a name not
loaded is no constraint, otherwise by name; a circle is a problem naming
them, and they follow the rest. Every extension starts with the layer, and
`M.stopExtensions()` stops every one that started.

`refresh()` redraws the picker when rows arrive late, an argument prompt's
search asked again as a view's rows are built again. App menus are read
in the background when an app comes to the front, so a picker opened
first is redrawn when they land -- each item's shortcut formatted then
(`⇧⌘S`, `appmenus.shortcuts`), never per row; a read that never answers is given up
after `M.pendingSeconds` (5), where it once blocked every later read of
that app. The calculator is another: a query hook cannot wait, so a new
expression starts `bc -l` in a task and shows nothing, and the answer, kept
by expression, is a row once the redraw asks again; an unfinished `bc` is
ended by the next expression. A refresh while rows are being built is ignored, so a cache that
calls back at once cannot recurse; a callback meant for "the scan landed"
should still not fire when nothing was scanned.

What a feature offers lives in the extension that owns it, never in a
shared list (Lock screen is `system.lua`, Show Logs `developer.lua`).
There is no `cl.config` for hand-written actions; a person's own are an
extension file in `~/.config/commandlayer/extensions/`.

If a new extension needs a change to the interface, say so rather than
widening it quietly — that is the signal the model is wrong.

## The goal

Someone wanting a *different* launcher should be able to build it
without forking the kernel — and that includes us, a year from now. The
test is not "can this be configured" but "could someone replace this
part without touching the rest".

| Plug point | Decides | State |
|---|---|---|
| **Extensions** | what there is to run | done — 50 files, one contract |
| **Commands** | how a thing runs | done — contributed by extensions, `menus = {}` |
| **Matchers** | which rows a query keeps | done — `fzf`, `substring` |
| **Rankers** | what decides the order | done — 4 files |
| **Views** | which rows a picker shows | done — declared in settings, fed by extensions |
| **Presenters** | how a picker is drawn | done — chooser, popup |

## Where things stand

The launcher is in daily use. 954 harness checks pass; run them before
claiming anything, and reload Hammerspoon (`cmd+alt+ctrl+R`) before
believing it -- a saved settings.json or keybindings.json reloads the
layer, a changed code file does not. `hs -c` reaches the public
layer as `spoon.CommandLayer.layer`, not the kernel.

What has not been seen, because the harness cannot touch macOS, is
[ROADMAP.md](ROADMAP.md)'s Owner checks: add to them what a change leaves to
be seen on screen.

## Ways forward

[ROADMAP.md](ROADMAP.md) holds what is left: the owner's checks, the work in
progress, and the items answered "later", each under a stable id (D9, C4).
A decision and its reason go to design.md once made, not there. Credits and
comparisons are in [PRIOR_ART.md](PRIOR_ART.md). Each step ends with the
harness green, each new check proven to fail with its code broken, and a
commit.

Work happens in parallel worktrees. A merge conflict in CLAUDE.md, or in any
document, is resolved by keeping what both sides wrote, joined into one text
-- never by taking one side, which silently drops the other batch's
paragraphs.

## What is on this machine to read

`reference_projects/` is gitignored — other people's repositories, cloned
to read, and not in every checkout. Nothing depends on them, but they answer most "has anyone
solved this" questions without a web search.

| Path | Worth reading for |
|---|---|
| `Spoons/Source/Seal.spoon` | The closest prior art in the official repo. Its `bare()`/`commands()` plugin split, and `seal_apps.lua`, which is where the live `hs.spotlight` app query came from |
| `Spoons/Source/TextClipboardHistory.spoon` | The `nspasteboard.org` ignore list — `ConcealedType`, `TransientType` — that keeps copied passwords out of a history |
| `Spoons/Source/RecursiveBinder.spoon` | A which-key style overlay of chords -- the launcher has none; `?` lists pickers and how to reach them |
| `Spoons/Source/` (89 spoons) | Window management, `SpoonInstall`, `ReloadConfiguration`, `Emojis`, `ClipboardTool` — check here before writing anything |
| `martillo/` | 9k lines, the closest competitor: a Raycast alternative with a git-repo action store. Flat command list, **no context model** |
| `Hammerflow.spoon/` | Leader-key launcher configured from one TOML file. Its `cmd:` / `text:` / `shortcut:` prefixes are our `command.type` in string form |
| `Ki/` | Vim-style modes with entity/action/select. The nearest thing to our subjects, and 3k lines of its own class system |
| `spacehammer/` | Spacemacs-style modal toolkit in Fennel, with a real state machine for modal transitions |
| `lunarySpoon/` | Sequential key binding, small |
| `hammerspoon-config/` | cmsj's working config, where Seal began: global hyper chords, URL events, audio, and the lessons about holding timers |

Also outside this repo: `~/dotfiles/Library/Application Support/Code/User/`
holds the VS Code `keybindings.json` the `cmd+e`/`cmd+d`/`tab` navigation
in `~/.config/commandlayer/keybindings.json` was copied from, under its
`inQuickOpen` bindings.

The field survey and credits are in [PRIOR_ART.md](PRIOR_ART.md): nothing
else has a context model every extension shares, which is the one thing
here that is not catching up.

## Known debt

- **Helpers duplicated across extensions**: `expand` in apps and
  projects, the Spotlight update fan-out
  in apps and files, and the browser's two AppleScript branches. Unifying
  the cross-file ones means widening what an extension is given, which is
  a decision rather than a tidy-up.
- **`hs.application.get(name)` is a window search when it misses**: for a
  name not running it matches every window's title of every app, close to
  a second each. Listing browsers that way made `cmd+r` take 6.5 seconds,
  and a click during the freeze closed the launcher as "away". Browsers
  are judged running by bundle id, apps found by bundle id or among the
  running apps; the harness checks no source calls it.
- **A timer nobody holds can be collected before it fires.** The windows
  list came from an `hs.timer.doAfter` nobody kept; after one reload it
  never ran. Keep every timer on the module until it has fired; the
  harness checks the source for one that is not.

## Exceptions to dispatch

A feature dispatches to an existing tool and implements no command logic of
its own. Reading the environment -- session files, VS Code's recents, the
apps and windows there are -- is not command logic, and neither is the
launcher's own machinery, such as ranking. Anything needing state or an
algorithm of its own is routed to a tool, or dropped; design.md lists what
the rule dropped and why. The exceptions, each kept because no tool holds it:

- **App-usage history** (`commandlayer.appMRU` in `hs.settings`,
  `extensions/apps.lua`). No tool keeps an app-activation history, and it
  is what finds an app you quit by a name you forgot. Later: try
  lsappinfo's front-to-back order plus Spotlight's kMDItemLastUsedDate in
  its place.
- **Frecency** (`rankers/frecency.lua`). Nothing outside counts what is
  picked in the palette; the algorithm is zoxide's, copied.

## Decided against, for now

- Saving a typed shell command as a command from the palette. Too much
  magic, and not how VS Code works: a command comes from an extension, or
  from a file a person writes.
- Hiding or quieting a typed prefix. `hs.chooser`'s field cannot be
  styled, so it would mean taking the prefix out of the field -- a
  placeholder that vanishes once you type, and a key watcher for backspace
  in an empty field -- or a toolbar above the chooser. The prefix stays in
  the field, as VS Code's `>` does; a short alias makes it less loud.
- A webview presenter, and a preview pane. One was built and seen working;
  it drew the same rows as the chooser, slower, and took focus from the
  app you were in on every open. Everything it could add -- preview,
  sections, multi-select, custom chrome -- was decided against for the
  palette. A webview is a destination instead.
- Rebasing on Seal. No context model, no modal chords, no per-item
  actions, substring matching instead of fzf.
- Porting the zsh palette wholesale. `env:` and `wez:` are session-bound
  and never migrate; `git:`/`task:` are verbs on a project, not rows.
- A snippets store of our own, or reading one into rows. Raycast keeps,
  searches and expands them; `snippets.lua` opens its snippet search
  through `raycast.open`, and another tool is one more provider entry.
- Reading Maccy's history into our own rows. Its store is a sandboxed Core
  Data database with a write-ahead log, so listing it means copying your
  whole clipboard history to a temp file on a timer -- a second stale copy
  of precisely the data least worth copying. `maccy.lua` hands off to its
  window instead.
- A clipboard manager of our own. `TextClipboardHistory.spoon` already
  ignores `org.nspasteboard.ConcealedType`/`TransientType`/
  `AutoGeneratedType`, so passwords never enter history. It is text-only;
  `brew install --cask maccy` is the richer option and respects the same
  types plus 1Password's and KeeWeb's by name. Neither expires entries,
  because the convention is "never record it", which is the stronger
  guarantee.
