-- CommandLayer.spoon/tests/extensions/appmenus.lua
-- The appmenus extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.appmenus

local reads, lookups = {}, 0
local front = {
  name = function() return "Front App" end,
  getMenuItems = function(_, callback) reads[#reads + 1] = callback end,
}
local saved = { front = hs.application.frontmostApplication, get = hs.application.get,
                pendingSeconds = M.pendingSeconds }
hs.application.frontmostApplication = function() return front end
hs.application.get = function() lookups = lookups + 1 end
M.stop()

local ready = 0
local first = M.items("Front App", function() ready = ready + 1 end)
M.items("Front App")
local asked = #reads
if reads[1] then
  reads[1]({ { AXTitle = "File", AXChildren = { { { AXTitle = "New" }, { AXTitle = "Open" } } } },
             { AXTitle = "Services", AXChildren = { { { AXTitle = "Mail" } } } } })
end
local after = M.items("Front App")
check("the front app's menus are read once while in flight, and a waiting picker is told",
      #first == 0 and asked == 1 and lookups == 0 and ready == 1 and #after == 2,
      ("%d first, %d reads, %d lookups, %d told, %d after"):format(#first, asked, lookups, ready, #after))

M.stop()
M.pendingSeconds = 0
M.items("Front App")
M.items("Front App")
check("a read that never calls back is given up on, so the app is read again",
      #reads == 3, tostring(#reads) .. " reads")

local offered = {}
for _, row in ipairs(cl.itemActions({ kind = "menu", app = "Front App", name = "File > New",
                                      path = { "File", "New" } }, {})) do
  if row.command then offered[row.command] = row end
end
local copied, realCopy = nil, cl.getCommand("system.copy")
local copyRun = realCopy and realCopy.run
if realCopy then realCopy.run = function(args) copied = args.text end end
if offered["appmenus.copyMenuPath"] then
  cl.executeCommand("appmenus.copyMenuPath", offered["appmenus.copyMenuPath"].args, {})
end
if realCopy then realCopy.run = copyRun end
check("a menu row's cmd+k offers running it and copying its path",
      offered["appmenus.runMenuItem"] ~= nil and copied == "File > New", tostring(copied))

-- Shortcuts, formatted as the menus are read.
do
  local spec
  for _, ext in ipairs(cl.extensions) do
    if ext.name == "appmenus" then spec = ext end
  end
  M.stop()
  T.stub(hs.application, "menuGlyphs", { [23] = "⌫" })
  local formatted, realShortcut = 0, M.shortcut
  T.stub(M, "shortcut", function(node)
    formatted = formatted + 1
    return realShortcut(node)
  end)
  M.items("Front App")
  if reads[#reads] then
    reads[#reads]({ { AXTitle = "File", AXChildren = { {
      { AXTitle = "New", AXMenuItemCmdChar = "N", AXMenuItemCmdGlyph = "", AXMenuItemCmdModifiers = { "cmd" } },
      { AXTitle = "Save As…", AXMenuItemCmdChar = "S", AXMenuItemCmdModifiers = { "cmd", "shift" } },
      { AXTitle = "Move to Trash", AXMenuItemCmdChar = "", AXMenuItemCmdGlyph = 23,
        AXMenuItemCmdModifiers = { "cmd" } },
      { AXTitle = "Plain", AXMenuItemCmdChar = "", AXMenuItemCmdGlyph = "", AXMenuItemCmdModifiers = {} },
    } } } })
  end

  local function details()
    local out = {}
    for i, row in ipairs(spec and spec.items({ frontmostApp = "Front App" }) or {}) do out[i] = row.detail or "-" end
    return table.concat(out, " ")
  end
  local on = details()
  local again = details()
  check("a menu item's shortcut is in its subtitle, modifiers in a menu's order, formatted once as menus are read",
        on == "⌘N ⇧⌘S ⌘⌫ -" and again == on and formatted == 4,
        ("%s / %d formatted"):format(on, formatted))

  local realSetting = cl.setting
  cl.setting = function(ext, key, ...)
    if ext == "appmenus" and key == "shortcuts" then return false, "settings.json" end
    return realSetting(ext, key, ...)
  end
  local off = details()
  cl.setting = realSetting
  check("and with appmenus.shortcuts off there is none", off == "- - - -", off)
end

hs.application.frontmostApplication, hs.application.get = saved.front, saved.get
M.pendingSeconds = saved.pendingSeconds
M.stop()

-- Where an app's menu items are offered: the palette and the context
-- picker, and the root too, where rank 0 keeps them under everything until
-- something is typed. Apps are already in the palette beside the root.
do
  local menus = {}
  for _, ext in ipairs(cl.extensions) do
    if ext.name == "appmenus" or ext.name == "apps" then
      local names = {}
      for _, name in ipairs(ext.menus or {}) do names[#names + 1] = name end
      table.sort(names)
      menus[ext.name] = table.concat(names, ",")
    end
  end
  check("menu items feed the root, the palette and the context picker; apps the root, palette and recent",
        menus.appmenus == "commandPalette,context,root"
        and menus.apps == "commandPalette,recent,root",
        tostring(menus.appmenus) .. " / " .. tostring(menus.apps))
end
