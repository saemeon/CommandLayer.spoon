# Why it is built this way

The arguments behind the shape, including the ones that turned out to be
wrong. The shape itself — what the folders are, what an extension
declares — is in `CLAUDE.md`; this is only the reasoning, kept so the
next person does not re-derive it or repeat a mistake already made.

## The goal

A launcher of our own, shaped like VS Code: one palette you enter with a
chord, commands contributed by extensions, prefixes that switch what the
palette lists, keybindings that carry arguments, and verbs for whatever
is in front of you.

It gets there by routing, not reimplementing. What macOS, a Spoon or a
CLI already does is reached, not rebuilt -- so the launcher is mostly a
registry, a context model and a palette, and every capability comes
from somewhere that already has it.

## Commands without going to where they live

Most commands belong to some context. `git init` and `git clone` are in
VS Code's palette or a shell; a tab is in the browser; a layout is in a
window manager. Running one means entering that context first -- open
the window, find its palette, type, pick, close it again -- only to call
one command.

The palette collects those commands from every context and makes the
context itself its job: it knows what is in front, asks for what is
missing (a folder, a repository), runs the command where it belongs, and
puts you back where you were. It is a context manager in Python's sense
-- a `with` block whose setup and teardown surround the one call you
wanted, so you never write them out by hand.

## Why not an existing launcher

Raycast and Alfred are good, and this is not a bet that it can match
their polish. It is a bet on a different shape:

- **Yours, as text.** Settings and keybindings are JSON files, as VS
  Code's are, and extensions are Lua files: diffable, reviewable, movable
  to another machine with `git clone`. A settings picker writes the same
  files, changing one value and nothing else, so it is never state behind
  a preferences window.
- **Every part replaceable.** Their extensions add commands to a palette
  they own; how rows are matched and ranked, how the list is drawn, what
  a key does to the selection is theirs. Here each of those is a file,
  and a second profile can be a different launcher.
- **Context first.** What is in front of you -- the app, the Finder
  selection, the clipboard, the browser tab -- is one model every
  extension shares, and verbs come from the subject, not from a list
  someone curated. Elsewhere context is an API an extension may call,
  not what the palette is built around.
- **One keyboard grammar with the editor.** The same prefixes, `cmd+k`
  for actions, the same command ids and keybindings file as VS Code's
  Quick Open -- and a held modifier whose sub-chords switch pickers, which
  a launcher app does not offer.
- **Rides macOS instead of its own stores.** Snippets are
  Raycast's, app commands are the menu bar, files are Spotlight, so
  nothing you depend on is locked inside the launcher.
- **Cheap to extend.** An extension is one file returning a table: no
  build step, no store, no framework.
- **Made to be changed by an AI agent.** Every part -- profiles,
  extensions, the kernel itself -- is plain text, and a harness checks it
  without Hammerspoon running. "Add a picker for my Linear issues" is
  something an agent can write, verify and hand back as a diff, which a
  preferences window and a compiled extension store do not allow.
- **No account, no licence, nothing leaves the machine.**

The trade-offs are real: the palette is `hs.chooser`'s list and no more,
and there is no store. The long tail of service integrations is reached
rather than written. Each launcher compared, with what was taken from it,
is in `PRIOR_ART.md` at the root of the repository.

## What it reaches

Each row is an extension, and each reaches something that already exists.
Raycast is one of them, no more central than the rest.

| What | Through |
|---|---|
| Apps, and which you used last | Spotlight, an activation watcher |
| Every app's menu bar | Accessibility (`getMenuItems`) |
| System Settings panes | the ExtensionKit bundles macOS ships |
| Snippets | Raycast's snippet search, `raycast://` |
| Files | Spotlight |
| Folders you visit | zoxide, which the launcher also tells |
| Browser tabs | Chromium's session files; AppleScript where there are none |
| Browser history and bookmarks | Chromium's SQLite and JSON |
| Clipboard history | Maccy's window |
| Arithmetic | `bc` |
| Projects | VS Code's Open Recent list, zoxide |
| Git | the `git` CLI, in the repository |
| VS Code: folders, and any of its commands | the `code` CLI; `vscode://` URLs into VS Code's own extensions and the Command Layer VS Code extension |
| GitHub repositories, PRs, issues | `gh` |
| Shortcuts | the `shortcuts` CLI |
| Windows | Hammerspoon's window filter; moves through Raycast, Rectangle, yabai or AeroSpace when chosen |
| A command in a terminal | Terminal.app's `do script`, under Automation; WezTerm, kitty or Alacritty when chosen |
| Locking the screen, Emoji & Symbols | `hs.caffeinate`, macOS's own chord |
| Raycast's extensions -- Linear, Jira, Spotify | `raycast://` deeplinks |
| A web page in a window of its own | `hs.webview` |

