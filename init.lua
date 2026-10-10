--- === CommandLayer ===
---
--- A keyboard launcher shaped like VS Code's quick open: the commands for
--- whatever is in front of you -- an app, a window, a Finder selection, a
--- browser tab, a project -- in one palette, each handed to whatever already
--- does the job -- Spotlight, the menu bar, a CLI, another Spoon.
---
--- Install to ~/.hammerspoon/Spoons/CommandLayer.spoon, then in init.lua:
---
--- ```
--- hs.loadSpoon("CommandLayer")
--- spoon.CommandLayer:start()
--- ```
---
--- alt+space opens it -- Raycast's and Alfred's default too, so whichever of
--- them holds it has to give it up first.
---
--- Settings, keybindings and profiles are JSONC files in ~/.hammerspoon/commandlayer/,
--- over the Spoon's own in config/. Anything needing code is a file in
--- extensions/, matchers/, rankers/ or presenters/, or an extension added
--- from init.lua with addExtension -- see README.md.

local obj = {}
obj.__index = obj

obj.name    = "CommandLayer"
obj.version = "1.0"
obj.author  = "Simon Niederberger"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Unset until the repository is public; SPOONS.md asks for it then.
obj.homepage = nil

--- CommandLayer.spoonPath
--- Variable
--- The Spoon's folder, ending in a slash.
-- From this chunk rather than hs.spoons.scriptPath(), whose answer
-- depends on how deep the call stack is when you ask.
obj.spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"

--- CommandLayer.defaultHotkeys
--- Variable
--- The mapping `CommandLayer:bindHotkeys()` takes, holding the chord that opens
--- the layer as shipped: `{ enter = { { "alt" }, "space" } }`.
---
--- Notes:
---  * start() binds alt+space from the shipped keybindings without it. Passing it to bindHotkeys binds the same
---    chord in init.lua instead, where a keybinding written from the launcher cannot remove it.
obj.defaultHotkeys = { enter = { { "alt" }, "space" } }

--- CommandLayer.profile
--- Variable
--- Which profile's settings.json and keybindings.json apply over the shipped defaults, or nil.
---
--- Notes:
---  * A name is the Spoon's config/profiles/<name>/, then ~/.hammerspoon/commandlayer/profiles/<name>/; a path
---    is that folder.
---  * Left nil, ~/.hammerspoon/commandlayer/profile.json decides, then "default", whose files are
---    ~/.hammerspoon/commandlayer/settings.json and keybindings.json.
---  * Read at the first start(); set it before.
obj.profile = nil

--- CommandLayer.userDir
--- Variable
--- The folder holding your settings, keybindings, profiles and plugin files, or nil.
---
--- Notes:
---  * Left nil, it is commandlayer/ in Hammerspoon's own folder: ~/.hammerspoon/commandlayer.
---  * Read at the first start(); set it before.
obj.userDir = nil

--- CommandLayer.layer
--- Variable
--- The layer itself, made by init(), as the console reaches it: `spoon.CommandLayer.layer`.
---
--- Notes:
---  * `executeCommand(id, args)` runs a command by id, asking for what args does not answer, and returns
---    true and what the command returned, or false when there is no such command.
---  * `rows(view)` gives a picker's rows as it would open on them, for an hs.menubar or a menu of your own:
---    each `{ label, subtitle, icon, enabled, submenu, run }`, `run()` doing what picking it does; nil for a
---    picker that does not exist.
---  * `setLogLevel(level)` takes VS Code's level names: "off", "trace", "debug", "info", "warning", "error".
---  * `problems` is a copy of what is wrong in your files, each `{ file, message }`.
---  * `apiVersion` is the plugin contract's version, 0 while in development.
---  * `start`, `stop`, `bindHotkeys` and `addExtension` are what the methods of the same names call.
---  * Reading or setting any other name raises.
obj.layer = nil

--- CommandLayer:init()
--- Method
--- Loads the layer without starting it.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The CommandLayer object
---
--- Notes:
---  * hs.loadSpoon calls this. No folder is read and no chord claimed until start(), so `profile` and
---    `userDir` can be set in between.
function obj:init()
  self.layer = dofile(self.spoonPath .. "commandlayer.lua")
  return self
end

--- CommandLayer:bindHotkeys(mapping)
--- Method
--- Binds the chord that opens the layer, in place of the one the keybindings files bind.
---
--- Parameters:
---  * mapping - A table with one key:
---   * enter - opens the default picker, from any app: `{ { "alt" }, "space" }`, or a keybinding's
---     `"alt+space"`
---
--- Returns:
---  * The CommandLayer object
---
--- Notes:
---  * The chord becomes a global keybinding after every file's, and every chord entering the layer
---    before it is removed. Every other chord still comes from the keybindings files.
---  * Before start() it applies at start; after, at once. A name other than `enter` is reported with
---    the problems in your files.
---  * `CommandLayer.defaultHotkeys` is the shipped chord in this shape.
function obj:bindHotkeys(mapping)
  self.layer.bindHotkeys(mapping)
  return self
end

--- CommandLayer:addExtension(name, module)
--- Method
--- Adds an extension kept anywhere Hammerspoon can load it, such as ~/.hammerspoon, under a name.
---
--- Parameters:
---  * name - The extension's name: a letter, then letters, digits or _. Its settings are `<name>.enabled` and
---    the rest under `<name>.`, and its commands' ids start with `<name>.`
---  * module - What an extension file returns: a table whose `extension(cl)` gives the extension, as
---    `require("media_control")` does
---
--- Returns:
---  * The CommandLayer object
---
--- Notes:
---  * It is an extension like any file in extensions/: switched off with `"<name>.enabled": false`, and a
---    mistake in it is shown with the problems in your files. One named like a file in extensions/
---    replaces that file.
---  * Before start() it applies at start; after, at once, by reloading the layer. Kept across reloads.
---  * Example: `spoon.CommandLayer:addExtension("mediacontrol", require("media_control"))`
function obj:addExtension(name, module)
  self.layer.addExtension(name, module)
  return self
end

--- CommandLayer:start()
--- Method
--- Starts the layer.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The CommandLayer object
---
--- Notes:
---  * The first start reads the plugin folders, the settings and the keybindings of `profile` from
---    `userDir`, and binds the keybindings. Every start then starts the extensions, binds the global
---    keybindings and shows any problem found in one alert.
function obj:start()
  self.layer.profile = self.profile
  self.layer.userDir = self.userDir
  self.layer.start()
  return self
end

--- CommandLayer:stop()
--- Method
--- Stops the layer.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The CommandLayer object
---
--- Notes:
---  * Closes the launcher if it is open, releases the global keybindings, and stops every extension that
---    started. start() starts it again.
function obj:stop()
  self.layer.stop()
  return self
end

return obj
