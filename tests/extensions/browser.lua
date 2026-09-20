-- CommandLayer.spoon/tests/extensions/browser.lua
-- The browser extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.browser

do
  local browser = M
  -- Never the real session files: a browser on the machine running the
  -- harness would change what every check sees, and put its tabs in the
  -- output. A check that wants a file gives its own folder.
  local realSessionDir = browser.sessionDir
  browser.sessionDir = function() return nil end
  check("knows Safari", browser.isBrowser("Safari"))
  check("knows the Chromium family", browser.isBrowser("Brave Browser"))
  check("does not claim Finder", browser.isBrowser("Finder") == false)
  check("does not claim nil", browser.isBrowser(nil) == false)
  check("no tab when the app is not a browser",
        browser.frontTab("Finder") == nil)

  -- The freeze this guards against: a browser asked on the main thread.
  local saved = { new = hs.task.new, doAfter = hs.timer.doAfter,
                  applescript = hs.osascript and hs.osascript.applescript,
                  onAnswer = browser.onAnswer }
  local spawned, finish, killed, blocking = 0, nil, false, false
  hs.task.new = function(_, callback)
    spawned = spawned + 1
    finish = callback
    return { start = function(t) return t end,
             terminate = function() killed = true; callback(15, "") end }
  end
  local fire
  hs.timer.doAfter = function(_, fn) fire = fn; return { stop = function() fire = nil end } end
  hs.osascript = hs.osascript or {}
  hs.osascript.applescript = function() blocking = true; return false end
  browser.onAnswer = nil
  browser.forget()

  local first = browser.frontTab("Brave Browser")
  check("a browser in front is asked without blocking",
        first == nil and spawned == 1 and not blocking)

  browser.tabs("Brave Browser")
  check("and asked once while an answer is pending", spawned == 1,
        tostring(spawned) .. " asks")

  finish(0, "https://a.example\tA\nhttps://a.example\tA\nhttps://b.example\tB\n")
  local front, tabs = browser.frontTab("Brave Browser"), browser.tabs("Brave Browser")
  local browserExt
  for _, ext in ipairs(cl.extensions) do
    if ext.name == "browser" then browserExt = ext end
  end
  local captured = { frontmostApp = "Brave Browser" }
  if browserExt and browserExt.capture then browserExt.capture(captured) end
  check("the front tab is captured as url and pageTitle, for when clauses",
        captured.url == "https://a.example" and captured.pageTitle == "A",
        tostring(captured.url))

  check("the answer gives the front tab and every tab",
        front and front.url == "https://a.example" and #tabs == 2
        and tabs[2].title == "B")

  browser.forget()
  browser.frontTab("Brave Browser")
  if fire then fire() end
  check("a browser that never answers is given up on", killed == true)

  hs.task.new, hs.timer.doAfter = saved.new, saved.doAfter
  hs.osascript.applescript = saved.applescript
  browser.onAnswer = saved.onAnswer
  browser.forget()

  -- Full screen rather than play / pause: playing is the media keys' job,
  -- which reach the player without pressing into the page.
  local full = cl.getCommand("browser.site.youtube.fullScreen")
  local shippedProblems = 0
  for _, p in ipairs(cl.problems) do
    if p.message:find("sites.jsonc", 1, true) then shippedProblems = shippedProblems + 1 end
  end
  check("YouTube's shortcuts, from the shipped sites.jsonc, are commands for while a video is in front",
        full ~= nil and full.command == "browser.keys" and full.args.keys == "f"
        and cl.getCommand("browser.site.youtube.nextVideo").args.keys == "shift+n"
        and cl.getCommand("browser.site.youtube.playPause") == nil
        and shippedProblems == 0
        and cl.when(full.menus.context.when, { url = "https://www.youtube.com/watch?v=x" })
        and not cl.when(full.menus.context.when, { url = "https://github.com/" }),
        full and full.menus and full.menus.context and full.menus.context.when)

  local function commandIds(ctx)
    local ids = {}
    for _, row in ipairs(cl.gather(cl.argContext(ctx, { activeView = "context" }), { menus = { "context" } })) do
      if row.command then ids[row.command] = true end
    end
    return ids
  end
  local onVideo = commandIds({ frontmostApp = "Brave Browser",
                               url = "https://www.youtube.com/watch?v=x" })
  local elsewhere = commandIds({ frontmostApp = "Brave Browser", url = "https://github.com/" })
  check("and they are rows only while that page is in front",
        onVideo["browser.site.youtube.fullScreen"] == true
        and elsewhere["browser.site.youtube.fullScreen"] == nil)

  -- What answers a video instead: the media keys, which reach whatever holds
  -- Now Playing -- from the root and the palette, and deliberately not from
  -- the context picker, where on every page they were noise.
  local inPalette = {}
  for _, row in ipairs(cl.gather(cl.argContext({}, { activeView = "palette" }),
                                 { menus = { "commandPalette" } })) do
    if row.command then inPalette[row.command] = true end
  end
  check("the media keys are in the palette, and in no picker about the page in front",
        inPalette["media.playPause"] == true and onVideo["media.playPause"] == nil,
        tostring(inPalette["media.playPause"]) .. " / " .. tostring(onVideo["media.playPause"]))

  local strokes, activated, gets = {}, 0, 0
  local restore = { get = hs.application.get, doAfter = hs.timer.doAfter,
                    stroke = hs.eventtap.keyStroke, new = hs.task.new,
                    byBundle = hs.application.applicationsForBundleID,
                    running = hs.application.runningApplications }
  local function fakeApp(name)
    return { name = function() return name end,
             activate = function() activated = activated + 1 end }
  end
  hs.application.get = function() gets = gets + 1 end
  hs.application.applicationsForBundleID = function(bundle)
    return bundle == "com.brave.Browser" and { fakeApp("Brave Browser") } or {}
  end
  hs.application.runningApplications = function()
    return { fakeApp("Finder"), fakeApp("Safari") }
  end
  hs.timer.doAfter = function(_, fn) fn(); return { stop = function() end } end
  hs.eventtap.keyStroke = function(mods, key)
    strokes[#strokes + 1] = table.concat(mods, "+") .. "|" .. key
  end
  cl.executeCommand("browser.keys", { keys = "shift+n" }, { frontmostApp = "Brave Browser" })
  cl.executeCommand("browser.keys", { keys = "k" }, { frontmostApp = "Safari" })
  check("a site's keys go to the browser in front", activated == 2 and strokes[1] == "shift|n"
        and strokes[2] == "|k", tostring(strokes[1]) .. " " .. tostring(strokes[2]))
  check("and the browser is found by bundle id or among running apps, never by hs.application.get",
        gets == 0, tostring(gets) .. " lookups")

  do
    local alerted, lookups = {}, {}
    local realAlert, realNew = hs.alert.show, hs.task.new
    hs.alert.show = function(message) alerted[#alerted + 1] = message end
    hs.task.new = function(program, done)
      lookups[#lookups + 1] = { program = program, done = done }
      return { start = function(t) return t end, terminate = function() end }
    end
    local pressedBeforeSecure, activatedBeforeSecure = #strokes, activated
    cl.executeCommand("browser.keys", { keys = "k" }, { frontmostApp = "Brave Browser", secureInput = true })
    for _, lookup in ipairs(lookups) do lookup.done(0, "") end
    hs.alert.show, hs.task.new = realAlert, realNew
    check("a site's keys are not pressed while Secure Input is on, and Secure Input says so",
          #strokes == pressedBeforeSecure and activated == activatedBeforeSecure
          and #alerted == 1 and alerted[1]:find("k was not pressed: Secure Input is on", 1, true) ~= nil,
          tostring(alerted[1]) .. ", " .. tostring(#strokes - pressedBeforeSecure) .. " pressed")
  end

  local pendingStop, pressedBefore = 0, #strokes
  hs.timer.doAfter = function()
    return { stop = function() pendingStop = pendingStop + 1 end }
  end
  cl.executeCommand("browser.keys", { keys = "k" }, { frontmostApp = "Brave Browser" })
  browser.stop()
  cl.stopRunning("browser")
  check("a site's keystroke waits on a timer, stopped with the extension",
        #strokes == pressedBefore and pendingStop == 1, tostring(pendingStop) .. " stopped")
  hs.application.applicationsForBundleID = restore.byBundle
  hs.application.runningApplications = restore.running

  local scripts = {}
  hs.task.new = function(_, _, _, args)
    scripts[#scripts + 1] = args[2]
    return { start = function(t) return t end, terminate = function() end }
  end
  cl.executeCommand("browser.js", { js = 'alert("hi")' }, { frontmostApp = "Brave Browser" })
  cl.executeCommand("browser.js", { js = "1" }, { frontmostApp = "Safari" })
  check("JavaScript runs in the front tab, quoted for AppleScript",
        scripts[1] ~= nil
        and scripts[1]:find('execute active tab of front window javascript "alert(\\"hi\\")"', 1, true) ~= nil
        and scripts[2] ~= nil and scripts[2]:find("do JavaScript", 1, true) ~= nil,
        tostring(scripts[1]))

  hs.application.get, hs.timer.doAfter = restore.get, restore.doAfter
  hs.eventtap.keyStroke, hs.task.new = restore.stroke, restore.new

  -- Inside a tell block `tab` is the browser's tab class, not the
  -- character, and a script using it fails -- so no tab, and no URL, was
  -- ever read.
  local asked, finishAsk
  local restoreAsk = { new = hs.task.new, doAfter = hs.timer.doAfter,
                       onAnswer = browser.onAnswer, refresh = cl.refresh }
  hs.task.new = function(_, callback, _, args)
    asked, finishAsk = args and args[2], callback
    return { start = function(t) return t end, terminate = function() end }
  end
  hs.timer.doAfter = function() return { stop = function() end } end
  browser.onAnswer = restoreAsk.onAnswer
  cl.refresh = function() end
  browser.forget()

  local ctx = { frontmostApp = "Brave Browser" }
  local browserExt2
  for _, ext in ipairs(cl.extensions) do
    if ext.name == "browser" then browserExt2 = ext end
  end
  browserExt2.capture(ctx)
  check("the tab script builds its separators outside the tell block",
        asked ~= nil and asked:find("character id 9", 1, true) ~= nil
        and asked:find("& tab &", 1, true) == nil)

  local before = ctx.url
  if finishAsk then finishAsk(0, "https://late.example\tLate\nhttps://late.example\tLate\n") end
  check("an answer landing after the picker opened fills in its url",
        before == nil and ctx.url == "https://late.example" and ctx.pageTitle == "Late",
        tostring(ctx.url))

  local alerts, realAlert = {}, hs.alert.show
  hs.alert.show = function(message) alerts[#alerts + 1] = message end
  browser.forget()
  browser.frontTab("Brave Browser")
  if finishAsk then
    finishAsk(1, "", "execution error: Not authorized to send Apple events to Brave Browser. (-1743)")
  end
  browser.frontTab("Brave Browser")
  if finishAsk then
    finishAsk(1, "", "execution error: Not authorized to send Apple events to Brave Browser. (-1743)")
  end
  hs.alert.show = realAlert
  check("a browser refusing Apple events says where to allow it, once",
        #alerts == 1 and alerts[1]:find("Automation", 1, true) ~= nil, tostring(#alerts))

  hs.task.new, hs.timer.doAfter = restoreAsk.new, restoreAsk.doAfter
  browser.onAnswer, cl.refresh = restoreAsk.onAnswer, restoreAsk.refresh
  browser.pendingCtx = nil
  browser.forget()

  -- Picking an open tab once opened its URL in a new tab beside it.
  local ran, opened = {}, {}
  local openCommand = cl.getCommand("system.open")
  local restoreTab = { new = hs.task.new, doAfter = hs.timer.doAfter,
                       onAnswer = browser.onAnswer, refresh = cl.refresh,
                       open = openCommand.run }
  hs.task.new = function(_, callback, _, args)
    ran[#ran + 1] = { script = args and args[2], done = callback }
    return { start = function(t) return t end, terminate = function() end }
  end
  hs.timer.doAfter = function() return { stop = function() end } end
  browser.onAnswer, cl.refresh = nil, function() end
  openCommand.run = function(args) opened[#opened + 1] = args.target end
  browser.forget()

  browser.frontTab("Brave Browser")
  ran[#ran].done(0, "https://a.example\tA\nhttps://a.example\tA\nhttps://b.example\tB\n")
  local tabRow
  for _, row in ipairs(cl.gather({ frontmostApp = "Brave Browser" }, { menus = { "root" } })) do
    if row.description == "Tab -- https://b.example" then tabRow = row end
  end
  check("an open tab's row goes to that tab rather than opening its URL again",
        tabRow and tabRow.command == "browser.tab" and tabRow.args.url == "https://b.example"
        and tabRow.args.app == "Brave Browser", tabRow and tabRow.command)
  check("tabs rank below recent projects and apps in the root",
        tabRow and tabRow.rank < 0.57, tostring(tabRow and tabRow.rank))
  check("a tab is found by its URL: the URL is its row's keywords",
        tabRow and type(tabRow.keywords) == "table" and tabRow.keywords[1] == "https://b.example"
        and #tabRow.keywords == 1)

  local before = #ran
  cl.executeCommand("browser.tab", { url = 'https://b.example/?q="x"', app = "Brave Browser" }, {})
  local chromium = ran[before + 1]
  cl.executeCommand("browser.tab", { url = "https://b.example", app = "Safari" }, {})
  local safari = ran[before + 2]
  check("the tab is found by its URL, quoted for AppleScript, each browser its own way",
        chromium and chromium.script:find('set target to "https://b.example/?q=\\"x\\""', 1, true)
        and chromium.script:find("set active tab index of w to i", 1, true)
        and safari and safari.script:find("set current tab of w to tab i of w", 1, true)
        and #opened == 0, chromium and chromium.script)

  chromium.done(0, "found\n")
  local afterFound = #opened
  safari.done(0, "missing\n")
  check("a tab closed since the list was made is opened instead",
        afterFound == 0 and opened[1] == "https://b.example", tostring(opened[1]))

  local function verbTexts(subject)
    local out = {}
    for _, v in ipairs(cl.itemActions(subject, {})) do out[#out + 1] = v.label end
    return table.concat(out, ", ")
  end
  local onTab = verbTexts({ kind = "url", value = "https://b.example", tabIn = "Brave Browser" })
  local onLink = verbTexts({ kind = "url", value = "https://b.example" })
  check("cmd+k on a tab offers going to it first; on a link, opening it",
        onTab:find("^Go to tab, Open in new tab") ~= nil
        and onLink:find("Go to tab", 1, true) == nil
        and onLink:find("Open in browser", 1, true) ~= nil, onTab .. " / " .. onLink)

  local function urls(list)
    local out = {}
    for _, t in ipairs(list) do out[#out + 1] = t.url end
    return table.concat(out, " ")
  end

  browser.forget()
  browser.ask("Brave Browser")
  ran[#ran].done(0, "https://b.example\tB\nhttps://a.example\tA\nhttps://b.example\tB\nhttps://c.example\tC\n")
  browser.ask("Brave Browser")
  ran[#ran].done(0, "https://c.example\tC\nhttps://a.example\tA\nhttps://b.example\tB\nhttps://c.example\tC\n")
  local tabs = browser.tabs("Brave Browser")
  cl.executeCommand("browser.tab", { url = "https://c.example", app = "Brave Browser" }, {})
  ran[#ran].done(0, "found\n")
  check("without a session file, tabs keep the browser's order, whichever was in front or gone to",
        urls(browser.orderTabs(tabs, "recent")) == "https://a.example https://b.example https://c.example"
        and urls(browser.orderTabs(tabs, "browser")) == "https://a.example https://b.example https://c.example",
        urls(browser.orderTabs(tabs, "recent")))

  local stamped = { { url = "https://x.example" }, { url = "https://y.example", lastActive = 10 },
                    { url = "https://z.example", lastActive = 20 }, { url = "https://w.example" } }
  check("recent orders by the last-active time alone, the tabs without one after, in order",
        urls(browser.orderTabs(stamped, "recent"))
          == "https://z.example https://y.example https://x.example https://w.example"
        and urls(browser.orderTabs(stamped, "browser"))
          == "https://x.example https://y.example https://z.example https://w.example",
        urls(browser.orderTabs(stamped, "recent")))

  local realGet, lookups = hs.application.get, 0
  hs.application.get = function() lookups = lookups + 1 end
  browser.ask("Safari")
  ran[#ran].done(0, "https://s.example\tS\nhttps://s.example\tS\n")
  local listed = table.concat(browser.runningBrowsers("Finder"), ", ")
  check("the browsers listed are those that answered, found without looking up any app",
        listed == "Brave Browser, Safari" and lookups == 0,
        listed .. " / " .. tostring(lookups) .. " lookups")

  local function browserRows(menu, ctx)
    local out = {}
    local asked = cl.argContext(ctx or { frontmostApp = "Finder" }, { activeView = menu })
    for _, row in ipairs(cl.gather(asked, { menus = { menu } })) do
      if row.source == "browser" then out[#out + 1] = row end
    end
    return out
  end
  local function describe(rows)
    local out = {}
    for _, row in ipairs(rows) do
      local c = row.args or {}
      local id = row.subject and row.subject.kind == "command" and row.subject.id
      out[#out + 1] = tostring(c.app) .. ":" .. tostring(id or c.url or c.target)
    end
    return table.concat(out, " ")
  end

  local recent = describe(browserRows("recent"))
  check("recent lists the tabs of every running browser",
        recent == "Brave Browser:https://a.example Brave Browser:https://b.example "
                  .. "Brave Browser:https://c.example Safari:https://s.example", recent)

  local savedLimit = cl.userSettings
  cl.userSettings = { ["browser.recentTabs"] = 2 }
  local limited = #browserRows("recent")
  cl.userSettings = savedLimit
  check("and only as many as recentTabs", limited == 2, tostring(limited))

  local savedSettings = cl.userSettings
  cl.userSettings = { ["browser.tabOrder"] = "browser" }
  local inBrowserOrder = describe(browserRows("recent"))
  cl.userSettings = savedSettings
  check("with tabOrder set to browser, tabs keep each browser's own order",
        inBrowserOrder == "Brave Browser:https://a.example Brave Browser:https://b.example "
                          .. "Brave Browser:https://c.example Safari:https://s.example", inBrowserOrder)

  local realBookmarks = browser.bookmarks
  browser.bookmarks = function() return { { url = "https://kept.example", title = "Kept" } } end
  local inContext = describe(browserRows("context", { frontmostApp = "Brave Browser" }))
  local elsewhere = #browserRows("context", { frontmostApp = "Claude" })
  check("with no browser in front, the context picker has no browser rows at all",
        elsewhere == 0, tostring(elsewhere) .. " rows")
  local inRoot = describe(browserRows("root", { frontmostApp = "Brave Browser" }))
  browser.bookmarks = realBookmarks
  local tabAt = inContext:find("Brave Browser:https://a.example", 1, true)
  local keptAt = inContext:find("kept.example", 1, true)
  check("the context picker lists the front browser's tabs first, then its bookmarks",
        tabAt ~= nil and keptAt ~= nil and tabAt < keptAt
        and inRoot:find("kept.example", 1, true) ~= nil, inContext)

  local fromElsewhere, tabsElsewhere = browserRows("root"), 0
  for _, row in ipairs(fromElsewhere) do
    if row.command == "browser.tab" then tabsElsewhere = tabsElsewhere + 1 end
  end
  check("only recent lists the tabs of browsers not in front: the root, from another app, has none",
        tabsElsewhere == 0 and #browserRows("recent") > 0, describe(fromElsewhere))

  local function tabsIn(rows)
    local n = 0
    for _, row in ipairs(rows) do
      if row.command == "browser.tab" then n = n + 1 end
    end
    return n
  end
  local goTo = cl.itemInputOf(cl.getCommand("browser.goToTab"))
  local askedTabs = tabsIn(cl.rowsForItemInput(goTo.picker, { frontmostApp = "Claude", activeView = "commandPalette" }))
  check("Go to tab asked from another app lists every running browser's tabs, as recent does",
        askedTabs > 0 and askedTabs == tabsIn(browserRows("recent")),
        ("%d asked, %d in recent"):format(askedTabs, tabsIn(browserRows("recent"))))

  local copy = cl.itemInputOf(cl.getCommand("browser.copyURL"))
  local page = copy.current({ url = "https://p.example", pageTitle = "P", frontmostApp = "Brave Browser" })
  local palette = {}
  for _, row in ipairs(cl.gather({ frontmostApp = "Finder" }, { menus = { "commandPalette" } })) do
    if row.command then palette[row.command] = true end
  end
  check("Go to tab, Open in new tab and Copy URL are palette rows, Open in browser only cmd+k's; "
        .. "Copy URL takes the page in front",
        palette["browser.goToTab"] and palette["browser.openInNewTab"] and palette["browser.copyURL"]
        and not palette["browser.openInBrowser"]
        and page ~= nil and page.value == "https://p.example" and copy.current({ frontmostApp = "Finder" }) == nil)

  browser.forget()
  local asksBeforeListing = #ran
  local unasked = #browserRows("recent")
  check("a browser not in front is only read from its last answer, never asked from a picker",
        #ran == asksBeforeListing and unasked == 0,
        tostring(#ran - asksBeforeListing) .. " asks, " .. tostring(unasked) .. " rows")

  local redraws = 0
  browser.onAnswer = function() redraws = redraws + 1 end
  local same = "https://a.example\tA\nhttps://a.example\tA\n"
  for _, out in ipairs({ same, same, same .. "https://b.example\tB\n" }) do
    browser.ask("Brave Browser")
    ran[#ran].done(0, out)
  end
  browser.onAnswer = nil
  check("an open picker is redrawn when an answer changed, not whenever one lands",
        redraws == 2, tostring(redraws) .. " redraws")

  hs.application.get = realGet

  local watching
  local savedWatcher, savedEvery = hs.application.watcher, hs.timer.doEvery
  hs.application.watcher = {
    new = function(fn) watching = fn; return { start = function() end, stop = function() end } end,
    activated = 1, terminated = 2, deactivated = 3,
  }
  hs.timer.doEvery = function() return { stop = function() end } end
  browser.start()
  local asksBefore = #ran
  browser.forget()
  watching("Brave Browser", 3)
  check("leaving a browser asks it which tab was in front", #ran == asksBefore + 1,
        tostring(#ran - asksBefore) .. " asks")

  browser.ask("Safari")
  ran[#ran].done(0, "https://s.example\tS\nhttps://s.example\tS\n")
  local beforeQuit = #browser.tabs("Safari", true)
  watching("Safari", 2)
  check("a browser that quits takes its tabs with it",
        beforeQuit == 1 and #browser.tabs("Safari", true) == 0, tostring(beforeQuit))
  browser.stop()
  cl.stopRunning("browser")
  hs.application.watcher, hs.timer.doEvery = savedWatcher, savedEvery

  hs.task.new, hs.timer.doAfter = restoreTab.new, restoreTab.doAfter
  browser.onAnswer, cl.refresh = restoreTab.onAnswer, restoreTab.refresh
  openCommand.run = restoreTab.open
  browser.forget()

  -- A session file written the way Chromium writes one.
  local session = browser.session
  local function record(id, body) return string.pack("<I2", #body + 1) .. string.char(id) .. body end
  local function padded(s) return s .. string.rep("\0", (4 - #s % 4) % 4) end
  local function utf16le(s)
    local out = {}
    for _, code in utf8.codes(s) do out[#out + 1] = string.pack("<I2", code) end
    return table.concat(out)
  end
  local function navigation(tab, index, url, title)
    local body = string.pack("<i4i4i4", tab, index, #url) .. padded(url)
                 .. string.pack("<i4", utf8.len(title)) .. padded(utf16le(title))
    return record(6, string.pack("<I4", #body) .. body)
  end
  local function chromiumTime(unix) return math.floor((unix + session.EPOCH_OFFSET) * 1e6) end
  local now = 1800000000
  local file = "SNSS" .. string.pack("<i4", 3)
    .. record(0, string.pack("<i4i4", 1, 11)) .. record(2, string.pack("<i4i4", 11, 0))
    .. navigation(11, 0, "https://old.example", "Old")
    .. navigation(11, 1, "https://first.example", "Café")
    -- Gone back from here: the selected page is not the last one.
    .. navigation(11, 2, "https://forward.example", "Forward")
    .. record(7, string.pack("<i4i4", 11, 1))
    .. record(0, string.pack("<i4i4", 1, 12)) .. record(2, string.pack("<i4i4", 12, 1))
    .. navigation(12, 0, "https://second.example", "Second")
    .. record(0, string.pack("<i4i4", 1, 13)) .. record(2, string.pack("<i4i4", 13, 2))
    .. navigation(13, 0, "https://closed.example", "Closed")
    .. record(16, string.pack("<i4i4i8", 13, 0, 0))
    .. record(21, string.pack("<i4i4i8", 11, 0, chromiumTime(now - 600)))
    .. record(21, string.pack("<i4i4i8", 12, 0, chromiumTime(now - 5)))
    .. record(99, "a record this does not know")
    .. record(20, string.pack("<i4", 1)) .. record(8, string.pack("<i4i4", 1, 1))

  local parsed = session.parse(file)
  local t = parsed and parsed.tabs or {}
  check("a session file gives the open tabs, each at its current page, in window order",
        #t == 2 and t[1].url == "https://first.example" and t[1].title == "Café"
        and t[2].url == "https://second.example",
        tostring(#t) .. " " .. tostring(t[1] and t[1].url) .. " " .. tostring(t[1] and t[1].title))
  check("and when each was last active, a closed tab left out, the front tab known",
        t[1] and math.abs((t[1].lastActive or 0) - (now - 600)) < 0.001
        and t[2] and math.abs((t[2].lastActive or 0) - (now - 5)) < 0.001
        and parsed.front == t[2] and session.parse("not a session") == nil,
        tostring(t[1] and t[1].lastActive))

  local records = file:sub(9)
  local fromVersion1 = session.parse("SNSS" .. string.pack("<i4", 1) .. records)
  local fromVersion4, unknownVersion = session.parse("SNSS" .. string.pack("<i4", 4) .. records)
  local fromVersion9, unknownNewer = session.parse("SNSS" .. string.pack("<i4", 9) .. records)
  check("a session file's version is read from its header: 1 and 3 are read, another is not guessed at",
        fromVersion1 ~= nil and #fromVersion1.tabs == 2 and session.version(file) == 3
        and fromVersion4 == nil and unknownVersion == 4 and fromVersion9 == nil and unknownNewer == 9
        and session.version("SNSS") == nil,
        ("%s tabs from 1, %s from 4 (%s)"):format(fromVersion1 and #fromVersion1.tabs,
          fromVersion4 and #fromVersion4.tabs, tostring(unknownVersion)))

  do
    local unknownDir = os.tmpname() .. "-unknown-sessions"
    os.execute(("mkdir -p %q"):format(unknownDir))
    local out = assert(io.open(unknownDir .. "/Session_1", "wb"))
    out:write("SNSS" .. string.pack("<i4", 4) .. records)
    out:close()
    local asks = 0
    local keep = { new = hs.task.new, running = hs.application.applicationsForBundleID,
                   dir = browser.sessionDir }
    hs.task.new = function()
      asks = asks + 1
      return { start = function(x) return x end, terminate = function() end }
    end
    hs.application.applicationsForBundleID = function(bundle)
      return bundle == "com.brave.Browser" and { {} } or {}
    end
    browser.sessionDir = function(app) return app == "Brave Browser" and unknownDir or nil end
    browser.forget()
    browser.readSessions()
    browser.readSessions()
    local said = {}
    for _, p in ipairs(cl.problems) do
      if p.file == "extension browser" and p.message:find("session file is format version", 1, true) then
        said[#said + 1] = p.message
      end
    end
    local fromFile = browser.sessionTabs("Brave Browser")
    browser.tabs("Brave Browser")
    hs.task.new, hs.application.applicationsForBundleID = keep.new, keep.running
    browser.sessionDir = keep.dir
    browser.forget()
    os.execute(("rm -rf %q"):format(unknownDir))
    check("a session file of a version not known is a problem once, naming the browser and the version, "
          .. "and the browser is asked instead",
          #said == 1 and said[1]:find("Brave Browser's session file is format version 4", 1, true) ~= nil
          and fromFile == nil and asks == 1,
          ("%d said (%s), %d asks"):format(#said, tostring(said[1]), asks))
  end

  local dir = os.tmpname() .. "-sessions"
  os.execute(("mkdir -p %q"):format(dir))
  local handle = io.open(dir .. "/Session_1", "wb")
  handle:write(file)
  handle:close()
  local asked = 0
  local saved = { new = hs.task.new, running = hs.application.applicationsForBundleID,
                  dir = browser.sessionDir }
  hs.task.new = function()
    asked = asked + 1
    return { start = function(x) return x end, terminate = function() end }
  end
  hs.application.applicationsForBundleID = function(bundle)
    return bundle == "com.brave.Browser" and { {} } or {}
  end
  browser.sessionDir = function() return dir end
  browser.forget()
  browser.readSessions()

  local listed = browser.tabs("Brave Browser")
  local readOnce, readAgain = session.read(dir), session.read(dir)
  check("an unchanged session file is read once, not on every build",
        readOnce ~= nil and rawequal(readOnce, readAgain))
  local ordered = browser.orderTabs(listed, "recent")
  local running = table.concat(browser.runningBrowsers("Finder"), ", ")
  local askedBefore = asked
  -- In the browser, whose front tab in the file is second.example.
  local inBrave = browserRows("context", { frontmostApp = "Brave Browser" })
  local firstInBrave = inBrave[1] and inBrave[1].args.url
  local lastInBrave = inBrave[2] and inBrave[2].args.url
  hs.application.applicationsForBundleID = function() return {} end
  local afterQuit = browser.tabs("Brave Browser", true)

  hs.task.new, hs.application.applicationsForBundleID = saved.new, saved.running
  browser.sessionDir = saved.dir
  browser.forget()
  os.execute(("rm -rf %q"):format(dir))
  check("a running Chromium browser's tabs come from its session file, without asking it",
        #listed == 2 and askedBefore == 0 and running == "Brave Browser" and #afterQuit == 0,
        ("%d tabs, %d asks, running %s, after quit %d"):format(#listed, askedBefore, running, #afterQuit))
  check("in the browser, the tab you are on goes last, so the one before it is first",
        firstInBrave == "https://first.example" and lastInBrave == "https://second.example",
        tostring(firstInBrave) .. " / " .. tostring(lastInBrave))
  check("and recent puts the tab last active first, by the file's times",
        ordered[1] and ordered[1].url == "https://second.example",
        tostring(ordered[1] and ordered[1].url))

  -- Chromium writes the file every few seconds while you browse: read when
  -- the folder changes, never while a picker builds.
  do
    local watchedDir = os.tmpname() .. "-watched-sessions"
    os.execute(("mkdir -p %q"):format(watchedDir))
    local out = assert(io.open(watchedDir .. "/Session_1", "wb"))
    out:write(file)
    out:close()
    local parses, listings, mtime, changed, watchedPaths, timers = 0, 0, 1, nil, {}, {}
    local keep = { parse = session.parse, dir = hs.fs.dir, attributes = hs.fs.attributes,
                   running = hs.application.applicationsForBundleID, sessionDir = browser.sessionDir,
                   pathwatcher = hs.pathwatcher, doAfter = hs.timer.doAfter, doEvery = hs.timer.doEvery,
                   watcher = hs.application.watcher, new = hs.task.new }
    session.parse = function(data) parses = parses + 1; return keep.parse(data) end
    hs.fs.dir = function(path) listings = listings + 1; return keep.dir(path) end
    hs.fs.attributes = function(path, key)
      if path:find(watchedDir, 1, true) then
        return key and mtime or { mode = "file", modification = mtime }
      end
      return keep.attributes(path, key)
    end
    hs.application.applicationsForBundleID = function(bundle)
      return bundle == "com.brave.Browser" and { {} } or {}
    end
    browser.sessionDir = function(app) return app == "Brave Browser" and watchedDir or nil end
    hs.pathwatcher = { new = function(path, fn)
      watchedPaths[#watchedPaths + 1], changed = path, fn
      return { start = function(w) return w end, stop = function() end }
    end }
    hs.timer.doAfter = function(seconds, fn)
      timers[#timers + 1] = { seconds = seconds, fn = fn }
      return { stop = function() end }
    end
    hs.timer.doEvery = function() return { stop = function() end } end
    hs.application.watcher = { new = function() return { start = function() end, stop = function() end } end,
                               activated = 1, terminated = 2, deactivated = 3 }
    hs.task.new = function() return { start = function(t) return t end, terminate = function() end } end
    browser.forget()

    browser.start()
    local parsedAtStart, listedAtStart = parses, listings
    local shown = 0
    for _ = 1, 3 do shown = shown + #browserRows("recent") end
    check("a picker lists the tabs kept from the session file: three builds, no folder listed, nothing parsed",
          parsedAtStart == 1 and #watchedPaths == 1 and watchedPaths[1] == watchedDir
          and shown == 6 and parses == parsedAtStart and listings == listedAtStart,
          ("%d parsed at start, %d rows, %d parses and %d listings after"):format(
            parsedAtStart, shown, parses - parsedAtStart, listings - listedAtStart))

    local function settle()
      local fired = 0
      for i = #timers, 1, -1 do
        if timers[i].seconds == browser.sessionDelay then
          local fn = table.remove(timers, i).fn
          fired = fired + 1
          fn()
        end
      end
      return fired
    end
    mtime = 2
    changed({ watchedDir .. "/Session_1" })
    changed({ watchedDir .. "/Session_1" })
    local beforeSettling = parses
    local settled = settle()
    local afterChange = parses
    changed({ watchedDir .. "/Session_1" })
    settle()
    check("a change to the folder reads it once the burst settles, and only a file written since is parsed",
          beforeSettling == parsedAtStart and settled == 1 and afterChange == parsedAtStart + 1
          and parses == afterChange,
          ("%d before settling, %d timers, %d then %d parses"):format(beforeSettling, settled, afterChange, parses))

    browser.stop()
    cl.stopRunning("browser")
    session.parse, hs.fs.dir, hs.fs.attributes = keep.parse, keep.dir, keep.attributes
    hs.application.applicationsForBundleID, browser.sessionDir = keep.running, keep.sessionDir
    hs.pathwatcher, hs.timer.doAfter, hs.timer.doEvery = keep.pathwatcher, keep.doAfter, keep.doEvery
    hs.application.watcher, hs.task.new = keep.watcher, keep.new
    browser.forget()
    os.execute(("rm -rf %q"):format(watchedDir))
  end

  -- History, read in processes of their own. No real profile is touched:
  -- the profiles are made up, found by a stubbed hs.fs.attributes, and the
  -- copy and the query are stubbed tasks answering with made-up rows.
  local savedHistory = { new = hs.task.new, execute = hs.execute, decode = hs.json.decode,
                         attributes = hs.fs.attributes, doAfter = hs.timer.doAfter,
                         doEvery = hs.timer.doEvery, watcher = hs.application.watcher,
                         profiles = browser.profiles }
  local tasks, executes, watchdogs, terminated = {}, 0, {}, 0
  hs.task.new = function(program, callback, _, args)
    local task = { program = program, callback = callback, args = args }
    task.start = function(t) return t end
    task.terminate = function() terminated = terminated + 1 end
    tasks[#tasks + 1] = task
    return task
  end
  hs.execute = function() executes = executes + 1; return "" end
  local canned = {
    ['["one"]'] = { { url = "https://a.example", title = "A" }, { url = "https://b.example", title = "B" } },
    ['["two"]'] = { { url = "https://b.example", title = "B again" }, { url = "https://c.example", title = "C" } },
  }
  hs.json.decode = function(text) return canned[text] end
  hs.fs.attributes = function(path)
    return path:find("CommandLayerTest/Missing", 1, true) == nil
           and path:find("CommandLayerTest/", 1, true) and { mode = "file" } or nil
  end
  hs.timer.doAfter = function(_, fn)
    local timer = { fn = fn, stopped = false }
    timer.stop = function() timer.stopped = true end
    watchdogs[#watchdogs + 1] = timer
    return timer
  end
  browser.profiles = { { name = "One", dir = "CommandLayerTest/One" },
                       { name = "Missing", dir = "CommandLayerTest/Missing" },
                       { name = "Two", dir = "CommandLayerTest/Two" } }

  local function exists(path)
    local h = io.open(path, "r")
    if h then h:close() end
    return h ~= nil
  end
  local function historyUrls()
    local out = {}
    for _, page in ipairs(browser.history()) do out[#out + 1] = page.url .. "@" .. page.browser end
    return table.concat(out, " ")
  end

  local cacheBefore = browser.history()
  local heard
  local started = browser.refreshHistory("/usr/bin/sqlite3", function(items) heard = items end)
  local copies = { tasks[1], tasks[2] }
  check("refreshing history copies each profile's database in a task, never through hs.execute",
        started == true and #tasks == 2 and executes == 0
        and copies[1].program == "/bin/cp" and copies[2].program == "/bin/cp"
        and copies[1].args[1]:find("CommandLayerTest/One/History", 1, true)
        and rawequal(browser.history(), cacheBefore),
        ("%d tasks, %d executes"):format(#tasks, executes))

  for _, copy in ipairs(copies) do
    local h = io.open(copy.args[2], "w"); h:write("copied"); h:close()
    copy.callback(0, "", "")
  end
  local queries = { tasks[3], tasks[4] }
  local again = browser.refreshHistory("/usr/bin/sqlite3")
  check("a refresh due while one is still running starts nothing",
        again == false and #tasks == 4, tostring(#tasks) .. " tasks")
  check("each copy is queried with sqlite3 as arguments, not a shell string",
        queries[1] and queries[1].program == "/usr/bin/sqlite3"
        and queries[1].args[1] == "-json" and queries[1].args[2] == copies[1].args[2]
        and queries[2] and queries[2].args[2] == copies[2].args[2])

  queries[1].callback(0, '["one"]', "")
  local midway = rawequal(browser.history(), cacheBefore)
  queries[2].callback(0, '["two"]', "")
  check("the cache is replaced once every profile has answered, merged and de-duplicated by URL",
        midway and heard ~= nil
        and historyUrls() == "https://a.example@One https://b.example@One https://c.example@Two"
        and executes == 0, historyUrls())
  check("and the copies are removed",
        not exists(copies[1].args[2]) and not exists(copies[2].args[2]))

  local firstRows = browser.history()
  local beforeHung = #tasks
  local restarted = browser.refreshHistory("/usr/bin/sqlite3")
  local hung = { tasks[beforeHung + 1], tasks[beforeHung + 2] }
  local watchdog = watchdogs[#watchdogs]
  if watchdog and watchdog.fn then watchdog.fn() end
  local afterGivenUp = #tasks
  local nextRun = browser.refreshHistory("/usr/bin/sqlite3")
  check("a refresh that never answers is given up, its copies removed and the cache kept",
        restarted == true and hung[1] and terminated == 2
        and not exists(hung[1].args[2]) and not exists(hung[2].args[2])
        and rawequal(browser.history(), firstRows)
        and nextRun == true and #tasks == afterGivenUp + 2,
        ("%d terminated, %d tasks after"):format(terminated, #tasks - afterGivenUp))

  local running = { tasks[#tasks - 1], tasks[#tasks] }
  hs.application.watcher = { new = function() return { start = function() end, stop = function() end } end,
                             activated = 1, terminated = 2, deactivated = 3 }
  hs.timer.doEvery = function() return { stop = function() end } end
  watchdogs = {}
  browser.start()
  local warm = watchdogs[1]
  check("the startup refresh waits on a timer", warm ~= nil and not warm.stopped)
  browser.stop()
  cl.stopRunning("browser")
  check("and stopping stops it, and the refresh still running",
        warm and warm.stopped and terminated >= 4
        and not exists(running[1].args[2]) and not exists(running[2].args[2]),
        tostring(terminated) .. " terminated")

  local function rowFor(url)
    for _, row in ipairs(browserRows("root")) do
      if row.args and row.args.target == url then return row end
    end
  end
  local pageRow, pageRowAgain = rowFor("https://a.example"), rowFor("https://a.example")
  check("a history row is made once per read of history, not on every open",
        pageRow ~= nil and rawequal(pageRow, pageRowAgain), tostring(pageRow))

  local decodes, stamp = 0, 1
  local savedOpen = io.open
  hs.json.decode = function()
    decodes = decodes + 1
    return { roots = { bookmark_bar = { children = {
      { type = "url", url = "https://kept.example", name = "Kept" } } } } }
  end
  hs.fs.attributes = function(path)
    if path:find("CommandLayerTest/Missing", 1, true) or not path:find("CommandLayerTest/", 1, true) then
      return nil
    end
    return { mode = "file", modification = stamp, size = 10 }
  end
  T.stub(io, "open", function(path, mode)
    if tostring(path):find("CommandLayerTest/", 1, true) then
      return { read = function() return '{ "roots": {} }' end, close = function() end }
    end
    return savedOpen(path, mode)
  end)
  local marks = browser.refreshBookmarks()
  local decodedFirst = decodes
  local marksAgain = browser.refreshBookmarks()
  local markRow, markRowAgain = rowFor("https://kept.example"), rowFor("https://kept.example")
  local decodedUnchanged = decodes
  stamp = 2
  browser.refreshBookmarks()
  local markRowRewritten = rowFor("https://kept.example")
  T.stub(io, "open", savedOpen)
  check("bookmarks are decoded again only when a file was written since, and their rows made once per read",
        decodedFirst == 2 and decodedUnchanged == 2 and decodes == 4 and #marks == 1
        and rawequal(marks, marksAgain) and markRow ~= nil and rawequal(markRow, markRowAgain)
        and markRowRewritten ~= nil and not rawequal(markRow, markRowRewritten),
        ("%d decodes, then %d, then %d"):format(decodedFirst, decodedUnchanged, decodes))

  -- A file read while it is being written ends before its last brace.
  local mark, decodesBefore = #T.logged, decodes
  T.stub(io, "open", function(path, mode)
    if tostring(path):find("CommandLayerTest/", 1, true) then
      return { read = function() return '{ "roots": { "bookmark_bar": ' end, close = function() end }
    end
    return savedOpen(path, mode)
  end)
  stamp = 3
  local keptMarks = browser.refreshBookmarks()
  stamp = 4
  browser.refreshBookmarks()
  T.stub(io, "open", savedOpen)
  local warned = 0
  for i = mark + 1, #T.logged do
    if T.logged[i]:find("Bookmarks file did not read as JSON", 1, true) then warned = warned + 1 end
  end
  check("a Bookmarks file cut short is not decoded, keeps its last bookmarks, and says so once per file",
        decodes == decodesBefore and #keptMarks == 1 and keptMarks[1].url == "https://kept.example"
        and warned == decodedFirst,
        ("%d decodes, %d bookmarks, %d warnings for %d files"):format(decodes - decodesBefore, #keptMarks,
          warned, decodedFirst))

  hs.task.new, hs.execute, hs.json.decode = savedHistory.new, savedHistory.execute, savedHistory.decode
  hs.fs.attributes, hs.timer.doAfter = savedHistory.attributes, savedHistory.doAfter
  hs.timer.doEvery, hs.application.watcher = savedHistory.doEvery, savedHistory.watcher
  browser.profiles = savedHistory.profiles
  browser.forget()

  browser.sessionDir = realSessionDir
end

-- A person's sites are JSONC files, each checked as it is read.
do
  local sites = os.tmpname() .. "-sites"
  os.execute(("mkdir -p %q"):format(sites))
  local function write(name, text)
    local handle = assert(io.open(sites .. "/" .. name, "w"))
    handle:write(text)
    handle:close()
  end
  write("github.jsonc", [[
// Pull requests: one site, with comments and trailing commas.
{
  "name": "GitHub", "match": "github.com/[^/]+/[^/]+/pulls",
  "commands": [ { "title": "Copy page title", "js": "document.title" }, ],
}
]])
  write("broken.json", "{ \"name\": ")
  write("mistakes.json", [[
[
  { "name": "Docs", "match": "docs%.example", "comands": [],
    "commands": [
      { "title": "Search", "keys": "/" },
      { "title": "Nothing" },
      { "title": "Both", "keys": "k", "js": "1" },
      { "title": "Bad chord", "keys": "cmd+k+j" }
    ] },
  { "name": "Bad pattern", "match": "[", "commands": [ { "title": "X", "keys": "x" } ] },
  "not a site"
]
]])
  write("old.lua", "return { name = 'Old', match = 'old', commands = { { title = 'Run', keys = 'r' } } }")

  local byId = {}
  for _, command in ipairs(M.siteCommands(M.sitesFrom(sites))) do byId[command.id] = command end
  os.execute(("rm -rf %q"):format(sites))

  local function said(...)
    local parts = { ... }
    for _, p in ipairs(cl.problems) do
      local all = p.file == "extension browser"
      for _, part in ipairs(parts) do all = all and p.message:find(part, 1, true) ~= nil end
      if all then return true end
    end
    return false
  end
  local ids = {}
  for id in pairs(byId) do ids[#ids + 1] = id end
  table.sort(ids)

  local mine = byId["browser.site.github.copyPageTitle"]
  check("a site file of your own is JSONC and becomes commands, slashes in its pattern and all",
        mine ~= nil and mine.command == "browser.js" and mine.args.js == "document.title"
        and cl.when(mine.menus.context.when, { url = "https://github.com/a/b/pulls" })
        and not cl.when(mine.menus.context.when, { url = "https://github.com/a/b" }), table.concat(ids, ", "))
  check("a site file that does not parse is a problem naming it",
        said("-sites/broken.json", "does not parse"))
  check("a site's mistakes are problems naming the file, the site, the command and the field",
        said("mistakes.json, site 1 \"Docs\": \"comands\" is not a field it can have")
        and said("mistakes.json, site 1 \"Docs\": command 2 \"Nothing\": needs \"keys\" or \"js\"")
        and said("command 3 \"Both\": has both \"keys\" and \"js\"")
        and said("command 4 \"Bad chord\": \"keys\" \"cmd+k+j\" does not read as a key")
        and said("mistakes.json, site 2 \"Bad pattern\": \"match\" \"[\" is not a Lua pattern")
        and said("mistakes.json, site 3: is not an object"))
  check("and leave out only what they are in: the site's good commands stay",
        byId["browser.site.docs.search"] ~= nil and byId["browser.site.docs.nothing"] == nil
        and byId["browser.site.docs.both"] == nil and byId["browser.site.docs.badChord"] == nil
        and byId["browser.site.badPattern.x"] == nil and #ids == 2, table.concat(ids, ", "))
  check("a Lua site file is not run, and is a problem saying a site file is JSON",
        said("-sites/old.lua is not read: a site file is JSON, old.json")
        and byId["browser.site.old.run"] == nil)
end

do
  local decodes = 0
  T.stub(hs, "json", { decode = function(text)
    decodes = decodes + 1
    if text == '[{"a":1}]' then return { { a = 1 } } end
    error("not JSON")
  end })
  local empty, blank, rows = M.decodeRows(""), M.decodeRows("  \n"), M.decodeRows('[{"a":1}]')
  check("history with no rows decodes nothing: sqlite prints nothing, and decoding that writes a console error",
        #empty == 0 and #blank == 0 and #rows == 1 and decodes == 1, decodes .. " decodes")
end

-- The page in front is a subject like any row, so the verbs a typed URL gets
-- are the verbs the page gets: cmd+. on a repository offers to clone it.
do
  local browser = M
  local saved = { new = hs.task.new, doAfter = hs.timer.doAfter }
  local finish
  hs.task.new = function(_, callback)
    finish = callback
    return { start = function(t) return t end, terminate = function() callback(15, "") end }
  end
  hs.timer.doAfter = function() return { stop = T.noop } end
  browser.forget()
  browser.frontTab("Brave Browser")
  finish(0, "https://github.com/torvalds/linux\tlinux\n")

  local ctx = cl.argContext({ frontmostApp = "Brave Browser",
                              url = "https://github.com/torvalds/linux" },
                            { activeView = "context" })
  local subjects = {}
  for _, subject in ipairs(cl.ambientSubjects(ctx)) do subjects[#subjects + 1] = subject.kind end
  -- One gather: asking again would find the browser's answer used up.
  local verbs, cloneRow = {}, nil
  for _, row in ipairs(cl.gather(ctx, { menus = { "context" } })) do
    if row.command then verbs[row.command] = true end
    if row.command == "git.cloneRepository" then cloneRow = row end
  end
  local typedGit = {}
  if cloneRow then
    local matchers = cl.matchers
    cl.matchers = T.substringOnly()
    cl.rankItems({ cloneRow }, "git", function(out) typedGit = out end)
    cl.matchers = matchers
  end

  browser.forget()
  hs.task.new, hs.timer.doAfter = saved.new, saved.doAfter

  check("the page in front is a url subject, and a GitHub page's verbs include cloning it, found by typing git",
        table.concat(subjects, ",") == "url" and verbs["git.cloneRepository"] == true
        and verbs["browser.copyURL"] == true and #typedGit == 1,
        table.concat(subjects, ",") .. " / clone " .. tostring(verbs["git.cloneRepository"])
        .. " / " .. #typedGit .. " for 'git'")
end

-- The script's shape and a tab gone since are checked above; what is left is
-- what can refuse it: macOS's Automation prompt, and a row from something
-- that is not a browser at all.
do
  local browser = M
  local saved = { new = hs.task.new, path = cl.tools.path }
  local scripts, opened = {}, {}
  hs.task.new = function(program, callback, _, args)
    scripts[#scripts + 1] = { program = program, script = args and args[2], done = callback }
    return { start = function(t) return t end, terminate = function() end }
  end
  cl.tools.path = function(name)
    if name == "osascript" then return "/usr/bin/osascript" end
    return saved.path(name)
  end
  local realOpen = cl.getCommand("system.open")
  cl.registerCommand("system.open", { title = "Open", menus = {},
    run = function(args) opened[#opened + 1] = args.target end })

  cl.executeCommand("browser.tab", { app = "Brave Browser", url = "https://refused.example" })
  local alerts, realAlert = {}, hs.alert.show
  hs.alert.show = function(message) alerts[#alerts + 1] = message end
  scripts[#scripts].done(1, "", "execution error: Not authorised (-1743)")
  hs.alert.show = realAlert

  local beforeNotBrowser = #scripts
  cl.executeCommand("browser.tab", { app = "Finder", url = "https://finder.example" })

  browser.forget()
  hs.task.new, cl.tools.path = saved.new, saved.path
  if realOpen then cl.registerCommand("system.open", realOpen) end

  check("a browser that refuses Automation says where to allow it and opens the URL; "
        .. "a row from no browser asks nothing",
        opened[1] == "https://refused.example" and opened[2] == "https://finder.example"
        and #scripts == beforeNotBrowser
        and (alerts[1] or ""):find("Automation", 1, true) ~= nil,
        table.concat(opened, ", ") .. " / " .. tostring(alerts[1]))
end

-- A site's commands are about a page, not about whichever page is in front:
-- on a tab row whose URL matches they are cmd+k verbs for that tab, and run
-- on it they bring it forward first.
do
  local function verbsOn(subject, front)
    local ids = {}
    for _, row in ipairs(cl.itemActions(subject, { frontmostApp = "Brave Browser", url = front })) do
      if row.command then ids[row.command] = row end
    end
    return ids
  end
  local video = { kind = "url", value = "https://www.youtube.com/watch?v=v", name = "A video",
                  tabIn = "Brave Browser" }
  local elsewhere = { kind = "url", value = "https://example.com/", name = "Not a video",
                      tabIn = "Brave Browser" }
  local onVideo = verbsOn(video, "https://github.com/")
  local onOther = verbsOn(elsewhere, "https://www.youtube.com/watch?v=front")
  check("a site's commands are cmd+k verbs on a tab whose URL matches, whatever page is in front",
        onVideo["browser.site.youtube.fullScreen"] ~= nil
        and onOther["browser.site.youtube.fullScreen"] == nil)

  local saved = { new = hs.task.new, after = cl.after }
  local scripts, strokes = {}, {}
  hs.task.new = function(_, callback, _, args)
    scripts[#scripts + 1] = { script = args and args[2], done = callback }
    return { start = function(t) return t end, terminate = function() end }
  end
  local realStroke = hs.eventtap.keyStroke
  hs.eventtap.keyStroke = function(mods, key) strokes[#strokes + 1] = table.concat(mods, "+") .. key end
  local realAfter = hs.timer.doAfter
  hs.timer.doAfter = function(_, fn) fn(); return { stop = T.noop } end

  -- Given the tab, not the page in front: the tab is brought forward, then the key.
  cl.executeCommand("browser.site.youtube.fullScreen", { tab = video },
                    { frontmostApp = "Brave Browser", url = "https://github.com/" })
  local switching = scripts[#scripts]
  local beforeFound = #strokes
  if switching and switching.done then switching.done(0, "found\n", "") end
  local afterFound = #strokes

  -- Gone since: said, and nothing pressed.
  local alerts, realAlert = {}, hs.alert.show
  hs.alert.show = function(message) alerts[#alerts + 1] = message end
  cl.executeCommand("browser.site.youtube.fullScreen", { tab = video },
                    { frontmostApp = "Brave Browser", url = "https://github.com/" })
  scripts[#scripts].done(0, "missing\n", "")
  hs.alert.show = realAlert

  hs.task.new, hs.eventtap.keyStroke, hs.timer.doAfter = saved.new, realStroke, realAfter

  check("run on a tab not in front, a site's command brings that tab forward, then presses its key; "
        .. "a tab gone says so",
        switching and switching.script:find('set target to "https://www.youtube.com/watch?v=v"', 1, true)
        and beforeFound == 0 and afterFound == 1 and strokes[1] == "f"
        and #strokes == 1 and alerts[1] == "That tab is no longer open",
        tostring(switching and switching.script and switching.script:sub(1, 70)) .. " / "
        .. table.concat(strokes, ",") .. " / " .. tostring(alerts[1]))
end