VS Code is reached in both directions: the palette here can run any VS
Code command through its URL handler, and the VS Code extension is the
same idea -- trigger, resolve, dispatch -- inside the editor.

## Contribution points

VS Code names what an extension may add under `contributes.*`, and each
name says where it shows up. The same list here is the whole of what an
extension can do to the launcher, so a feature that fits none of them is
a sign the model is missing a point, not a reason to reach past it.

| Point | Declares | VS Code | State |
|---|---|---|---|
| commands | `commands = { { id, title, category, icon, when, enablement, inputs, run or command and args, menus } }`, registered by id and run with `executeCommand`; how a thing runs is a command too (`system.open`); one taking the typed text may declare its own `prefix` | `commands` | exists |
| inputs | `inputs = { { id, description, picker = { options, menus, when, kind, search, typed } } }`, or `{ id, command, args }` | `inputs` in tasks and launch configs, without `type`; `picker` is ours | exists |
| menus | `menus`: which pickers a row appears in, each with its own `when` | `menus` | exists |
| views | quick access providers, declared in settings: `prefix` (one or a list), `parent`, `menus` or one text `command`, `kind` -- chords are keybindings; rows with `submenu = "view"`; an extension feeding one hears `left` as its level comes off the stack | `quickAccess` providers, `viewsContainers` | exists |
| keybindings | a list of chord, control or command, and args | `keybindings` with `args` | exists; any registered command can be bound |
| `when` clauses | `when = "frontmostApp == 'Finder' && !clipboard"` on any command: a string over context keys | `when` | exists |
| context keys | fields for `ctx`, from `capture` | context keys set with `setContext` | exists |
| subjects and verbs | `subjects`; a verb is a command taking a row (an input whose picker has a `when`), on cmd+k through `view/item/context` | `view/item/context` menus | exists |
| query rows | rows made from typed text, from `query` | a quick access provider's filter | exists |
| text commands | commands taking the typed text: a picker's `textCommands`, `fallback` when nothing matched, `first` before its own matches | none; Alfred's fallback searches | exists |
| configuration | `settings = { key = { type, description, default, enum } }`, read with `cl.setting(ext, key)` | `configuration` | exists |
| matchers, rankers, presenters | which rows a query keeps, their order, how a picker is drawn | the workbench itself | exists, as folders rather than extension hooks |

Subjects and verbs are the row with no VS Code equivalent, and that is
the point of the launcher: VS Code knows its subject is always the
active editor, while here the subject is whatever is in front of you,
and verbs attach to its kind rather than to a menu someone keeps.

`when` replaces the hand-rolled checks -- `ctx.frontmostApp == "Finder"`
inside a hook -- with a declaration the kernel evaluates. A declared
condition can be listed by `?`, tested by the harness, and skipped
without running the extension's code at all.

`cl.setting` falls back to the declared `default`, so an extension never
sees a missing key.

The last row is not contributed by extensions. Matchers, rankers and
presenters are folders a profile chooses among, since two
extensions disagreeing over how a row is ranked has no sensible answer.

### The typed text as an argument

Typed text does one of two things today: it filters rows, or a `query`
hook consumes it and makes rows of its own, as the calculator does.
Quicklinks sit awkwardly beside both: you type "foo", find the quicklink
by its name, pick it, and are then asked for "foo" again.

One flag on an input answers it. An input may declare `fromQuery = true`.
While the field is non-empty, that input is pre-answered with the typed
text, with a view's prefix already stripped, and the row's title can show
it through a `${query}` template:

```lua
{ id = "browser.searchWeb", title = "Search the web for “${query}”",
  inputs = { { id = "query", picker = { typed = true }, fromQuery = true, encode = "query" } },
  command = "system.open",
  args = { target = "https://search.brave.com/search?q=${query}" } }
```

- Picking such a row runs it at once, with no second prompt. With an
  empty field the input is asked for as usual, so the same command
  works from a chord.
