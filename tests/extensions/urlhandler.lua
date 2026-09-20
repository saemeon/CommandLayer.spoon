-- CommandLayer.spoon/tests/extensions/urlhandler.lua
-- The URL handler's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.urlhandler

local bound, binds = {}, 0
stub(hs.urlevent, "bind", function(name, fn) binds = binds + 1; bound[name] = fn end)
local alerts = {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
-- hs.json.decode raises on text that is not JSON.
local DECODED = { ['{"target":"a b"}'] = { target = "a b" }, ["[1,2]"] = { 1, 2 } }
stub(hs.json, "decode", function(text)
  if DECODED[text] == nil then error("not JSON") end
  return DECODED[text]
end)

local ran = {}
for _, id in ipairs({ "urltest.allowed", "urltest.other" }) do
  cl.registerCommand(id, { title = id, menus = {},
                           run = function(args) ran[#ran + 1] = { id = id, args = args } end })
end

M.stop()
M.start()
local handler = bound[M.event]

-- Guarded, so a handler that throws still gives print back.
local function open(params)
  local lines, restore = T.capturingPrint()
  local ok = handler ~= nil and pcall(handler, M.event, params)
  restore()
  if not ok then lines.threw = true end
  return lines
end

local refusedByDefault = open({ command = "urltest.allowed" })
check("the URL is bound, and with the allowlist as shipped nothing runs",
      type(handler) == "function" and #ran == 0 and #alerts == 1
      and (refusedByDefault[1] or ""):find("urltest.allowed", 1, true) ~= nil,
      tostring(refusedByDefault[1]))

local saved = cl.userSettings
cl.userSettings = { ["urlhandler.allowedCommands"] = { "urltest.allowed" } }

open({ command = "urltest.allowed", args = '{"target":"a b"}' })
check("a command listed runs by id with its args decoded",
      #ran == 1 and ran[1].id == "urltest.allowed" and ran[1].args.target == "a b",
      ran[1] and ran[1].id)

local other = open({ command = "urltest.other", args = '{"target":"a b"}' })
check("a command not listed is refused with an alert and a log line naming it",
      #ran == 1 and #alerts == 2 and alerts[2]:find("urltest.other", 1, true)
      and (other[1] or ""):match("^%[commandlayer%].*urltest%.other") ~= nil,
      tostring(alerts[2]) .. " / " .. tostring(other[1]))

open({ command = "urltest.allowed", args = "[1,2]" })
open({ command = "urltest.allowed", args = "{nope" })
check("args that are not a JSON object refuse the call",
      #ran == 1 and #alerts == 4 and alerts[4]:find("not a JSON object", 1, true), tostring(alerts[4]))

cl.userSettings = saved

M.stop()
check("stop unbinds the URL", bound[M.event] == nil and binds == 2, tostring(binds))
