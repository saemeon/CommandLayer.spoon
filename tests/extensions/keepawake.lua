-- CommandLayer.spoon/tests/extensions/keepawake.lua
-- The keepawake extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.keepawake

check("caffeinate keeps the display and the machine awake, for a while when asked, the machine alone when set",
      table.concat(M.args(nil, true), " ") == "-di"
      and table.concat(M.args(60, true), " ") == "-di -t 3600"
      and table.concat(M.args(15, false), " ") == "-i -t 900")

check("pmset's assertions name what keeps the Mac awake, once each, in its order", (function()
        local text = table.concat({
          "Assertion status system-wide:",
          "   PreventUserIdleSystemSleep     1",
          "Listed by owning process:",
          '   pid 412(coreaudiod): [0x0001] 00:10:00 PreventUserIdleSystemSleep named: "audio"',
          '   pid 99(caffeinate): [0x0002] 00:01:00 PreventUserIdleDisplaySleep named: "caffeinate"',
          '   pid 412(coreaudiod): [0x0003] 00:10:00 PreventUserIdleSystemSleep named: "again"',
          '   pid 7(sharingd): [0x0004] 00:00:05 UserIsActive named: "not about sleep"',
        }, "\n")
        local names = M.holders(text)
        return table.concat(names, ", ")
               == "coreaudiod (PreventUserIdleSystemSleep), caffeinate (PreventUserIdleDisplaySleep)"
               and #M.holders("") == 0, table.concat(names, ", ")
      end)())

-- One caffeinate held at a time, and keepAwake in the context while it runs.
local started, alerts = {}, {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
local realPath = cl.tools.path
stub(cl.tools, "path", function(name)
  if name == "caffeinate" then return "/usr/bin/caffeinate" end
  return realPath(name)
end)
stub(hs.task, "new", function(program, callback, _, args)
  local task = { program = program, args = table.concat(args or {}, " "), done = callback }
  function task:start() return self end
  function task:terminate() self.terminated = true; if self.done then self.done(15, "", "") end end
  function task:isRunning() return not self.terminated end
  started[#started + 1] = task
  return task
end)

cl.executeCommand("keepawake.on", {}, {})
local first = started[#started]
local awake = cl.buildContext().keepAwake
cl.executeCommand("keepawake.for", { minutes = 15 }, {})
local second = started[#started]
cl.executeCommand("keepawake.off", {}, {})
local after = cl.buildContext().keepAwake
check("Keep awake runs caffeinate and says so in the context; a new one replaces it; Allow sleep ends it",
      first and first.program == "/usr/bin/caffeinate" and first.args == "-di" and awake == true
      and first.terminated and second ~= first and second.args == "-di -t 900"
      and second.terminated and after == nil,
      ("%s / %s / awake %s then %s"):format(first and first.args, second and second.args,
                                           tostring(awake), tostring(after)))

check("Keep awake for… offers the minutes in keepawake.durations, by the hour where they are whole hours",
      (function()
        local options = cl.getCommand("keepawake.for").inputs[1].picker.options()
        local labels = {}
        for i, o in ipairs(options) do labels[i] = o.label .. "=" .. tostring(o.value) end
        return table.concat(labels, " ") == "15 minutes=15 1 hour=60 2 hours=120", table.concat(labels, " ")
      end)())
