-- CommandLayer.spoon/tests/extensions/secureinput.lua
-- The Secure Input extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
stub(cl.tools.paths, "ioreg", "/usr/sbin/ioreg")
local M = cl.modules.secureinput

local IOREG = [[
+-o Root  <class IORegistryEntry, id 0x100000100, retain 60>
    {
      "IOKitBuildVersion" = "Darwin Kernel Version"
      "IOConsoleUsers" = ({"kCGSSessionOnConsoleKey"=No,"kCGSSessionSecureInputPID"=11,"kCGSSessionUserIDKey"=502},{"kCGSSessionOnConsoleKey"=Yes,"kCGSSessionSecureInputPID"=407,"kCGSSessionUserIDKey"=501})
    }
]]
check("the app holding Secure Input is the console session's, read from ioreg",
      M.holderPID(IOREG) == 407
      and M.holderPID('"IOConsoleUsers" = ({"kCGSSessionSecureInputPID"=9})') == 9
      and M.holderPID('"IOConsoleUsers" = ({"kCGSSessionOnConsoleKey"=Yes})') == nil
      and M.holderPID("") == nil,
      tostring(M.holderPID(IOREG)))

local secure = false
stub(hs.eventtap, "isSecureInputEnabled", function() return secure end)
local spawned = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done }
  function t.start(self) return self end
  function t.terminate() end
  spawned[#spawned + 1] = t
  return t
end)
local function ioregTasks()
  local n = 0
  for _, t in ipairs(spawned) do if t.program == "/usr/sbin/ioreg" then n = n + 1 end end
  return n
end
stub(hs.application, "applicationForPID", function(pid)
  if pid == 407 then return { name = function() return "1Password" end } end
end)

local off = cl.buildContext()
local asksWhileOff = ioregTasks()
secure = true
local on = cl.buildContext()
cl.buildContext()
check("secureInput is set only while it is on, and ioreg is asked once, only then",
      off.secureInput == nil and asksWhileOff == 0 and on.secureInput == true and ioregTasks() == 1,
      tostring(off.secureInput) .. " / " .. tostring(on.secureInput) .. " / " .. ioregTasks() .. " asks")

local alerts, pasted = {}, {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
stub(hs.pasteboard, "setContents", function(text) pasted[#pasted + 1] = text end)
cl.executeCommand("system.paste", { text = "hunter2" }, on)
local alertedEarly = #alerts
for _, t in ipairs(spawned) do
  if t.program == "/usr/sbin/ioreg" and t.done then t.done(0, IOREG, "") end
end
check("Paste while Secure Input is on says so, naming the app once ioreg answers, and still pastes",
      alertedEarly == 0 and #alerts == 1 and alerts[1]:find("1Password", 1, true) ~= nil
      and pasted[1] == "hunter2",
      table.concat(alerts, " | "))

local fire
stub(hs.timer, "doAfter", function(_, fn) fire = fn; return { stop = function() end } end)
local pressed = 0
stub(hs.eventtap, "keyStroke", function() pressed = pressed + 1 end)
-- Off by the time the command runs, as it is once the picker has focus.
secure = false
cl.executeCommand("system.emojiAndSymbols", {}, { secureInput = true })
if fire then fire() end
check("Emoji & Symbols is not pressed when Secure Input was on as the layer opened, the name kept, not asked again",
      pressed == 0 and #alerts == 2 and alerts[2]:find("1Password", 1, true) ~= nil and ioregTasks() == 1,
      table.concat(alerts, " | "))

secure = false
fire = nil
cl.executeCommand("system.emojiAndSymbols", {}, {})
if fire then fire() end
check("with Secure Input off, nothing is said and the chord is pressed", pressed == 1 and #alerts == 2)
