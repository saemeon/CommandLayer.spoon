-- CommandLayer.spoon/tests/extensions/workbench.lua
-- The workbench extension's checks.

local T = ...
local check = T.check
local cl = T.layer()

local command = cl.getCommand("workbench.actions.view.problems")
local function options()
  return command and command.inputs and command.inputs[1].picker.options() or {}
end

local none = options()
check("Show Problems is a workbench command, and says so when there are none",
      command ~= nil and command.extension == "workbench" and #none == 1 and none[1].value == "",
      none[1] and none[1].label)

local file = os.tmpname()
cl.problem(file, "a problem to list")
cl.problem("extension somewhere", "a problem in no file")
local listed = options()

local opened
cl.registerCommand("editor.open", { title = "spy", menus = {}, run = function(args) opened = args.target end })
cl.executeCommand("workbench.actions.view.problems", { problem = "extension somewhere" })
local afterNoFile = opened
cl.executeCommand("workbench.actions.view.problems", { problem = file })
check("it lists every problem with where it is, and picking one in a file opens that file",
      #listed == 2 and listed[1].label == "a problem to list" and listed[1].description == file
      and afterNoFile == nil and opened == file, tostring(opened))
os.remove(file)

local frecency
for _, ranker in ipairs(cl.rankers) do
  if ranker.name == "frecency" then frecency = ranker.spec end
end

local function remover(subject)
  for _, row in ipairs(cl.itemActions(subject, {})) do
    if row.command == "workbench.action.removeFromRecentlyUsed" then return row end
  end
end

frecency.reset()
local usedThing = { kind = "t", name = "used" }
cl.recordUse({ label = "used", subject = usedThing })
local offered, notOffered = remover(usedThing), remover({ kind = "t", name = "never" })
if offered then cl.executeCommand(offered.command, offered.args, {}) end
check("cmd+k on a row picked before offers Remove from Recently Used, which forgets it",
      offered ~= nil and offered.label == "Remove from Recently Used" and notOffered == nil
      and cl.lastUsed({ label = "used", subject = usedThing }) == 0 and remover(usedThing) == nil,
      tostring(offered and offered.label) .. " / " .. tostring(notOffered ~= nil))

local clear = cl.getCommand("workbench.action.clearCommandHistory")
cl.recordUse({ label = "kept" })
if clear then clear.run({}) end
local unconfirmed = cl.lastUsed({ label = "kept" })
cl.executeCommand("workbench.action.clearCommandHistory", { confirm = "clear" }, {})
check("Clear Command History asks first, and then every row picked is forgotten",
      clear ~= nil and clear.inputs[1].picker.options ~= nil and unconfirmed > 0
      and cl.lastUsed({ label = "kept" }) == 0,
      tostring(unconfirmed))
frecency.reset()

