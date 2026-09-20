-- CommandLayer.spoon/tests/keybindingwrites.lua
-- Removing and changing a keybinding: the active profile's own
-- keybindings.json edited in its text, and every key bound again.

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

-- A folder of its own as the user folder, never the person's.
local folder = os.tmpname() .. "-keywrites"
os.execute(("mkdir -p %q"):format(folder))
local path = folder .. "/keybindings.json"
writeFile(path, [=[// mine
[
  { "key": "cmd+9", "command": "quickOpen.back" }, // back
  { "key": "cmd+8", "command": "quickOpen.accept", "when": "activeView == 'root'" },
  { "key": "cmd+6", "command": "no.such.command" }
]
]=])

local layer = T.loadKernel()
layer.userDir = folder

-- As hs.hotkey.modal binds: a hotkey per chord, kept in `keys`, enabled as
-- the modal is entered.
local modal = layer.modal
modal.keys = {}
modal.bind = function(self, mods, key)
  local hotkey = { key = key, mods = mods, enabled = false }
  function hotkey.delete() hotkey.deleted = true end
  function hotkey.enable()
    hotkey.enabled = true
    return hotkey
  end
  self.keys[#self.keys + 1] = hotkey
  return self
end

local globals = {}
local function recordGlobals()
  stub(hs.hotkey, "new", function(mods, key)
    local hotkey = { key = key, mods = mods }
    function hotkey.enable() return hotkey end
    function hotkey.delete() hotkey.deleted = true end
    globals[#globals + 1] = hotkey
    return hotkey
  end)
end
local alerts = {}
local function recordAlerts()
  stub(hs.alert, "show", function(text) alerts[#alerts + 1] = text end)
end

recordGlobals()
layer.setup()
T.adopt(layer)
layer.bindGlobalKeybindings()

local function entryFor(key, command)
  for _, entry in ipairs(layer.effectiveKeybindings()) do
    if layer.chordId(entry.key) == layer.chordId(key) and entry.command == command then return entry end
  end
end

-- What the keybindings extension writes from: a copy getKeybindings handed out.
local function copyFor(key, command)
  for _, entry in ipairs(layer.getKeybindings()) do
    if layer.chordId(entry.key) == layer.chordId(key) and entry.command == command then return entry end
  end
end

local writes = layer.modules.keybindings

local function modalKeys()
  local keys = {}
  for _, hotkey in ipairs(modal.keys) do
    if not hotkey.deleted then keys[#keys + 1] = hotkey.key end
  end
  table.sort(keys)
  return " " .. table.concat(keys, " ") .. " "
end

local function said(piece)
  for _, text in ipairs(alerts) do
    if tostring(text):find(piece, 1, true) then return true end
  end
  return false
end

group("keybindings: a written chord")
check("a key press is written as keybindings.json writes a chord: VS Code's order, hyper for all four, fn left "
      .. "out, and it binds as the same key",
      layer.chordText({ cmd = true, shift = true }, "P") == "shift+cmd+p"
      and layer.chordText({ ctrl = true, alt = true, shift = true, cmd = true, fn = true }, "left") == "hyper+left"
      and layer.chordText({ fn = true }, "f5") == "f5"
      and layer.chordId(layer.chordText({ alt = true, cmd = true }, "k")) == layer.chordId("cmd+alt+k")
      and layer.chordText({ cmd = true }, nil) == nil,
      tostring(layer.chordText({ cmd = true, shift = true }, "P")))

group("keybindings: where one came from")
check("a keybinding's origin is default for the shipped file, user for the active profile's own, and nothing "
      .. "for one no file gave",
      layer.keybindingOrigin(entryFor("cmd+k", "quickOpen.showActions")) == "default"
      and layer.keybindingOrigin(entryFor("cmd+9", "quickOpen.back")) == "user"
      and layer.keybindingOrigin({ key = "cmd+1", command = "quickOpen.back" }) == nil)

group("keybindings: removing")
recordGlobals()
recordAlerts()
do
  local removed = writes.removeKeybinding(copyFor("cmd+k", "quickOpen.showActions"))
  local text = readFile(path)
  check("removing a default appends a removal naming its key, keeps the file as written, and unbinds the key",
        removed and text == [=[// mine
[
  { "key": "cmd+9", "command": "quickOpen.back" }, // back
  { "key": "cmd+8", "command": "quickOpen.accept", "when": "activeView == 'root'" },
  { "key": "cmd+6", "command": "no.such.command" },
  { "key": "cmd+k", "command": "-quickOpen.showActions" }
]
]=] and layer.resolveKeybinding("cmd+k", {}) == nil and not modalKeys():find(" k ", 1, true)
        and modalKeys():find(" 9 ", 1, true) ~= nil,
        tostring(text) .. modalKeys())

  local function mentionsUnknown()
    for _, p in ipairs(layer.problems) do
      if p.message:find("no.such.command", 1, true) then return true end
    end
    return false
  end
  local wasProblem = mentionsUnknown()
  local first = writes.removeKeybinding(copyFor("cmd+6", "no.such.command"))
  local second = writes.removeKeybinding(copyFor("cmd+9", "quickOpen.back"))
  text = readFile(path)
  check("removing your own entry deletes it from the file, comment and all; a problem it was goes with it, and "
        .. "the reload watching the file takes the write for no change",
        first and second and text == [=[// mine
[
  { "key": "cmd+8", "command": "quickOpen.accept", "when": "activeView == 'root'" },
  { "key": "cmd+k", "command": "-quickOpen.showActions" }
]
]=] and layer.resolveKeybinding("cmd+9", {}) == nil and wasProblem and not mentionsUnknown()
        and layer.profileFilesChanged() == false,
        tostring(text))
end

group("keybindings: changing")
recordGlobals()
recordAlerts()
do
  local closed = layer.topView
  layer.topView = function() return { name = "root" } end
  local changed = writes.changeKeybinding(copyFor("cmd+8", "quickOpen.accept"), "cmd+7")
  layer.topView = closed
  local text = readFile(path)
  local allEnabled = #modal.keys > 0
  for _, hotkey in ipairs(modal.keys) do allEnabled = allEnabled and hotkey.enabled end
  check("changing your own entry's key removes it and adds it again on the new key, its when kept; a key bound "
        .. "while the layer is open is live at once",
        changed and text == [=[// mine
[
  { "key": "cmd+k", "command": "-quickOpen.showActions" },
  { "key": "cmd+7", "command": "quickOpen.accept", "when": "activeView == 'root'" }
]
]=] and (layer.resolveKeybinding("cmd+7", { activeView = "root" }) or {}).command == "quickOpen.accept"
        and layer.resolveKeybinding("cmd+8", { activeView = "root" }) == nil and allEnabled,
        tostring(text))
end
T.restoreStubs()
recordGlobals()
recordAlerts()
do
  local changed = writes.changeKeybinding(copyFor("cmd+o", "quickOpen"), "shift+cmd+o")
  local text = readFile(path)
  local entry = layer.resolveKeybinding("cmd+shift+o", {})
  check("changing a default appends its removal, then the same entry on the new key, its args kept",
        changed and text:find('  { "key": "cmd+7", "command": "quickOpen.accept", "when": "activeView == \'root\'" },\n'
                              .. '  { "key": "cmd+o", "command": "-quickOpen" },\n'
                              .. '  { "key": "shift+cmd+o", "command": "quickOpen", '
                              .. '"args": { "view": "palette" } }\n]\n', 1, true) ~= nil
        and entry ~= nil and entry.args.view == "palette" and layer.resolveKeybinding("cmd+o", {}) == nil
        and (layer.resolveKeybinding("cmd+r", {}) or { args = {} }).args.view == "recent",
        tostring(text))

  globals = {}
  local global = writes.changeKeybinding(copyFor("alt+space", "quickOpen"), "hyper+space")
  local live = {}
  for _, hotkey in ipairs(globals) do
    if not hotkey.deleted then live[#live + 1] = hotkey end
  end
  check("changing a global entry binds the new key in every app at once",
        global and #live == 1 and live[1].key == "space" and #live[1].mods == 4
        and readFile(path):find('{ "key": "hyper+space", "command": "quickOpen", "global": true }', 1, true) ~= nil,
        ("%d live"):format(#live))
end

group("keybindings: refused")
recordGlobals()
recordAlerts()
do
  local before = readFile(path)
  local editsText = writes.changeKeybinding(copyFor("cmd+7", "quickOpen.accept"), "cmd+v")
  local unreadable = writes.changeKeybinding(copyFor("cmd+7", "quickOpen.accept"), "cmmd+k")
  layer.bindHotkeys({ enter = "alt+space" })
  local initLua = writes.removeKeybinding(copyFor("alt+space", "quickOpen"))
  check("a key the search field needs, a key that does not read, and init.lua's bindHotkeys are refused, "
        .. "saying why, and the file is left as it was",
        not editsText and not unreadable and not initLua and readFile(path) == before
        and said("cmd+v: the search field needs this key to edit text") and said('"cmmd+k" is not a key')
        and said("init.lua"),
        table.concat(alerts, " | "))

  local gone = copyFor("cmd+7", "quickOpen.accept")
  writeFile(path, '// by hand\n[\n  { "key": "cmd+r", "command": "-quickOpen" }\n]\n')
  local handEdited = writes.removeKeybinding(gone)
  local afterHand = readFile(path)
  writeFile(path, '[ { "key": ')
  local broken = writes.removeKeybinding(copyFor("cmd+p", "quickOpen"))
  local afterBroken = readFile(path)
  check("an entry no longer in the file, or a file that does not parse, is refused and the file left as it is",
        not handEdited and afterHand == '// by hand\n[\n  { "key": "cmd+r", "command": "-quickOpen" }\n]\n'
        and said("no longer in keybindings.json") and not broken and afterBroken == '[ { "key": '
        and said("does not parse"),
        table.concat(alerts, " | "))

  writeFile(path, "[]\n")
  local afterFix = writes.removeKeybinding(copyFor("cmd+p", "quickOpen"))
  local entering = {}
  for _, entry in ipairs(layer.effectiveKeybindings()) do
    if layer.entersLayer(entry) then entering[#entering + 1] = entry.key end
  end
  check("a write reads the files again from disk, a hand edit since included, and init.lua's bindHotkeys stay",
        afterFix and readFile(path) == '[\n  { "key": "cmd+p", "command": "-quickOpen" }\n]\n'
        and layer.resolveKeybinding("cmd+r", {}) ~= nil and table.concat(entering, " ") == "alt+space",
        table.concat(entering, " "))
end

group("keybindings: a copy")
recordGlobals()
recordAlerts()
do
  writeFile(path, '[\n  { "key": "cmd+3", "command": "quickOpen.back" }\n]\n')
  layer.keybindingsWritten()
  local copy
  for _, entry in ipairs(layer.getKeybindings()) do
    if entry.key == "cmd+3" then copy = entry end
  end
  local removed = copy ~= nil and writes.removeKeybinding(copy)
  local text = readFile(path)
  check("removing a copy getKeybindings handed out removes the entry it was copied from",
        copy ~= nil and copy.source == "user" and removed and not text:find("cmd+3", 1, true)
        and layer.resolveKeybinding("cmd+3", {}) == nil,
        tostring(text) .. " / " .. table.concat(alerts, " | "))
end
os.execute(("rm -rf %q"):format(folder))

-- A shipped profile's keybindings are the profile's; a change to them is the
-- person's, in the profile's folder under the user folder.
group("keybindings: a profile's")
recordGlobals()
do
  local userDir = os.tmpname() .. "-keywrites-profile"
  os.execute(("mkdir -p %q"):format(userDir))
  local profiled = T.loadKernel()
  profiled.userDir, profiled.profile = userDir, "raycast"
  profiled.setup()
  local entry, copy
  for _, e in ipairs(profiled.effectiveKeybindings()) do
    if e.key == "alt+space" then entry = e end
  end
  for _, e in ipairs(profiled.getKeybindings()) do
    if e.key == "alt+space" then copy = e end
  end
  local origin = profiled.keybindingOrigin(entry)
  local removed = profiled.modules.keybindings.removeKeybinding(copy)
  local text = readFile(userDir .. "/profiles/raycast/keybindings.json")
  check("a shipped profile's entry is the profile's, and removing it writes a removal into a file of the "
        .. "person's own for that profile, made as needed",
        origin == "profile" and removed and text == '[\n  { "key": "alt+space", "command": "-quickOpen" }\n]\n',
        tostring(origin) .. " " .. tostring(text))
  os.execute(("rm -rf %q"):format(userDir))
end
