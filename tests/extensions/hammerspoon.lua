-- CommandLayer.spoon/tests/extensions/hammerspoon.lua
-- The hammerspoon extension's checks.

local T = ...
local check = T.check
local cl = T.layer()


local found = {}
for _, row in ipairs(cl.gather(cl.buildContext(), { menus = { "root" } })) do
  if row.command then found[row.command] = row.label end
end
check("Hammerspoon's commands are rows in the root, reading 'Hammerspoon: Reload'",
      found["hammerspoon.reload"] == "Hammerspoon: Reload"
      and found["hammerspoon.console"] ~= nil, tostring(found["hammerspoon.reload"]))

local reloaded, delay = false, nil
local saved = { reload = hs.reload, doAfter = hs.timer.doAfter }
hs.reload = function() reloaded = true end
hs.timer.doAfter = function(seconds, fn) delay = seconds; fn(); return { stop = function() end } end
cl.executeCommand("hammerspoon.reload", {})
hs.reload, hs.timer.doAfter = saved.reload, saved.doAfter
check("Reload reloads Hammerspoon, once the picker is gone", reloaded and delay and delay > 0,
      tostring(delay))

local opened
local editor = cl.getCommand("editor.open")
local savedRun = editor and editor.run
if editor then editor.run = function(args) opened = args.target end end
cl.executeCommand("hammerspoon.configFolder", {})
if editor then editor.run = savedRun end
check("Open config folder opens Hammerspoon's config folder in the editor",
      type(opened) == "string" and opened ~= "", tostring(opened))
