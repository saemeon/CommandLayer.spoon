-- CommandLayer.spoon/tests/extensions/raycast.lua
-- The raycast extension's checks.

local T = ...
local check = T.check
local cl = T.layer({ ["raycast.enabled"] = true })
local M = cl.modules.raycast

local command = cl.getCommand("raycast.open")
check("raycast.open is a command that is never a row",
      command ~= nil and type(command.run) == "function" and next(command.menus) == nil)

local opened, installed = {}, M.installed
local savedOpen = hs.urlevent.openURL
hs.urlevent.openURL = function(url) opened[#opened + 1] = url end
M.installed = function() return true end
local saved = cl.userSettings
cl.userSettings = { ["raycast.commands"] = {
  { title = "Mine", url = "raycast://extensions/me/mine?x=1" },
} }
local rows
for _, ext in ipairs(cl.extensions) do
  if ext.name == "raycast" then rows = ext.items({}) end
end
cl.userSettings = saved
M.installed = installed
local row = rows and rows[1]
if row then cl.executeCommand(row.command, { target = row.args.target, fallbackText = "a b" }, {}) end
hs.urlevent.openURL = savedOpen

check("its rows are the raycast.commands setting, each opening its deeplink",
      rows ~= nil and #rows == 1 and row.label == "Mine" and row.command == "raycast.open"
      and opened[1] == "raycast://extensions/me/mine?x=1&fallbackText=a%20b",
      tostring(opened[1]))
