-- CommandLayer.spoon/extensions/codicons.lua
-- VS Code's icons, drawn from Microsoft's codicon font: a row or a command
-- writes `icon = "$(repo-clone)"`, or starts its label with `$(repo-clone)`,
-- as VS Code does.
--
-- The font is not shipped with the Spoon: `brew install --cask font-codicon`.
-- Without it nothing is drawn and rows look as they did.

local M = {}

M.fontName = "codicon"

-- Drawn at this many points square; the chooser scales a row's icon down.
M.size = 32

local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"

-- 630 names, read the first time an icon is asked for rather than at load.
local names

function M.codepoint(name)
  if not names then
    local ok, loaded = pcall(dofile, here .. "codicons/names.lua")
    names = (ok and type(loaded) == "table") and loaded or {}
  end
  return names[name]
end

function M.available()
  return hs.styledtext.validFont ~= nil and hs.styledtext.validFont(M.fontName) == true
end

local cache = {}

function M.forget()
  cache = {}
end

-- One image per name and colour, made once. A name the font lacks is
-- remembered as missing; a missing font is not, so installing it takes
-- effect without a reload.
function M.image(name, dark)
  local key = name .. (dark and "\0dark" or "\0light")
  if cache[key] ~= nil then return cache[key] or nil end

  local point = M.codepoint(name)
  if not point then
    cache[key] = false
    return nil
  end
  if not M.available() then return nil end

  local canvas = hs.canvas.new({ x = 0, y = 0, w = M.size, h = M.size })
  canvas[1] = {
    type  = "text",
    -- Glyphs sit a little high in their line box; this centres them.
    frame = { x = 0, y = M.size * 0.06, w = M.size, h = M.size },
    text  = hs.styledtext.new(utf8.char(point), {
      font  = { name = M.fontName, size = M.size * 0.8 },
      color = dark and { white = 1, alpha = 0.9 } or { white = 0, alpha = 0.85 },
      paragraphStyle = { alignment = "center" },
    }),
  }
  local ok, image = pcall(function() return canvas:imageFromCanvas() end)
  canvas:delete()
  cache[key] = (ok and image) or false
  return cache[key] or nil
end

function M.extension(cl)
  cl.themeIconProvider(function(name)
    return M.image(name, cl.appearance and cl.appearance.dark)
  end)

  return {
    name        = "codicons",
    displayName = "Codicons",
    description = "VS Code's $(icon) names, drawn from the codicon font",
    menus       = {},
  }
end

-- Checks for this extension, run by test.lua.

return M
