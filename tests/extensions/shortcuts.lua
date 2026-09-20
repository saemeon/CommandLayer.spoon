-- CommandLayer.spoon/tests/extensions/shortcuts.lua
-- The shortcuts extension's checks.

local T = ...
local check = T.check
local cl = T.layer()


local ext
for _, e in ipairs(cl.extensions) do
  if e.name == "shortcuts" then ext = e end
end
if not ext then return check("shortcuts extension is registered", false) end

local limit = cl.setting("shortcuts", "limit")
local asked = {}
local saved = { new = hs.task.new, path = cl.tools.path }
cl.tools.path = function(name)
  if name == "shortcuts" then return "/usr/bin/shortcuts" end
  return saved.path(name)
end
hs.task.new = function(program, done, _, args)
  asked[#asked + 1] = { program = program, args = args, done = done }
  return { start = function(t) return t end, terminate = function() end,
           setInput = function() end, closeInput = function() end }
end
cl.stopRunning("shortcuts")

local before = ext.items({})
local names = {}
for i = 1, limit + 5 do names[i] = "Shortcut " .. i end
if asked[1] then asked[1].done(0, table.concat(names, "\n"), "") end
local rows = ext.items({})
local listing = asked[1]
cl.executeCommand("shortcuts.run", { name = "Shortcut 2" }, {})
local ran = asked[#asked]

hs.task.new, cl.tools.path = saved.new, saved.path
cl.stopRunning("shortcuts")

check("the Shortcuts app's shortcuts are listed in a task, then are rows, as many as the limit",
      #before == 0 and listing ~= nil and listing.args[1] == "list"
      and #rows == limit and limit == 30 and rows[1].label == "Shortcut 1"
      and rows[1].command == "shortcuts.run" and rows[1].args.name == "Shortcut 1",
      tostring(#rows))
check("a shortcut runs through shortcuts run",
      ran ~= nil and ran.args[1] == "run" and ran.args[2] == "Shortcut 2")
