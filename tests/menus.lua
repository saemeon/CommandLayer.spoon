-- CommandLayer.spoon/tests/menus.lua
-- A person's <ext>.menus setting, over the menus an extension declares.

local T = ...
local check, group = T.check, T.group

local function has(layer, menu, wantedCommand, wantedSource, ctx)
  for _, row in ipairs(layer.gather(ctx or layer.contextFromKeys(), { menus = { menu } })) do
    if (wantedCommand and row.command == wantedCommand) or (wantedSource and row.source == wantedSource) then
      return true
    end
  end
  return false
end

group("menus overridden in settings")

local shipped = T.layer()
local brewInRoot = T.layer({ ["developer.menus"] = { root = true }, ["terminal.menus"] = { root = true } })
local brewOutOfPalette = T.layer({ ["developer.menus"] = { commandPalette = false } })

check("unset, an extension's commands are where it declares them: Developer: Show Logs in the palette, not the root",
      has(shipped, "commandPalette", "developer.showLogs") and not has(shipped, "root", "developer.showLogs"))
check("true adds a menu it does not declare, and a command that is no row anywhere stays none",
      has(brewInRoot, "root", "developer.showLogs") and has(brewInRoot, "commandPalette", "developer.showLogs")
      and not has(brewInRoot, "root", "terminal.run"))
check("false takes out a menu it declares",
      not has(brewOutOfPalette, "commandPalette", "developer.showLogs"))

-- The harness has no world, so no shipped extension gives item rows here.
local own = T.layer()
own.register({ name = "menutest", menus = { "root" }, items = function()
  return { { label = "a thing", subject = { kind = "thing", name = "a" }, run = function() end } }
end })
local declared = has(own, "root", nil, "menutest") and not has(own, "context", nil, "menutest")
own.userSettings = { ["menutest.menus"] = { root = false, context = true } }
check("an extension's own rows move the same way",
      declared and not has(own, "root", nil, "menutest") and has(own, "context", nil, "menutest"))

local windowsInContext = T.layer({ ["windows.menus"] = { context = true } })
local noWindow = windowsInContext.contextFromKeys()
local withWindow = windowsInContext.contextFromKeys()
withWindow.focusedWindow = "Notes"
check("true on a menu the extension declares with a when of its own keeps that when",
      not has(windowsInContext, "context", "windows.leftHalf", nil, noWindow)
      and has(windowsInContext, "context", "windows.leftHalf", nil, withWindow))

local filesOff = T.layer({ ["files.menus"] = { files = false } })
local function started(layer)
  local stops, count = layer.searchExtensions(layer.contextFromKeys(), { menus = { "files" } }, "abc", function() end)
  for _, stop in ipairs(stops) do pcall(stop) end
  return count
end
check("a search hook follows the setting too", started(shipped) >= 1 and started(filesOff) == started(shipped) - 1,
      ("%d shipped, %d with files off"):format(started(shipped), started(filesOff)))

local mistaken = T.layer({ ["brew.menus"] = { nowhere = true, root = "yes" }, ["apps.menus"] = { "root" } })
local messages = {}
for _, p in ipairs(mistaken.problems) do messages[#messages + 1] = p.message end
local text = table.concat(messages, " | ")
check("a menu no picker lists, a value not true or false, or a list is a problem",
      text:find('"brew.menus": no picker lists the menu "nowhere"', 1, true) ~= nil
      and text:find('"brew.menus.root" should be true or false', 1, true) ~= nil
      and text:find('"apps.menus" should be an object, not array', 1, true) ~= nil, text)

local defaults = shipped.modules.workbench.defaultSettingsText()
check("Default Settings writes each extension's declared menus beside its switch",
      defaults:find('"brew.menus": { "commandPalette": true, "root": true },', 1, true) ~= nil
      and defaults:find('"apps.menus": {', 1, true) ~= nil
      and defaults:find('"terminal.menus"', 1, true) == nil)
