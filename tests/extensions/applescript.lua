-- CommandLayer.spoon/tests/extensions/applescript.lua
-- The AppleScript extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
stub(cl.tools.paths, "osascript", "/usr/bin/osascript")

local spawned = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done }
  function t.start(self) return self end
  function t.terminate() end
  spawned[#spawned + 1] = t
  return t
end)
local alerts = {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
local waited = 0
stub(hs.osascript, "applescript", function() waited = waited + 1; return true, "", {} end)

local answer
cl.executeCommand("applescript.run", {
  script = 'tell application "${frontmostApp}" to get name',
  done = function(ok, output) answer = { ok = ok, output = output } end,
}, { frontmostApp = "Finder" })
local task = spawned[#spawned] or { args = {} }
local beforeExit = answer
if task.done then task.done(0, "Finder\n", "") end

check("an AppleScript runs in osascript's own process, the context filled in, and nothing waits for it",
      task.program == "/usr/bin/osascript" and task.args[1] == "-e"
      and task.args[2] == 'tell application "Finder" to get name' and #task.args == 2
      and waited == 0 and beforeExit == nil,
      tostring(task.program) .. " " .. tostring(task.args[2]))
check("a caller given done hears what the script returned once it exits, and nothing is alerted",
      answer ~= nil and answer.ok == true and answer.output == "Finder" and #alerts == 0,
      answer and tostring(answer.output))

local lines, restore = T.capturingPrint()
cl.executeCommand("applescript.run", { script = "error 1" }, {})
local failing = spawned[#spawned]
if failing ~= task and failing.done then failing.done(1, "", "execution error") end
restore()
check("a script that fails, run with no done, alerts and logs an error",
      failing ~= task and #alerts == 1 and (lines[1] or ""):match("^%[commandlayer%].*execution error") ~= nil,
      tostring(lines[1]))

local before = #spawned
cl.executeCommand("applescript.run", { script = "${notCaptured}" }, {})
check("a script that resolves to nothing starts no process", #spawned == before)