- In an ordinary picker they are shown only while there is typed text,
  and placed after real matches: the text is an argument to them, not
  something they matched. When nothing matches they are what is left,
  which makes them **fallbacks** in Alfred's sense without a separate
  mechanism.

Fallbacks alone are not a way in. Over thousands of rows fuzzy matching
nearly always keeps something, so "nothing matched" hardly happens and
the search sits under rows that matched by accident. Two things reach
these commands directly:

- **`?` with text after it.** `? lofi beats` lists every command that
  takes text, each with the rest of the field as its argument -- "Search
  Brave for “lofi beats”", "Search YouTube for “lofi beats”" -- first,
  then the pickers the text matches. Bare `?` is help, VS Code's list of
  pickers. This was a separate `!` view once; with nothing typed the two
  were the same question, "where can I go from here", so they merged. It
  is a declared picker with `"textCommands": "first"`, the root's fallbacks
  being `"textCommands": "fallback"`: the kernel offers the text commands
  either way, and the list of pickers is the help extension's rows.
- **A command's own prefix.** A command that takes text may declare
  `prefix = "yt "`. Typing `yt lofi beats` shows that command alone,
  already filled in, and return runs it. It is a view's word prefix
  (`files `) on a single command: the space commits, so `yt` alone still
  searches, and the longest prefix wins. This is the part Alfred's
  keywords, DuckDuckGo's bangs and Raycast's quicklink aliases play.

There is no default text command, and no chord such as `cmd+return`
that runs one. Which command a bare chord sends the text to would be a
choice made out of sight; `?` shows the same choice for one keystroke.

The browser contributes web search and YouTube search, and every quicklink
with `${query}` in its URL is one more.

Why this shape: quicklinks, the calculator's query rows and fallback
searches become one model -- a command with an argument the field may
already hold. It is also how VS Code's quick open works, where the text
after a prefix is handed to the provider as its argument rather than
matched against labels.

### `when` clauses

A `when` is VS Code's syntax: a string expression over context keys.

```lua
when = "frontmostApp == 'Brave Browser' && url =~ /youtube%.com%/watch/"
when = "url =~ /youtube%.com/ || url =~ /youtu%.be/"
when = "finderSelection && !clipboard"
```

The subset is `==`, `!=`, `=~`, `!`, `&&`, `||`, parentheses, a bare key
meaning the key is set, and VS Code's `in`, `not in` and numeric `<`,
`<=`, `>`, `>=`. The keys are the `ctx` fields extensions
capture -- `frontmostApp`, `frontmostAppID`, `url`, `pageTitle`,
`finderSelection`, `clipboard` and the rest -- so a key whose extension
is absent is simply unset.

A string rather than a Lua table, because "either of these" and "not
this" then compose with no table shape invented for each, and anyone
who has written a VS Code keybinding already reads it. There is one form
only, with no table shorthand beside it; the kernel parses each clause
once and caches it, and the harness tests the grammar.

`=~` takes a Lua pattern, and that is fixed: `.` is written `%.`, and a
slash inside the pattern `%/`. It is not a plug point and there is no
replaceable pattern engine, because what a clause means must never
depend on what is installed.

Not regex, because regex would buy little here:

- A clause copied verbatim from VS Code would not work anyway: its keys
  -- `editorLangId`, `resourceExtname` -- do not exist here. The
  operators stay VS Code's either way; only the pattern inside the
  slashes differs.
- What a Lua pattern lacks is alternation, repeated groups and counts.
  For matching an app or a URL, the clause's own `||` covers those.
- A regex engine is code to maintain, run on every keystroke, and a
  class of engine bugs, for no gain in practice.

If real regex is ever needed, it gets an operator of its own, so no
existing clause changes meaning.

### Site commands

Site commands are configuration of the browser extension, not a
mechanism of their own. The extension contributes:

- the context keys `url` and `pageTitle`, for the front tab;
- two backends. `browser.keys` brings the tab forward and presses the
  site's own shortcut -- YouTube's `k` to pause, `f` for full screen.
  `browser.js` runs JavaScript in a tab through AppleScript, and needs
  the browser's "Allow JavaScript from Apple Events", which is off by
  default;
