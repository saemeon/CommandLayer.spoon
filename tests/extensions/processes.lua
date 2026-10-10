-- CommandLayer.spoon/tests/extensions/processes.lua
-- The processes extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.processes

local parsed = M.parse("  12   1.5 2048 /usr/sbin/quiet\n  98043  45.1 392848 /Applications/X.app/Contents/MacOS/Busy One\n")
check("ps's lines read as processes, busiest first, by the program's name, memory in megabytes",
      #parsed == 2 and parsed[1].name == "Busy One" and parsed[1].pid == 98043 and parsed[1].mb == 383
      and parsed[2].cpu == 1.5, parsed[1] and parsed[1].name)

M.forget()
local tasks, ticks = {}, {}
stub(cl.tools.paths, "ps", "/bin/ps")
stub(cl.tools.paths, "kill", "/bin/kill")
stub(hs.task, "new", function(program, complete, _, args)
  tasks[#tasks + 1] = { program = program, complete = complete, args = args }
  return { start = function(t) return t end, terminate = function() end }
end)
stub(hs.timer, "doEvery", function(seconds, fn)
  local t = { seconds = seconds, fn = fn, stopped = false }
  function t:stop() t.stopped = true end
  ticks[#ticks + 1] = t
  return t
end)
local refreshed = 0
stub(cl, "refresh", function() refreshed = refreshed + 1 end)

local opening = cl.gather({ activeView = "processes" }, { menus = { "processes" } })
local readOnOpen = #tasks == 1 and tasks[1].program == "/bin/ps"
if tasks[1] then tasks[1].complete(0, "  7  3.0 1024 /bin/top\n", "") end
local rows = cl.gather({ activeView = "processes" }, { menus = { "processes" } })
local ext
for _, e in ipairs(cl.extensions) do if e.name == "processes" then ext = e end end
ext.left({ activeView = "processes" })
check("opening reads the processes and starts a timer, the answer redraws, and leaving stops the timer",
      #opening == 0 and readOnOpen and refreshed == 1 and #rows == 1 and rows[1].label == "top"
      and rows[1].subject.pid == 7 and #ticks == 1 and ticks[1].seconds == M.seconds and ticks[1].stopped,
      ("%d tasks, %d refreshes, %d rows, %d ticks"):format(#tasks, refreshed, #rows, #ticks))

cl.executeCommand("processes.quit", { process = { kind = "process", pid = 7, name = "top" } }, {})
local quitArgs = tasks[#tasks] and table.concat(tasks[#tasks].args, " ")
local confirm = cl.getCommand("processes.forceQuit").confirm({ process = { name = "top" } })
check("Quit sends kill -TERM to its pid, and Force quit asks first, naming it",
      quitArgs == "-TERM 7" and confirm:find("Force quit top", 1, true) ~= nil, tostring(quitArgs))
M.forget()
