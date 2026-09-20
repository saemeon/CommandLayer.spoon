-- CommandLayer.spoon/tests/extensions/keybindings.lua
-- The Keyboard Shortcuts picker, and the keybindings extension's verbs on
-- its rows, against a keybindings.json in a folder of the suite's own.

local T = ...
local check, group, stub = T.check, T.group, T.stub

local function writeFile(path, text)
  local handle = assert(io.open(path, "w"))
  handle:write(text)
  handle:close()
end

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("a")
  handle:close()
  return text
end

local folder = os.tmpname() .. "-keybindings-picker"
os.execute(("mkdir -p %q"):format(folder))
local path = folder .. "/keybindings.json"
writeFile(path, [=[[
  { "key": "cmd+9", "command": "quickOpen.back", "when": "activeView == 'root'" },
  { "key": "cmd+8", "command": "workbench.action.openSettingsJson" },
  { "key": "cmd+r", "command": "-quickOpen" }
]
]=])

local layer = T.loadKernel()
layer.userDir = folder
layer.setup()
local cl = T.adopt(layer)
-- An entry naming a command nobody registered, added after the files were
-- checked, so it is a row and not a problem.
cl.keybindings[#cl.keybindings + 1] = { key = "cmd+6", command = "nobody.registered" }

local ctx = T.context()

local function rowsOf()
  return cl.rowsOfView("keybindings", ctx)
end

local function rowFor(rows, key)
  for _, row in ipairs(rows) do
    if row.subject and cl.chordId(row.subject.key) == cl.chordId(key) then return row end
  end
end

local function verb(subject, id)
  for _, row in ipairs(cl.itemActions(subject, ctx)) do
    if row.command == id then return row end
  end
end

-- Timers held until a check lets time pass.
local timers = {}
local function holdTimers()
  timers = {}
  stub(hs.timer, "doAfter", function(_, fn)
    local t = { fn = fn }
    function t.stop() t.stopped = true end
    timers[#timers + 1] = t
    return t
  end)
end
local function letTimePass()
  local due = timers
  timers = {}
  for _, t in ipairs(due) do
    if not t.stopped then t.fn() end
  end
end

local alerts, closed = {}, {}
local function recordAlerts()
  alerts, closed = {}, {}
  stub(hs.alert, "show", function(text)
    alerts[#alerts + 1] = text
    return "alert" .. #alerts
  end)
  stub(hs.alert, "closeSpecific", function(id) closed[#closed + 1] = id end)
end
local function said(piece)
  for _, text in ipairs(alerts) do
    if tostring(text):find(piece, 1, true) then return true end
  end
  return false
end

group("keybindings: the picker")
do
  local rows = rowsOf()
  local back, settings = rowFor(rows, "cmd+9"), rowFor(rows, "cmd+8")
  local actions, palette, unknown = rowFor(rows, "cmd+k"), rowFor(rows, "cmd+o"), rowFor(rows, "cmd+6")
  check("every keybinding in effect is a row: its command's title with category, its key, where it came from "
        .. "and its when; one removed is not listed, and one naming no command shows the id and runs nothing",
        back and back.label == "back" and back.description == "cmd+9"
        and back.detail == "User, when activeView == 'root'"
        and settings and settings.label == "Preferences: Open User Settings (JSON)" and settings.detail == "User"
        and actions and actions.detail == "Default" and actions.subject.source == "default"
        and palette and palette.label == "Quick Open -- palette"
        and unknown and unknown.label == "nobody.registered" and unknown.command == nil
        and unknown.detail == "No file, no such command"
        and rowFor(rows, "cmd+r") == nil and cl.viewForPrefix("keybindings ") ~= nil,
        ("%s | %s | %s | %s"):format(tostring(back and back.detail), tostring(settings and settings.label),
                                     tostring(palette and palette.label), tostring(unknown and unknown.detail)))

  local ran
  stub(cl.getCommand("workbench.action.openSettingsJson"), "run", function() ran = true end)
  cl.runRow(settings)
  local bad = {}
  for _, row in ipairs(rows) do
    for _, message in ipairs(cl.checkRow(row)) do bad[#bad + 1] = row.label .. ": " .. message end
  end
  check("picking a row runs its command with its args, and every row has a row's fields",
        ran and palette.command == "quickOpen" and palette.args.view == "palette" and #bad == 0,
        table.concat(bad, "; "))

  local remove = verb(back.subject, "keybindings.editor.removeKeybinding")
  local change = verb(back.subject, "keybindings.editor.defineKeybinding")
  check("cmd+k on a keybinding offers Remove Keybinding, naming its key, and Change Keybinding…, and on "
        .. "another row neither",
        remove and remove.label == "Remove Keybinding -- cmd+9" and change and change.label == "Change Keybinding…"
        and verb({ kind = "command", id = "x" }, "keybindings.editor.removeKeybinding") == nil
        and verb({ kind = "command", id = "x" }, "keybindings.editor.defineKeybinding") == nil,
        tostring(remove and remove.label))

  local opened
  stub(cl, "quickOpen", function(name) opened = name end)
  cl.executeCommand("workbench.action.openGlobalKeybindings", {}, ctx)
  check("Preferences: Open Keyboard Shortcuts opens the picker", opened == "keybindings", tostring(opened))
end

group("keybindings: removing from the picker")
holdTimers()
do
  local list = T.openRecorded("keybindings")
  local row = rowFor(list.shown, "cmd+9")
  T.recordedSpec("actions")
  cl.push("actions", { ctx = row.ctx, subject = row.subject, label = row.label })
  local panel = T.lastRecorded()
  local index
  for i, action in ipairs(panel.shown or {}) do
    if action.command == "keybindings.editor.removeKeybinding" then index = i end
  end
  if index then
    panel.row = index
    panel.accept()
  end
  local backOn = cl.topView() and cl.topView().name
  letTimePass()
  local shown = T.lastRecorded().shown or {}
  check("Remove Keybinding deletes the entry from keybindings.json, unbinds it, and goes back to the list, "
        .. "drawn again without it",
        index ~= nil and not readFile(path):find("cmd+9", 1, true) and cl.resolveKeybinding("cmd+9", {
          activeView = "root" }) == nil and backOn == "keybindings" and rowFor(shown, "cmd+9") == nil
        and rowFor(shown, "cmd+8") ~= nil,
        ("%s on %s, %d rows"):format(tostring(index), tostring(backOn), #shown))
  cl.executeCommand("quickOpen.hide")
end

group("keybindings: changing a key")
holdTimers()
recordAlerts()
do
  local taps = {}
  stub(hs.eventtap, "new", function(types, fn)
    local tap = { types = types, fn = fn }
    function tap.start(t) t.running = true; return t end
    function tap.stop(t) t.running = false end
    taps[#taps + 1] = tap
    return tap
  end)
  stub(hs.keycodes, "map", { [40] = "k", [53] = "escape" })
  local function press(keyCode, flags)
    local tap = taps[#taps]
    return tap.fn({ getKeyCode = function() return keyCode end, getFlags = function() return flags end })
  end
  local reopened = {}
  stub(cl, "quickOpen", function(name) reopened[#reopened + 1] = name end)

  local function subject(key)
    return rowFor(rowsOf(), key).subject
  end

  cl.executeCommand("keybindings.editor.defineKeybinding", { keybinding = subject("cmd+8") }, ctx)
  local tap = taps[#taps]
  local asked = tap and tap.running and tap.types[1] == hs.eventtap.event.types.keyDown and said("Press")
  local swallowed = tap and press(40, { cmd = true, alt = true })
  local stoppedAtOnce = tap and not tap.running and readFile(path):find("cmd+8", 1, true) ~= nil
  letTimePass()
  local text = readFile(path)
  check("Change Keybinding… asks for the keys, takes one chord from a key-down tap and stops it, then writes the "
        .. "entry on the new key a turn later, binds it, and opens the list again",
        asked and swallowed == true and stoppedAtOnce and #closed == 1
        and text:find('{ "key": "alt+cmd+k", "command": "workbench.action.openSettingsJson" }', 1, true) ~= nil
        and not text:find("cmd+8", 1, true)
        and (cl.resolveKeybinding("cmd+alt+k", {}) or {}).command == "workbench.action.openSettingsJson"
        and reopened[1] == "keybindings",
        tostring(text) .. " / " .. table.concat(alerts, " | "))

  local before = readFile(path)
  cl.executeCommand("keybindings.editor.defineKeybinding", { keybinding = subject("cmd+alt+k") }, ctx)
  local escapeTap = taps[#taps]
  press(53, {})
  letTimePass()
  cl.executeCommand("keybindings.editor.defineKeybinding", { keybinding = subject("cmd+alt+k") }, ctx)
  local waitingTap = taps[#taps]
  letTimePass()
  check("escape stops the tap and writes nothing, and a capture nobody answers stops by itself",
        escapeTap ~= tap and not escapeTap.running and readFile(path) == before and #reopened == 2
        and waitingTap ~= escapeTap and not waitingTap.running and #reopened == 2,
        ("%s %s %d"):format(tostring(escapeTap.running), tostring(waitingTap.running), #reopened))

  -- Only this extension started: the others would reach parts of macOS the
  -- harness does not stub.
  for name, module in pairs(cl.modules) do
    if name ~= "keybindings" and type(module) == "table" and module.start then stub(module, "start", T.noop) end
  end
  cl.startExtensions()
  cl.executeCommand("keybindings.editor.defineKeybinding", { keybinding = subject("cmd+alt+k") }, ctx)
  local stoppedTap = taps[#taps]
  local wasRunning = stoppedTap.running
  cl.stopExtensions()
  check("stopping the extension stops a capture still waiting", wasRunning and stoppedTap.running == false)
end

group("keybindings: refused")
recordAlerts()
do
  cl.bindHotkeys({ enter = "alt+space" })
  local entry = rowFor(rowsOf(), "alt+space")
  local before = readFile(path)
  if entry then cl.executeCommand("keybindings.editor.removeKeybinding", { keybinding = entry.subject }, ctx) end
  check("a keybinding from init.lua's bindHotkeys is listed as such, and removing it is refused with an alert",
        entry and entry.subject.source == "bindHotkeys" and readFile(path) == before and said("init.lua"),
        table.concat(alerts, " | "))
end

os.execute(("rm -rf %q"):format(folder))

group("keybindings: switched off")
recordAlerts()
do
  local off = T.layer({ ["keybindings.enabled"] = false })
  T.openRecorded("keybindings")
  check("switched off, the Keyboard Shortcuts picker has no rows, and says so when opened",
        #off.rowsOfView("keybindings", ctx) == 0 and #alerts == 1
        and said('"keybindings.enabled": true in settings.json'),
        table.concat(alerts, " | "))
end