- sites as data. A site is a name, a `match` pattern and its commands,
  each with `keys` or `js`, written in JSONC. The shipped sites live with
  the browser extension (`extensions/browser/sites.jsonc`), and the user's
  own go in `~/.config/commandlayer/sites/`, so adding one needs no code
  and loading one runs none.

Prefer keystrokes wherever the site has a shortcut: they need no
permission, and they are what the site itself supports, so they survive
its markup changing. JavaScript is for what has no shortcut, and it can
reach background tabs.

A site that needs real logic is an ordinary extension. Because `when` is
general, it writes `when = "url =~ /github%.com/"` and dispatches to
`browser.js`. It relies only on the browser extension being present, and
on no browser-specific API.

### Decided

- Fallbacks need no hook of their own: they are commands with
  `fromQuery`, shown after the matches. `?` with text and a command's own
  `prefix` are how those commands are reached on purpose.
- `when` composes inside the expression, with `&&`, `||`, `!` and
  parentheses, rather than through rules about which keys must match.
- `=~` takes a Lua pattern, fixed rather than a plug point. Real regex,
  if ever needed, gets a distinct operator.
- Site commands are data the browser extension reads, and its two
  backends; a site with logic is its own extension using `when` and
  `browser.js`.
- Decided against: a default text command bound to a chord such as
  `cmd+return`. The user wants no implicit default.
- Decided against: a regex engine for `=~`, replaceable or default.

## Settings as VS Code has them

The shipped settings and chords are `config/defaults.jsonc` and
`config/defaultKeybindings.jsonc`; a person's are `settings.json` and
`keybindings.json` in `~/.config/commandlayer/`, outside the repository,
because a setting is a machine's answer. The arrangement is VS Code's on
purpose -- the same file names, the same merge, the same command ids to
open them -- so nothing has to be learned twice.

- **JSON rather than Lua.** A settings picker writes these files back,
  and rewriting a person's Lua would lose what they wrote. JSON with
  comments can be edited in place: a write changes one value where it
  stands, and comments, order and layout survive, as they do under VS
  Code's settings editor.
- **Profiles switch, they do not stack.** A profile is a folder with its
  own two files over the defaults; under another profile the default
  profile's files are not read. Stacking made every profile a patch to
  the one before, and "which file set this" unanswerable.
- **The kernel binds no chord.** Which keys move and open is a
  preference, so it lives in keybindings files like any other; the
  shipped file has the pickers' chords and `cmd+k`, which every launcher
  has.
- **A mistake is shown, once.** A setting that does not exist, a value
  it cannot take, a keybinding to no command -- each was a console line
  nobody read, and most silent failures here were exactly that. They are
  collected while the files are read and shown in one alert, and the
  rest of the file still applies.

## Commands that take a thing

