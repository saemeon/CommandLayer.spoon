-- CommandLayer.spoon/tests/reload.lua
-- Reloading the layer: stopped, what setup made undone, and started again.

local T = ...
local check, group, stub = T.check, T.group, T.stub

group("reload")
do
  local folder = os.tmpname() .. "-reload"
  os.execute(("mkdir -p %q"):format(folder))
  local function write(name, text)
    local handle = assert(io.open(folder .. "/" .. name, "w"))
    handle:write(text)
    handle:close()
  end
  local QUIET = '"tools": { "loginShell": false }'
  write("settings.json", '{ "prefixes": { "recent": "rr " }, ' .. QUIET .. ' }')
  write("keybindings.json", '[ { "key": "cmd+9", "command": "quickOpen.back" } ]')

  -- Everything started and not yet stopped, by kind: what a reload must not
  -- leave a second of behind.
  local live = {}
  local function startable(kind, fields)
    local object = fields or {}
    function object.start()
      if not object.running then
        object.running = true
        live[kind] = (live[kind] or 0) + 1
      end
      return object
    end
    function object.stop()
      if object.running then
        object.running = false
        live[kind] = live[kind] - 1
      end
      return object
    end
    return object
  end
  local function started(kind, fields) return startable(kind, fields).start() end

  local kernel = T.loadKernel()
  local modal = hs.hotkey.modal.last
  -- As hs.hotkey.modal binds: a hotkey per chord, kept in `keys`.
  modal.keys = {}
  modal.bind = function(self, _, key)
    local hotkey = started("modal hotkey", { key = key })
    hotkey.delete = hotkey.stop
    self.keys[#self.keys + 1] = hotkey
    return self
  end
  stub(hs.hotkey, "bind", function()
    local hotkey = started("hotkey")
    hotkey.delete = hotkey.stop
    return hotkey
  end)
  stub(hs.pathwatcher, "new", function() return startable("path watcher") end)
  stub(hs.application.watcher, "new", function() return startable("application watcher") end)
  stub(hs.timer, "doAfter", function() return started("timer") end)
  stub(hs.timer, "doEvery", function() return started("timer") end)
  local spotlight = hs.spotlight.new
  stub(hs.spotlight, "new", function()
    local query = spotlight()
    local counted = startable("spotlight query")
    function query.start() counted.start() return query end
    function query.stop() counted.stop() return query end
    return query
  end)
  stub(hs.task, "new", function()
    local task = startable("task", { setInput = T.noop, closeInput = T.noop })
    task.terminate = task.stop
    return task
  end)

  -- Guarded as every harness layer is, before its extensions start: never the
  -- browser's or VS Code's real files.
  local startExtensions = kernel.startExtensions
  kernel.startExtensions = function()
    T.adopt(kernel)
    return startExtensions()
  end
  kernel.userDir = folder

  local function state()
    local kinds, presenters = {}, 0
    for kind, count in pairs(live) do kinds[#kinds + 1] = kind .. " " .. count end
    table.sort(kinds)
    for _ in pairs(kernel.presenters) do presenters = presenters + 1 end
    return table.concat(kinds, ", ")
           .. (" | %d commands, %d views, %d extensions, %d keybindings, %d problems, %d presenters"):format(
             #kernel.getCommands(), #kernel.views, #kernel.extensions, #kernel.keybindings,
             #kernel.problems, presenters)
  end

  kernel.start()
  local atStart = state()
  local watching = (live["path watcher"] or 0) > 0 and (live["modal hotkey"] or 0) > 0
  local exits = modal.exits
  kernel.reload()
  kernel.reload()
  local afterTwo = state()

  check("a reload closes the layer, and leaves exactly as much running and registered as starting did",
        watching and modal.exits == exits + 2 and afterTwo == atStart and #kernel.problems == 0,
        ("%d exits: %s / %s"):format(modal.exits - exits, atStart, afterTwo))

  write("settings.json", '{ "prefixes": { "recent": "r2 " }, ' .. QUIET
                         .. ', "views": [ { "name": "root", "placeholder": "Reloaded" },'
                         .. ' { "name": "extra", "menus": [ "extra" ] } ] }')
  write("keybindings.json", '[ { "key": "cmd+8", "command": "quickOpen.back" } ]')
  kernel.reload()
  local keys = {}
  for _, hotkey in ipairs(modal.keys) do
    if hotkey.running then keys[hotkey.key] = true end
  end
  local chords = kernel.keybindingsFor("quickOpen.back")

  check("a reload reads settings.json and keybindings.json again, and binds what they say now",
        kernel.prefixes.recent == "r2 " and kernel.viewNamed("root").placeholder == "Reloaded"
        and kernel.viewNamed("extra") ~= nil
        and keys["8"] and not keys["9"] and #chords == 1 and chords[1] == "cmd+8",
        tostring(kernel.prefixes.recent) .. " " .. table.concat(chords, " "))

  local exitsBefore = modal.exits
  local unchanged = kernel.reload({ ifChanged = true })
  write("keybindings.json", '// the same, said again\n[ { "key": "cmd+8", "command": "quickOpen.back", }, ]')
  local sameValue = kernel.reload({ ifChanged = true })
  local exitsWhileSame = modal.exits
  write("keybindings.json", '[ { "key": "cmd+7", "command": "quickOpen.back" } ]')
  local changed = kernel.reload({ ifChanged = true })
  local chordsNow = kernel.keybindingsFor("quickOpen.back")
  write("settings.json", '{ "prefixes": ')
  local broken = kernel.reload({ ifChanged = true })
  local reported = false
  for _, p in ipairs(kernel.problems) do
    if p.file:find("settings.json", 1, true) and p.message:find("does not parse", 1, true) then reported = true end
  end

  check("reload({ ifChanged = true }) reloads, and says so, only when settings.json or keybindings.json says "
        .. "something new; one that does not parse is a problem and reloads nothing",
        unchanged == false and sameValue == false and exitsWhileSame == exitsBefore
        and changed == true and chordsNow[1] == "cmd+7" and broken == false and reported
        and modal.exits == exitsBefore + 1,
        ("%s %s %s %s, %d exits"):format(tostring(unchanged), tostring(sameValue), tostring(changed),
          tostring(broken), modal.exits - exitsBefore))

  write("settings.json", '{ "bogus": 1, ' .. QUIET .. ' }')
  kernel.reload()
  kernel.reload()

  check("what settings.json no longer says is gone, the profile stays, and problems are found again, never piled up",
        kernel.prefixes.recent == nil and kernel.viewNamed("root").placeholder == "Search"
        and kernel.viewNamed("extra") == nil
        and kernel.profile == "default" and #kernel.problems == 1,
        ("%s, %d problems"):format(tostring(kernel.prefixes.recent), #kernel.problems))

  kernel.stop()
  os.execute(("rm -rf %q"):format(folder))
end
