-- CommandLayer.spoon/tests/settings.lua
-- Settings: the user folder, extension settings, Preferences, problems.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()

local NO_USER_DIR = T.NO_USER_DIR
local loadKernel = T.loadKernel
local openRecorded = T.openRecorded
local recordedSpec = T.recordedSpec
local layerModal = T.layerModal

group("user config")
-- Real folders, as ~/.config/commandlayer would be, loaded into layers of
-- their own.
do
  local userDir = os.tmpname() .. "-user"
  local pathedDir = userDir .. "-pathed"
  os.execute(("mkdir -p %q %q %q"):format(userDir .. "/profiles/mine", userDir .. "/extensions", pathedDir))
  local function write(path, text)
    local handle = io.open(path:sub(1, 1) == "/" and path or (userDir .. "/" .. path), "w")
    handle:write(text)
    handle:close()
  end

  -- The default profile's own files, written as a person would.
  write("settings.json", [[
    // Comments, as VS Code's settings allow.
    { "prefixes": { "recent": "rr " },
      "zoxide.enabled": false,
      "browser.tabOrder": "browser", }]])
  write("keybindings.json", [=[[ { "key": "cmd+9", "command": "quickOpen.back" } ]]=])
  -- Another profile, with files of its own.
  write("profiles/mine/settings.json", [=[{ "views": [ { "name": "root", "placeholder": "Mine" } ] }]=])
  write("profiles/mine/keybindings.json", [=[[ { "key": "cmd+8", "command": "quickOpen.back" } ]]=])
  write(pathedDir .. "/settings.json", [=[{ "views": [ { "name": "root", "placeholder": "Pathed" } ] }]=])
  write("extensions/userext.lua", [[
    local M = {}
    function M.extension(cl)
      return { name = "userext", menus = { "root" },
               items = function() return { { label = "from the user's folder" } } end }
    end
    return M]])
  write("extensions/ambient.lua", [[
    local M = {}
    function M.extension(cl)
      return { name = "ambient", before = { "finder" },
               capture = function(ctx) ctx.frontmostApp = "FromUser" end }
    end
    return M]])

  local function layer(profile)
    local l = loadKernel()
    l.userDir = userDir
    l.profile = profile
    l.setup()
    return l
  end

  local user = layer(nil)
  write("profile.json", [[{ "profile": "mine" }]])
  local mine = layer(nil)
  local explicit = layer("raycast")
  local pathed = layer(pathedDir)

  local function has(l, name)
    for _, ext in ipairs(l.extensions) do
      if ext.name == name then return true end
    end
    return false
  end
  local function bound(l, command, key)
    for _, chord in ipairs(l.keybindingsFor(command)) do
      if chord == key then return true end
    end
    return false
  end

  check("the user folder's settings.json and keybindings.json are the default profile's",
        user.profile == "default" and user.prefixes.recent == "rr "
        and bound(user, "quickOpen.back", "cmd+9") and user.setting("browser", "tabOrder") == "browser",
        tostring(user.prefixes.recent))
  check("profile.json switches to a profile in the profiles folder, with its own keybindings",
        mine.profile == "mine" and mine.viewNamed("root").placeholder == "Mine"
        and bound(mine, "quickOpen.back", "cmd+8"), tostring(mine.profile))
  check("switching does not stack: the default profile's settings and keys are not read",
        mine.prefixes.recent ~= "rr " and has(mine, "zoxide") and not bound(mine, "quickOpen.back", "cmd+9"))
  check("an explicit profile wins over profile.json, and a shipped one can remove pickers",
        explicit.profile == "raycast" and explicit.viewNamed("root").placeholder ~= "Mine"
        and explicit.viewNamed("palette") == nil)
  check("a profile's settings merge into the defaults key by key",
        explicit.appearance.width == 40 and explicit.settings.appearance.actionRows == 8
        and explicit.settings.appearance.dark == true,
        tostring(explicit.settings.appearance and explicit.settings.appearance.actionRows))
  check("a profile named by a path is that folder", pathed.viewNamed("root").placeholder == "Pathed")
  check("an extension in the user's folder is loaded", has(user, "userext"))
  check("a user file named like a shipped one replaces it",
        user.buildContext().frontmostApp == "FromUser",
        tostring(user.buildContext().frontmostApp))
  check("settings.json can switch an extension off", not has(user, "zoxide") and has(explicit, "userext"))
  check("without a user folder, nothing of it is read", cl.userDir == NO_USER_DIR
        and cl.viewNamed("root").placeholder == "Search")

  os.execute(("rm -rf %q %q"):format(userDir, pathedDir))