`git init` needs a folder; a layout needs a window; Open in terminal needs
a path. Written as per-source verbs, the same command was copied onto
projects, zoxide's folders and Finder's selection, and still missing from
file search. Written as a command with an input that says what it takes --
a `when` over a row's kind, `viewItem == 'folder' || viewItem ==
'project'` -- one declaration gives both ways in: picked from search it
asks which, and cmd+k on any row that kind offers it with the row given.
That is VS Code's `view/item/context` menu, generated rather than written.

The kind is a `when` rather than a type system because the question is
already "does this row qualify", and a clause can ask more than the kind:
`gitRepository`, worked out per row, is what separates Pull from Init.
And a command run from a chord, or picked while something is in front,
takes that thing (`preferCurrent`), so "Left half" plus return moves the
window you were in, and cmd+k is how to choose another.

## The core idea

VS Code's Command Layer worked because VS Code hands you two things for free:

1. **A command registry** — thousands of named, invokable actions, contributed
   by the editor and every extension you have installed.
2. **A context model** — the active file, the selection, the language, the
   workspace, all queryable at the moment a trigger fires.

The extension itself did almost nothing. It resolved arguments from context and
dispatched a command id. All the capability came from elsewhere.

macOS gives you the context model — frontmost app, Finder selection, clipboard,
window state. The command registry looked like the missing half.

That was half wrong, and worth recording as the most useful mistake in this
document. macOS *does* ship a registry of named, invokable actions per app:
the menu bar. `hs.application:getMenuItems()` reads it and `selectMenuItem()`
runs it, which makes every menu item of every installed app dispatchable with
no per-app configuration. That is the direct analogue of `fetchVSCodeCommands`,
and it was sitting in plain sight for the first several iterations of this.

What remains true is that no *single* registry covers the machine, so the
design question stands: **what plays the role the VS Code command registry
played?** The answer is several things at once, the menu bar among them.

## The answer: assemble one

Not a single backend. A registry assembled from everything on the machine that
already exposes callable functionality.

Almost every serious Mac tool exposes an API of some kind — a CLI, a URL
scheme, an AppleScript dictionary, a socket. Each is a slice of a command
registry that nobody has bothered to unify. That's the gap this layer fills:

| Surface | Examples |
|---|---|
| URL scheme | Obsidian, Things, Spotify, Raycast |
| CLI | `shortcuts`, `gh`, `wezterm cli`, `yabai`, `op`, `docker` |
| AppleScript | Safari, Chrome, Finder, Music, Mail |
| Shell | anything else |

Hammerspoon is the **trigger and context layer**. It is good at knowing *when*
something should happen and *what the situation is*, and mediocre at nearly
everything downstream — its list UI is one flat column, its file search is
`mdfind`, it has no service integrations.

So it shouldn't own execution. It should route.

## Fuzzy matching belongs to fzf

`hs.chooser` filters on plain substrings. That's the difference between a
picker that feels like VS Code and one that doesn't — typing `ovc` should find
"Open in VS Code", and substring matching never will.

Rather than implement fuzzy matching and scoring, pipe candidates through
`fzf --filter=QUERY` on stdin and read back the ranked order. fzf is a mature,
tuned matcher that already exists on the machine. Same principle as the
backends: don't own what something else does better.

This also leaves the door open to fzf's *interactive* mode for cases where its
UI beats `hs.chooser` — spawning a WezTerm window running `fzf` and reading the
selection back is a legitimate picker backend, not a hack.

## Interaction model

Entering the layer opens the root picker immediately. No invisible armed state,
no timeout needed — the layer is visible the whole time it's active, and closing
the picker leaves it.

```
alt+space          root picker: everything applicable right now
  cmd+p            file search
  cmd+o            command palette
  cmd+.            context actions
  cmd+r            recent apps and projects
  cmd+k            actions for the highlighted row
  esc              back one level, or leave
