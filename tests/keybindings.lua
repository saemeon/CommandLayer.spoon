-- CommandLayer.spoon/tests/keybindings.lua
-- Resolving a key: the entries sharing it, what a press knows, holding it.

local T = ...
local check, group, stub = T.check, T.group, T.stub
local cl = T.layer()
local NO_USER_DIR = T.NO_USER_DIR
local loadKernel = T.loadKernel

-- Appended and then removed, so later checks see the list as it was.
local function withKeybindings(entries, fn)
  local n = #cl.keybindings
  for i, entry in ipairs(entries) do cl.keybindings[n + i] = entry end
  local ok, a, b = pcall(fn)
  for i = #cl.keybindings, n + 1, -1 do cl.keybindings[i] = nil end
  if not ok then return false, tostring(a) end
  return a, b
end

local ran = {}
local function command(id, spec)
  spec = spec or {}
  spec.title, spec.menus = id, {}
  spec.run = function() ran[#ran + 1] = id end
  cl.registerCommand(id, spec)
end
command("test.first")
command("test.second")
command("test.third")
command("test.greyed", { enablement = "neverSet" })

local function pressed(key, held)
  ran = {}
  cl.pressKeybinding(key, held)
  return table.concat(ran, " ")
end

group("keybindings: resolving a key")
check("of the entries on one key, the latest whose when holds runs", withKeybindings(
        { { key = "cmd+shift+1", command = "test.first" },
          { key = "Shift+Cmd+1", command = "test.second", when = "neverSet" },
          { key = "cmd+shift+1", command = "test.third", when = "!neverSet" } },
        function()
          local latest = pressed("cmd+shift+1")
          cl.keybindings[#cl.keybindings].when = "neverSet"
          local earlier = pressed("cmd+shift+1")
          return latest == "test.third" and earlier == "test.first", latest .. " / " .. earlier
        end))
check("a command whose enablement does not hold leaves the key to the entry before it", withKeybindings(
        { { key = "cmd+shift+2", command = "test.first" },
          { key = "cmd+shift+2", command = "test.greyed" } },
        function()
          local got = pressed("cmd+shift+2")
          return got == "test.first", got
        end))
check("a key whose entries all decline runs nothing", withKeybindings(
        { { key = "cmd+shift+3", command = "test.first", when = "neverSet" } },
        function()
          local got = pressed("cmd+shift+3")
          return got == "", got
        end))

group("keybindings: what a press knows")
check("activeView, hasQuery after the prefix, and the highlighted row's viewItem", withKeybindings(
        { { key = "cmd+shift+4", command = "test.first",
            when = "activeView == 'palette' && !hasQuery && viewItem == 'command'" },
          { key = "cmd+shift+4", command = "test.second",
            when = "activeView == 'palette' && hasQuery && viewItem == 'command'" } },
        function()
          T.recordedSpec("root")
          T.recordedSpec("palette")
          cl.quickOpen("palette")
          local top = cl.topView()
          local picker = top and top.picker
          if not (top and top.name == "palette" and picker) then
            cl.modal:exited()
            return false, "palette did not open by its prefix"
          end
          local function highlightCommand()
            for i, row in ipairs(picker.shown or {}) do
              if type(row.subject) == "table" and row.subject.kind == "command" then
                picker.row = i
                return
              end
            end
          end
          highlightCommand()
          local prefixOnly = pressed("cmd+shift+4")
          picker.type(">git")
          highlightCommand()
          local typed = pressed("cmd+shift+4")
          stub(picker, "selected", function() return { label = "plain" } end)
          local plainRow = pressed("cmd+shift+4")
          cl.modal:exited()
          return prefixOnly == "test.first" and typed == "test.second" and plainRow == "",
                 ("%q %q %q"):format(prefixOnly, typed, plainRow)
        end))

group("keybindings: holding a key")
check("a held key runs again only an entry that repeats", withKeybindings(
        { { key = "cmd+shift+5", command = "test.first" },
          { key = "cmd+shift+6", command = "test.second", ["repeat"] = true } },
        function()
          local held, once, repeating = pressed("cmd+shift+5", true), pressed("cmd+shift+5"),
                                        pressed("cmd+shift+6", true)
          return held == "" and once == "test.first" and repeating == "test.second",
                 ("%q %q %q"):format(held, once, repeating)
        end))
check("the moves repeat unless their keybinding says not to", (function()
        return cl.keybindingRepeats({ key = "cmd+d", command = "quickOpen.selectNext" })
               and cl.keybindingRepeats({ key = "cmd+e", command = "quickOpen.selectPrevious" })
               and not cl.keybindingRepeats({ key = "cmd+d", command = "quickOpen.selectNext",
                                              ["repeat"] = false })
               and not cl.keybindingRepeats({ key = "cmd+w", command = "quickOpen.back" })
      end)())

group("keybindings: the search field's keys")
check("the keys the search field edits text with are known, and the picker's own are not", (function()
        local wrong = {}
        for _, key in ipairs({ "a", "shift+a", "space", "1", "/", "delete", "shift+backspace",
                               "alt+delete", "cmd+forwarddelete", "left", "shift+right", "alt+left",
                               "cmd+shift+left", "home", "cmd+a", "cmd+c", "cmd+v", "cmd+x", "cmd+z",
                               "cmd+shift+z" }) do
          if not cl.editsText(key) then wrong[#wrong + 1] = key end
        end
        for _, key in ipairs({ "cmd+k", "cmd+e", "cmd+d", "tab", "cmd+w", "up", "down", "return",
                               "escape", "cmd+.", "cmd+shift+p", "ctrl+n", "cmd+shift+a", "alt+o" }) do
          if cl.editsText(key) then wrong[#wrong + 1] = key end
        end
        return #wrong == 0, table.concat(wrong, " ")
      end)())

-- A real keybindings.json, set up in a layer of its own, since binding
-- happens in setup and nowhere a check could call it directly. The context
-- is given, so this layer never captures from the machine.
group("keybindings: binding")
do
  local folder = os.tmpname() .. "-keys"
  os.execute(("mkdir -p %q"):format(folder))
  local handle = io.open(folder .. "/keybindings.json", "w")
  handle:write([=[[
    { "key": "cmd+k", "command": "quickOpen.accept" },
    { "key": "cmd+9", "command": "quickOpen.back", "when": "activeView == 'root'" },
    { "key": "Cmd+9", "command": "quickOpen.accept", "when": "activeView == 'palette'" },
    { "key": "cmd+d", "command": "quickOpen.selectNext" },
    { "key": "cmd+e", "command": "quickOpen.selectPrevious", "repeat": false },
    { "key": "cmd+w", "command": "quickOpen.back", "repeat": true },
    { "key": "cmd+v", "command": "quickOpen.back" }
  ]]=])
  handle:close()

  local layer = loadKernel()
  layer.userDir, layer.profile = NO_USER_DIR, folder
  local binds = {}
  hs.hotkey.modal.last.bind = function(_, _, key, ...)
    local pressedfn, releasedfn, repeatfn = T.hotkeyFunctions(...)
    binds[key] = binds[key] or {}
    table.insert(binds[key], { pressed = pressedfn, released = releasedfn, held = repeatfn })
  end
  local ok, err = pcall(layer.setup)
  os.execute(("rm -rf %q"):format(folder))

  local function count(key) return binds[key] and #binds[key] or 0 end
  local function said(piece)
    for _, p in ipairs(ok and layer.problems or {}) do
      if p.message:find(piece, 1, true) then return true end
    end
    return false
  end

  check("each key is bound once, however many entries share it",
        ok and count("9") == 1 and count("k") == 1 and count("o") == 1,
        ok and ("9:%d k:%d o:%d"):format(count("9"), count("k"), count("o")) or tostring(err))
  check("a profile's entry on a default's key wins, and is not a collision", ok
        and not said("cmd+k") and not said("cmd+9")
        and (layer.resolveKeybinding("cmd+k", {}) or {}).command == "quickOpen.accept"
        and (layer.resolveKeybinding("cmd+9", { activeView = "root" }) or {}).command == "quickOpen.back"
        and (layer.resolveKeybinding("cmd+9", { activeView = "palette" }) or {}).command == "quickOpen.accept")
  check("a key the search field needs is a problem, and not bound",
        ok and count("v") == 0 and said("cmd+v: the search field needs this key"))
  check("a held key repeats the moves by default, and an entry saying repeat; a key runs when pressed",
        ok and count("d") == 1 and binds["d"][1].held ~= nil and binds["e"][1].held == nil
        and binds["d"][1].pressed ~= nil and binds["d"][1].released == nil
        and binds["w"][1].held ~= nil and binds["k"][1].held == nil)
end
