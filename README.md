# Command Layer

A keyboard launcher for macOS, built on [Hammerspoon](https://www.hammerspoon.org).

Press `alt+space` and you get one list: your apps, the projects you were
working in, your browser tabs, System Settings panes, and the things you can
do with whatever is in front of you right now. Press `cmd+k` on any row to see
what else you can do with it.

It works like VS Code's command palette, for the whole Mac.

## Why another launcher

Command Layer doesn't reimplement features. It routes to tools you already
have:

| It shows you | By reading |
|---|---|
| Applications | a live Spotlight query |
| System Settings panes | the bundles macOS ships them in |
| Recent projects | VS Code's Open Recent list, then zoxide |
| Folders you visit | zoxide |
| Recent files | Spotlight |
| Open windows | Hammerspoon |
| Browser tabs, bookmarks, history | Chromium's own files |
| Any app's commands | its menu bar, through Accessibility |
| Your repos, PRs, issues | `gh` |
| Shortcuts | `shortcuts list` |

Everything is plain text you own: settings and keybindings are JSON files
shaped like VS Code's, and extensions are single Lua files. No account, and
nothing leaves your machine. [design.md](design.md) has the reasoning, and
[PRIOR_ART.md](PRIOR_ART.md) compares it with Raycast, Alfred and others.

## Install

Clone it into Hammerspoon's Spoons folder:

```bash
git clone https://github.com/saemeon/CommandLayer.spoon ~/.hammerspoon/Spoons/CommandLayer.spoon
```

Start it from `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("CommandLayer")
spoon.CommandLayer:start()
```

Reload Hammerspoon and press `alt+space`.

Or with [SpoonInstall](https://www.hammerspoon.org/Spoons/SpoonInstall.html),
which also updates it:

```lua
hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall.repos.CommandLayer = {
  url = "https://github.com/saemeon/CommandLayer.spoon",
  desc = "Command Layer",
  branch = "spoons",
}
spoon.SpoonInstall:andUse("CommandLayer", { repo = "CommandLayer", start = true })
```

If Raycast or Alfred already uses `alt+space`, free it there first, or pick
another key (see [Changing the entry key](#changing-the-entry-key)).

### Permissions

- **Accessibility** (System Settings ▸ Privacy & Security), for app menus
  and moving windows. Without it those two don't work; everything else does.
- **Automation**, asked for the first time you need it: to control the
  browser (going to a tab, a site's JavaScript commands) and Terminal
  (Git: Pull, lazygit, Homebrew, tasks, SSH). Until you allow it, the command
  tells you where to do that.

Chromium browsers (Brave, Chrome, Edge, Vivaldi, Arc) need nothing extra for
tabs, history and bookmarks. Safari's history and bookmarks are not read.

### Optional tools

Each one you have makes the launcher better, and none is required:
`fzf` (fuzzy matching), `zoxide` (folders you visit), `gh` (GitHub), `git`,
`fd`, `rg` (text search), `lazygit`, `brew`, an editor (`code`, `cursor`,
`zed`, `subl`), and the codicon font for icons
(`brew install --cask font-codicon`).

The extensions for Raycast, Maccy, GitHub and the VS Code bridge are switched
off by default because they need those tools. Switch one on in your
settings.json, e.g. `"raycast.enabled": true`.

Commands that run in a terminal use Terminal.app unless you set
`"terminal.application"` to `"wezterm"`, `"kitty"` or `"alacritty"`.

## Using it

```
alt+space          open
  cmd+p            files: recent ones first, then search
  cmd+o            command palette: everything you can run
  cmd+.            actions for what is in front of you
  cmd+r            recent projects, tabs, windows and apps
  cmd+k            what you can do with the highlighted row
  arrows, return   move, run
  escape           back one level, or close
```

Each chord is a shortcut for typing a **prefix**, as in VS Code: `>` for
commands, `files `, `recent `, `context `, `settings `, `keybindings `.
Type `?` to list every picker and how to reach it. Delete the prefix and
you're back to searching everything.

### Searching with what you typed

Some commands take what you type as their argument: web search, YouTube
search, and quicklinks.

- `? lofi beats` lists all of them with "lofi beats" filled in.
- `search lofi beats` or `youtube lofi beats` goes straight to one.
- In the main list, typing something that matches nothing offers them too.

Nothing runs until you pick it.

## Configuring it

Your files live in `~/.hammerspoon/commandlayer/`, outside the Spoon, so they can
go in your dotfiles and survive updates:

    ~/.hammerspoon/commandlayer/
      settings.json        your settings, over the shipped defaults
      keybindings.json     your keys, added after the shipped ones
      tasks.json           VS Code-style tasks, each a row
      sites/*.json         commands for one website
      extensions/*.lua     your own extensions
      profiles/<name>/     other profiles

Usually you won't need to edit them by hand. Type `settings ` in the
launcher to see every extension and setting, and pick one to flip it. It
saves just that value and keeps your comments. **Preferences: Open Default
Settings (JSON)** in the palette shows everything you can set, and so does
the generated [reference](docs/api.md).

If a file has a mistake (an unknown setting, a wrong value, a key bound to a
command that doesn't exist), the launcher shows it in one alert when it
loads, and the rest of the file still applies.

### Settings

```jsonc
// ~/.hammerspoon/commandlayer/settings.json
{
  // Completion and error underlining in VS Code
  "$schema": "file:///Users/you/.hammerspoon/Spoons/CommandLayer.spoon/config/settings.schema.json",
  "terminal.application": "wezterm",
  "prefixes": { "recent": "r ", "files": "f " },   // shorter prefixes of your own
  "browser.history": false,
  "rankers": { "relevance": 1, "specificity": 0.35, "frecency": 0.2, "alphabetical": 0 }
}
```

Rows are ordered by a weighted sum of how well they match what you typed,
how specific they are, and how often you pick them. Set `frecency` to 0 for
a list that never reorders itself.

### Keybindings

```jsonc
// ~/.hammerspoon/commandlayer/keybindings.json
[
  // VS Code's quick open navigation
  { "key": "cmd+e", "command": "quickOpen.selectPrevious" },
  { "key": "cmd+d", "command": "quickOpen.selectNext" },

  // move cmd+k to cmd+j: a leading "-" removes a default
  { "key": "cmd+k", "command": "-quickOpen.showActions" },
  { "key": "cmd+j", "command": "quickOpen.showActions" },

  // open file search directly
  { "key": "cmd+g", "command": "quickOpen", "args": { "query": "files " } },

  // any command, with arguments: here one item from Brave's menu bar
  { "key": "cmd+shift+n", "command": "appmenus.select",
    "args": { "app": "Brave Browser", "path": [ "File", "New Window" ] } }
]
```

Escape always steps back one level and can't be rebound.

To act on selected text from any app in one key -- Look Up, Search the web,
Copy -- bind Show actions globally:

```jsonc
{ "key": "alt+shift+space", "command": "selection.showActions", "global": true }
```

### Changing the entry key

The entry key is a global keybinding, so it works in every app:

```jsonc
[
  { "key": "alt+space", "command": "-quickOpen" },
  { "key": "cmd+space", "command": "quickOpen", "global": true }
]
```

(`cmd+space` also needs Spotlight's shortcut freed in System Settings ▸
Keyboard ▸ Keyboard Shortcuts ▸ Spotlight.) Or in `init.lua`, as with any
Spoon:

```lua
spoon.CommandLayer:bindHotkeys({ enter = { { "alt" }, "space" } })
```

### Profiles

A profile is a different set of settings and keybindings. `raycast` ships as
an example: one list, no picker chords. Switch with **Profiles: Switch
Profile…** in the palette, or set `cl.profile = "raycast"` before `start()`.
As in VS Code, a profile replaces your settings rather than adding to them.

### Pickers

Pickers are declared in settings, not code. This adds a `History ▸` row to
the main list that opens the rows on the `recent` menu:

```json
{ "views": [ { "name": "history", "title": "History", "menus": [ "recent" ], "parent": "root" } ] }
```

Add `"presenter": "popup"` to draw a picker as a native menu instead.

### Site commands

Commands that only appear while a website is in front, either as the site's
own keyboard shortcuts or as JavaScript run in the tab:

```jsonc
// ~/.hammerspoon/commandlayer/sites/github.json
{
  "name": "GitHub",
  "match": "github%.com/[^/]+/[^/]+/pulls",   // a Lua pattern over the URL
  "commands": [
    { "title": "Copy page title", "js": "navigator.clipboard.writeText(document.title)" },
    { "title": "Next file", "keys": "j" }
  ]
}
```

`keys` needs nothing. `js` needs the browser's **Allow JavaScript from Apple
Events** (Chrome and Brave: View ▸ Developer; Safari: Develop).

## Writing an extension

An extension is a Lua module. Keep it wherever you keep your Hammerspoon
code, e.g. `~/.hammerspoon/example.lua`, and hand it over in `init.lua`
before `start()`:

```lua
hs.loadSpoon("CommandLayer")
spoon.CommandLayer:addExtension("example", require("example"))
spoon.CommandLayer:start()
```

Or put the file in `~/.hammerspoon/commandlayer/extensions/`, where it's picked up
on its own, named after the file. Either way, one named like a shipped
extension replaces it. Installing someone else's extension is the same:
clone it anywhere Hammerspoon can `require` it, and add one line.

```lua
local M = {}

function M.extension(cl)
  return {
    name  = "example",                     -- the file's name: example.lua
    rank  = 0.29,                          -- how specific its rows are, 0 to 1
    menus = { "root", "commandPalette" },  -- which pickers show its rows

    -- Rows: things to pick.
    items = function(ctx)
      return {
        { label = "Example site", description = "Link",
          command = "system.open", args = { target = "https://example.com" },
          subject = { kind = "url", value = "https://example.com" } },
      }
    end,

    -- Commands: verbs with an id, which keys can bind and cmd+k can offer.
    commands = {
      { id = "example.hello", title = "Say hello", category = "Example",
        run = function(args, ctx) hs.alert.show("hi") end },

      -- Takes a url row: offered on cmd+k for any url, or asks for one.
      { id = "example.copyLink", title = "Copy link",
        inputs = { { id = "link", picker = { when = "viewItem == 'url'" } } },
        run = function(args, ctx)
          cl.executeCommand("system.copy", { text = args.link.value }, ctx)
        end },
    },

    -- Shown in the settings picker, read with cl.setting("example", "loud").
    settings = { loud = { type = "boolean", description = "Say it loudly", default = false } },
  }
end

return M
```

The ideas worth knowing:

- **Rows and commands.** Rows are the things you pick. Commands are verbs
  with a stable id, so keybindings, other extensions and `cmd+k` can reach
  them. A row runs a command with arguments.
- **Subjects.** A row's `subject` says what it is (a `url`, a `file`, a
  `project`…). Any command whose input takes that kind is offered on `cmd+k`.
  Extensions don't need to know about each other: the browser extension
  makes the page in front a `url`, and the git extension offers "Clone" on
  any `url` that looks like a repository.
- **Dispatch.** How things run is itself a command: `system.open`,
  `shell.run`, `terminal.run`, `editor.open`, `webview.open`. Call those
  rather than shelling out yourself.
- **Cleanup is automatic.** Timers, watchers and tasks started through `cl`
  are stopped when the extension stops or is switched off.

Every field, hook and `cl` member is in the generated
[reference](docs/api.md). How each part behaves in detail is in
[docs/behaviour.md](docs/behaviour.md).

## A picker's rows in your own menu

Hammerspoon code can show any picker's rows, for example as a menu bar icon:

```lua
local menu = hs.menubar.new()
menu:setTitle("⌘")
menu:setMenu(function()
  local items = {}
  for _, row in ipairs(spoon.CommandLayer.layer.rows("recent") or {}) do
    items[#items + 1] = { title = row.label, fn = row.run, disabled = not row.enabled }
  end
  return items
end)
```

`rows(view)` gives what the picker would open on; each row's `run()` does
what picking it does.

## What ships

Every extension, as it describes itself, with the verbs it offers on `cmd+k`.
Those shipped off need a tool not everyone has; `"<name>.enabled": true`
switches one on.

<!-- extensions: generated by lua tests/reference.lua -->

| Extension | What it is | On cmd+k | As shipped |
|---|---|---|---|
| `ambient` | The app in front, the clipboard, this Mac's name and whether it is online, as context keys |  | on |
| `applescript` | Run an AppleScript |  | on |
| `appmenus` | App menus | Copy menu path, Run menu item | on |
| `apps` | Every installed app, and the ones you used recently as macOS keeps it: launch, focus, hide, quit | Hide, Launch or focus, Quit, Reveal in Finder, Toggle | on |
| `audio` | Switch the sound output and input device, and mute the microphones |  | on |
| `brew` | brew update, upgrade, outdated, doctor, cleanup, install, search and info, in the terminal |  | on |
| `browser` | Tabs, bookmarks and history from the browsers' own files; site commands while a page is in front | Back 10 seconds, Captions, Copy URL, Forward 10 seconds, Full screen, Go to tab, Mute, Next video, Open in browser, Open in new tab, Theatre mode | on |
| `calculator` | Arithmetic typed into the field, answered by bc | Copy | on |
| `codicons` | VS Code's $(icon) names, drawn from the codicon font |  | on |
| `context` | What is in front of you as subjects: Finder's selection, the clipboard | Copy title, Run | on |
| `developer` | Show the log and set how much reaches it, see where the time goes, and inspect the context |  | on |
| `editor` | Open a file or folder in the editor you have |  | on |
| `files` | File search through Spotlight, recent files, and the verbs on a file, folder or project | Copy path, Open, Open in editor, Open in terminal, Reveal in Finder | on |
| `finder` | Finder's selection, read in a task, as context keys |  | on |
| `git` | Git commands on a repository: pull, push and checkout in the terminal, the rest in a task | Apply stash…, Checkout…, Clone repository, Create branch…, Delete branch…, Drop stash…, Fetch, Fetch (prune), Fetch from all remotes, Init, Merge branch…, Pop latest stash, Pop stash…, Publish branch, Pull, Pull (rebase), Push, Rebase branch…, Rename branch…, Stash, Stash (include untracked), Sync, Undo last commit | on |
| `github` | Your repositories, pull requests and issues through gh |  | off |
| `grep` | Text in a folder or a file, searched with ripgrep as you type | Search Text in… | on |
| `hammerspoon` | Reload Hammerspoon, open its console, preferences and config |  | on |
| `help` | Every picker there is a way to, and how, in the ? picker |  | on |
| `icons` | Icons for rows: apps' own, System Settings', and a theme icon's |  | on |
| `keepawake` | Keep the Mac awake through caffeinate, and say what else is keeping it awake |  | on |
| `keybindings` | Every keybinding in effect, in the Keyboard Shortcuts picker, removed or changed in keybindings.json | Change Keybinding…, Remove Keybinding | on |
| `lazygit` | Open a project or folder in lazygit, in the terminal | Open in lazygit | on |
| `maccy` | Maccy's clipboard history, opened in its own window |  | off |
| `media` | Play/pause, next and previous track in whatever is playing, as the media keys do |  | on |
| `processes` | The processes running, busiest first, updated while the picker is open; Quit and Force quit | Force quit, Quit | on |
| `projects` | Recent projects from VS Code's Open Recent list, then zoxide |  | on |
| `quicklinks` | Links you name in settings, and searches with what you typed in their URL | Copy URL | on |
| `raycast` | Raycast's deeplinks as rows, and its script commands in scripts |  | off |
| `rerun` | Run a command picked before again, with the arguments it had |  | on |
| `secureinput` | Notice when macOS's Secure Input would drop the keys a command presses, and say which app holds it |  | on |
| `selection` | The text selected in the app in front, read through Accessibility: Look Up, search, copy | Copy, Look Up, Search the web | on |
| `settings` | Every extension and the switches each declares, flipped in the settings picker |  | on |
| `shell` | Run a command line |  | on |
| `shortcuts` | Your Shortcuts, each run through the shortcuts command |  | on |
| `snippets` | Raycast's snippet search |  | on |
| `spoon` | Call another Spoon, or open a fallback when it is not loaded |  | on |
| `spoons` | The other Spoons loaded, their methods to run, and every Hammerspoon hotkey to press |  | on |
| `ssh` | The hosts in ~/.ssh/config: ssh in the terminal, or a remote window in the editor | Connect in editor, Connect in terminal | on |
| `system` | Open and reveal things, Open With, lock the screen, macOS's Emoji & Symbols and its screenshots | Open with… | on |
| `systemsettings` | System Settings | Copy URL, Open pane | on |
| `tasks` | The tasks in tasks.json beside settings.json, run in the terminal |  | on |
| `terminal` | Open a folder, or run a command line, in the terminal you choose |  | on |
| `url` | A typed URL: open it, or cmd+k for Open with…, Copy URL and the other link verbs |  | on |
| `urlhandler` | Run a command from a hammerspoon://commandlayer URL |  | on |
| `vscode` | VS Code | Open file at line…, Open in VS Code, Open in VS Code (new window) | on |
| `vscodebridge` | Commands answered by the Command Layer extension in VS Code; switch this on once it is installed |  | off |
| `webview` | Show a page, some HTML or a file in a window of its own |  | on |
| `wezterm` | WezTerm's panes as rows, each focused when picked; needs WezTerm |  | off |
| `windows` | The windows on screen, focused or moved through hs.window or a window manager | Bottom half, Bottom left, Bottom right, Centre, Close, Focus, Full screen, Left half, Left third, Left two thirds, Maximise, Middle third, Minimise, Next screen, Previous screen, Right half, Right third, Top half, Top left, Top right | on |
| `workbench` | Open the settings and keybindings files, switch profile, list problems, and forget what was picked | Remove from Recently Used, Reset Setting | on |
| `yabai` | yabai's spaces as rows, each focused when picked; needs yabai |  | off |
| `zoxide` | Folders you visit, ranked by zoxide; folders opened here are added to it |  | on |

<!-- /extensions -->

## How it's built

    commandlayer.lua   loads the kernel
    core/              the kernel: registries, context, `when`, the picker stack
    config/            shipped settings, keybindings and profiles
    extensions/        everything there is to run
    matchers/          which rows a query keeps (fzf, substring)
    rankers/           what order they come in
    presenters/        how a picker is drawn (hs.chooser, or a native menu)
    docs/              the generated reference, and how each part behaves

The kernel knows nothing about the world. Which app is in front, what's on
the clipboard, what a project or a terminal is all comes from an extension,
and any extension can be switched off.

## Development

```bash
lua test.lua
```

This runs the harness. It stubs `hs.*`, loads the launcher outside
Hammerspoon and runs about a thousand checks. Run it before any change.
Anything that talks to macOS still needs a real reload of Hammerspoon to
test. [CLAUDE.md](CLAUDE.md) holds the rules a change has to follow, and
[ROADMAP.md](ROADMAP.md) what is left to do.

## The VS Code extension

The launcher doesn't need anything installed in VS Code: it uses the URLs a
stock install answers, the `code` command and VS Code's menu bar. The
optional companion extension `saemeon.command-layer`, kept outside this
repository, adds four rows (Find in files, Go to file, Run task…, Run
command…) once `"vscodebridge.enabled": true` is set.

## License

MIT, see [LICENSE](LICENSE).
