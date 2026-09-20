-- CommandLayer.spoon/tests/extensions/selection.lua
-- The selection extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
stub(cl.tools.paths, "open", "/usr/bin/open")
local M = cl.modules.selection

-- Elements as hs.axuielement hands them out, every message recorded. One from
-- an app that never answers costs the timeout set on it, else macOS's six
-- seconds, on a clock only these checks move.
local now, calls = 0, {}
stub(cl, "clock", function() return now end)

local function element(name, attrs, hangs)
  local e = {}
  function e.setTimeout(self, seconds)
    calls[#calls + 1] = name .. " timeout"
    self.timeout = seconds
    return self
  end
  function e.attributeValue(self, attr)
    calls[#calls + 1] = name .. " " .. attr .. (self.timeout and "" or " untimed")
    if hangs then
      now = now + (self.timeout or 6) * 1000
      return nil, "timeout"
    end
    return attrs[attr]
  end
  return e
end

local root
stub(hs, "axuielement", { applicationElement = function()
  calls[#calls + 1] = "applicationElement"
  return root
end })
stub(hs, "processInfo", { processID = 7 })
local pid = 42
stub(hs.application, "frontmostApplication", function()
  return { name = function() return "TextEdit" end, bundleID = function() return "com.apple.TextEdit" end,
           pid = function() return pid end }
end)

local function focusedWith(attrs, hangs)
  root = element("app", { AXFocusedUIElement = element("focused", attrs, hangs) })
end

local function capture()
  calls = {}
  return cl.buildContext()
end

local function called(entry)
  for _, c in ipairs(calls) do if c == entry then return true end end
  return false
end

focusedWith({ AXRole = "AXTextArea", AXSelectedText = "hello world" })
local ctx = capture()
local untimed = false
for _, c in ipairs(calls) do if c:find("untimed", 1, true) then untimed = true end end
check("the focused element's selected text is the selection, every message under a short timeout",
      ctx.selection == "hello world" and not untimed and called("focused AXSelectedText")
      and M.timeoutSeconds > 0 and M.timeoutSeconds <= 0.25,
      table.concat(calls, ", "))

focusedWith({ AXRole = "AXTextField", AXSubrole = "AXSecureTextField", AXSelectedText = "hunter2" })
local bySubrole = capture()
local askedBySubrole = called("focused AXSelectedText")
focusedWith({ AXRole = "AXSecureTextField", AXSelectedText = "hunter2" })
local byRole = capture()
check("a password field's text is never asked for",
      bySubrole.selection == nil and byRole.selection == nil and not askedBySubrole
      and not called("focused AXSelectedText"),
      table.concat(calls, ", "))

stub(hs.eventtap, "isSecureInputEnabled", function() return true end)
focusedWith({ AXRole = "AXTextArea", AXSelectedText = "hello" })
local secure = capture()
check("while Secure Input is on, Accessibility is not asked at all",
      secure.secureInput == true and secure.selection == nil and #calls == 0, table.concat(calls, ", "))
stub(hs.eventtap, "isSecureInputEnabled", function() return false end)

local function selectionOf(text)
  focusedWith({ AXRole = "AXTextArea", AXSelectedText = text })
  return capture().selection
end
check("a selection longer than maxLength, or nothing but spaces, is no selection",
      selectionOf(("x"):rep(M.maxLength + 1)) == nil and selectionOf(("x"):rep(M.maxLength)) ~= nil
      and selectionOf(" \n ") == nil and selectionOf("") == nil and M.maxLength <= 10000)

root = element("app", {})
local noFocus = capture()
local noFocusCalls = table.concat(calls, ", ")
focusedWith({ AXSelectedText = "no role" })
local noRole = capture()
local noRoleAsked = called("focused AXSelectedText")
pid = 7
focusedWith({ AXRole = "AXTextArea", AXSelectedText = "own" })
local own = capture()
local ownCalls = #calls
pid = 42
check("no focused element, a role that does not read, or Hammerspoon in front: nothing more is asked",
      noFocus.selection == nil and noFocusCalls == "applicationElement, app timeout, app AXFocusedUIElement"
      and noRole.selection == nil and not noRoleAsked and own.selection == nil and ownCalls == 0,
      noFocusCalls .. " / " .. tostring(noRoleAsked) .. " / " .. ownCalls)

root = element("app", {}, true)
capture()
local hungApp = cl.performance()["capture.selection"]
local before = now
focusedWith({}, true)
capture()
local hungElement = now - before
check("an app that stops answering costs one timeout, as capture.selection measures it",
      hungApp ~= nil and hungApp.max == M.timeoutSeconds * 1000 and hungElement == M.timeoutSeconds * 1000,
      ("%s ms, then %s ms"):format(hungApp and tostring(hungApp.max), tostring(hungElement)))

-- Lua's own share of an open, with an app that answers at once.
do
  local front = hs.application.frontmostApplication()
  focusedWith({ AXRole = "AXTextArea", AXSubrole = "AXContentList", AXSelectedText = "hello world" })
  local rounds = 2000
  local started = os.clock()
  for _ = 1, rounds do M.read(front) end
  local each = (os.clock() - started) * 1000 / rounds
  check("reading the selection costs well under a millisecond of Lua", each < 0.1, ("%.4f ms"):format(each))
end

local subjectCtx = { selection = "  two words ", clipboard = "SECRET" }
local function selectionSubjects(context)
  local out = {}
  for _, s in ipairs(cl.ambientSubjects(context)) do
    if s.kind == "selection" then out[#out + 1] = s end
  end
  return out
end
local subjects = selectionSubjects(subjectCtx)
local verbs = {}
for _, row in ipairs(cl.itemActions(subjects[1] or { kind = "selection" }, subjectCtx)) do
  verbs[#verbs + 1] = row.command
end
table.sort(verbs)
check("a selection is a subject whose verbs are Look Up, Search the web and Copy",
      #subjects == 1 and subjects[1].value == "  two words " and #selectionSubjects({}) == 0
      and table.concat(verbs, " ") == "selection.copy selection.lookUp selection.searchWeb",
      table.concat(verbs, " "))

local opened = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done }
  function t.start(self) return self end
  function t.terminate() end
  if program == "/usr/bin/open" then opened[#opened + 1] = t end
  return t
end)
local function lastOpened(i)
  local t = opened[i]
  return t and t.args[#t.args]
end

cl.executeCommand("selection.lookUp", { text = { kind = "selection", value = "naïve ${clipboard} a&b" } }, subjectCtx)
check("Look Up opens dict:// with the text percent-encoded, so nothing in it is filled in as a template",
      lastOpened(1) == "dict://na%C3%AFve%20%24%7Bclipboard%7D%20a%26b", tostring(lastOpened(1)))

stub(hs.http, "encodeForQuery", function(text) return M.encode(text) end)
cl.executeCommand("selection.searchWeb", { text = { kind = "selection", value = "  two words " } }, subjectCtx)
local wanted = cl.setting("browser", "searchURL"):gsub("%${query}", "two%%20words")
check("Search the web runs the browser's search by id, with the text trimmed and encoded",
      lastOpened(2) == wanted, tostring(lastOpened(2)) .. " / " .. wanted)

local alerts = {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
local realExecute = cl.executeCommand
stub(cl, "executeCommand", function(id, ...)
  if id == "browser.searchWeb" then return false end
  return realExecute(id, ...)
end)
cl.getCommand("selection.searchWeb").run({ text = { kind = "selection", value = "x" } }, subjectCtx)
check("without the browser's search, Search the web says so",
      #alerts == 1 and alerts[1]:find("Browser", 1, true) ~= nil and #opened == 2, table.concat(alerts, " | "))
cl.executeCommand = realExecute

local copied
stub(hs.pasteboard, "setContents", function(text) copied = text end)
cl.executeCommand("selection.copy", { text = { kind = "selection", value = "  two ${clipboard} " } }, subjectCtx)
check("Copy puts the selected text on the clipboard as it is", copied == "  two ${clipboard} ", tostring(copied))
