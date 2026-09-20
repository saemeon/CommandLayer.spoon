-- The shape of a row.

local M = ...

----------------------------------------------------------------------
-- ROWS
----------------------------------------------------------------------

-- `$(name)` icons, VS Code's ThemeIcon syntax, drawn by whichever extension
-- provides them -- codicons.lua draws Microsoft's font. Keyed by provider
-- name, so setting up again replaces rather than adds.
local iconProviders, providerOrder = {}, {}

function M.themeIconProvider(name, fn)
  if type(name) ~= "string" or type(fn) ~= "function" then return false end
  if not iconProviders[name] then providerOrder[#providerOrder + 1] = name end
  iconProviders[name] = fn
  return true
end

function M.removeThemeIconProvider(name, fn)
  if iconProviders[name] == nil or (fn and iconProviders[name] ~= fn) then return false end
  iconProviders[name] = nil
  for i, provider in ipairs(providerOrder) do
    if provider == name then table.remove(providerOrder, i) break end
  end
  return true
end

function M.themeIcon(name)
  for _, provider in ipairs(providerOrder) do
    local ok, image = pcall(iconProviders[provider], name)
    if ok and image then return image end
  end
  return nil
end

-- `sync~spin` is VS Code's animated variant; the name is before the `~`.
local ICON = "^%$%(([%w%-]+)[~%w%-]*%)"

-- A row's second line: VS Code draws `description` beside the label and
-- `detail` below it, and a chooser row has only the one line below.
local function secondLine(item)
  local parts = {}
  if item.description ~= nil and item.description ~= "" then parts[#parts + 1] = tostring(item.description) end
  if item.detail ~= nil and item.detail ~= "" then parts[#parts + 1] = tostring(item.detail) end
  if #parts == 0 then return nil end
  return table.concat(parts, "  --  ")
end

M.secondLine = secondLine

-- VS Code's quick pick item names: `label`, `description`, `detail` and
-- `iconPath` -- an image, or a `$(name)` icon.
local function normaliseRow(item)
  if type(item) ~= "table" then return item end

  -- An icon from `icon`, a `$(name)` iconPath, or the front of the label.
  -- Taken out of the label even when nothing can draw it, so it never shows
  -- as text.
  local icon = (type(item.icon) == "string" and item.icon:match(ICON .. "$"))
               or (type(item.iconPath) == "string" and item.iconPath:match(ICON .. "$"))
  if type(item.label) == "string" then
    local lead, rest = item.label:match(ICON .. "%s*(.*)$")
    if lead then
      icon = icon or lead
      item.label = rest
    end
  end
  if type(item.iconPath) == "string" and item.iconPath:match(ICON .. "$") then item.iconPath = nil end
  if icon and item.iconPath == nil then item.iconPath = M.themeIcon(icon) end
  return item
end

M.normaliseRow = normaliseRow