```

`cmd+k` is the verb/noun split. The root picker lists *things* — apps,
projects, files, settings panes — and pressing return does the obvious
thing with one. Everything else you might do with it lives behind cmd+k,
so "Open in terminal" is one command that asks for a path, not a root
entry for every project you own. Each row carries a `subject` saying what
it is; cmd+k asks the subject, not the row's title.

Cmd stays held throughout. The sub-pickers are refinements of the root, not
separate destinations you have to decide about before you start.

Modal chording is the reason Hammerspoon is in this stack at all.
Everything else about Hammerspoon is a compromise. So lean hard on
chording and delegate the rest.

## Pickers as data

A picker is a declaration: how it is reached -- a prefix, a `quickOpen`
chord, a parent it is a row in -- where its rows come from -- the menus
extensions feed, or one text command -- and a few flags (`kind`, `sections`,
`recentlyUsed`, `textCommands`, `compact`). No field of it is code, so a
profile composes pickers freely, and a person's settings.json can declare
any picker the Spoon ships. Kinds: `list` narrows the rows it gathered as
you type, `search` asks the extensions' search hooks again, and `item`
offers the verbs on the subject it is given, which is what cmd+k is.

A subject goes in and comes out, and nothing else says what a picker is
about: a picker may be given a subject -- cmd+k's is the highlighted row's --
and picking in a command's question hands the row's subject back as the
answer. There is no `about` field.

The kernel keeps the registries (commands, menus, pickers, keybindings,
settings), the context and `when`, and the loop: the stack, matching,
ranking, presenting, a subject in and out. Everything that knows the world
or builds rows is an extension. `?`, settings and keybindings are extensions
feeding menus from read-only copies of the layer's lists; an extension that
starts something for a picker stops it in `left`, heard as that picker's
level comes off the stack. A Lua file in `views/` is a problem rather than
run, so a picker that stopped working says why.

## Which pickers ship

A picker earns its place by showing what the root cannot, or by being where
one kind of work is done. The set:

- **root**, the entry: everything applicable now, opening on the top of the
  context picker, recent projects and recent windows.
- **palette** (`>`, cmd+o): every command, and nothing else. Where the root
  is ranked by what is in front, the palette is predictable -- the same
  command is always there under the same name, with its chord beside it.
- **recent** (cmd+r): for discovering history. It lists the things you
  used, including the ones whose name you no longer remember: an app you
  installed, used once and quit is found under "Recent apps" without
  knowing what it was called. And since it is opened on purpose rather than
  on every entry, it is where slower, fuller history sources belong --
  every window, say, rather than only the visible ones -- which the root
  cannot afford to gather each time it opens.
- **context** (cmd+.): what applies to the app in front. An app's menu
  items alone run to hundreds, and in the root they would flood every
  search.
- **files** (cmd+p) and **grep**: each asks another program again as you
  type -- Spotlight, rg -- which the root must not do on every keystroke.
  grep has no prefix: "Search Text in…" chooses its place first.
- **The tools**: settings, keybindings, help (`?`) and actions (cmd+k).
  Each edits or explains the launcher itself, or acts on one row, with rows
  no other picker has. All four are declarations; the rows of the first
  three come from extensions of the same names, which read the layer's own
  lists as copies of a documented shape -- the pickers, the keybindings, the
  setting declarations -- and change anything only through the API, so the
  launcher's own tools are built the way anyone else's would be.

Dropped on September 15: `windows`, `browser` and `git`. The first two were
the root narrowed to one extension -- the root already lists windows and
the front browser's tabs, and opens on recent windows, and `recent` has
every running browser's tabs. Git was a submenu, "Git ▸", adding a level
without adding anything: its commands are palette rows found by typing
"git", and verbs on a project's or folder's cmd+k. Each extension still
contributes its rows to the pickers that stayed.

## Recents: track what nothing else tracks

**Recent apps.** macOS keeps this in a binary `.sfl2` plist that is awkward and
version-fragile to parse. An `hs.application.watcher` recording activation order
is less code, more reliable, and more accurate to how you actually work. It
persists through `hs.settings` and seeds from running apps on load, so the list
is useful immediately rather than after a warm-up period.

**Recent projects.** The first instinct was to scan for `.git` directories.
Wrong: `zoxide` is already installed, already tracks every directory you visit,
and already ranks them by frecency. Scanning throws that ranking away and
returns an unordered dump.

So projects come from VS Code's own Open Recent list first, then
`zoxide query --list` filtered to git repositories, with the frecency order
left intact. `~/.z` and a `find` scan remain as fallbacks, chosen
automatically by what's present. The launcher tells zoxide about a folder
opened here, so its ranking learns from the palette as well as from `cd`.

This is the delegate-everything rule applying somewhere it wasn't obvious it
would: frecency ranking for projects is something zoxide already did. For
what you pick in the palette, where nothing external keeps count, the
ranking is zoxide's algorithm, copied rather than invented.

Both apps and projects land in one list, the recent picker, because looking
through what you used doesn't distinguish between them — though each is
emitted by the extension that owns it rather than by a module that knows
about both.

## Where the boundary sits

Roughly: **own the routing, delegate the capability.**

Keys, windows, context detection, chord handling — Hammerspoon, natively.
Nothing else does these as well.

Anything with an API, auth token, refresh cycle, or a UI worth more than a flat
list — delegate. Writing one Linear client is a weekend. Writing five is a
second job, and extension stores already have them.

The awkward middle is the browser. A launcher app can ship a browser
extension; Hammerspoon has per-browser AppleScript that's decent for Safari and the
Chromium family and absent for Firefox. Mostly it turned out not to be needed:
Chromium keeps history and bookmarks on disk in SQLite and JSON, and its open
tabs, with when each was last active, in its session files.

## Dispatch, stated exactly

A feature dispatches to a tool that already does the work, and implements
no command logic of its own. Two things are not command logic: reading the
environment -- a browser's session file, VS Code's recents, the apps and
windows there are -- and the launcher's own machinery, such as ranking.
Anything needing state or an algorithm of its own is routed to a tool, or
dropped.

Held against the shipped code, the rule put arithmetic in `bc -l`, snippets
in Raycast's snippet search, the window focus order in `hs.window.filter`'s
own `sortByFocusedLast`, tab recency in the session file's last-active times
alone, cloning in `gh repo clone` into a folder from `git.cloneRoots` or a
dialog (never a guessed folder, never a URL built here), and System
Settings' pane names in the panes' own plists. Quicklinks stay, being
configuration rather than logic.

Two things are kept although they are ours, because nothing else holds
them:

- **App-usage history.** No tool keeps an app-activation history, and it is
  what finds an app you quit by a name you forgot. `lsappinfo`'s
  front-to-back order with Spotlight's last-used date may one day replace it.
- **Frecency.** Nothing outside counts what is picked in the palette. The
  algorithm is zoxide's, copied rather than invented.

Dropped under the rule, each needing state the launcher would have to keep:
window undo, running a layout again to cycle sizes, nudges and repeatable
moves, "screen left" by position rather than display order, Maximise
toggling back, saved multi-app layouts, and text converters (time, base64,
JWT, colour, case, URL-encoding, JSON). Window moves go instead to a
provider chosen by `windows.provider` -- Raycast, Rectangle, yabai,
AeroSpace, or `hs.window` for the plain layouts -- and a move the tool has no
action for is no command.

## The terminal

One terminal, `terminal.application`, Terminal.app by default because every
Mac has it. A command reaches Terminal.app only through its own scripting,
`do script`, which needs Hammerspoon allowed under Automation. A refusal is
said once, with where to allow it, and nothing else is tried: typing into a
window through System Events or keystrokes would be a workaround around the
permission macOS asks for, and fails where nobody sees it.

## What ships, and on which key

The entry chord is alt+space, what Raycast and Alfred ship with, so a
launcher's user already has it under their fingers. cmd+space is
Spotlight's, and taking it means changing a system setting before the
launcher works at all.

Everything on by default should make sense on a machine that has only
macOS, Hammerspoon and the tools the kernel lists. So extensions needing a
tool not everyone has -- Raycast, Maccy, `gh`, the VS Code bridge -- ship
switched off, rather than as rows that open nothing. That is also why a
profile has no `viewsOnly` list: the defaults stay lean, shipping only the
pickers that add something (Which pickers ship), and one nobody wants is
removed with `"enabled": false`.

## Fast where it is felt

Opening a picker and typing must stay snappy; starting may take longer. The
logging follows that. A span on the picker path over
`performance.slowMilliseconds` is a warning. A task or a cache waits on
another process, off the main thread, so however long it takes it slows
nothing on screen: its slow line is `debug`, since as warnings they buried
the ones about opens and keystrokes. Setup and start write their summary at
`debug` too.

Measured on September 15, over about ten reloads and opens: no open or
keystroke passed 250 ms. Start spent 1.3-2.9 s in `activate.windows`,
building `hs.window.filter` on Hammerspoon's one thread, which is the next
thing to move off start.

## Declined, and why

From the September reviews, so they are not proposed again:

- **Right-click on a row for its actions.** The launcher is keyboard only.
- **A fuzzy matcher of our own** between fzf and substring. fzf does it
  well.
- **Splitting the browser extension.** The browser is one extension; its
  session-file reader is a helper file of it.
- **Machine-scoped settings.** A setting is already a machine's answer: the
  files live outside the repository.
- Declined with no reason given: pins in the root, "Add keybinding…" on a
  command row, showing the matched alias ("Title (lh)"), patterns with
  captures over the clipboard, a URL or the selection (`ISSUE-(\d+)` opening
  a tracker), a next-meeting context key, coverage with luacov, and a live
  smoke run through `hs -c`.
- **Reading the selection with cmd+c** where accessibility has none. It
  would overwrite the clipboard, so Electron apps and browsers have no
  selection.
- **Browser automation beyond selecting a tab.** Going to a tab is Apple
  Events and a site's `js` is too; nothing else is. Turned down on the way
  there: `chrome-cli`, which wraps the same Apple Events and would be one
  more install; Raycast as a hand-off, which lands the tabs in Raycast's
  picker rather than ours; and a Raycast extension of our own calling
  `BrowserExtension.getTabs()`, which is the only way to reach Raycast's
  browser extension from outside and means a headless round trip through two
  apps on every open, to replace a session file we already read with no
  permission. What that last one would add -- Safari and Arc, a list current
  to the moment, page content without the Apple Events JavaScript switch --
  is written down in ROADMAP.md, for the day one of them is felt.
  Hammerspoon has no browser module: the request (issue #144, 2014) was
  closed with nothing built, because the script is ten lines and the hard
  parts are permissions and coverage.
- **Tab completion** in the picker (C5), filling the field from the
  highlighted row. VS Code's Quick Open has no such key, and the arrows and
  a prefix already get you where tab would.
- **Two-part chords** (D6), `cmd+k cmd+s`. That is VS Code's keybindings
  feature, not its palette; one chord per entry is what is needed here, and
  `M.chordId` is built on that.
- **Cycling an app's windows** (I10). It means keeping our own place in a
  list between presses, which is state rather than dispatch, and macOS
  already has cmd+` for it.
