-- CommandLayer.spoon/tests/extensions/apps.lua
-- The apps extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.apps

-- A watcher that is created and never started records nothing, which
-- is silent: the recents list simply stops changing.
local started, stopped = 0, 0
local realNew = hs.application.watcher.new
M.stop()
hs.application.watcher.new = function()
  return { start = function() started = started + 1 end,
           stop = function() stopped = stopped + 1 end }
end
pcall(M.start)
local afterStart = started
M.stop()
hs.application.watcher.new = realNew
check("the activation watcher is started by start(), and stopped by stop()",
      afterStart == 1 and stopped == 1, ("%d starts, %d stops"):format(started, stopped))

local function verbs(subject)
  local found = {}
  for _, row in ipairs(cl.itemActions(subject, cl.buildContext())) do
    if row.command then found[row.command] = row end
  end
  return found
end
local function runningApp(id, name)
  return { bundleID = function() return id end, name = function() return name end }
end
T.stub(hs.application, "runningApplications", function() return { runningApp("com.apple.mail", "Mail") } end)
local withPath = verbs({ kind = "app", name = "Mail", id = "com.apple.mail",
                         path = "/System/Applications/Mail.app" })
local withoutPath = verbs({ kind = "app", name = "Mail", id = "com.apple.mail" })
check("an app's cmd+k offers launch, quit and hide, and Reveal in Finder only with a path",
      withPath["apps.launchOrFocus"] and withPath["apps.quit"] and withPath["apps.hide"]
      and withPath["apps.revealInFinder"] and withPath["apps.quit"].args.app.name == "Mail"
      and withoutPath["apps.quit"] and not withoutPath["apps.revealInFinder"])

check("an app row is found by its other names: its running name, its bundle's file name, its bundle id",
      (function()
        local ext
        for _, e in ipairs(cl.extensions) do
          if e.name == "apps" then ext = e end
        end
        local stub = T.stub
        stub(M, "apps", function() return { { id = "com.microsoft.VSCode", name = "Code", running = true } } end)
        stub(M, "get", function()
          return { name = "Visual Studio Code", path = "/Applications/Visual Studio Code.app" }
        end)
        stub(M, "icon", function() return nil end)
        stub(M, "all", function()
          return { { name = "Mail", bundleID = "com.apple.mail", path = "/System/Applications/Mail.app" } }
        end)
        local rows = ext.items({ activeView = "root" })
        local used, mail = rows[1], rows[2]
        local function words(row) return row and table.concat(row.keywords or {}, "|") or "" end
        return used and mail and used.label == "Visual Studio Code"
               and words(used) == "Code|com.microsoft.VSCode" and words(mail) == "com.apple.mail",
               words(used) .. " / " .. words(mail)
      end)())

local quit = cl.getCommand("apps.quit")
local asked = cl.confirmText(quit, { app = { kind = "app", name = "Mail" } }, {})
local settingsBefore = cl.userSettings
cl.userSettings = { ["apps.confirmQuit"] = false }
local unasked = cl.confirmText(quit, { app = { kind = "app", name = "Mail" } }, {})
cl.userSettings = settingsBefore
check("Quit names the app, and asks first unless apps.confirmQuit is off",
      withPath["apps.quit"].label == "Quit -- Mail" and withPath["apps.hide"].label == "Hide"
      and asked == "Quit Mail?" and unasked == nil,
      tostring(withPath["apps.quit"].label) .. " / " .. tostring(asked) .. " / " .. tostring(unasked))

