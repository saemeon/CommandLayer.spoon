-- CommandLayer.spoon/tests/extensions/maccy.lua
-- The maccy extension's checks.

local T = ...
local check = T.check
local cl = T.layer({ ["maccy.enabled"] = true })
local M = cl.modules.maccy

do
  check("maccy detects whether it is installed", type(M.installed()) == "boolean",
        tostring(M.installed()))

  local decoded = M.decodePopup([[{"carbonKeyCode":8,"carbonModifiers":768}]])
  local names = {}
  for _, name in ipairs(decoded and decoded[1] or {}) do names[#names + 1] = name end
  table.sort(names)
  check("decodes Maccy's popup chord from its key code and carbon modifiers",
        decoded ~= nil and decoded[2] == "c" and table.concat(names, "+") == "cmd+shift",
        decoded and tostring(decoded[2]) or "nil")

  check("maps a key code to a name", M.keyName(8) == "c",
        tostring(M.keyName(8)))

  local savedAttributes, savedDoAfter, savedEventtap = hs.fs.attributes, hs.timer.doAfter, hs.eventtap
  local pressed
  hs.fs.attributes = function(path) return path == M.appPath and {} or savedAttributes(path) end
  hs.timer.doAfter = function(_, fn) fn(); return { stop = function() end } end
  hs.eventtap = { keyStroke = function(mods, key) pressed = table.concat(mods, "+") .. "+" .. key end }
  local ext
  for _, e in ipairs(cl.extensions) do
    if e.name == "maccy" then ext = e end
  end
  local row = ext and ext.items({})[1]
  if row then row.run({}) end
  hs.fs.attributes, hs.timer.doAfter, hs.eventtap = savedAttributes, savedDoAfter, savedEventtap
  check("without Maccy's preferences, the history opens on the popupChord setting",
        row ~= nil and pressed == "cmd+shift+c", tostring(pressed))
end
