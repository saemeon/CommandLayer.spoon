-- Hammerspoon itself: reload it, open its console, its preferences, its
-- folder. Typing "reload" finds "Hammerspoon: Reload", since a command's
-- category is part of what is matched.

local M = {}

function M.extension(cl)
  -- Hammerspoon's own answer, which follows a config file moved with
  -- `defaults write org.hammerspoon.Hammerspoon MJConfigFile`.
  local configDir = hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")

  return {
    name        = "hammerspoon",
    displayName = "Hammerspoon",
    description = "Reload Hammerspoon, open its console, preferences and config",
    rank        = 0.29,

    commands = {
      { id = "hammerspoon.reload", title = "Reload", category = "Hammerspoon",
        icon = "$(refresh)",
        menus = { "root", "commandPalette" },
        -- A turn later, so the picker has closed and the reload does not
        -- happen from inside dispatching the pick.
        run = function() cl.after(0.1, function() hs.reload() end) end },

      { id = "hammerspoon.console", title = "Open console", category = "Hammerspoon",
        icon = "$(output)",
        menus = { "root", "commandPalette" },
        run = function() hs.openConsole() end },

      { id = "hammerspoon.preferences", title = "Open preferences", category = "Hammerspoon",
        icon = "$(settings-gear)",
        menus = { "root", "commandPalette" },
        run = function() hs.openPreferences() end },

      { id = "hammerspoon.configFolder", title = "Open config folder", category = "Hammerspoon",
        icon = "$(folder-opened)",
        menus = { "root", "commandPalette" },
        command = "editor.open", args = { target = configDir } },
    },
  }
end

-- Checks for this extension, run by test.lua.

return M
