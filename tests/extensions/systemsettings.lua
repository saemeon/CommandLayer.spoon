-- CommandLayer.spoon/tests/extensions/systemsettings.lua
-- The systemsettings extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.systemsettings

local saved = { scan = M.scan }
local scans = 0
M.scan = function()
  scans = scans + 1
  return { { name = "Wi-Fi", id = "com.apple.wifi-settings-extension",
             url = "x-apple.systempreferences:com.apple.wifi-settings-extension" } }
end
cl.stopRunning("systemsettings")

local ext
for _, e in ipairs(cl.extensions) do
  if e.name == "systemsettings" then ext = e end
end
local rows = ext and ext.items({}) or {}
local again = ext and ext.items({}) or {}
M.scan = saved.scan
cl.stopRunning("systemsettings")

local row = rows[1]
local verbs = {}
for _, verb in ipairs(row and cl.itemActions(row.subject, {}) or {}) do
  if verb.command == "systemsettings.openPane" or verb.command == "systemsettings.copyURL" then
    verbs[verb.label] = verb.args.pane == row.subject
  end
end
check("a settings pane is a row opening its URL, scanned once while the cache is fresh",
      row ~= nil and row.label == "Wi-Fi" and row.command == "system.open"
      and row.args.target == "x-apple.systempreferences:com.apple.wifi-settings-extension"
      and #again == 1 and scans == 1,
      tostring(scans) .. " scans")
check("a pane offers Open pane and Copy URL on cmd+k", verbs["Open pane"] and verbs["Copy URL"])

local point = { EXExtensionPointIdentifier = M.extensionPoint }
local bundles = {
  ["Shown.appex"] = { info = { CFBundleIdentifier = "a.shown", CFBundleDisplayName = "ShownExtension",
                               EXAppExtensionAttributes = point },
                      strings = { en = { CFBundleDisplayName = "Date & Time" } } },
  ["Display.appex"] = { info = { CFBundleIdentifier = "a.display", CFBundleDisplayName = "Bluetooth",
                                 CFBundleName = "BluetoothSettings", EXAppExtensionAttributes = point } },
  ["Named.appex"] = { info = { CFBundleIdentifier = "a.named", CFBundleName = "CDs & DVDs",
                               EXAppExtensionAttributes = point } },
  ["Nameless.appex"] = { info = { CFBundleIdentifier = "a.nameless", EXAppExtensionAttributes = point } },
  ["Other.appex"] = { info = { CFBundleIdentifier = "a.other", CFBundleDisplayName = "Other",
                               EXAppExtensionAttributes = { EXExtensionPointIdentifier = "elsewhere" } } },
}
local restore = { dir = hs.fs.dir, read = hs.plist.read }
hs.fs.dir = function()
  local names, i = {}, 0
  for name in pairs(bundles) do names[#names + 1] = name end
  table.sort(names)
  return function() i = i + 1 return names[i] end, nil
end
hs.plist.read = function(path)
  local entry, file = path:match("/([^/]+%.appex)/Contents/(.+)$")
  local bundle = bundles[entry]
  if not bundle then return nil end
  if file == "Info.plist" then return bundle.info end
  if file == "Resources/InfoPlist.loctable" then return bundle.strings end
end
local scanned = M.scan()
hs.fs.dir, hs.plist.read = restore.dir, restore.read
local names = {}
for _, pane in ipairs(scanned) do names[#names + 1] = pane.name .. "=" .. pane.id end
check("a pane is named as System Settings shows it, then by its plist, and one with no name is left out",
      table.concat(names, " ") == "Bluetooth=a.display CDs & DVDs=a.named Date & Time=a.shown",
      table.concat(names, " "))