- **Learning tied to what was typed** (E5): a count per typed prefix and
  row, so "ca" would learn Calendar. Frecency already learns the row; a
  second history keyed by text is a second thing to explain when the order
  surprises you.
- **lazygit's recent repositories** as a source of projects (I16). VS Code's
  recents, zoxide and the project roots already find them.
- **An alternate verb on cmd+return** (C4), without going through cmd+k.
  cmd+k already offers every verb a row has, with their names in front of
  you; a second, invisible verb per row is a thing to learn rather than to
  read.
- **VS Code's own tasks.json files**, for now. The launcher's `tasks.json`
  sits beside settings.json in VS Code's shape, so a task copies either way.

## What this is not

Not a reimplementation of every service integration. Those are reached
through extensions, never written here. An integration that runs without
a window makes a good backend; one that takes over the screen is a
handoff, a fine destination but never the way in.

Not an orchestrator. No sequencing, retries, or branching in the dispatcher —
that belongs in a shell script or a Shortcut. The VS Code
version deferred to `runCommands` for the same reason.

## Constraints worth remembering

- `hs.task` runs a non-login shell. **Absolute paths for every binary** —
  the kernel's tools section resolves them, and picks between tools that do
  the same job.
- Choosers must be held at module scope or they get garbage-collected mid-display.
- `chooser:hide()` fires the completion callback with nil, so swapping pickers
  needs a guard flag or the layer exits on every switch.
