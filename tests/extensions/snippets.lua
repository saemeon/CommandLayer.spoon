-- CommandLayer.spoon/tests/extensions/snippets.lua
-- The snippets extension's checks.

local T = ...
local check = T.check
local cl = T.layer({ ["raycast.enabled"] = true })
local raycast = cl.modules.raycast

local ext
for _, e in ipairs(cl.extensions) do
  if e.name == "snippets" then ext = e end
end
if not ext then return check("snippets extension is registered", false) end

local deeplink = "raycast://extensions/raycast/snippets/search-snippets"
local open = cl.getCommand("raycast.open")
local saved = { installed = raycast.installed, run = open.run, alert = hs.alert.show,
                openURL = hs.urlevent.openURL, extensionNamed = cl.extensionNamed }
local dispatched, opened, alerts = {}, {}, 0
open.run = function(args) dispatched[#dispatched + 1] = args.target end
hs.urlevent.openURL = function(url) opened[#opened + 1] = url end
hs.alert.show = function() alerts = alerts + 1 end

raycast.installed = function() return false end
local notInstalled = ext.items({})

raycast.installed = function() return true end
local rows = ext.items({})
local row = rows[1]
if row then cl.executeCommand(row.command, row.args, {}) end

cl.extensionNamed = function(name)
  if name == "raycast" then return nil end
  return saved.extensionNamed(name)
end
local switchedOff = ext.items({})
local ok = pcall(cl.executeCommand, "snippets.open", {}, {})

raycast.installed, open.run, hs.alert.show = saved.installed, saved.run, saved.alert
hs.urlevent.openURL, cl.extensionNamed = saved.openURL, saved.extensionNamed

check("Snippets is a row only while Raycast is installed",
      #notInstalled == 0 and #rows == 1 and row.label == "Snippets",
      tostring(#notInstalled) .. " / " .. tostring(#rows))
check("picking it runs raycast.open by id with Raycast's snippet search, opening nothing itself",
      row ~= nil and row.command == "snippets.open" and #dispatched == 1
      and dispatched[1] == deeplink and #opened == 0,
      tostring(dispatched[1]) .. " / " .. tostring(#opened) .. " opened")
check("with Raycast switched off there is no row, and running it by id says so",
      #switchedOff == 0 and ok and alerts == 1 and #dispatched == 1,
      tostring(#switchedOff) .. " rows, " .. tostring(alerts) .. " alerts")
check("snippets keeps no store of its own, so it has no settings", ext.settings == nil)
