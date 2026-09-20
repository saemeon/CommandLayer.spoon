-- CommandLayer.spoon/tests/extensions/settings.lua
-- The settings extension's rows, and the picker once it is switched off.

local T = ...
local check, stub = T.check, T.stub

local cl = T.layer()
local rows = cl.rowsOfView("settings", T.context())
local own
for _, row in ipairs(rows) do
  if row.subject and row.subject.name == "settings" and row.subject.key == "enabled" then own = row end
end
check("the settings rows list the settings extension itself, so it can be switched off from there",
      own ~= nil and own.label == "Settings" and own.description == "Extension -- on" and own.keepOpen == true,
      tostring(own and own.description))

local off = T.layer({ ["settings.enabled"] = false })
local alerts = {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
T.openRecorded("settings")
check("switched off, the settings picker has no rows, and says settings.json is the way back",
      #off.rowsOfView("settings", T.context()) == 0 and #alerts == 1
      and alerts[1]:find('"settings.enabled": true in settings.json', 1, true) ~= nil,
      table.concat(alerts, " | "))
T.restoreStubs()

-- A settings.json in a folder of its own; stopping and starting are stand-ins,
-- so a reload that happened is counted rather than run.
do
  local folder = os.tmpname() .. "-settings-write"
  os.execute(("mkdir -p %q"):format(folder))
  local handle = assert(io.open(folder .. "/settings.json", "w"))
  handle:write("{\n  // mine\n}\n")
  handle:close()
  local l = T.loadKernel()
  l.userDir = folder
  l.setup()
  T.adopt(l)
  local reloads = 0
  stub(l, "stop", T.noop)
  stub(l, "unloadPlugins", T.noop)
  stub(l, "start", function() reloads = reloads + 1 end)

  local ok = l.extensionNamed("settings").exports.update("browser", "tabOrder", "browser")
  local value, source = l.pluginAPI("extension", "settings").inspectSetting("browser", "tabOrder")
  local reloaded = l.reload({ ifChanged = true })
  check("a setting written through the settings extension is what cl.setting reads afterwards, and "
        .. "reload({ ifChanged = true }) takes the write for no change",
        ok and value == "browser" and source == "settings.json" and reloaded == false and reloads == 0,
        ("%s from %s, reloaded %s"):format(tostring(value), tostring(source), tostring(reloaded)))
  T.restoreStubs()
  os.execute(("rm -rf %q"):format(folder))
end