- In the Raycast extension, deeplinks push context *into* Raycast
  (`fallbackText`, `arguments`) but nothing comes back. For the return trip, a Raycast Script Command calls `hs -c "..."`.
- `fzfRank` keys items by display text. Each text now holds a queue rather
  than one item, so duplicate titles survive ranking — necessary once apps,
  projects and settings panes share one list.
- Lua patterns are not regex. No `\d`, no alternation.
- macOS owns a lot of chords. Failed registration errors loudly in the console
  with `RegisterEventHotKey failed: -9878` — check there first. The entry
  chord, alt+space, will not bind while Raycast or Alfred holds it.

## What turned out to be wrong

Worth keeping rather than quietly deleting, since each cost real work:

**"macOS has no command registry."** It has one per app: the menu bar.
`getMenuItems` reads it, `selectMenuItem` runs it. Several iterations
went past before anyone noticed.

**Recency as a module.** One file held the app MRU, project discovery
and recent files, because all three were "recent things". They have
nothing in common: each belongs to whoever owns that kind of thing, and
recency is a property of a row.

**A backend per idea.** A `project` backend existed whose whole job was
choosing between `editor`, `terminal` and `open`. It looked like a
mechanism and was an indirection. The tell: one caller, and every line
delegating.

**Views without a seam.** The first view refactor left one view calling
`chooser:choices()` directly — the exact leak the refactor existed to
prevent, written the same day the rule was written down. The harness now
asserts it, because a rule nobody checks lasts one commit.

**Configuration in Lua.** Profiles were Lua files, which read naturally
until a settings picker had to write one back. JSON with comments, edited
in place, is what VS Code settled on for the same reason.

**A shared list of hand-written actions.** One extension held global,
file, app and clipboard actions for every other extension's subjects. Each
had an owner already -- Finder, the clipboard, the browser, macOS -- and
half duplicated what the owner offered.

**A window extension and a windows extension.** One moved the window in
front, the other listed windows and focused one; both needed "which
window", and each had its own copy of it. They were one feature.

**An overlay of chord hints.** It named every control at the bottom of the
screen, and read as noise; a command's row shows its chord, and `?` lists
the pickers.

**Looking an app up by name.** `hs.application.get(name)` searches every
window's title when the name is not a running app, close to a second a
time. Listing browsers that way froze `cmd+r` for six seconds. A running
app is found by bundle id.
