-- CommandLayer.spoon/tests/extensions/windows.lua
-- The windows extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.windows

local focused, closed, alerts, searches = {}, {}, 0, 0

local function fakeWindow(id, title, appName, bundleID)
  local w = { current = title }
  w.id = function() return id end
  w.title = function() return w.current end
  w.application = function()
    return { name = function() return appName end,
             bundleID = function() return bundleID end }
  end
  w.focus = function() focused[#focused + 1] = id end
  w.close = function() closed[#closed + 1] = id end
  w.minimize = function() end
  return w
end

local broken = { id = function() error("window gone") end }
local notes    = fakeWindow(3, "Notes", "Notes", "com.apple.Notes")
local console  = fakeWindow(9, "Console", "Hammerspoon", "org.hammerspoon.Hammerspoon")
local terminal = fakeWindow(5, "", "Terminal", "com.apple.Terminal")
local mail     = fakeWindow(7, "Inbox", "Mail", "com.apple.mail")
local live = { [3] = notes, [9] = console, [5] = terminal, [7] = mail }

-- Each of hs.window's lists in an order of its own, and the window server's
-- ids front to back, so an order in the rows can only come from one of them.
-- Counted, so a check sees which was read and how often.
local lists = { all = { broken, mail, notes, console, terminal },
                ordered = { notes, terminal },
                visible = { notes, terminal, console } }
local zOrder = { 5, 9, 3 }
local asked = { all = 0, ordered = 0, visible = 0, z = 0 }
local function reads() return asked.all + asked.ordered + asked.visible + asked.z end
local function orderedIds() asked.z = asked.z + 1; return zOrder end
-- "all" is every window on screen and every window of the apps in the Dock, so a
-- Dock app gives lists.all; a background service is never asked.
local backgroundAsked = 0
local apps = {
  { kind = function() return 1 end, bundleID = function() return "test.dock" end, name = function() return "Dock app" end,
    allWindows = function() asked.all = asked.all + 1; return lists.all end },
  { kind = function() return 0 end, bundleID = function() return "test.service" end, name = function() return "Service" end,
    allWindows = function() backgroundAsked = backgroundAsked + 1; return {} end },
}
stub(hs.application, "runningApplications", function() return apps end)
stub(hs.window, "orderedWindows", function() asked.ordered = asked.ordered + 1; return lists.ordered end)
stub(hs.window, "visibleWindows", function() asked.visible = asked.visible + 1; return lists.visible end)
stub(hs.window, "_orderedwinids", orderedIds)
stub(hs.window, "get", function(id) searches = searches + 1; return live[id] end)
stub(hs.alert, "show", function() alerts = alerts + 1 end)
-- Timers kept, so a check can end a turn by firing the ones it started.
local timers = {}
stub(hs.timer, "doAfter", function(_, fn)
  timers[#timers + 1] = fn
  return { stop = function() end }
end)

local function ids(list)
  local out = {}
  for _, w in ipairs(list) do out[#out + 1] = tostring(w.id) end
  return table.concat(out, " ")
end

local function listed(source)
  local saved = cl.userSettings
  cl.userSettings = { ["windows.source"] = source }
  M.forget()
  local ok, result = pcall(M.windows)
  M.forget()
  cl.userSettings = saved
  if not ok then error(result, 0) end
  return ids(result)
end

M.stop()
local before = reads()
M.start()
check("starting reads no window list", reads() == before, tostring(reads() - before) .. " reads")

local byPickerDefault = cl.setting("windows", "sourceByPicker")
check("by default a picker lists ordered windows, and recent every window",
      cl.setting("windows", "source") == "ordered" and M.sourceFor({ activeView = "root" }) == "ordered"
      and type(byPickerDefault) == "table" and byPickerDefault.recent == "all"
      and M.sourceFor({ activeView = "recent" }) == "all",
      tostring(cl.setting("windows", "source")) .. " / " .. tostring(M.sourceFor({ activeView = "recent" })))

check("all lists every window front to back by the window server's order, one not in that order "
        .. "after the rest, one that cannot be read and Hammerspoon's left out",
      listed("all") == "5 3 7", listed("all"))
check("all never asks a background service for its windows, only the apps in the Dock",
      backgroundAsked == 0, backgroundAsked .. " asks")
local visibleOnly = fakeWindow(11, "Display", "BetterDisplay", "pro.betterdisplay.BetterDisplay")
lists.ordered = { notes, terminal, visibleOnly }
local withVisible = listed("all")
lists.ordered = { notes, terminal }
check("all lists a window on screen whatever its app, though that app is not in the Dock",
      withVisible == "5 3 11 7" and backgroundAsked == 0, withVisible)

local zBefore, orderedBefore = asked.z, asked.ordered
local ordered = listed("ordered")
check("ordered keeps orderedWindows' own order, asking nothing more",
      ordered == "3 5" and asked.z == zBefore and asked.ordered == orderedBefore + 1, ordered)

check("visible is visibleWindows, front to back", listed("visible") == "5 3", listed("visible"))

stub(hs.window, "_orderedwinids", nil)
local withoutOrder = listed("all")
stub(hs.window, "_orderedwinids", function() error("private, and gone") end)
local failingOrder = listed("all")
stub(hs.window, "_orderedwinids", orderedIds)
check("without the window server's order, or with it failing, the list keeps its own order",
      withoutOrder == "3 5 7" and failingOrder == "3 5 7", withoutOrder .. " / " .. failingOrder)

local savedSettings = cl.userSettings
cl.userSettings = { ["windows.source"] = "all", ["windows.sourceByPicker"] = { recent = "ordered" } }
M.forget()
local readsBefore = { all = asked.all, ordered = asked.ordered }
local inRecent = ids(M.windows({ activeView = "recent" }))
local inRoot = ids(M.windows({ activeView = "root" }))
local again = ids(M.windows({ activeView = "recent" }))
-- all reads the windows on screen too, so ordered is read by both.
local readEach = asked.all == readsBefore.all + 1 and asked.ordered == readsBefore.ordered + 2
cl.userSettings = savedSettings
M.forget()
check("sourceByPicker chooses a picker's source, others take windows.source, and one open reads each source once",
      inRecent == "3 5" and again == "3 5" and inRoot == "5 3 7" and readEach,
      ("%s / %s / %s / all %d ordered %d"):format(inRecent, inRoot, again, asked.all - readsBefore.all,
        asked.ordered - readsBefore.ordered))

local problemLines, restorePrint = T.capturingPrint()
local problemLayer = T.setup(T.loadKernel(), { ["windows.sourceByPicker"] = { root = "everything", recent = "visible" } })
restorePrint()
local problemsNamed = {}
for _, p in ipairs(problemLayer.getProblems()) do
  if p.message:find("sourceByPicker", 1, true) then problemsNamed[#problemsNamed + 1] = p.message end
end
check("a sourceByPicker value that is not a source is a problem naming the picker and the value",
      #problemsNamed == 1 and #problemLines >= 1 and problemsNamed[1]:find('"root"', 1, true) ~= nil
      and problemsNamed[1]:find('"everything"', 1, true) ~= nil,
      table.concat(problemsNamed, " | "))

M.forget()
-- The checks from here on read the full list, which the source "all" gives.
cl.userSettings = { ["windows.source"] = "all" }
M.forget()
local allBefore, timersBefore = asked.all, #timers
cl.gather({}, { menus = { "windows" } })
cl.gather({}, { menus = { "root" } })
local once = asked.all == allBefore + 1
for i = timersBefore + 1, #timers do timers[i]() end
cl.gather({}, { menus = { "windows" } })
check("one open reads the list once, however many views gather it, and the next open reads it again",
      once and asked.all == allBefore + 2, tostring(asked.all - allBefore) .. " reads")
M.forget()

local function rowIds(ctx)
  local out = {}
  for _, row in ipairs(cl.gather(ctx, { menus = { "windows" } })) do
    if row.subject and row.subject.kind == "window" then out[#out + 1] = tostring(row.subject.id) end
  end
  return table.concat(out, " ")
end
local altTab = rowIds({ focusedWindow = { id = function() return 5 end } })
check("the window you were in is listed last, so the first is the one before it",
      altTab == "3 7 5", altTab)

local searchedBefore = searches
cl.executeCommand("windows.focus", { window = { kind = "window", id = 5 } })
check("focusing a listed window uses the one kept, not a search of all windows",
      focused[1] == 5 and searches == searchedBefore,
      tostring(searches - searchedBefore) .. " searches")

live[5] = nil
lists.all, lists.ordered = { mail, notes }, { notes }
M.forget()
M.windows()
local ok = pcall(cl.executeCommand, "windows.close", { window = { kind = "window", id = 5 } })
check("a window that has gone is reported, not acted on",
      ok and alerts == 1 and #closed == 0)

local verbs = cl.itemActions({ kind = "window", id = 7, app = "Mail" }, cl.buildContext())
local offered = {}
for _, v in ipairs(verbs) do offered[v.label] = true end
local inContext = {}
for _, row in ipairs(cl.gather({ focusedWindow = fakeWindow(99, "Front", "App") }, { menus = { "context" } })) do
  if row.command then inContext[row.command] = true end
end
check("close, minimise and the layouts are context actions for the window in front; focus is not",
      inContext["windows.close"] and inContext["windows.minimize"] and inContext["windows.leftHalf"]
      and not inContext["windows.focus"])
local withoutWindow = {}
for _, row in ipairs(cl.gather({ screenCount = 1 }, { menus = { "context" } })) do
  if row.command then withoutWindow[row.command] = true end
end
check("with no window in front, none of them are", not withoutWindow["windows.close"]
      and not withoutWindow["windows.leftHalf"])

check("a window row offers focus, close, minimise and the layouts, close and minimise naming its app",
      offered["Focus"] and offered["Close -- Mail"] and offered["Minimise -- Mail"]
      and offered["Left half"])

local function rootRow(ctx, id)
  for _, row in ipairs(cl.gather(ctx, { menus = { "root" } })) do
    if row.command == id then return row end
  end
end
local frontClose = rootRow({ focusedWindow = fakeWindow(98, "Draft", "Notes"), frontmostApp = "Notes",
                             screenCount = 1 }, "windows.close")
local noWindowClose = rootRow({ frontmostApp = "Notes", screenCount = 1 }, "windows.close")
check("in the root, Close names the app whose window it closes, and nothing while there is no window",
      frontClose ~= nil and frontClose.label == "Window: Close -- Notes"
      and noWindowClose ~= nil and noWindowClose.label == "Window: Close",
      tostring(frontClose and frontClose.label) .. " / " .. tostring(noWindowClose and noWindowClose.label))

local moved
local win = { application = function() end,
              moveToUnit = function(_, unit) moved = unit end }
cl.executeCommand("windows.leftHalf", { window = { kind = "window", window = win } }, {})
check("a layout moves the window it is given", moved ~= nil and moved.x == 0 and moved.w == 0.5)

local function onApp(name)
  local found = {}
  local ctx = { frontmostApp = "Mail", screenCount = 1 }
  for _, row in ipairs(cl.itemActions({ kind = "app", name = name, id = "x." .. name }, ctx)) do
    if row.command then found[row.command] = row end
  end
  return found
end
local frontApp, otherApp = onApp("Mail"), onApp("Notes")
moved = nil
if frontApp["windows.leftHalf"] then
  cl.executeCommand("windows.leftHalf", frontApp["windows.leftHalf"].args, { focusedWindow = win })
end
check("cmd+k on the app in front moves its focused window; on another app, no layouts",
      frontApp["windows.leftHalf"] and not frontApp["windows.close"] and not frontApp["windows.focus"]
      and not otherApp["windows.leftHalf"] and moved ~= nil and moved.w == 0.5)

local function commandsIn(ctx)
  local found = {}
  for _, row in ipairs(cl.gather(ctx, { menus = { "root" } })) do
    if row.command then found[row.command] = true end
  end
  return found
end
local oneScreen, twoScreens = commandsIn({ screenCount = 1 }), commandsIn({ screenCount = 2 })
check("layouts are in the root; moving to another screen only with more than one",
      oneScreen["windows.leftHalf"] and not oneScreen["windows.nextScreen"]
      and twoScreens["windows.nextScreen"] == true)

local layoutVerbs = {}
for _, v in ipairs(cl.itemActions({ kind = "window", id = 7 }, {})) do
  if v.command == "windows.leftHalf" then layoutVerbs[#layoutVerbs + 1] = v end
end
check("cmd+k on a window offers each layout with that window given",
      #layoutVerbs == 1 and layoutVerbs[1].label == "Left half" and layoutVerbs[1].args.window.id == 7)

local input = cl.itemInputOf(cl.getCommand("windows.leftHalf"))
check("a layout picked from search moves the window you were in",
      input ~= nil and input.preferCurrent == true)

M.stop()

----------------------------------------------------------------------

T.group("window providers")

-- A kernel whose settings.json chooses the provider, as a person's would.
local function withProvider(name)
  local folder = os.tmpname() .. "-windows-" .. name
  os.execute(("mkdir -p %q"):format(folder))
  local handle = assert(io.open(folder .. "/settings.json", "w"))
  handle:write(('{ "windows.provider": %q, "raycast.enabled": true }'):format(name))
  handle:close()
  local kernel = T.loadKernel()
  kernel.userDir = folder
  kernel.setup()
  return T.adopt(kernel)
end

-- What each command a move could be sent through was given.
local function recording(kernel)
  local sent = {}
  for _, id in ipairs({ "raycast.open", "system.open", "shell.run" }) do
    local command = kernel.getCommand(id)
    if command then
      command.run = function(args)
        sent[#sent + 1] = id .. " " .. (type(args.cmd) == "table" and table.concat(args.cmd, " ")
                                        or tostring(args.target))
      end
    end
  end
  return sent
end

local focusedIds, movedByHammerspoon, alertTexts = {}, false, {}
local win7 = { id = function() return 7 end, application = function() end,
               focus = function() focusedIds[#focusedIds + 1] = 7 end,
               moveToUnit = function() movedByHammerspoon = true end }
local given = { kind = "window", window = win7 }
stub(hs.alert, "show", function(text) alerts = alerts + 1; alertTexts[#alertTexts + 1] = tostring(text) end)
stub(hs.window, "get", function(id) return id == 7 and win7 or nil end)
stub(hs.timer, "doAfter", function() return { stop = function() end } end)

local function registered(kernel, ids)
  local out = {}
  for _, id in ipairs(ids) do out[#out + 1] = id .. "=" .. tostring(kernel.getCommand("windows." .. id) ~= nil) end
  return table.concat(out, " ")
end

local raycastLayer = withProvider("raycast")
raycastLayer.modules.raycast.installed = function() return true end
local toRaycast = recording(raycastLayer)
raycastLayer.executeCommand("windows.leftHalf", { window = given }, {})
raycastLayer.executeCommand("windows.fullScreen", { window = given }, {})
raycastLayer.executeCommand("windows.nextScreen", { window = { kind = "window", id = 7 } }, {})
check("with Raycast, a move opens its Window Management deeplink through raycast.open, and Centre, "
      .. "which it has no action for, is no command",
      table.concat(toRaycast, " | ") == "raycast.open raycast://extensions/raycast/window-management/left-half"
        .. " | raycast.open raycast://extensions/raycast/window-management/toggle-fullscreen"
        .. " | raycast.open raycast://extensions/raycast/window-management/next-display"
      and registered(raycastLayer, { "leftHalf", "centre" }) == "leftHalf=true centre=false",
      table.concat(toRaycast, " | ") .. " / " .. registered(raycastLayer, { "leftHalf", "centre" }))
check("a tool that moves the window in front has a window chosen from the list focused first",
      #focusedIds == 1, tostring(#focusedIds))

stub(hs.application, "pathForBundleID", function(id)
  return id == "com.knollsoft.Rectangle" and "/Applications/Rectangle.app" or nil
end)
local rectangleLayer = withProvider("rectangle")
local toRectangle = recording(rectangleLayer)
rectangleLayer.executeCommand("windows.topLeft", { window = given }, {})
check("with Rectangle, a move is its URL scheme through system.open, and there is no full screen",
      table.concat(toRectangle, " | ") == "system.open rectangle://execute-action?name=top-left"
      and registered(rectangleLayer, { "topLeft", "fullScreen", "centre" })
          == "topLeft=true fullScreen=false centre=false",
      table.concat(toRectangle, " | ") .. " / " .. registered(rectangleLayer, { "topLeft", "fullScreen" }))

local yabaiLayer = withProvider("yabai")
yabaiLayer.tools.paths.yabai = "/fake/yabai"
local toYabai = recording(yabaiLayer)
yabaiLayer.executeCommand("windows.rightHalf", { window = given }, {})
yabaiLayer.executeCommand("windows.centre", { window = given }, {})
yabaiLayer.executeCommand("windows.previousScreen", { window = given }, {})
check("with yabai, a move runs yabai -m window on that window's id, as an argv list through shell.run",
      table.concat(toYabai, " | ") == "shell.run yabai -m window 7 --grid 1:2:1:0:1:1"
        .. " | shell.run yabai -m window 7 --grid 10:20:3:1:14:8"
        .. " | shell.run yabai -m window 7 --display prev"
      and #focusedIds == 1,
      table.concat(toYabai, " | "))

local aerospaceLayer = withProvider("aerospace")
aerospaceLayer.tools.paths.aerospace = "/fake/aerospace"
local toAerospace = recording(aerospaceLayer)
aerospaceLayer.executeCommand("windows.nextScreen", { window = given }, {})
aerospaceLayer.executeCommand("windows.fullScreen", { window = given }, {})
check("with AeroSpace, only what its CLI does: other monitors and full screen, and no layouts",
      table.concat(toAerospace, " | ")
        == "shell.run aerospace move-node-to-monitor --window-id 7 --wrap-around next"
        .. " | shell.run aerospace macos-native-fullscreen --window-id 7"
      and registered(aerospaceLayer, { "leftHalf", "maximise", "nextScreen" })
          == "leftHalf=false maximise=false nextScreen=true",
      table.concat(toAerospace, " | ") .. " / " .. registered(aerospaceLayer, { "leftHalf", "maximise" }))

local function rootMoves(kernel)
  local found = {}
  -- Built by the kernel, so it carries the keys setContext set.
  local ctx = kernel.buildContext()
  ctx.screenCount = 2
  for _, row in ipairs(kernel.gather(ctx, { menus = { "root" } })) do
    if row.command and row.command:find("^windows%.") and row.command ~= "windows.focus"
       and row.command ~= "windows.close" and row.command ~= "windows.minimize" then
      found[#found + 1] = row.command
    end
  end
  return #found
end
yabaiLayer.modules.windows.start()
local installedRows = rootMoves(yabaiLayer)
yabaiLayer.modules.windows.stop()

local missingLayer = withProvider("yabai")
missingLayer.tools.candidates.yabai = { "/nonexistent/yabai" }
missingLayer.tools.forget()
local lines, restore = T.capturingPrint()
missingLayer.modules.windows.start()
local toMissing = recording(missingLayer)
local alertsBefore = alerts
missingLayer.executeCommand("windows.leftHalf", { window = given }, {})
restore()
missingLayer.modules.windows.stop()
local named = false
for _, p in ipairs(missingLayer.getProblems()) do
  if p.message:find('"yabai", which is not installed', 1, true) then named = true end
end
check("a provider not installed is a problem naming it; its moves are no rows, and run by id say so and send nothing",
      named and installedRows > 0 and rootMoves(missingLayer) == 0 and #toMissing == 0
      and alerts == alertsBefore + 1 and alertTexts[#alertTexts] == "yabai is not installed"
      and not movedByHammerspoon and #lines >= 1,
      ("problem %s, rows %d then %d, %d sent, alert %s, moved %s"):format(tostring(named), installedRows,
        rootMoves(missingLayer), #toMissing, tostring(alertTexts[#alertTexts]), tostring(movedByHammerspoon)))

-- One app slow to say what its window is called holds up every open, and the
-- console should say which app.
do
  local t = 0
  stub(hs.timer, "secondsSinceEpoch", function() return t end)
  local slowMail = fakeWindow(7, "Inbox", "Mail", "com.apple.mail")
  slowMail.title = function() t = t + 0.6; return "Inbox" end
  stub(hs.window, "orderedWindows", function() return { notes } end)
  stub(hs.application, "runningApplications", function()
    return { { kind = function() return 1 end, allWindows = function() return { notes, slowMail } end } }
  end)
  stub(hs.window, "_orderedwinids", function() return { 3, 7 } end)
  local savedSettings = cl.userSettings
  cl.userSettings = { ["windows.source"] = "all" }
  local mark = #T.logged
  M.forget()
  M.windows({ activeView = "root" })
  local said = {}
  for i = mark + 1, #T.logged do said[#said + 1] = T.logged[i] end
  M.forget()
  slowMail.title = function() return "Inbox" end
  local quietMark = #T.logged
  M.windows({ activeView = "root" })
  local quiet = #T.logged == quietMark
  M.forget()
  cl.userSettings = savedSettings
  local line = table.concat(said, " | ")
  check("reading the windows slowly says how long, how much was listing, and which app's window was slowest",
        #said == 1 and quiet
        and line:find("reading the all list took 600 ms: 0 ms listing, the slowest window 600 ms (com.apple.mail)",
                      1, true) ~= nil, line)
end
