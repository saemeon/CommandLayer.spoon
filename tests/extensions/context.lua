-- CommandLayer.spoon/tests/extensions/context.lua
-- The context extension's checks.

local T = ...
local check = T.check
local cl = T.layer()


local ran, copied
local saved = { copy = hs.pasteboard.setContents, shortcuts = cl.getCommand("shortcuts.run") }
hs.pasteboard.setContents = function(text) copied = text end
local shortcuts = saved.shortcuts
local savedRun = shortcuts and shortcuts.run
if shortcuts then shortcuts.run = function(args) ran = args.name end end

local subject = { kind = "action", name = "Make GIF", command = "shortcuts.run", args = { name = "Make GIF" } }
local verbs = {}
for _, row in ipairs(cl.itemActions(subject, {})) do
  if row.command == "context.run" or row.command == "context.copyTitle" then
    verbs[row.label] = row
  end
end
if verbs.Run then cl.executeCommand(verbs.Run.command, verbs.Run.args, {}) end
if verbs["Copy title"] then cl.executeCommand(verbs["Copy title"].command, verbs["Copy title"].args, {}) end
local bare = 0
for _, row in ipairs(cl.itemActions({ kind = "action" }, {})) do
  if row.command == "context.run" or row.command == "context.copyTitle" then bare = bare + 1 end
end

hs.pasteboard.setContents = saved.copy
if shortcuts then shortcuts.run = savedRun end
check("an action row offers Run, which runs its command, and Copy title, on cmd+k only",
      ran == "Make GIF" and copied == "Make GIF" and bare == 0
      and cl.getCommand("context.run").menus.commandPalette == nil,
      tostring(ran) .. " / " .. tostring(copied) .. " / " .. bare)
