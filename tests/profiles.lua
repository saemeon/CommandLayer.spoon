-- CommandLayer.spoon/tests/profiles.lua
-- Profiles and keybindings.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local NO_USER_DIR = T.NO_USER_DIR
local logged = T.logged
local loadKernel = T.loadKernel

group("profiles")
check("the default profile was read", type(cl.settings) == "table")
check("it declares the pickers", #(cl.settings.views or {}) >= 4,
      tostring(#(cl.settings.views or {})))
check("a ranker weight came from it",
      cl.settings.rankers and cl.settings.rankers.alphabetical == 0)

-- Which keys move and open is a person's preference, so the only control
-- shipped with a chord is cmd+k, which every launcher has.
check("the shipped defaults bind no control but cmd+k; the rest are the entry chord and the pickers' chords",
      (function()
        local keys = cl.decodeJSONC(cl.modules.workbench.defaultKeybindingsText()) or {}
        local controls = {}
        for _, control in ipairs(cl.controls) do controls[control.name] = true end
        for _, entry in ipairs(keys) do
          if controls[entry.command] and entry.command ~= "quickOpen.showActions" then
            return false, entry.command
          end
        end
        return #keys == 6 and cl.keybindingsFor("quickOpen.showActions")[1] == "cmd+k"
               and #cl.keybindingsFor("quickOpen.selectNext") == 0, tostring(#keys)
      end)())

-- Appended and then removed, so later checks see the list as it was.
local function withKeybindings(entries, fn)
  local n = #cl.keybindings
  for i, entry in ipairs(entries) do cl.keybindings[n + i] = entry end
  local ok, a, b = pcall(fn)
  for i = #cl.keybindings, n + 1, -1 do cl.keybindings[i] = nil end
  if not ok then return false, tostring(a) end
  return a, b
end

check("a chord may be written as a table", withKeybindings(
        { { key = { { "cmd" }, "1" }, command = "quickOpen.back" } },
        function()
          local chords = cl.keybindingsFor("quickOpen.back")
          return #chords == 1 and type(chords[1]) == "table"
        end))

check("'-' with a key removes only that key's earlier entry", withKeybindings(
        { { key = "cmd+d", command = "quickOpen.selectNext" },
          { key = "ctrl+d", command = "quickOpen.selectNext" },
          { key = "Ctrl+D", command = "-quickOpen.selectNext" } },
        function()
          local chords = cl.keybindingsFor("quickOpen.selectNext")
          return #chords == 1 and chords[1] == "cmd+d", table.concat(chords, " ")
        end))

check("'-' without a key removes every earlier entry for that command", withKeybindings(
        { { key = "cmd+d", command = "quickOpen.selectNext" },
          { key = "ctrl+d", command = "quickOpen.selectNext" },
          { key = "cmd+e", command = "quickOpen.selectPrevious" },
          { command = "-quickOpen.selectNext" } },
        function()
          local chords = cl.keybindingsFor("quickOpen.selectNext")
          return #chords == 0 and #cl.keybindingsFor("quickOpen.selectPrevious") == 1,
                 table.concat(chords, " ")
        end))

check("an unknown command run directly logs and does not throw", (function()
        local mark = #logged
        local ok = pcall(cl.runKeybinding, { key = "cmd+1", command = "no.such" })
        local said = false
        for i = mark + 1, #logged do
          if logged[i]:find("no.such", 1, true) then said = true end
        end
        return ok and said
      end)())

-- A real keybindings.json, loaded by setup() into a layer of its own,
-- because the merge happens there and nowhere a check could call it
-- directly. The profile is named by its folder's path.
do
  local folder = os.tmpname() .. "-profile"
  os.execute(("mkdir -p %q"):format(folder))
  local handle = io.open(folder .. "/keybindings.json", "w")
  handle:write([=[[
    { "key": "cmd+9",  "command": "quickOpen.back" },
    { "key": "cmd+8",  "command": "no.such.command" },
    { "key": "cmmd+7", "command": "quickOpen.back" }
  ]]=])
  handle:close()

  local third = loadKernel()
  third.userDir = NO_USER_DIR
  third.profile = folder
  local bound = {}
  hs.hotkey.modal.last.bind = function(_, _, key) bound[key] = true end
  local mark = #logged
  local ok, err = pcall(third.setup)
  os.execute(("rm -rf %q"):format(folder))

  local said = {}
  for i = mark + 1, #logged do said[#said + 1] = logged[i] end
  said = table.concat(said, "\n")

  check("a profile's keybindings add to the defaults", ok
        and bound["9"] and bound["o"] and bound["r"] ~= nil,
        ok and table.concat((function()
          local keys = {}
          for key in pairs(bound) do keys[#keys + 1] = key end
          table.sort(keys)
          return keys
        end)(), " ") or tostring(err))

  check("an unknown command or unreadable chord is skipped, and logged",
        ok and not bound["8"] and not bound["7"]
        and said:find("no.such.command", 1, true) ~= nil
        and said:find("cmmd+7", 1, true) ~= nil, said)
end

-- VS Code's "Use Default Profile" for keyboard shortcuts: another profile
-- takes the default profile's keybindings.json when it says so, before its
-- own, which still win; without saying so it does not.
do
  local userDir = os.tmpname() .. "-usedefault"
  local profile = userDir .. "/profiles/work"
  os.execute(("mkdir -p %q"):format(profile))
  local function write(path, text)
    local handle = io.open(path, "w")
    handle:write(text)
    handle:close()
  end
  write(userDir .. "/keybindings.json", [=[[
    { "key": "cmd+6", "command": "quickOpen.back" },
    { "key": "cmd+5", "command": "quickOpen.back" }
  ]]=])
  write(profile .. "/keybindings.json", [=[[
    { "key": "cmd+5", "command": "quickOpen.hide" }
  ]]=])

  local function commandsOn(settingsText)
    write(profile .. "/settings.json", settingsText)
    local kernel = loadKernel()
    kernel.userDir = userDir
    kernel.profile = "work"
    hs.hotkey.modal.last.bind = function() end
    local ok, err = pcall(kernel.setup)
    if not ok then return nil, tostring(err) end
    local on, origin = {}, {}
    for _, entry in ipairs(kernel.effectiveKeybindings()) do
      if entry.key == "cmd+6" or entry.key == "cmd+5" then
        on[entry.key] = entry.command
        origin[entry.key] = kernel.keybindingOrigin(entry)
      end
    end
    return on, origin
  end

  local used, usedFrom = commandsOn('{ "useDefaultProfile": { "keybindings": true } }')
  local alone = commandsOn("{}")
  os.execute(("rm -rf %q"):format(userDir))

  check("a profile using the default profile's keybindings gets them before its own, which still win; "
        .. "one that does not, does not",
        used and used["cmd+6"] == "quickOpen.back" and used["cmd+5"] == "quickOpen.hide"
        and usedFrom["cmd+6"] == "defaultProfile" and usedFrom["cmd+5"] == "user"
        and alone and alone["cmd+6"] == nil and alone["cmd+5"] == "quickOpen.hide",
        ("%s %s / %s"):format(tostring(used and used["cmd+6"]), tostring(usedFrom and usedFrom["cmd+6"]),
                             tostring(alone and alone["cmd+6"])))
end

-- The claim the profile folder makes: a second file is a second
-- launcher, not a patch to the first. Loaded for real into its own
-- layer, because checking the declaration only proves the file parses
-- -- it says nothing about what the layer ends up with.
local second = loadKernel()
second.userDir = NO_USER_DIR
second.profile = "raycast"
second.setup()

check("a second profile is a second launcher", (function()
        local names = {}
        for _, v in ipairs(second.views) do names[#names + 1] = v.name end
        table.sort(names)
        -- root holds all four menus; actions, keybindings, settings and help
        -- are declared in the defaults, the text commands with a prefix are
        -- pickers of their own, and files and grep are kept from the defaults.
        return table.concat(names, " ")
               == "actions brew.info brew.install brew.search browser.searchWeb browser.searchYouTube "
                  .. "files grep help keybindings root settings",
               table.concat(names, " ")
      end)())

check("and its cmd+k panel still has a view", (function()
        return second.viewNamed(second.actionsView) ~= nil
      end)())

check("its one picker holds every menu", (function()
        local root = second.viewNamed("root")
        return root and #(root.menus or {}) >= 4,
               tostring(root and #(root.menus or {}))
      end)())

check("a profile can remove the default chords, keeping the ones it does not name", (function()
        local chords = second.keybindingsFor("quickOpen")
        local entering = 0
        for _, entry in ipairs(second.effectiveKeybindings()) do
          if second.entersLayer(entry) then entering = entering + 1 end
        end
        return #chords == 1 and chords[1] == "alt+space" and entering == 1
               and second.keybindingsFor("quickOpen.showActions")[1] == "cmd+k",
               table.concat(chords, " ")
      end)())

check("which the default profile keeps", (function()
        return #cl.keybindingsFor("quickOpen") == 5, tostring(#cl.keybindingsFor("quickOpen"))
      end)())

-- The helper is the only thing telling you what the keys are, so a
-- rebind it does not follow is a lie on screen.
check("the layer shows no key hints of its own: ? is where pickers and chords are listed", (function()
        return cl.helperText == nil and cl.helperStyle == nil
      end)())

check("the entry chord is a global keybinding the defaults ship, and no setting", (function()
        local found
        for _, entry in ipairs(cl.effectiveKeybindings()) do
          if cl.entersLayer(entry) then found = entry end
        end
        return found ~= nil and found.key == "alt+space" and cl.keybindingSource(found):find("defaultKeybindings", 1, true)
               and cl.hotkeys == nil and cl.settings.hotkeys == nil
               and cl.modules.workbench.defaultKeybindingsText():find('"command": "quickOpen", "global": true', 1, true) ~= nil,
               found and tostring(found.key)
      end)())
check("hyper is cmd, alt, ctrl and shift, written or in a table", (function()
        local mods, key = cl.chord("hyper+left")
        table.sort(mods)
        return key == "left" and table.concat(mods, "+") == "alt+cmd+ctrl+shift"
               and cl.chordId("Hyper+Left") == cl.chordId("cmd+alt+ctrl+shift+left")
               and cl.chordId({ { "hyper" }, "left" }) == "alt+cmd+ctrl+shift+left"
               and not cl.editsText("hyper+a"),
               table.concat(mods, "+")
      end)())
check("a chord is read from its written form", (function()
        local mods, key = cl.chord("cmd+shift+o")
        table.sort(mods)
        return key == "o" and table.concat(mods, "+") == "cmd+shift"
      end)())
check("option and its aliases", (function()
        local _, k1 = cl.chord("alt+space")
        local m2 = cl.chord("option+space")
        local m3 = cl.chord("opt+space")
        return k1 == "space" and m2[1] == "alt" and m3[1] == "alt"
      end)())
check("a mistyped modifier is unreadable, not a bare key", (function()
        return cl.chord("cmmd+k") == nil and cl.chord("cmd+k+j") == nil
      end)())
check("a table chord still works", (function()
        local mods, key = cl.chord({ { "ctrl" }, "j" })
        return key == "j" and mods[1] == "ctrl"
      end)())
check("nonsense is refused", cl.chord("cmd+") == nil and cl.chord(nil) == nil)
