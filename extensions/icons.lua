-- CommandLayer.spoon/extensions/icons.lua
-- One icon per kind of row.
--
-- A row without one looks ragged beside a row with one, so everything
-- that is not a file or an app -- which carry their own -- takes a
-- shared glyph from here. Resolved once and kept.

local M = {}

local cache = {}

local function icon(name, get)
  if cache[name] == nil then
    local ok, image = pcall(get)
    cache[name] = (ok and image) or false
  end
  return cache[name] or nil
end

function M.action()
  return icon("action", function()
    return hs.image.imageFromName(hs.image.systemImageNames.ActionTemplate)
  end)
end

function M.folder()
  return icon("folder", function()
    return hs.image.iconForFile(os.getenv("HOME"))
  end)
end

function M.settings()
  return icon("settings", function()
    return hs.image.iconForFile("/System/Applications/System Settings.app")
  end)
end

function M.extension()
  return {
    name  = "icons",
    menus = {},

    -- For an extension listing "icons" in optionalExtensionDependencies.
    exports = { action = M.action, folder = M.folder, settings = M.settings },
  }
end

return M