-- A profile folder of its own, watched as the person's would be. The kernel's
-- reload decides whether anything changed; stopping and starting are stand-ins,
-- starting reading the files again as setup would.
do
  local folder = os.tmpname() .. "-workbench"
  os.execute(("mkdir -p %q"):format(folder))
  local settingsPath, keysPath = folder .. "/settings.json", folder .. "/keybindings.json"
  local function write(path, text)
    local handle = assert(io.open(path, "w"))
    handle:write(text)
    handle:close()
  end
  write(settingsPath, '{\n  "browser.tabOrder": "browser"\n}\n')
  write(keysPath, "[]\n")

  local l = T.loadKernel()
  l.userDir = folder
  l.setup()
  T.adopt(l)

  local watched, changed, stops, timers = nil, nil, 0, {}
  T.stub(hs, "pathwatcher", { new = function(path, fn)
    watched, changed = path, fn
    return { start = function(w) return w end, stop = function() stops = stops + 1 end }
  end })
  T.stub(hs.timer, "doAfter", function(_, fn)
    local t = { fn = fn }
    function t.stop() t.stopped = true end
    timers[#timers + 1] = t
    return t
  end)
  -- Each timer not stopped fires, as time passing would fire it.
  local function settled()
    local due, ran = timers, 0
    timers = {}
    for _, t in ipairs(due) do
      if not t.stopped then
        ran = ran + 1
        t.fn()
      end
    end
    return ran
  end
  local reloads = 0
  l.stop, l.unloadPlugins = T.noop, T.noop
  l.start = function()
    reloads = reloads + 1
    l.userSettings = l.readJSONC(settingsPath)
    l.readJSONC(keysPath)
  end
  local function unparsed(name)
    for _, p in ipairs(l.problems) do
      if p.file:find("/" .. name, 1, true) and p.message:find("does not parse, so it was not read again", 1, true) then
        return true
      end
    end
    return false
  end

  local onAtFirst = l.setting("workbench", "autoReload") == true
  l.modules.workbench.start()
  changed({ folder .. "/profile.json" })
  local otherFile = settled()

  l.extensionNamed("settings").exports.update("browser", "tabOrder", "recent")
  changed({ settingsPath })
  settled()
  local afterOwnWrite = reloads
  write(settingsPath, '// mine\n{\n  "browser.tabOrder": "recent", // set by the picker\n}\n')
  changed({ settingsPath })
  settled()
  local afterComment = reloads
  write(settingsPath, '{ "browser.tabOrder": "browser" }')
  changed({ settingsPath })
  changed({ settingsPath })
  local burst = settled()
  local afterEdit = reloads

  check("Preferences watches the active profile's folder; a write of the layer's own, a comment, or another "
        .. "file reloads nothing, and a change made by hand reloads once however many writes it took",
        watched == folder and otherFile == 0 and afterOwnWrite == 0 and afterComment == 0
        and burst == 1 and afterEdit == 1,
        ("%s: other %d, own %d, comment %d, burst %d, edit %d"):format(tostring(watched), otherFile,
          afterOwnWrite, afterComment, burst, afterEdit))

  write(keysPath, '[ { "key": "cmd+9", "command": "quickOpen.back" } ]')
  changed({ keysPath })
  settled()
  local afterKeys = reloads
  write(keysPath, '[ { "key": ')
  changed({ keysPath })
  settled()
  local whileBroken, reported = reloads, unparsed("keybindings.json")
  -- Empty, so only having been broken tells it from the file read last.
  write(keysPath, "[]\n")
  changed({ keysPath })
  settled()

  check("a keybindings.json change reloads; one that does not parse is a problem, and reloads nothing until it "
        .. "parses", afterKeys == 2 and whileBroken == 2 and reported and reloads == 3,
        ("keys %d, broken %d (%s), fixed %d"):format(afterKeys, whileBroken, tostring(reported), reloads))

  l.extensionNamed("settings").exports.update("workbench", "autoReload", false)
  changed({ settingsPath })
  settled()
  write(settingsPath, '{ "browser.tabOrder": "recent", "workbench.autoReload": false }')
  changed({ settingsPath })
  settled()
  local whileOff = reloads
  l.modules.workbench.stop()
  l.stopRunning("workbench")

  check("workbench.autoReload is on by default; off, nothing reloads, and stopping stops the watcher",
        onAtFirst and whileOff == 3 and stops == 1, ("%d reloads, %d stops"):format(whileOff, stops))

  os.execute(("rm -rf %q"):format(folder))
end

do
  local off = T.layer({ ["settings.enabled"] = false })
  local alerts = {}
  T.stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
  local ran = off.executeCommand("workbench.action.resetSetting",
    { setting = { kind = "setting", id = "browser.tabOrder", name = "browser", key = "tabOrder", modified = true } }, {})
  check("with the settings extension switched off, Reset Setting says it cannot write settings.json, rather than "
        .. "failing without a word",
        ran == true and #alerts == 1 and alerts[1]:find("settings extension is switched off", 1, true) ~= nil,
        table.concat(alerts, " | "))
  T.restoreStubs()
end
