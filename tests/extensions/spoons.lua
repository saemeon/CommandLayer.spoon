-- CommandLayer.spoon/tests/extensions/spoons.lua
-- The spoons extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()

local Class = {}
Class.__index = Class
function Class:toggle() self.toggled = (self.toggled or 0) + 1 end
function Class.init() end
function Class._private() end
local caffeine = setmetatable({ name = "Caffeine" }, Class)
function caffeine.start() end
function caffeine.bindHotkeys() end

stub(_G, "spoon", { Caffeine = caffeine, CommandLayer = { stop = function() end } })
stub(hs.hotkey, "getHotkeys", function()
  return { { idx = "⌃⌥⇧K", msg = "⌃⌥⇧K: Toggle the thing" }, { idx = "F13", msg = "F13" },
           { idx = "⌘NotAKey", msg = "⌘NotAKey" } }
end)
stub(hs, "keycodes", { map = { k = 40, f13 = 105 } })

local rows = cl.gather({}, { menus = { "spoons" } })
local labels = {}
for _, row in ipairs(rows) do labels[#labels + 1] = row.label end
check("another Spoon's methods are rows, its class's included, but init, bindHotkeys and the private; "
        .. "this Spoon is left out; a hotkey is a row by its message, one hs.keycodes cannot press is not",
      table.concat(labels, " | ") == "Caffeine: start | Caffeine: toggle | ⌃⌥⇧K: Toggle the thing | Hotkey F13",
      table.concat(labels, " | "))

local pressed, timers = {}, {}
stub(hs.eventtap, "keyStroke", function(mods, key) pressed[#pressed + 1] = table.concat(mods, "+") .. "+" .. key end)
stub(hs.timer, "doAfter", function(_, fn) timers[#timers + 1] = fn; return { stop = function() end } end)
for _, row in ipairs(rows) do
  if row.label == "Caffeine: toggle" or row.label == "⌃⌥⇧K: Toggle the thing" then cl.runRow(row) end
end
for _, fn in ipairs(timers) do fn() end
local mods = pressed[1] and pressed[1]:match("^(.*)%+k$") or ""
local sorted = {}
for mod in mods:gmatch("[^+]+") do sorted[#sorted + 1] = mod end
table.sort(sorted)
check("picking a method runs it on its Spoon, and picking a hotkey presses its chord once the picker is gone",
      caffeine.toggled == 1 and table.concat(sorted, "+") == "alt+ctrl+shift" and #pressed == 1,
      table.concat(pressed, " "))

check("a hotkey's idx reads back as a chord, and a key hs.keycodes does not know is nil",
      select(2, cl.modules.spoons.chordOf("F13")) == "f13" and cl.modules.spoons.chordOf("⌘NotAKey") == nil)