end

group("extension settings")
do
  local settingsDir = os.tmpname() .. "-settings"
  local saved = { dir = cl.userDir, settings = cl.userSettings }
  cl.userDir = settingsDir
  cl.userSettings = {}
  local function readText(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("a")
    handle:close()
    return text
  end
  local function writeText(path, text)
    os.execute(("mkdir -p %q"):format(settingsDir))
    local handle = io.open(path, "w")
    handle:write(text)
    handle:close()
  end
  cl.register({ name = "switchy", displayName = "Switchy", menus = {},
    settings = { loud = { type = "boolean", description = "Loud", default = true },
                 mode = { description = "Mode", default = "quiet", enum = { "quiet", "loud", "off" },
                          enumDescriptions = { "Quiet please", "Loud please", "Silent" } } } })
  local function setSetting(...) return cl.extensionNamed("settings").exports.update(...) end

  check("a setting is its declared default until settings.json says otherwise", (function()
          local v1, s1 = cl.setting("switchy", "loud")
          cl.userSettings = { ["switchy.loud"] = false }
          local v2, s2 = cl.setting("switchy", "loud")
          -- One spelling: a nested block is not another way to say it.
          cl.userSettings = { extensions = { switchy = { loud = false } } }
          local v3 = cl.setting("switchy", "loud")
          cl.userSettings = {}
          return v1 == true and s1 == "default" and v2 == false and s2 == "settings.json" and v3 == true,
                 ("%s %s / %s %s"):format(tostring(v1), tostring(s1), tostring(v2), tostring(s2))
        end)())

  check("setting one writes settings.json, and reads back", (function()
          local ok = setSetting("switchy", "loud", false)
          local written = cl.decodeJSONC(readText(settingsDir .. "/settings.json") or "")
          return ok and type(written) == "table"
                 and written["switchy.loud"] == false
                 and cl.setting("switchy", "loud") == false
        end)())

  check("a settings.json that does not parse is never overwritten", (function()
          local path = settingsDir .. "/settings.json"
          local kept, broken = readText(path), '{ "switchy.loud": false '
          writeText(path, broken)
          local alerts, real = 0, hs.alert.show
          hs.alert.show = function() alerts = alerts + 1 end
          local ok = setSetting("switchy", "loud", true)
          hs.alert.show = real
          local after = readText(path)
          writeText(path, kept or "{}")
          return ok == false and after == broken and alerts == 1, tostring(alerts) .. " alerts"
        end)())

  -- As VS Code's settings editor edits settings.json: only the value
  -- changes, and a person's comments, order and layout stay.
  check("a write changes only that value: comments, order and layout stay", (function()
          local path = settingsDir .. "/settings.json"
          local kept = readText(path)
          writeText(path, table.concat({
            "// Mine",
            "{",
            "  // tabs first",
            '  "browser.tabOrder": "browser", // as the browser has them',
            '  "switchy.loud": true',
            "}",
            "" }, "\n"))
          setSetting("switchy", "loud", false)
          setSetting("switchy", "mode", "loud")
          setSetting("browser", "tabOrder", "recent")
          setSetting("fresh", "on", true)
          local after = readText(path)
          writeText(path, kept or "{}")
          return after == table.concat({
            "// Mine",
            "{",
            "  // tabs first",
            '  "browser.tabOrder": "recent", // as the browser has them',
            '  "switchy.loud": false,',
            '  "switchy.mode": "loud",',
            '  "fresh.on": true',
            "}",
            "" }, "\n"), tostring(after)
        end)())

  check("writing nothing removes the setting from settings.json, keeping the rest, and it reads its default; "
        .. "with no file there is nothing to remove, and no file is made", (function()
          local path = settingsDir .. "/settings.json"
          local kept = readText(path)
          writeText(path, '{\n  // mine\n  "switchy.loud": false,\n  "switchy.mode": "loud"\n}\n')
          local ok = setSetting("switchy", "mode", nil)
          local after = readText(path)
          local value, source = cl.setting("switchy", "mode")
          os.remove(path)
          local nothing = setSetting("switchy", "mode", nil) and readText(path) == nil
          writeText(path, kept or "{}")
          return ok and after == '{\n  // mine\n  "switchy.loud": false\n}\n' and value == "quiet"
                 and source == "default" and nothing, tostring(after)
        end)())

  check("editing JSONC in place: an empty object, past a comment, after a trailing comma, through a value", (function()
          local cases = {
            { "{}", { "a" }, 1, '{\n  "a": 1\n}' },
            { "{\n}\n", { "a", "b" }, true, '{\n  "a": {\n    "b": true\n  }\n}\n' },
            { '{\n  "a": 1 // one\n}', { "b" }, 2, '{\n  "a": 1, // one\n  "b": 2\n}' },
            { '{\n  "a": 1,\n}', { "b" }, 2, '{\n  "a": 1,\n  "b": 2\n}' },
            { '{ "a": 5 }', { "a", "b" }, 1, '{ "a": {\n  "b": 1\n} }' },
            { '{ "a": 1, "a": 2 }', { "a" }, 3, '{ "a": 1, "a": 3 }' },
            { '{ "a": 1 }', { "b" }, 2, '{ "a": 1, "b": 2 }' },
          }
          for i, case in ipairs(cases) do
            local out = cl.editJSONC(case[1], case[2], case[3])
            if out ~= case[4] then return false, ("case %d: %s"):format(i, tostring(out)) end
          end
          return cl.editJSONC("{ nope", { "a" }, 1) == nil and cl.editJSONC("[]", { "a" }, 1) == nil
        end)())

  check("the settings picker toggles a setting in place, and stays open", (function()
          cl.userSettings = {}
          local spec = recordedSpec("settings")
          openRecorded("root").type("settings ")
          local p = spec.picker
          if not p then return false, "did not open" end
          local index
          for i, row in ipairs(p.shown or {}) do
            if row.label == "Switchy: Loud" then index = i end
          end
          if not index then return false, "no Switchy row" end
          local before = layerModal.exits
          p.row = index
          p.accept()
          local after
          for _, row in ipairs(p.shown or {}) do
            if row.label == "Switchy: Loud" then after = row.description end
          end
          return layerModal.exits == before and cl.setting("switchy", "loud") == false
                 and after ~= nil and after:find("off", 1, true) ~= nil, tostring(after)
        end)())

  check("a choice setting steps to its next value in the settings picker, and round", (function()
          cl.userSettings = {}
          local spec = recordedSpec("settings")
          openRecorded("root").type("settings ")
          local p = spec.picker
          if not p then return false, "did not open" end
          local function modeRow()
            for i, row in ipairs(p.shown or {}) do
              if row.label == "Switchy: Mode" then return i, row.description end
            end
          end
          local index, before = modeRow()
          if not index then return false, "no Switchy: Mode row" end
          local seen = {}
          for _ = 1, 3 do
            p.row = modeRow()
            p.accept()
            seen[#seen + 1] = cl.setting("switchy", "mode")
          end
          local _, after = modeRow()
          return before == "Setting -- quiet (default)  --  Quiet please"
                 and table.concat(seen, " ") == "loud off quiet"
                 and after == "Setting -- quiet  --  Quiet please",
                 tostring(before) .. " / " .. table.concat(seen, " ") .. " / " .. tostring(after)
        end)())

  check("an extension switched off is listed so it can come back on", (function()
          cl.register({ name = "gone-ext", displayName = "gone-ext", menus = {} })
          cl.unregisterExtension("gone-ext")
          cl.userSettings = { ["gone-ext.enabled"] = false }
          local spec = recordedSpec("settings")
          openRecorded("root").type("settings ")
          local p = spec.picker
          for _, row in ipairs(p and p.shown or {}) do
            if row.label == "gone-ext" and row.description:find("off", 1, true) then return true end
          end
          return false
        end)())

  check("cmd+k on a setting settings.json sets offers Reset Setting, which removes it; a default offers none", (function()
          writeText(settingsDir .. "/settings.json", "{}\n")
          cl.userSettings = {}
          setSetting("switchy", "loud", false)
          local spec = recordedSpec("settings")
          openRecorded("root").type("settings ")
          local p = spec.picker
          local loud, mode
          for _, row in ipairs(p and p.shown or {}) do
            if row.label == "Switchy: Loud" then loud = row end
            if row.label == "Switchy: Mode" then mode = row end
          end
          if not (loud and mode) then return false, "no Switchy rows" end
          local function reset(row)
            for _, action in ipairs(cl.itemActions(row.subject, row.ctx or {})) do
              if action.command == "workbench.action.resetSetting" then return action end
            end
          end
          local offered = reset(loud)
          if offered then cl.executeCommand(offered.command, offered.args, {}) end
          local value, source = cl.setting("switchy", "loud")
          local written = cl.decodeJSONC(readText(settingsDir .. "/settings.json") or "")
          return offered ~= nil and offered.label == "Reset Setting" and reset(mode) == nil
                 and value == true and source == "default" and type(written) == "table"
                 and written["switchy.loud"] == nil,
                 tostring(offered and offered.label) .. " " .. tostring(source)
        end)())

  check("with browser tabs switched off, the browser is not asked", (function()
          local browserExt
          for _, ext in ipairs(cl.extensions) do
            if ext.name == "browser" then browserExt = ext end
          end
          if not browserExt then return false, "no browser extension" end
          local spawned, realNew = 0, hs.task.new
          hs.task.new = function(...) spawned = spawned + 1; return realNew(...) end
          cl.modules.browser.forget()
          local ctx = cl.buildContext()
          ctx.frontmostApp = "Brave Browser"
          cl.userSettings = { ["browser.tabs"] = false }
          browserExt.items(ctx)
          local whileOff = spawned
          cl.userSettings = {}
          browserExt.items(ctx)
          hs.task.new = realNew
          cl.modules.browser.forget()
          return whileOff == 0 and spawned == 1,
                 ("%d asks while off, %d after"):format(whileOff, spawned)
        end)())

  cl.unregisterExtension("switchy")
  cl.userDir, cl.userSettings = saved.dir, saved.settings
  os.execute(("rm -rf %q"):format(settingsDir))
end

group("preferences")
do
  local prefsDir = os.tmpname() .. "-prefs"
  local saved = { dir = cl.userDir, settings = cl.userSettings,
                  profile = cl.profile, editor = cl.getCommand("editor.open").run, reload = hs.reload,
                  doAfter = hs.timer.doAfter }
  cl.userDir, cl.userSettings, cl.profile = prefsDir, {}, "default"
  local opened, reloads = {}, 0
  cl.getCommand("editor.open").run = function(args) opened[#opened + 1] = args.target end
  hs.reload = function() reloads = reloads + 1 end
  hs.timer.doAfter = function(_, fn) fn(); return { stop = function() end } end
  local function readFile(path)
    local handle = path and io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("a")
    handle:close()
    return text
  end

  cl.executeCommand("workbench.action.openSettingsJson", {})
  cl.executeCommand("workbench.action.openGlobalKeybindingsFile", {})
  check("Open User Settings and Keyboard Shortcuts open the profile's own files, made if missing",
        opened[1] == prefsDir .. "/settings.json" and opened[2] == prefsDir .. "/keybindings.json"
        and type(cl.decodeJSONC(readFile(opened[1]) or "")) == "table"
        and type(cl.decodeJSONC(readFile(opened[2]) or "")) == "table",
        tostring(opened[1]) .. " / " .. tostring(opened[2]))

  cl.executeCommand("workbench.action.openRawDefaultSettings", {})
  local defaults = cl.decodeJSONC(readFile(opened[3]) or "")
  check("Default Settings is the shipped defaults with every extension's declared settings, as one object",
        type(defaults) == "table" and type(defaults.views) == "table"
        and defaults["browser.tabOrder"] == "recent" and defaults["browser.tabs"] == true
        and defaults["zoxide.enabled"] == true,
        type(defaults) == "table" and "missing keys" or tostring(opened[3]))

  cl.executeCommand("workbench.action.openDefaultKeybindingsFile", {})
  local keys = cl.decodeJSONC(readFile(opened[4]) or "")
  local found = {}
  for _, entry in ipairs(type(keys) == "table" and keys or {}) do
    found[tostring(entry.key) .. " " .. tostring(entry.command)] = true
  end
  check("Default Keyboard Shortcuts lists the shipped chords, cmd+k among them",
        found["cmd+o quickOpen"] == true and found["cmd+k quickOpen.showActions"] == true
        and not found["tab quickOpen.accept"],
        tostring(opened[4]))

  local options = cl.getCommand("workbench.profiles.actions.switchProfile").inputs[1].picker.options()
  local names = {}
  for _, option in ipairs(options) do names[option.value] = true end
  cl.executeCommand("workbench.profiles.actions.switchProfile", { profile = "raycast" })
  local chosen = cl.decodeJSONC(readFile(prefsDir .. "/profile.json") or "")
  check("Switch Profile offers default and the shipped profiles, writes profile.json and reloads",
        names.default and names.raycast and type(chosen) == "table" and chosen.profile == "raycast"
        and reloads == 1, tostring(reloads) .. " reloads")

  check("the settings picker offers a presenter's settings, and saves the one stepped", (function()
          cl.userSettings = {}
          local spec = recordedSpec("settings")
          openRecorded("root").type("settings ")
          local p = spec.picker
          local index
          for i, row in ipairs(p and p.shown or {}) do
            if row.label == "Chooser: Open on display" then index = i end
          end
          if not index then return false, "no row" end
          p.row = index
          p.accept()
          local written = cl.decodeJSONC(readFile(prefsDir .. "/settings.json") or "")
          return cl.setting("chooser", "screen") == "focused" and type(written) == "table"
                 and written["chooser.screen"] == "focused",
                 tostring(cl.setting("chooser", "screen"))
        end)())

  os.execute(("rm -rf %q"):format(prefsDir))
  cl.userDir, cl.userSettings, cl.profile = saved.dir, saved.settings, saved.profile
  cl.getCommand("editor.open").run, hs.reload, hs.timer.doAfter = saved.editor, saved.reload, saved.doAfter

end

group("settings problems")
-- Files with a mistake of every kind, loaded into layers of their own.
do
  local problemsDir = os.tmpname() .. "-problems"
  local brokenDir = problemsDir .. "-broken"
  local cleanDir = problemsDir .. "-clean"
  os.execute(("mkdir -p %q %q %q"):format(problemsDir, brokenDir, cleanDir))
  local function write(path, text)
    local handle = io.open(path, "w")
    handle:write(text)
    handle:close()
  end
  write(problemsDir .. "/settings.json", [[
    { "$schema": 5,
      "browser.tabOrder": "sideways",
      "browser.nope": true,
      "nosuch.enabled": false,
      "maccy.enabled": "no",
      "extensions": { "maccy": { "enabled": false } },
      "appearance": { "screen": "left" },
      "chooser.screen": "left",
      "logLevel": "loud",
      "bogus": 1,
      "hotkeys": "cmd+space",
      "prefixes": { "nowhere": "nw " },
      "defaultView": "nowhere",
      "rankers": { "relevance": "high", "psychic": 1 },
      "matchers": [ "fzf", "telepathy" ],
      "presenter": "hologram",
      "views": [ { "name": "actions", "enabled": false },
                 { "name": "loopA", "menus": [ "commandPalette" ], "sections": [ { "view": "loopB" } ],
                   "fallbacks": true },
                 { "name": "loopB", "menus": [ "commandPalette" ],
                   "sections": [ { "view": "loopA" }, { "from": "nosuchext" } ] },
                 { "name": "notext", "command": "quickOpen.back" } ] }]])
  write(problemsDir .. "/keybindings.json", [[
    [ { "key": "cmd+9", "command": "no.such" },
      { "key": "cmmd+k", "command": "quickOpen.back" },
      { "key": "cmd+8", "command": "quickOpen.back", "when": "a &&" },
      { "key": "cmd+7", "command": "quickOpen", "args": { "view": "nowhere" } },
      { "key": "cmd+6", "command": "quickOpen.back" },
      { "key": "Cmd+6", "command": "quickOpen.accept" },
      { "key": "cmd+5", "command": "quickOpen.back", "when": "activeView == 'root'" },
      { "key": "cmd+5", "command": "quickOpen.accept" },
      { "key": "cmd+a", "command": "quickOpen.back" },
      { "key": "shift+left", "command": "quickOpen.back" },
      { "key": "cmd+4", "command": "quickOpen.selectNext", "repeat": "yes" },
      { "command": "-also.missing" } ]
  ]])
  write(brokenDir .. "/settings.json", [[{ "a": 1 ]])
  -- An empty list decodes as {}, and a switched-off extension's settings
  -- are still its settings.
  write(cleanDir .. "/settings.json", [[
    { "$schema": "../settings.schema.json",
      "matchers": [], "prefixes": { "recent": "r " },
      "appearance": { "width": 50 },
      "chooser.screen": "focused",
      "maccy.enabled": false,
      "workbench.enabled": false,
      "views": [ { "name": "mine", "placeholder": "Mine", "menus": [ "commandPalette" ] } ],
      "tools": { "paths": { "fzf": "/bin/echo" }, "use": { "editor": "zed" }, "loginShell": false },
      "logLevel": "error",
      "browser.tabOrder": "browser" }]])

  local function layer(userDir, profile)
    local l = loadKernel()
    l.userDir, l.profile = userDir, profile
    l.setup()
    return l
  end
  local function messages(l)
    local out = {}
    for _, p in ipairs(l.problems) do out[#out + 1] = p.message end
    return table.concat(out, " | ")
  end
  local function reports(l, wanted)
    local text = messages(l)
    for _, piece in ipairs(wanted) do
      if not text:find(piece, 1, true) then return false, "missing: " .. piece end
    end
    return true
  end

  local bad, broken, clean = layer(problemsDir), layer(brokenDir), layer(cleanDir)
  local shipped, raycast, popup = layer(NO_USER_DIR), layer(NO_USER_DIR, "raycast"), layer(NO_USER_DIR, "popup")

  check("a setting that is not one, or holds the wrong value, is a problem", reports(bad, {
          '"browser.tabOrder" should be one of recent, browser',
          '"browser.nope" is not a setting of Browser',
          '"nosuch.enabled": there is no extension "nosuch"',
          '"maccy.enabled" should be a boolean, not string',
          '"extensions" is not a setting',
          '"appearance.screen" is not a setting',
          '"chooser.screen" should be one of primary, focused',
          '"logLevel" should be one of off, trace, debug, info, warning, error',
          '"bogus" is not a setting',
          '"hotkeys" is not a setting: the entry chord is a global keybinding, '
          .. '{ "key": "alt+space", "command": "quickOpen", "global": true } in keybindings.json' }))
  check("\"$schema\" names where an editor finds the JSON Schema, and is a string", (function()
          local ok, why = reports(bad, { '"$schema" should be a string, not number' })
          if not ok then return false, why end
          return not messages(clean):find("$schema", 1, true), messages(clean)
        end)())
  check("a name that points nowhere is a problem: pickers, rankers, matchers, presenters", reports(bad, {
          '"prefixes": there is no picker "nowhere"',
          '"defaultView": there is no picker "nowhere"',
          '"rankers.relevance" should be a number',
          '"rankers": there is no ranker "psychic"',
          '"matchers": there is no matcher "telepathy"',
          '"presenter": there is no presenter "hologram"',
          '"views": the sections of loopA lead back to it',
          '"views": a section of loopB names no extension "nosuchext"',
          '"views": actions is removed, and actionsView still names it' }))
  check("a picker's old fallbacks is a problem saying textCommands took its place", reports(bad, {
          '"views": loopA: "fallbacks" is not a field of a picker: use "textCommands": "fallback"' }))
  check("a picker's command names a command taking text", reports(bad, {
          '"views": notext: "command" names no command taking text "quickOpen.back"' }))
  check("logLevel sets the logger's level, in VS Code's names",
        clean.logLevel == "error" and clean.log.getLogLevel() == 1
        and shipped.logLevel == "warning" and shipped.log.getLogLevel() == 2,
        ("%s %s / %s %s"):format(tostring(clean.logLevel), tostring(clean.log.getLogLevel()),
                                 tostring(shipped.logLevel), tostring(shipped.log.getLogLevel())))
  check("a picker declared in settings alone is a picker, with the fields it names", (function()
          local spec = clean.viewNamed("mine")
          return spec ~= nil and spec.placeholder == "Mine" and type(spec.menus) == "table"
                 and spec.menus[1] == "commandPalette"
        end)())
  check("matchers is the whole set, in its order: one not named does not run", (function()
          local function names(l)
            local out = {}
            for _, m in ipairs(l.matchers) do out[#out + 1] = m.name end
            return table.concat(out, " ")
          end
          return names(shipped) == "fzf substring" and names(clean) == "" and names(bad) == "fzf",
                 names(shipped) .. " / " .. names(clean) .. " / " .. names(bad)
        end)())
  check("tools settings say where a tool is, which provider does a job, and whether a login shell is asked", (function()
          return clean.tools.path("fzf") == "/bin/echo" and clean.tools.overrides.editor == "zed"
                 and clean.loginShellLookup() == false and shipped.loginShellLookup() == true
        end)())
  check("Preferences is an extension, and switched off its commands are gone", (function()
          local command = shipped.getCommand("workbench.action.openSettingsJson")
          return command ~= nil and command.extension == "workbench"
                 and clean.getCommand("workbench.action.openSettingsJson") == nil
        end)())
  check("a keybinding to no command, with no readable key or a broken when clause, is a problem", reports(bad, {
          'cmd+9: there is no command "no.such"',
          '"cmmd+k" is not a key',
          'cmd+8: the when clause "a &&" does not parse',
          'cmd+7: there is no picker "nowhere"',
          '-also.missing: there is no command "also.missing"' }))
  check("two entries on one key in one file with no when between them, a text-editing key, "
        .. "and a repeat that is not a boolean, are problems", (function()
          local ok, why = reports(bad, {
            "Cmd+6 is bound to quickOpen.back and to quickOpen.accept with no when to tell them apart, "
            .. "so only quickOpen.accept runs",
            "cmd+a: the search field needs this key to edit text, so it is not bound",
            "shift+left: the search field needs this key to edit text, so it is not bound",
            'cmd+4: "repeat" should be a boolean, not string' })
          if not ok then return false, why end
          return not messages(bad):find("cmd+5 is bound", 1, true), messages(bad)
        end)())
  check("each problem names the file it is in", (function()
          for _, p in ipairs(bad.problems) do
            if not (p.file:find("/settings.json", 1, true) or p.file:find("/keybindings.json", 1, true)) then
              return false, p.file .. ": " .. p.message
            end
          end
          return #bad.problems > 0
        end)())
  check("a settings file that does not parse is a problem, not a silent nothing",
        reports(broken, { "does not parse, so it was ignored" }))
  local everyDir = problemsDir .. "-every"
  os.execute(("mkdir -p %q"):format(everyDir))
  write(everyDir .. "/settings.json", shipped.encodeJSON(T.everyExtensionOn(shipped)))
  local every = layer(everyDir)
  os.execute(("rm -rf %q"):format(everyDir))

  check("the shipped defaults and profiles have no problems, nor does a file of good settings, "
        .. "nor every shipped extension switched on",
        #shipped.problems == 0 and #raycast.problems == 0 and #popup.problems == 0 and #clean.problems == 0
        and #every.problems == 0,
        messages(shipped) .. messages(raycast) .. messages(popup) .. messages(clean) .. messages(every))

  check("Raycast, Maccy, GitHub and the VS Code bridge ship switched off, settings.json switches each on, "
        .. "and Default Settings says so once, in the extension's own part", (function()
          local function registered(l, name)
            for _, ext in ipairs(l.extensions) do
              if ext.name == name then return true end
            end
            return false
          end
          local text = shipped.modules.workbench.defaultSettingsText()
          local decoded = shipped.decodeJSONC(text)
          if type(decoded) ~= "table" then return false, "Default Settings does not parse" end
          for _, name in ipairs({ "github", "maccy", "raycast", "vscodebridge" }) do
            -- Entries only: a comment may mention the key.
            local key, count = '"' .. name .. '.enabled"', 0
            for line in (text .. "\n"):gmatch("(.-)\n") do
              if line:match("^%s*(\"[^\"]*\")%s*:") == key then count = count + 1 end
            end
            local value, source = shipped.setting(name, "enabled")
            if registered(shipped, name) or not registered(every, name) or value ~= false
               or source ~= "profile" or count ~= 1 or decoded[name .. ".enabled"] ~= false then
              return false, ("%s: on %s, on when switched on %s, %s from %s, written %d times"):format(name,
                tostring(registered(shipped, name)), tostring(registered(every, name)), tostring(value),
                tostring(source), count)
            end
          end
          return registered(shipped, "apps") and decoded["apps.enabled"] == true, "apps"
        end)())
  check("the popup demo is a profile of its own, not part of the defaults", (function()
          local chord = false
          for _, key in ipairs(popup.keybindingsFor("quickOpen")) do
            if key == "cmd+m" then chord = true end
          end
          return shipped.viewNamed("popup-demo") == nil and popup.viewNamed("popup-demo") ~= nil
                 and popup.viewNamed("popup-demo").presenter == "popup" and chord
        end)())
  check("problems are shown in one alert, naming the first; none when there are none", (function()
          local shown, real = {}, hs.alert.show
          hs.alert.show = function(message) shown[#shown + 1] = message end
          local reported, quiet = bad.reportProblems(), shipped.reportProblems()
          hs.alert.show = real
          return reported == true and quiet == false and #shown == 1
                 and shown[1]:find("^Command Layer: %d+ problems") ~= nil
                 and shown[1]:find("and more: Show Problems lists them all", 1, true) ~= nil,
                 tostring(shown[1])
        end)())

  os.execute(("rm -rf %q %q %q"):format(problemsDir, brokenDir, cleanDir))
end
