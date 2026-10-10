-- The other Spoons loaded and every Hammerspoon hotkey: a Spoon's methods to
-- run, a hotkey's chord to press. Read as the picker opens, from what
-- Hammerspoon already holds -- the global `spoon` table and
-- hs.hotkey.getHotkeys() -- so nothing is kept.

local M = {}

-- What every Spoon has and running from a list would not mean anything:
-- init is hs.loadSpoon's, bindHotkeys takes a mapping.
M.skipped = { init = true, bindHotkeys = true }

-- This Spoon itself: its own commands are rows already.
M.self = "CommandLayer"

-- A Spoon's methods, its own and its class's, sorted, without the skipped
-- and the private (_name).
function M.methods(obj)
  local names, seen = {}, {}
  local function add(source)
    for name, value in pairs(type(source) == "table" and source or {}) do
      if type(name) == "string" and type(value) == "function" and not seen[name]
         and not M.skipped[name] and name:sub(1, 1) ~= "_" then
        seen[name] = true
        names[#names + 1] = name
      end
    end
  end
  add(obj)
  local meta = getmetatable(obj)
  if meta and type(meta.__index) == "table" then add(meta.__index) end
  table.sort(names)
  return names
end

-- ⌃⌥⇧⌘ and a key, as hs.hotkey writes a hotkey's idx, back into what
-- hs.eventtap presses; nil for a key hs.keycodes does not know.
local SYMBOLS = { ["⌘"] = "cmd", ["⌥"] = "alt", ["⌃"] = "ctrl", ["⇧"] = "shift" }
function M.chordOf(idx)
  if type(idx) ~= "string" or idx == "" then return nil end
  local mods, rest = {}, idx
  while true do
    local found
    for symbol, name in pairs(SYMBOLS) do
      if rest:sub(1, #symbol) == symbol then
        mods[#mods + 1] = name
        rest = rest:sub(#symbol + 1)
        found = true
      end
    end
    if not found then break end
  end
  local key = rest:lower()
  if key == "" or not (hs.keycodes and hs.keycodes.map and hs.keycodes.map[key] ~= nil) then return nil end
  return mods, key
end

function M.extension(cl)
  return {
    name        = "spoons",
    displayName = "Spoons",
    description = "The other Spoons loaded, their methods to run, and every Hammerspoon hotkey to press",
    menus       = { "spoons" },
    rank        = 0.2,

    items = function(ctx)
      local rows = {}
      local names = {}
      for name in pairs(type(spoon) == "table" and spoon or {}) do
        if name ~= M.self then names[#names + 1] = name end
      end
      table.sort(names)
      for _, name in ipairs(names) do
        local obj = spoon[name]
        for _, method in ipairs(M.methods(obj)) do
          rows[#rows + 1] = {
            label = name .. ": " .. method, description = "Spoon -- " .. name .. ":" .. method .. "()",
            icon = "$(extensions)", ctx = ctx,
            run = function()
              local ok, err = pcall(obj[method], obj)
              if not ok then hs.alert.show(("%s:%s() failed"):format(name, method)) cl.log.e(tostring(err)) end
            end,
          }
        end
      end

      for _, hotkey in ipairs(hs.hotkey.getHotkeys and hs.hotkey.getHotkeys() or {}) do
        local mods, key = M.chordOf(hotkey.idx)
        if key then
          local message = type(hotkey.msg) == "string" and hotkey.msg ~= hotkey.idx and hotkey.msg or nil
          rows[#rows + 1] = {
            label = message or ("Hotkey " .. hotkey.idx), description = "Hotkey -- " .. hotkey.idx,
            icon = "$(keyboard)", ctx = ctx,
            -- Once the picker has closed, so the chord reaches what it is bound in.
            run = function() cl.after(0.1, function() hs.eventtap.keyStroke(mods, key, 0) end) end,
          }
        end
      end
      return rows
    end,
  }
end

return M
