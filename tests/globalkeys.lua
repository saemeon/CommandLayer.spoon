-- CommandLayer.spoon/tests/globalkeys.lua
-- Global keybindings: bound in every app, resolved against a context made at
-- the press, the entry chord among them, bindHotkeys, and closing the layer.

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
for _, id in ipairs({ "test.first", "test.second", "test.global", "test.modal" }) do
  cl.registerCommand(id, { title = id, menus = {}, run = function() ran[#ran + 1] = id end })
end

-- Counts every context made, and answers a when clause with what it is set to.
local captures, captured = 0, "yes"
cl.register({ name = "test-counting", capture = function(ctx)
  captures = captures + 1
  ctx.testGlobal = captured
end })

local function pressed(key, held, global)
  ran = {}
  cl.pressKeybinding(key, held, global)
  return table.concat(ran, " ")
end

group("global keys: resolving")
cl.modal:exited()
check("a global press is answered by global entries alone; the modal's walks every entry", withKeybindings(
        { { key = "hyper+9", command = "test.global", global = true },
          { key = "hyper+9", command = "test.modal" } },
        function()
          local global, modal = pressed("hyper+9", false, true), pressed("hyper+9")
          cl.keybindings[#cl.keybindings].when = "neverSet"
          local fallen = pressed("hyper+9")
          return global == "test.global" and modal == "test.modal" and fallen == "test.global",
                 ("%q %q %q"):format(global, modal, fallen)
        end))
check("a global key with nothing to check makes no context to resolve it", withKeybindings(
        { { key = "hyper+8", command = "test.first", global = true } },
        function()
          captures = 0
          local entry, ctx = cl.resolveKeybinding("hyper+8", nil, true)
          return entry ~= nil and ctx == nil and captures == 0, tostring(captures)
        end))
check("a global key's when is checked against a context made when it is pressed", withKeybindings(
        { { key = "hyper+7", command = "test.first", global = true },
          { key = "hyper+7", command = "test.second", global = true, when = "testGlobal == 'yes'" } },
        function()
          captured = "yes"
          local yes = pressed("hyper+7", false, true)
          captured = "no"
          local no = pressed("hyper+7", false, true)
          captured = "yes"
          return yes == "test.second" and no == "test.first", ("%q %q"):format(yes, no)
        end))
-- VS Code's keyboard shortcuts troubleshooting: at debug, a press says which
-- entry ran and why each newer one on its chord did not; below debug, nothing.
check("at debug a press explains itself, the entries on its chord newest first; below it, silent",
      withKeybindings(
        { { key = "hyper+7", command = "test.first", global = true },
          { key = "hyper+7", command = "test.second", global = true, when = "testGlobal == 'yes'" } },
        function()
          local mark = #T.logged
          captured = "no"
          pressed("hyper+7", false, true)
          local quiet = #T.logged == mark
          cl.setLogLevel("debug")
          pressed("hyper+7", false, true)
          cl.setLogLevel("warning")
          captured = "yes"
          local line = T.logged[#T.logged] or ""
          return quiet and line:find("key hyper+7 -> test.first", 1, true) ~= nil
                 and line:find("test.second (keybindings) when is false: testGlobal == 'yes'", 1, true) ~= nil
                 and line:find("test.first (keybindings) runs", 1, true) ~= nil,
                 tostring(quiet) .. " / " .. line
        end))

check("quickOpen from a closed layer enters it on the picker named, in the one context the press made",
      withKeybindings(
        { { key = "hyper+p", command = "quickOpen", args = { view = "palette" }, global = true,
            when = "testGlobal == 'yes'" } },
        function()
          T.recordedSpec("root")
          T.recordedSpec("palette")
          cl.modal:exited()
          local entered = 0
          stub(cl.modal, "enter", function(self)
            entered = entered + 1
            self:entered()
          end)
          captures = 0
          pressed("hyper+p", false, true)
          local top = cl.topView()
          local name = top and top.name
          cl.modal:exited()
          return name == "palette" and captures == 1 and entered == 1,
                 ("%s, %d contexts, entered %d"):format(tostring(name), captures, entered)
        end))

group("global keys: closing the layer")
check("quickOpen.hide closes every level at once, and is no row", (function()
        T.openRecorded("root")
        cl.push("palette")
        local before = T.layerModal.exits
        cl.executeCommand("quickOpen.hide")
        local command = cl.getCommand("quickOpen.hide")
        local closed = T.layerModal.exits == before + 1
        cl.modal:exited()
        return closed and command ~= nil and next(command.menus) == nil
      end)())

-- Keybindings and settings files set up in a layer of their own, since
-- binding happens in setup and start.
group("global keys: binding")
do
  local folder = os.tmpname() .. "-globalkeys"
  os.execute(("mkdir -p %q"):format(folder))
  local function write(name, text)
    local handle = io.open(folder .. "/" .. name, "w")
    handle:write(text)
    handle:close()
  end
  write("keybindings.json", [=[[
    { "key": "alt+space", "command": "-quickOpen" },
    { "key": "hyper+left", "command": "quickOpen.hide", "global": true },
    { "key": "cmd+k", "command": "quickOpen.back", "global": true },
    { "key": "cmd+c", "command": "quickOpen.back", "global": true },
    { "key": "cmd+1", "command": "quickOpen.back", "global": "yes" },
    { "key": "cmd+2", "command": "quickOpen.back" },
    { "key": "cmd+2", "command": "quickOpen.accept", "global": true },
    { "key": "cmd+3", "command": "quickOpen.accept", "global": true },
    { "key": "cmd+3", "command": "quickOpen.back" },
    { "key": "cmd+4", "command": "quickOpen.back", "global": true },
    { "key": "cmd+4", "command": "quickOpen.accept", "global": true }
  ]]=])
  write("settings.json", [[{ "hotkeys": { "enter": "cmd+space" } }]])

  -- Again in each group, whose start puts stubs back.
  local hotkeys, refuse = {}, {}
  local function recordHotkeys()
    stub(hs.hotkey, "new", function(mods, key, ...)
      local pressedfn, releasedfn, repeatfn = T.hotkeyFunctions(...)
      local hk = { key = key, mods = mods, pressed = pressedfn, released = releasedfn, held = repeatfn,
                   deleted = false }
      function hk.enable() if refuse[key] then return nil end return hk end
      function hk.delete() hk.deleted = true end
      function hk.disable() end
      hotkeys[#hotkeys + 1] = hk
      return hk
    end)
  end
  recordHotkeys()
  local function bound(key)
    local out = {}
    for _, hk in ipairs(hotkeys) do
      if hk.key == key and not hk.deleted then out[#out + 1] = hk end
    end
    return out
  end

  local layer = loadKernel()
  layer.userDir, layer.profile = NO_USER_DIR, folder
  local modal = {}
  hs.hotkey.modal.last.bind = function(_, _, key) modal[key] = (modal[key] or 0) + 1 end
  local ok, err = pcall(layer.setup)
  if ok then ok, err = pcall(layer.bindGlobalKeybindings) end
  local function said(piece)
    for _, p in ipairs(ok and layer.problems or {}) do
      if p.message:find(piece, 1, true) then return true end
    end
    return false
  end

  check("a global keybinding is bound with hs.hotkey, and not in the modal", ok
        and #bound("left") == 1 and modal["left"] == nil and #bound("o") == 0 and modal["o"] == 1
        and (function()
          local mods = {}
          for _, mod in ipairs(bound("left")[1].mods) do mods[#mods + 1] = mod end
          table.sort(mods)
          return table.concat(mods, "+") == "alt+cmd+ctrl+shift"
        end)(), tostring(err))
  check("a global key runs when pressed, not when released", ok and #bound("left") == 1
        and bound("left")[1].pressed ~= nil and bound("left")[1].released == nil)
  check("a chord a global and a modal entry share is bound in both", ok
        and #bound("k") == 1 and modal["k"] == 1 and #bound("3") == 1 and modal["3"] == 1)
  check("-quickOpen removes the entry chord like any keybinding, and no key opening the layer is a problem",
        ok and #bound("space") == 0 and said("no global keybinding runs quickOpen, so no key opens the layer"))
  check("a global text-editing key, a global that is not a boolean, and a global entry after a modal or "
        .. "a global one on its key are problems; a modal entry after a global one is not", ok
        and #bound("c") == 0 and #bound("1") == 0 and modal["1"] == nil
        and said("cmd+c: every app needs this key to edit text, so it is not bound")
        and said('cmd+1: "global" should be a boolean, not string')
        and said("cmd+2 is bound to quickOpen.back and to quickOpen.accept")
        and said("cmd+4 is bound to quickOpen.back and to quickOpen.accept")
        and not said("cmd+3 is bound"))
  check("a leftover hotkeys setting is a problem naming the keybinding that replaces it", ok
        and said('"hotkeys" is not a setting: the entry chord is a global keybinding, '
                 .. '{ "key": "cmd+space", "command": "quickOpen", "global": true } in keybindings.json, '
                 .. 'after { "key": "alt+space", "command": "-quickOpen" }'))
  check("the global key resolves among global entries, the modal's key among all", ok and (function()
          local entry = layer.resolveKeybinding("cmd+3", {}, true)
          local modalEntry = layer.resolveKeybinding("cmd+3", {})
          return entry ~= nil and entry.command == "quickOpen.accept"
                 and modalEntry ~= nil and modalEntry.command == "quickOpen.back"
        end)())
  check("a key macOS or another app holds is a problem naming it", ok and (function()
          refuse["left"] = true
          layer.bindGlobalKeybindings()
          refuse["left"] = nil
          return said("hyper+left could not be bound: macOS or another app holds it")
        end)())
  check("start claims the global keys and stop gives every one back", ok and (function()
          stub(layer, "startExtensions", function() end)
          stub(layer, "stopExtensions", function() end)
          stub(layer, "reportProblems", function() end)
          stub(layer, "loginShellLookup", function() return false end)
          layer.stop()
          local afterStop = #bound("left") + #bound("k")
          layer.start()
          local started = #bound("left") + #bound("k")
          layer.stop()
          local stopped = #bound("left") + #bound("k")
          return afterStop == 0 and started == 2 and stopped == 0,
                 ("%d %d %d"):format(afterStop, started, stopped)
        end)())

  os.execute(("rm -rf %q"):format(folder))

  group("global keys: bindHotkeys")
  recordHotkeys()
  hotkeys = {}
  local spoon = loadKernel()
  spoon.userDir = NO_USER_DIR
  local function entering(kernel)
    local keys = {}
    for _, entry in ipairs(kernel.effectiveKeybindings()) do
      if kernel.entersLayer(entry) then keys[#keys + 1] = kernel.chordId(entry.key) end
    end
    return table.concat(keys, " ")
  end
  spoon.bindHotkeys({ enter = "cmd+space" })
  local set = pcall(spoon.setup)
  if set then set = pcall(spoon.bindGlobalKeybindings) end
  check("bindHotkeys before start replaces the entry chord with a global keybinding of its own",
        set and entering(spoon) == "cmd+space" and #bound("space") == 1
        and bound("space")[1].mods[1] == "cmd" and #spoon.problems == 0,
        entering(spoon))
  check("and after start it rebinds at once, a table chord as SPOONS.md writes one", set and (function()
          spoon.bindHotkeys({ enter = { { "ctrl" }, "return" } })
          return entering(spoon) == "ctrl+return" and #bound("space") == 0 and #bound("return") == 1,
                 entering(spoon)
        end)())
  check("a mapping naming no hotkey is a problem", set and (function()
          spoon.bindHotkeys({ open = "cmd+x" })
          for _, p in ipairs(spoon.problems) do
            if p.message == '"open" is not a hotkey; enter is' then return true end
          end
          return false
        end)())
end
