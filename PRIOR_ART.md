# Prior art and credits

Command Layer is built out of other people's ideas. This page says, for
each project it learned from, what that project does, what was taken from
it, and how the two compare -- including where the other one is better.
Nothing here is an endorsement by them.

No code from the projects below is copied into Command Layer. Where an
approach was adapted, the entry says so. Projects without a licence file
were read, not reused.

## At a glance

| | Context model | Extensions | Configuration | Ordering | Keyboard grammar |
|---|---|---|---|---|---|
| **VS Code** | the active editor, `when` clauses | manifest + API, own process | JSONC, profiles | MRU palette, fuzzy scorer | palette, prefixes, chords |
| **Alfred** | selection via Universal Actions (3 types) | workflows, Script Filter JSON, any language | preferences bundle | usage latched to the typed keyword | keywords, hotkeys, fallbacks |
| **Raycast** | an API an extension calls | React/TS, store | app UI, `.rayconfig` | aliases, then fuzzy, then frecency per query | root search, aliases, hotkeys |
| **LaunchBar** | Instant Send of the selection | script bundles | app UI | learned abbreviations | abbreviations, send with Tab |
| **Quicksilver** | proxy objects (Current Selection) | plug-ins | app UI | learned mnemonics | object → action → object |
| **Seal** | none | `seal_*.lua` plug-ins | Lua | none (table order) | keyword commands |
| **martillo** | none | Lua actions, git "store" | Lua `setup{}` | tiered fuzzy with aliases | palette, child pickers |
| **Hammerflow** | per-app key suffixes | action-string prefixes | TOML | none (keys are fixed) | leader-key tree |
| **Ki** | entities (per app) | Lua classes | Lua | none | vi-like modes |
| **Command Layer** | subjects any extension names, `when` clauses | Lua files, VS Code-shaped commands | JSONC, profiles | weighted rankers, zoxide frecency | palette, prefixes, cmd+k on any row |

## The model

**[Visual Studio Code](https://github.com/microsoft/vscode)** (Microsoft,
MIT). The shape Command Layer copies, on purpose and by name: a command
registry with stable ids and categories; Quick Open, whose mode is chosen
by a prefix and whose `?` lists the modes; `when` clauses and
`setContext`; `keybindings.json` with `args` and `-` removal;
`settings.json` over shipped defaults, edited in place as JSONC;
profiles that switch; `contributes.configuration`-style settings; the
input and variable names of `tasks.json`; codicons; and the
`view/item/context` menu, generated here from typed command inputs. What
was left out follows VS Code's own rule that extensions feed fixed UI
rather than draw it. Its keybinding resolution (a rule whose `when` is
false falls through), its undoing of what an extension registered and its
allowlisted API were copied here; it is still better at keeping that API
stable.