do
  local calls = {}
  local function fakeApp(id, name)
    return { bundleID = function() return id end, name = function() return name end,
             hide = function() calls[#calls + 1] = "hide " .. name end,
             activate = function() calls[#calls + 1] = "activate " .. name end }
  end
  local running = { ["com.apple.Terminal"] = fakeApp("com.apple.Terminal", "Terminal") }
  T.stub(hs.application, "runningApplications", function() return {} end)
  T.stub(hs.application, "applicationsForBundleID", function(id) return { running[id] } end)
  T.stub(hs.application, "launchOrFocusByBundleID", function(id)
    calls[#calls + 1] = "launch " .. id
    return true
  end)
  local terminal = { app = { id = "com.apple.Terminal" } }
  cl.executeCommand("apps.toggle", terminal, { frontmostApp = "Terminal", frontmostAppID = "com.apple.Terminal" })
  cl.executeCommand("apps.toggle", terminal, { frontmostApp = "Finder", frontmostAppID = "com.apple.finder" })
  cl.executeCommand("apps.toggle", { app = { id = "com.apple.mail", name = "Mail" } },
                    { frontmostAppID = "com.apple.finder" })
  check("Toggle hides the app that was in front as the layer opened, focuses one behind, launches one not running",
        table.concat(calls, ", ") == "hide Terminal, activate Terminal, launch com.apple.mail"
        and withPath["apps.toggle"] ~= nil,
        table.concat(calls, ", "))
end

local notRunning = verbs({ kind = "app", name = "Notes", id = "com.apple.Notes",
                           path = "/System/Applications/Notes.app" })
local palette = {}
for _, row in ipairs(cl.gather(cl.buildContext(), { menus = { "commandPalette" } })) do
  if row.command then palette[row.command] = true end
end
check("Quit, Hide and Reveal in Finder are palette rows; Launch or focus and Toggle, which picking an app does, are not",
      palette["apps.quit"] and palette["apps.hide"] and palette["apps.revealInFinder"]
      and not palette["apps.launchOrFocus"] and not palette["apps.toggle"])
local quitInput = cl.itemInputOf(cl.getCommand("apps.quit"))
local front = quitInput.current({ frontmostApp = "Mail", frontmostAppID = "com.apple.mail" })
local fromHammerspoon = quitInput.current({ frontmostApp = "Hammerspoon", frontmostAppID = "org.hammerspoon.Hammerspoon" })
check("Quit and Hide take the app you were in, asking among running apps; on one not running cmd+k offers neither",
      front ~= nil and front.id == "com.apple.mail" and fromHammerspoon == nil and quitInput.preferCurrent == true
      and notRunning["apps.launchOrFocus"] and not notRunning["apps.quit"] and not notRunning["apps.hide"]
      and notRunning["apps.revealInFinder"] ~= nil)

T.group("an app quitting")
local function app(id, name)
  return { kind = function() return 1 end, bundleID = function() return id end,
           name = function() return name end }
end
T.stub(hs.application, "runningApplications", function()
  return { app(nil, nil), app("com.apple.mail", "Mail") }
end)
local listed, all = pcall(M.apps)
local mail = false
for _, entry in ipairs(listed and all or {}) do
  if entry.id == "com.apple.mail" and entry.running then mail = true end
end
check("an app that answers neither a bundle id nor a name, as one quitting may, is left out and the rest listed",
      listed and mail, tostring(all))

T.group("which apps you used, as macOS keeps it")
do
  local names = M.parseOrder('ASN:0x0-0x13013-"Brave_Browser": ASN:0x0-0x1c31c3-"Code": ASN:0x0-0x2b02b-"Finder":')
  local callback
  T.stub(hs.spotlight, "new", function()
    local q = {}
    for _, method in ipairs({ "queryString", "callbackMessages", "searchScopes" }) do q[method] = function() return q end end
    function q.setCallback(_, fn) callback = fn; return q end
    function q.start() return q end
    function q.stop() return q end
    return q
  end)
  local completes = {}
  T.stub(cl.tools.paths, "lsappinfo", "/usr/bin/lsappinfo")
  T.stub(hs.task, "new", function(_, complete)
    completes[#completes + 1] = complete
    return { start = function(t) return t end, terminate = function() end }
  end)
  local written = 0
  T.stub(hs.settings, "set", function() written = written + 1 end)
  M.stop()
  M.start()
  if completes[1] then completes[1](0, 'ASN:0x0-1-"Code": ASN:0x0-2-"Brave_Browser": ASN:0x0-3-"Hammerspoon":', "") end
  if callback then
    callback(nil, nil, { kMDQueryUpdateAddedItems = {
      { kMDItemPath = "/Applications/Old.app", kMDItemDisplayName = "Old", kMDItemCFBundleIdentifier = "x.old",
        kMDItemLastUsedDate = 100 },
      { kMDItemPath = "/Applications/Newer.app", kMDItemDisplayName = "Newer", kMDItemCFBundleIdentifier = "x.newer",
        kMDItemLastUsedDate = 200 },
      { kMDItemPath = "/Applications/Never.app", kMDItemDisplayName = "Never", kMDItemCFBundleIdentifier = "x.never" },
      { kMDItemPath = "/Applications/Brave Browser.app", kMDItemDisplayName = "Brave Browser",
        kMDItemCFBundleIdentifier = "com.brave.Browser", kMDItemLastUsedDate = 300 },
    } })
  end
  local function app(id, name)
    return { kind = function() return 1 end, bundleID = function() return id end, name = function() return name end }
  end
  T.stub(hs.application, "runningApplications", function()
    return { app("com.brave.Browser", "Brave Browser"), app("org.hammerspoon.Hammerspoon", "Hammerspoon"),
             app("com.microsoft.VSCode", "Code") }
  end)
  local order = {}
  for _, entry in ipairs(M.apps()) do order[#order + 1] = entry.name .. (entry.running and "*" or "") end
  M.stop()
  check("an app list reads as lsappinfo writes it",
        table.concat(names, "|") == "Brave Browser|Code|Finder", table.concat(names, "|"))
  check("the running apps come front to back as macOS keeps them, then those quit, last used first by "
          .. "Spotlight; an ignored app is left out, and nothing is written to hs.settings",
        table.concat(order, " ") == "Code* Brave Browser* Newer Old" and written == 0,
        table.concat(order, " ") .. " / " .. written .. " writes")
end
