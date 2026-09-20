# Command Layer

A keyboard launcher for macOS, built on [Hammerspoon](https://www.hammerspoon.org).

`alt+space` opens one list: the apps you have, the projects you were in,
the System Settings panes, the things you can do with whatever is in front of
you right now. `cmd+k` on any row asks what else can be done with it.

It is a **router, not an implementation**. Almost nothing here is a
feature macOS lacks — it is a way to reach features that already exist:

| It shows you | By reading |
|---|---|
| Applications | a live Spotlight query |
| System Settings panes | the ExtensionKit bundles that define them |
| Recent projects | VS Code's Open Recent list, then zoxide |
| Folders you visit | zoxide |
| Recent files | Spotlight's `kMDItemLastUsedDate` |
| Open windows | Hammerspoon's window filter |
| Snippets | Raycast's snippet search, through its deeplink |
| Browser tabs | Chromium's own session files |
| Bookmarks and history | Chromium's SQLite and JSON stores |
| Any app's commands | its **menu bar**, via the accessibility API |
| Your repos, PRs, issues | `gh` |
| Shortcuts | `shortcuts list` |

What needs a tool not everyone has ships switched off: Raycast, Maccy, GitHub
(`gh`) and the VS Code bridge. `"raycast.enabled": true` in your settings.json
switches Raycast on, and with it Snippets.

The rule throughout: if macOS, a CLI, or an app already does something,
route to it rather than rebuild it. See
[design.md](hammerspoon/CommandLayer.spoon/design.md) for why, including
the arguments that turned out to be wrong.

## Install

Copy the Spoon into Hammerspoon's Spoons folder:

```bash
cp -R hammerspoon/CommandLayer.spoon ~/.hammerspoon/Spoons/
```

and start it from `~/.hammerspoon/init.lua`, as any Spoon is:

```lua
hs.loadSpoon("CommandLayer")
spoon.CommandLayer:start()
```

`alt+space` is Raycast's and Alfred's default as well, so whichever of them
holds it has to give it up first. The entry chord is a global keybinding --
one that works in every app, with the launcher closed -- so to use a
different one, put this in your keybindings.json (see below); `cmd+space`
also needs Spotlight's binding freed, in **System Settings ▸ Keyboard ▸
Keyboard Shortcuts ▸ Spotlight**:

```jsonc
[
  { "key": "alt+space", "command": "-quickOpen" },
  { "key": "cmd+space", "command": "quickOpen", "global": true }
]
```

or give `bindHotkeys` a mapping before `start()`, as with any Spoon:

```lua
hs.loadSpoon("CommandLayer")
spoon.CommandLayer:bindHotkeys({ enter = { { "alt" }, "space" } })
spoon.CommandLayer:start()
```

`spoon.CommandLayer.defaultHotkeys` is the shipped chord in that shape. What
else init.lua offers -- `profile`, `userDir`, and `layer` for the console --
is described in its docstrings, which `docs.json` is generated from.

### Permissions

Hammerspoon needs **Accessibility** (System Settings ▸ Privacy &
Security) for app menus and moving windows. Without it
those degrade; everything else works.

Chromium browsers (Brave, Chrome, Edge, Vivaldi, Arc) need no extra
permission for their tabs, history and bookmarks. Going to a tab and a
site's JavaScript commands need Hammerspoon allowed to control the browser
(**Automation**). Safari's history and bookmarks are **not** read —
different schema, behind Full Disk Access.

Commands that run in a terminal -- Git: Pull, Push and Checkout…, lazygit,
Homebrew, tasks, SSH -- need Hammerspoon allowed to control Terminal
(**Automation**). Until it is, each says where to allow it and does nothing
else.

### Optional

Everything below is detected, never required. Each one you have makes
the layer better; none of them breaks it by being absent.

`fzf` (fuzzy matching — without it, plain substring matching) ·
`zoxide` (folders you visit, and project frecency) · `gh` (GitHub) ·
`git` (repository commands) · `fd` (file search fallback) · the codicon
font, `brew install --cask font-codicon` (icons) · `rg` ("Search Text in…",
text search) · `lazygit` · `brew` · an editor (`code`, `cursor`, `zed`, `subl`,
else the default app)

The terminal is not detected: `"terminal.application"` in settings.json names
one -- `"terminal"` (Terminal.app, the default), `"wezterm"`, `"kitty"` or
`"alacritty"` -- and nothing else is used in its place.

## Keys

```
alt+space          open
  cmd+p            file search, recent files before you type
  cmd+o            command palette — everything runnable
  cmd+.            actions for what is in front of you
  cmd+r            recent projects, tabs, windows and apps
  cmd+k            what can be done with the highlighted row
  arrows, return   move, open the highlighted row
  escape           back one level, or leave
```

The pickers are also reached by typing a prefix — `>`, `recent `,
`context `, `files `, `settings `, `keybindings `, and `?` for all of them — and
each picker chord above is the root with that prefix typed. `?`, `settings `
and `keybindings ` are pickers declared in `config/defaults.jsonc` like the
rest, their rows from the help, settings and keybindings extensions, so each
can be switched off like any extension. Those chords
are `config/defaultKeybindings.jsonc`; your `keybindings.json` adds to or
removes any of them. Moving by chord is yours to choose — VS Code's quick
open style is:

```jsonc
[
  { "key": "cmd+e", "command": "quickOpen.selectPrevious" },
  { "key": "cmd+d", "command": "quickOpen.selectNext" },
  { "key": "tab",   "command": "quickOpen.accept" },
  { "key": "cmd+w", "command": "quickOpen.back" }
]
```

Escape is the exception — the chooser reports its own dismissal, so escape
always steps back and cannot be reassigned.

## Configuring it

Settings are arranged as VS Code arranges them: the launcher ships its
defaults, and yours go over them.
[`config/defaults.jsonc`](hammerspoon/CommandLayer.spoon/config/defaults.jsonc)
describes the whole launcher — which pickers exist, how rows are ordered,
how the panel looks — and `config/defaultKeybindings.jsonc` its chords.
Anything needing code is an extension, a matcher, a ranker or a presenter;
a picker is a declaration, its rows fed by extensions.
In the palette, **Preferences: Open Default Settings (JSON)** shows every
setting there is, the extensions' included; so does the generated
[reference](hammerspoon/CommandLayer.spoon/docs/api.md), with the fields of
a keybinding and every command a key can run.

```jsonc
// ~/.config/commandlayer/settings.json
{
  // Pickers merge by name: this changes one field of the palette, and
  // "enabled": false would remove it.
  "views": [
    { "name": "palette", "placeholder": "Commands" }
  ],
  "rankers": { "relevance": 1, "specificity": 0.35, "frecency": 0.2, "alphabetical": 0 }
}
```

Every ranker scores a row 0..1, so the weight beside it is the whole of
how much it counts. Set `specificity` to 0 to order purely on what you
typed, or `frecency` to 0 for a list that never reorders under you.

```jsonc
// ~/.config/commandlayer/keybindings.json, added after the defaults
[
  { "key": "cmd+j", "command": "quickOpen.showActions" },
  { "key": "cmd+k", "command": "-quickOpen.showActions" },  // remove a default
  { "key": "cmd+g", "command": "quickOpen", "args": { "query": "files " } },
  { "key": "cmd+shift+n", "command": "appmenus.select",
    "args": { "app": "Brave Browser", "path": [ "File", "New Window" ] } }
]
```

A `command` is any registered command, so a key can run one with args —
the last entry picks one item from an app's menu bar. A command starting
with `-` removes that command's earlier entries, only the named `key` when
there is one. `quickOpen` opens a view (`args.view`, the entry picker by
default) with `args.query` already typed, so `"files "` lands in the Files
view.

The defaults are shaped like VS Code's quick open.
`config/profiles/raycast/` is a profile with one picker instead of several
and no picker chords. **Profiles: Switch Profile…** in the palette switches
to it or to one of your own, as does `{ "profile": "raycast" }` in
`~/.config/commandlayer/profile.json`, or before `start()`:

```lua
local cl = hs.loadSpoon("CommandLayer")
cl.profile = "raycast"
cl:start()
```

Menus nest. A view declared with a `parent` is a row in it, and picking
that row opens it on top — escape comes back:

```json
{ "name": "history", "title": "History", "menus": [ "recent" ], "parent": "root" }
```

That puts `History ▸` in the root; its rows are whatever extensions put on
the `recent` menu. Any row can open a view the same way with
`submenu = "history"`.

A view can also have a `prefix`, the way VS Code's Quick Open does:
typing `files ` in the root opens file search and searches for what
follows, and `>` opens the command palette. Delete the prefix and you are
back where you were. `cmd+o` is simply the root with `>` already typed,
and `?` lists every picker and how to reach it. Shipped prefixes are
whole words, so they never catch an ordinary search; `prefixes` adds
shorter ones of your own.

A picker with `"kind": "search"` searches again as you type instead of
narrowing a list it already has. File search is one: recent files before
you type, then whatever the files extension's `search` hook finds.

## Your own settings

What is yours lives in `~/.config/commandlayer/`, outside the Spoon, so it
can go in your dotfiles and survive an update:

    ~/.config/commandlayer/
      settings.json        your settings, over config/defaults.jsonc
      keybindings.json     your chords, after config/defaultKeybindings.jsonc
      profile.json         which profile is active, by name or folder path
      profiles/<name>/     another profile's own settings.json and keybindings.json
      tasks.json           tasks in VS Code's tasks.json shape, each a row in the root
      extensions/*.lua     your own extensions; one named like a shipped one replaces it
      sites/*.json         commands for a website, shown only while it is in front

`matchers/`, `rankers/` and `presenters/` there work the same way as
`extensions/`. A picker is declared in `settings.json`'s `views`; a Lua file
in `views/` is shown as a problem, never run. **Tasks: Open User Tasks** makes `tasks.json`
and opens it; under another profile it is that profile's folder's.

As in VS Code, a profile switches rather than stacks: under another
profile, the default profile's settings.json and keybindings.json are not
read. Both files may carry comments.

```jsonc
// settings.json
{
  // Completion and underlining in VS Code; keybindings.json, a list, is
  // matched to config/keybindings.schema.json through VS Code's "json.schemas"
  "$schema": "file:///Users/you/.hammerspoon/Spoons/CommandLayer.spoon/config/settings.schema.json",
  "terminal.application": "wezterm",
  "prefixes": { "recent": "r ", "files": "f " },
  "chooser.screen": "focused",
  "maccy.enabled": true,
  "browser.history": false
}
```

```jsonc
// keybindings.json
[
  { "key": "cmd+e", "command": "quickOpen.selectPrevious" },
  { "key": "cmd+d", "command": "quickOpen.selectNext" }
]
```

You rarely need to write it by hand: `settings ` in the launcher lists every
extension and the switches each one offers — browser tabs, bookmarks and
history — and picking one flips it and saves. Saving changes only that
value, so your comments and layout stay.

A mistake in either file — a setting that does not exist, a value it cannot
take, a keybinding to a command that is not there, a file that does not
parse — is shown in one alert when Hammerspoon loads, naming the file, and
the rest of the file still applies.

A site is commands for while one website is in front — its own shortcuts,
or JavaScript run in the tab. YouTube ships; one of your own is a JSON file,
comments allowed, holding one site or a list of them:

```jsonc
// ~/.config/commandlayer/sites/github.json
{
  "name": "GitHub",
  "match": "github%.com/[^/]+/[^/]+/pulls",   // a Lua pattern over the URL
  "commands": [
    { "title": "Copy page title", "js": "navigator.clipboard.writeText(document.title)" },
    { "title": "Next file", "keys": "j" }
  ]
}
```

Each command has `keys` or `js`, never both. `keys` needs nothing; `js`
needs the browser's **Allow JavaScript from Apple Events** (Chrome and
Brave: View › Developer; Safari: Develop). A mistake in a site file — a
field a site cannot have, a command with neither, a `match` that is not a
pattern, `keys` that do not read as a key — is shown like a mistake in your
settings, naming the file, and leaves out only the site or command it is in.

## Searching with what you typed

Some commands take what you type as their argument — web search, YouTube
search, and every quicklink with `${query}` in its URL:

- `? lofi beats` lists all of them with "lofi beats" filled in, above
  the pickers the text matches.
- `search lofi beats` or `youtube lofi beats` shows just that one.
- Typing something in the root that matches nothing offers them too.

Nothing runs without you picking it. A shorter prefix is yours to add:

```json
{ "prefixes": { "browser.searchYouTube": "yt " } }
```

## Writing an extension

Drop a file in `extensions/`. It is loaded and registered on its own —
there is no list to add yourself to.

```lua
local M = {}

function M.extension(cl)
  return {
    name  = "example",
    rank  = 0.29,                      -- how specific: 0 to 1
    menus = { "root", "commandPalette" },  -- which pickers

    items = function(ctx)              -- nouns: plain rows
      return {
        { label = "Hello", description = "Example",
          run = function() hs.alert.show("hi") end },
        { label = "Example site", description = "Link",
          command = "system.open", args = { target = "https://example.com" },
          subject = { kind = "url", value = "https://example.com" } },
      }
    end,

    commands = {                       -- verbs: on cmd+k for any url row
      { id = "example.copyLink", title = "Copy link",
        menus = { ["view/item/context"] = true },
        inputs = { { id = "link", picker = { when = "viewItem == 'url'" } } },
        run = function(args, ctx)
          cl.executeCommand("system.copy", { text = args.link.value }, ctx)
        end },
    },
  }
end

return M
```

A verb worth binding or calling by name is a **command** instead of a
row: registered under an id starting with the extension's name, a row in
its `menus` (the palette unless it says), and runnable with
`cl.executeCommand(id, args)`.

```lua
return {
  name = "example",
  commands = {
    { id = "example.hello", title = "Say hello", category = "Example",
      run = function(args, ctx) hs.alert.show("hi " .. (args.who or "")) end },
    { id = "example.search", title = "Search the web", menus = { "root" },
      inputs  = { { id = "q", picker = { typed = true }, encode = "query" } },
      command = "system.open", args = { target = "https://duckduckgo.com/?q=${q}" } },
  },
}
```

A command can take a *thing* rather than text. An input names the picker
that asks it; declare what it takes as that picker's `when` over a row's
kind, and it works both ways round: picked from search it asks which, and
`cmd+k` on any row of that kind offers it with the row given. This is all
of Open in terminal:

```lua
{ id = "example.terminal", title = "Open in terminal",
  inputs = { { id = "target",
               picker = { when = "viewItem == 'folder' || viewItem == 'project'" } } },
  run = function(args, ctx)
    cl.executeCommand("terminal.open", { target = args.target.path }, ctx)
  end }
```

Settings are declared the way VS Code's extensions declare them, and read
with `cl.setting("example", "loud")`; the `settings ` picker lists them:

```lua
settings = { loud = { type = "boolean", description = "Say it loudly", default = false } }
```

Rows that come and go -- menu items, tabs, files -- stay plain rows and
call a command with args, the way every scraped menu item runs
`appmenus.select`.

Every hook is optional -- `items`, `subjects`, `query` (rows made *from*
what you typed, like the calculator), `search` (rows found by asking again
as you type, like file search), `capture`, `scope`, `picked` and `left`
(told when a picker its rows feed is left, to stop what it started for it)
-- plus
`start` and `stop`, which the loader calls if they exist. An extension's
checks are `tests/extensions/<name>.lua`, not part of it.

`cl` is the extension's own API, not the whole launcher. What an extension
registers or starts through it is undone when it stops or is switched
off, so it never has to clean up after itself. Reaching for anything else
raises.

Every field of an extension, command, input, row and view, every setting,
and every member of `cl` is listed in the generated reference,
[docs/api.md](hammerspoon/CommandLayer.spoon/docs/api.md).

**More than one extension may answer for the same subject kind**, which
is the point. The browser extension turns the page you are looking at
into a `url`; the git extension puts "Clone" on any `url` that looks
like a repository. Neither knows the other exists, and cloning the repo
you are reading about works because of it.

Rows are ordered by a sum — how well they matched (fzf), how specific
they are (`rank`), and how often you pick them (frecency) — so a context
verb floats above the catalogue without ever being able to bury an exact
match.

A row can open a page in a window of its own instead of a browser tab:

```lua
{ label = "Weather", command = "webview.open", args = { target = "https://wttr.in/?0" } }
```

`html = ...` or `file = ...` work in place of `target`; escape closes it.

## How it is put together

    commandlayer.lua   loads the kernel
    core/              the kernel, one file per concern
    config/            the shipped settings, keybindings and profiles
    extensions/        what there is to run, how it runs, and what can be done with it
    matchers/          which rows a query keeps
    rankers/           what decides the order
    presenters/        how a picker is drawn

The kernel knows nothing about the world. Which app is frontmost, what
is on the clipboard, what a terminal is, what a project is, what Finder
has selected, what a row's icon looks like — all of it is contributed by
a file in one of those folders.

So is what draws a picker. `presenters/chooser.lua` wraps Hammerspoon's
native search panel and is the default; a view can name another with
`"presenter": "name"`, and a profile can change the default the same way.
A presenter shows the rows it is given and reports what was picked and
what was typed — which rows, in what order and what happens next stay
in the kernel.

Two presenters ship. `chooser` is the default. `popup` draws a picker
as a native menu, with views declared with a `parent` as real submenus
and no search field:

```json
{ "name": "history", "title": "History", "menus": [ "recent" ], "parent": "root", "presenter": "popup" }
```

## Development

```bash
cd hammerspoon/CommandLayer.spoon && lua test.lua
```

Stubs `hs.*`, loads the layer outside Hammerspoon, exercises the pure
logic. It is the gate before any change: `luac -p` proves a file parses
and has never once caught a bug here, whereas this harness found two
dead features within minutes of existing.

`hs.reload` remains the only real test of anything that talks to macOS.

## Where it is going, and who it learned from

[ROADMAP.md](ROADMAP.md) is what is left: the checks only a person at the
screen can make, and the work still planned.
[PRIOR_ART.md](PRIOR_ART.md) credits the projects this one learned from --
VS Code first, then Hammerspoon's Spoons, martillo, Hammerflow, Ki,
spacehammer, Alfred, Raycast, LaunchBar, Quicksilver and others -- with
what each does, what was taken, and where each is better.

## Also in this repository

- `vscode/command-layer-extension` — the VS Code extension this idea
  started as. The launcher does not need it: it reaches VS Code through the
  URLs a stock install answers (`vscode://file/`, `vscode://settings/`,
  `vscode://vscode.git/clone`), the `code` command and VS Code's menu bar.
  Installed, it adds four rows -- Find in files, Go to file, Run task… and
  Run command… -- once `"vscodebridge.enabled": true` is in settings.json.
  From the repository root:

  ```bash
  ln -s "$PWD/vscode/command-layer-extension" ~/.vscode/extensions/local.command-layer-1.0.0
  ```

  then reopen VS Code (if the link is not picked up, **Developer: Install
  Extension from Location…**), and list the VS Code commands the launcher
  may run in its `commandLayer.uriHandler.allowedCommands` setting --
  `workbench.action.findInFiles` and `workbench.action.quickOpen` for the
  first two rows. Its README has the rest.
- `zsh/` — the same idea in the shell: fuzzy-find, then pick an action.
  Session-bound things (`cd`, virtualenvs, terminal panes) live there
  and deliberately do not migrate.

## License

MIT -- see [LICENSE](LICENSE).