**[Command Layer for VS Code](vscode/command-layer-extension)** and the
**[zsh palette](zsh/)** (this repository's author). The two prototypes this
Spoon grew from. The extension named trigger → resolve → dispatch: a thin
layer that fills a command's arguments from context and hands its id to a
registry it does not own, with `when` scoping and the rule that a generic
menu entry always shows its choices. The zsh palette found a thing with
fzf, then chose what to do with it, and drew the line between what belongs
to a shell session (`cd`, virtualenvs, panes) and what does not.

## Hammerspoon and its Spoons

**[Hammerspoon](https://www.hammerspoon.org)** (MIT). The platform:
hotkeys, `hs.chooser`, window, application, Spotlight and accessibility
APIs, all scriptable in Lua. Everything here is a dispatcher on top of it.

From the **[official Spoons](https://github.com/Hammerspoon/Spoons)**
(each MIT unless its `obj.license` says otherwise):

- **Seal** (Chris Jones). A pluggable `hs.chooser` launch bar with keyword
  commands and per-plug-in matches. The live `hs.spotlight` app query --
  added, changed and removed apps -- was adapted from `seal_apps.lua`, and
  picking a command row types its keyword, as here. Command Layer adds
  isolation of every hook, ranking, cancellable asynchronous search and a
  context model.
- **TextClipboardHistory** (Diego Zamboni). Text clipboard history that
  never records `org.nspasteboard.ConcealedType` or `TransientType`, so
  passwords stay out. The ambient extension applies the same filter to the
  clipboard as context.
- **RecursiveBinder**. Leader-key trees with a hint strip. It is why the
  launcher once had a hint overlay, and why it no longer does: a row shows
  its chord, and `?` lists the pickers.
- **Commander** and **HSearch**. A chooser over every loaded Spoon's
  functions, and folder-loaded sources switched by keyword. Close cousins
  of the palette and its prefix views.
- **KSheet** and **HSKeybindings**. Cheat sheets of an app's menu shortcuts
  and of bound hotkeys; how menu rows could show their own shortcut.
- **ClipboardTool**, **URLDispatcher**, **SpoonInstall**,
  **ReloadConfiguration**, **WindowHalfsAndThirds**,
  **MiroWindowsManager**, **WindowScreenLeftAndRight**,
  **AppWindowSwitcher**, **Emojis**, **LookupSelection**. Right-click row
  menus, URL routing by pattern, declarative installation, reloading on
  change, window undo and size cycling, directional screen moves,
  per-app window cycling, subtitle matching, and the selection as input --
  each an idea on the roadmap, or a convention to meet before publishing.

## Launchers on Hammerspoon

**[martillo](https://github.com/sjdonado/martillo)** (sjdonado, MIT). A
Raycast-style launcher on Hammerspoon: a `setup{}` in the style of
lazy.nvim, a weighted pure-Lua fuzzy search with aliases, nested pickers,
bundled utilities, and a git sparse-checkout store pinned by a lock file.
It is ahead on global per-command chords, pickers that refresh while open,
matching without fzf, and installing actions from a repository. Command
Layer differs in its context model, one picker stack behind a presenter
seam, JSONC settings, frecency and an automated harness, and in routing
to existing tools where martillo writes its own.

**[Hammerflow.spoon](https://github.com/saml-dev/Hammerflow.spoon)**
(saml-dev, MIT). A leader-key launcher from one TOML file, whose string
prefixes (`cmd:`, `menu:`, `window:`, `input:`) are a compact vocabulary
of action types -- the same ground as backends and declared inputs here.
It is faster for memorised actions and warns when Secure Input blocks
keystrokes; Command Layer is searchable and context-aware, and never
interpolates typed text into a shell.

**[Ki](https://github.com/andweeb/Ki)** (andweeb, MIT). vi's modal grammar
for macOS: a state machine of normal, entity, action and select modes,
entities with generated cheat sheets, and a well-kept project with lint,
coverage and a mock factory. Its entity/action/select split is the closest
prior art to subjects, verbs and inputs that take a row; here verbs attach to a
subject kind any extension names and are found by search. Its hotkey
conflict detection and test tooling are worth adopting.

**[spacehammer](https://github.com/agzam/spacehammer)** (agzam and
contributors, MIT). A Spacemacs-style toolkit in Fennel: nested leader
menus, app-specific keys with lifecycle hooks, repeatable actions, and a
small tested state machine whose effects return their own cleanup. The
reference for explicit transition tables, key repeat on bindings, and
repeatable window commands.

**[lunarySpoon](https://github.com/casouri/lunarySpoon)** (casouri; no
licence file, read only). A personal config pairing a leader-key tree with
Commander's searchable chooser -- early evidence that chords and a palette
each need the other, the split this launcher makes -- and a window module
that combines successive presses into corners.

**[hammerspoon-config](https://github.com/cmsj/hammerspoon-config)** (Chris
Jones; no licence file, read only). A decade of Hammerspoon's lead
maintainer's own configuration, and where Seal began. Its history records
lessons this project had to learn again -- hold every timer and watcher,
prefer `hs.task` to blocking calls, look devices up by stable id -- and
that `hs.chooser`'s default callback refocuses the previous window on
every hide. Global hyper chords, URL-event triggers and audio device
switching are on the roadmap because of it.

## Launchers

- **[Alfred](https://www.alfredapp.com)**. Workflows and Script Filters made
  a launcher scriptable in any language, with fallback searches and
  Universal Actions on a selection. Text commands shown when nothing
  matches come from it. Ahead on learning tied to the typed keyword; its
  actions know three item types, where subjects here are any kind an
  extension names.
- **[Raycast](https://www.raycast.com)**. A React extension platform with
  arguments, preferences, per-command aliases and hotkeys, frecency per
  query, and a store. The `raycast` profile borrows its single-list shape,
  and `extensions/raycast.lua` routes to its extensions through deeplinks.
  Ahead on aliases, confirming destructive actions, loading states and
  Script Commands; its context is an API one extension calls, not a model
  every extension shares.
- **[LaunchBar](https://www.obdev.at/products/launchbar/)**. Learned
  abbreviations, and Instant Send, which puts the selection in front of a
  verb in two keystrokes. cmd+k on a row is the same shape as its send.
- **[Quicksilver](https://qsapp.com)**. The object → action → argument
  grammar, with actions by type and proxy objects such as Current
  Selection: the nearest ancestor of subjects, verbs and inputs that take a row.
- **[PowerToys Command
  Palette](https://learn.microsoft.com/windows/powertoys/command-palette/overview)**
  (Microsoft, MIT). Out-of-process extensions with top-level, fallback and
  context commands, and results that say whether the palette stays open,
  goes back or asks to confirm -- a vocabulary worth adopting.
- **[Flow Launcher](https://www.flowlauncher.com)** / Wox,
  **[Albert](https://albertlauncher.github.io)**,
  **[Ulauncher](https://ulauncher.io)**,
  **[KRunner](https://develop.kde.org/docs/plasma/krunner/)**, GNOME search
  providers, **[pop-launcher](https://github.com/pop-os/launcher)**,
  **[rofi](https://github.com/davatorium/rofi)**/dmenu,
  **[Cerebro](https://github.com/cerebroapp/cerebro)**,
  **[Ueli](https://github.com/oliverschwendener/ueli)**,
  **[Sol](https://github.com/ospfranco/sol)**. Keyword-scoped plug-ins in
  other processes, relevance merged with usage and tunable decay,
  advertised query syntax, narrowing a result set as terms are added,
  hidden search terms on rows, autocomplete apart from picking, and
  favourites. Together they confirm the prefix-plus-global-search model
  and show what isolation from slow providers buys.
- **Spotlight** (macOS 26). Actions from App Intents and short user-set
  Quick Keys -- exact aliases, validated by Apple. A destination only:
  there is no API for adding rows to it.
- **[cmdk](https://github.com/pacocoursey/cmdk)**,
  **[kbar](https://github.com/timc1/kbar)**, and the palettes in Linear and
  Superhuman. Keyword aliases, nesting, context registration and shortcuts
  shown on every row; the chord in a command's subtitle comes from here.

## Tools it routes to

Command Layer is mostly a way to reach these. They do the work.

[fzf](https://github.com/junegunn/fzf) (matching),
[zoxide](https://github.com/ajeetdsouza/zoxide) (folders, and the frecency
algorithm the ranker copies), [fd](https://github.com/sharkdp/fd),
[gh](https://cli.github.com), [git](https://git-scm.com),
[Maccy](https://github.com/p0deje/Maccy),
[codicons](https://github.com/microsoft/vscode-codicons), Spotlight and
`mdfind`, the Shortcuts app, macOS Text Replacements, System Settings'
ExtensionKit panes, every app's menu bar, VS Code's Open Recent list, and
Chromium's history, bookmarks and session files.
