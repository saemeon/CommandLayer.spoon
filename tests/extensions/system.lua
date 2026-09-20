-- CommandLayer.spoon/tests/extensions/system.lua
-- The system extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
T.stub(cl.tools.paths, "open", "/usr/bin/open")
T.stub(cl.tools.paths, "osascript", "/usr/bin/osascript")

local locked, pressed = 0, nil
local saved = { caffeinate = hs.caffeinate, eventtap = hs.eventtap, doAfter = hs.timer.doAfter }
hs.caffeinate = { lockScreen = function() locked = locked + 1 end }
hs.eventtap = { keyStroke = function(mods, key) pressed = table.concat(mods, "+") .. "+" .. key end }
local fire, delay
hs.timer.doAfter = function(seconds, fn) delay, fire = seconds, fn; return { stop = function() end } end

cl.executeCommand("system.lockScreen", {})
cl.executeCommand("system.emojiAndSymbols", {})
local early = pressed
if fire then fire() end

hs.caffeinate, hs.eventtap, hs.timer.doAfter = saved.caffeinate, saved.eventtap, saved.doAfter
check("Lock screen locks through macOS", locked == 1)

local copied, pasted = {}, {}
local savedClipboard = hs.pasteboard.setContents
hs.pasteboard.setContents = function(text) copied[#copied + 1] = text end
cl.executeCommand("system.copy", { text = "a ${clipboard} b" }, { clipboard = "no" })
hs.pasteboard.setContents = function(text) pasted[#pasted + 1] = text end
cl.executeCommand("system.paste", { text = "pasted" }, {})
hs.pasteboard.setContents = savedClipboard
check("Copy and Paste take the text as it is, never as a template",
      copied[1] == "a ${clipboard} b" and pasted[1] == "pasted",
      tostring(copied[1]) .. " / " .. tostring(pasted[1]))
check("Emoji & Symbols presses macOS's own chord once the launcher has closed",
      early == nil and delay and delay > 0 and pressed == "ctrl+cmd+space", tostring(pressed))

check("paste is the system extension's command, and not on the layer",
      (cl.getCommand("system.paste") or {}).extension == "system" and cl.paste == nil)
do
  -- Put back by hand: restoring every stub would also take back the tool paths stubbed above.
  local onClipboard, strokes, timers = {}, {}, {}
  local before = { set = hs.pasteboard.setContents, stroke = hs.eventtap.keyStroke, after = hs.timer.doAfter }
  hs.pasteboard.setContents = function(text) onClipboard[#onClipboard + 1] = text end
  hs.eventtap.keyStroke = function(mods, key) strokes[#strokes + 1] = table.concat(mods, "+") .. "+" .. key end
  hs.timer.doAfter = function(seconds, fn)
    timers[#timers + 1] = { seconds = seconds, fn = fn }
    return { stop = function() end }
  end
  cl.executeCommand("system.paste", { text = "" }, {})
  cl.executeCommand("system.paste", {}, {})
  check("paste ignores nothing", #onClipboard == 0 and #timers == 0)
  cl.executeCommand("system.paste", { text = "later" }, {})
  local early = #strokes
  for _, t in ipairs(timers) do t.fn() end
  check("Paste puts the text on the clipboard and presses cmd+v a tenth of a second later, once the picker is gone",
        early == 0 and onClipboard[1] == "later" and #timers == 1 and timers[1].seconds == 0.1
        and strokes[1] == "cmd+v", table.concat(strokes, " "))
  hs.pasteboard.setContents, hs.eventtap.keyStroke, hs.timer.doAfter = before.set, before.stroke, before.after
end

local M = cl.modules.system
local parsed = M.parseHandlers(table.concat({
  "com.apple.TextEdit\t/System/Applications/TextEdit.app\tTextEdit\t",
  "com.microsoft.VSCode\t/Applications/Visual Studio Code.app\tVisual Studio Code\tdefault",
  "\t/Applications/bbedit.app\t\t",
  "com.apple.TextEdit\t/System/Applications/TextEdit.app\tTextEdit\t",
}, "\n"))
check("Launch Services' apps read with the default first, then by name, each once",
      #parsed == 3 and parsed[1].name == "Visual Studio Code" and parsed[1].default == true
      and parsed[2].name == "bbedit" and parsed[2].id == nil and parsed[3].id == "com.apple.TextEdit",
      (parsed[1] and parsed[1].name or "") .. ", " .. (parsed[2] and parsed[2].name or ""))

local function keyOf(subject) return select(2, M.openWithTarget(subject)) end
check("the apps are kept by file extension, folder or URL scheme",
      keyOf({ kind = "file", path = "/tmp/a.TXT" }) == "file:txt"
      and keyOf({ kind = "file", path = "/tmp/dir/" }) == "folder"
      and keyOf({ kind = "project", path = "/code/x" }) == "folder"
      and keyOf({ kind = "file", path = "/tmp/Makefile" }) == "path:/tmp/Makefile"
      and keyOf({ kind = "url", value = "HTTPS://example.com" }) == "scheme:https"
      and M.openWithTarget({ kind = "url", value = "not a url" }) == nil
      and M.openWithTarget({ kind = "window" }) == nil)

do
  local spawned = {}
  local savedNew = hs.task.new
  hs.task.new = function(program, done, _, args)
    local t = { program = program, args = args or {}, done = done }
    function t.start(self) return self end
    function t.terminate() end
    spawned[#spawned + 1] = t
    return t
  end
  local command = cl.getCommand("system.openWith")
  local search = command and command.inputs[2].picker.search
  local file = { kind = "file", path = "/tmp/it's $(x).txt" }
  local first, second, third
  if search then
    search("", {}, { target = file }, function(results) first = results end)
    search("code", {}, { target = file }, function(results) second = results end)
  end
  local asked = #spawned
  local task = spawned[1] or { args = {} }
  if task.done then
    task.done(0, "com.apple.TextEdit\t/System/Applications/TextEdit.app\tTextEdit\t\n"
                 .. "com.microsoft.VSCode\t/Applications/Visual Studio Code.app\tVisual Studio Code\tdefault\n", "")
  end
  if search then
    search("", {}, { target = { kind = "file", path = "/elsewhere/b.txt" } },
           function(results) third = results end)
  end
  check("Open with… asks Launch Services once per kind of thing, off the main thread, the path an argument",
        asked == 1 and task.program == "/usr/bin/osascript" and task.args[1] == "-l"
        and task.args[2] == "JavaScript" and task.args[4] == M.HANDLERS_SCRIPT
        and task.args[5] == file.path and #spawned == 1 and third ~= nil and #third == 2,
        asked .. " asks, " .. #spawned .. " tasks")
  check("its answer lists the apps, default first, whatever was typed: the layer's matcher narrows them",
        first and #first == 2 and first[1].label == "Visual Studio Code" and first[1].description == "Default"
        and first[1].value.id == "com.microsoft.VSCode"
        and second and #second == 2 and second[1].label == "Visual Studio Code")

  cl.executeCommand("system.openWith", { target = file,
    app = { id = "com.apple.TextEdit", path = "/System/Applications/TextEdit.app", name = "TextEdit" } }, {})
  local byBundle = spawned[#spawned]
  cl.executeCommand("system.openWith", { target = { kind = "url", value = "https://example.com" },
    app = { path = "/Applications/bbedit.app", name = "bbedit" } }, {})
  local byPath = spawned[#spawned]
  hs.task.new = savedNew
  check("the app chosen opens it through open -b, or open -a with a path when it has no bundle id",
        byBundle.program == "/usr/bin/open" and byBundle.args[1] == "-b"
        and byBundle.args[2] == "com.apple.TextEdit" and byBundle.args[3] == file.path
        and byPath.program == "/usr/bin/open" and byPath.args[1] == "-a"
        and byPath.args[2] == "/Applications/bbedit.app" and byPath.args[3] == "https://example.com",
        tostring(byBundle.args[1]) .. " " .. tostring(byPath.args[1]))
end

local function labels(subject)
  local out = {}
  for _, row in ipairs(cl.itemActions(subject, {})) do out[row.label] = true end
  return out
end
check("Open with… is a verb on files, folders, projects and links, and not on a window",
      labels({ kind = "file", path = "/tmp/a.txt" })["Open with…"]
      and labels({ kind = "folder", path = "/tmp" })["Open with…"]
      and labels({ kind = "url", value = "https://example.com" })["Open with…"]
      and not labels({ kind = "window", id = 1 })["Open with…"])

do
  local stub = T.stub
  local spawned = {}
  stub(hs.task, "new", function(program, done, _, args)
    local t = { program = program, args = args or {}, done = done }
    function t.start(self) return self end
    function t.terminate() end
    spawned[#spawned + 1] = t
    return t
  end)
  cl.executeCommand("system.screenshotToolbar", {}, {})
  cl.executeCommand("system.open", {}, {})
  local toolbar = spawned[1] or { args = {} }
  check("Show toolbar opens Screenshot.app by its bundle id, and Open given nothing to open runs nothing",
        #spawned == 1 and toolbar.program == "/usr/bin/open" and toolbar.args[1] == "-b"
        and toolbar.args[2] == "com.apple.screenshot.launcher" and #toolbar.args == 2,
        #spawned .. " tasks: " .. table.concat(toolbar.args, " "))

  local fires, pressed = {}, {}
  stub(hs.timer, "doAfter", function(_, fn) fires[#fires + 1] = fn; return { stop = function() end } end)
  stub(hs.eventtap, "keyStroke", function(mods, key) pressed[#pressed + 1] = table.concat(mods, "+") .. "+" .. key end)
  for _, id in ipairs({ "captureScreen", "captureSelection", "copyScreen", "copySelection" }) do
    cl.executeCommand("system." .. id, {}, {})
  end
  local early = #pressed
  for _, fn in ipairs(fires) do fn() end
  check("the captures press macOS's own shortcuts, once the launcher has closed",
        early == 0 and table.concat(pressed, " ") == "cmd+shift+3 cmd+shift+4 ctrl+cmd+shift+3 ctrl+cmd+shift+4",
        table.concat(pressed, " "))

  fires, pressed = {}, {}
  cl.executeCommand("system.captureSelection", {}, { secureInput = true })
  for _, fn in ipairs(fires) do fn() end
  check("a capture is not pressed while Secure Input held the keys as the layer opened", #fires == 1 and #pressed == 0)

  local found = {}
  for _, file in ipairs(T.pluginCode({ "extensions", "views" })) do
    T.eachCodeLine(file, function(code, n)
      if code:find("screencapture") then found[#found + 1] = file.path .. ":" .. n end
    end)
  end
  check("nothing runs screencapture, which would ask for Screen Recording", #found == 0, table.concat(found, ", "))
end
