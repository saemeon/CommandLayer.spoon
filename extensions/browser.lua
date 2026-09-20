-- The page you are looking at, its tabs, and its history and bookmarks.
--
-- The front tab becomes a `url` subject, which is what makes the git
-- extension's clone verb work on a repository page without either
-- extension knowing the other exists.
--
-- Safari is absent: different schema, behind Full Disk Access, with
-- bookmarks in a binary plist.

local M = {}

-- The layer, for the asks and refreshes that run outside the extension.
local layer

-- The reader for Chromium's session files and the shipped sites, beside this
-- file. A folder, so the extension loader does not take them for extensions.
do
  local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
  local ok, loaded = pcall(dofile, here .. "browser/session.lua")
  M.session = ok and loaded or nil
  M.sitesFile = here .. "browser/sites.jsonc"
end

-- Chromium-family browsers all answer the same script; Safari has its
-- own vocabulary. Firefox has no useful AppleScript dictionary at all.
M.chromium = {
  ["Google Chrome"]         = true,
  ["Google Chrome Canary"]  = true,
  ["Brave Browser"]         = true,
  ["Microsoft Edge"]        = true,
  ["Arc"]                   = true,
  ["Vivaldi"]               = true,
  ["Chromium"]              = true,
}

M.safari = {
  ["Safari"]                = true,
  ["Safari Technology Preview"] = true,
}

function M.isBrowser(app)
  return M.chromium[app] == true or M.safari[app] == true
end

----------------------------------------------------------------------
-- SITES
--
-- Commands that exist only while a particular page is in front: the site's
-- own shortcuts, or JavaScript run in the tab. Data, never code: loading a
-- Lua file runs whatever it holds. The shipped ones are sites.jsonc beside
-- this file; a person's are JSONC files in ~/.config/commandlayer/sites/,
-- each one site or a list of them.
----------------------------------------------------------------------

-- "Play / pause" -> "playPause", for a command id.
local function slug(text)
  local out = ""
  for word in tostring(text):gmatch("%w+") do
    out = out .. (out == "" and word:lower() or word:sub(1, 1):upper() .. word:sub(2):lower())
  end
  return out
end

local SITE_FIELDS    = { name = true, match = true, commands = true }
local COMMAND_FIELDS = { title = true, keys = true, js = true }

local function shortPath(path)
  local home = os.getenv("HOME")
  if home and path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
  return path
end

-- Text a command id can be made from: an empty slug would give
-- `browser.site..title`.
local function naming(value)
  return type(value) == "string" and slug(value) ~= ""
end

local function isObject(value)
  return type(value) == "table" and value[1] == nil
end

-- Named as a person finds it in the file: `site 2 "GitHub"`.
local function place(where, value)
  return type(value) == "string" and ("%s %q"):format(where, value) or where
end

-- A field it cannot have is said, and what holds it kept.
local function unknownFields(value, known, say)
  local names = {}
  for key in pairs(value) do
    if not known[key] then names[#names + 1] = tostring(key) end
  end
  table.sort(names)
  for _, key in ipairs(names) do say(("%q is not a field it can have"):format(key)) end
end

-- The command, or nil when it has a mistake, which is said.
local function checkCommand(command, say)
  if not isObject(command) then return say("is not an object") end
  unknownFields(command, COMMAND_FIELDS, say)
  if not naming(command.title) then return say('"title" must be text with a letter or digit') end
  if command.keys ~= nil and command.js ~= nil then return say('has both "keys" and "js"; it takes one') end
  if command.keys ~= nil then
    local _, key
    if type(command.keys) == "string" then _, key = layer.chord(command.keys) end
    if not key then return say(('"keys" %q does not read as a key'):format(tostring(command.keys))) end
  elseif command.js ~= nil then
    if type(command.js) ~= "string" or command.js == "" then return say('"js" must be text') end
  else
    return say('needs "keys" or "js"')
  end
  return command
end

-- A wrong name, match or commands leaves out the whole site; a wrong command
-- only that command.
local function checkSite(site, say)
  if not isObject(site) then return say("is not an object") end
  unknownFields(site, SITE_FIELDS, say)
  if not naming(site.name) then return say('"name" must be text with a letter or digit') end
  if type(site.match) ~= "string" or site.match == "" then return say('"match" must be text') end
  -- As a when clause tries its pattern: the site's becomes one.
  if not pcall(string.find, "", site.match) then
    return say(('"match" %q is not a Lua pattern'):format(site.match))
  end
  if type(site.commands) ~= "table" or (next(site.commands) ~= nil and site.commands[1] == nil) then
    return say('"commands" must be a list')
  end
  local checked = { name = site.name, match = site.match, commands = {} }
  for i, command in ipairs(site.commands) do
    local where = place("command " .. i, isObject(command) and command.title or nil)
    checked.commands[#checked.commands + 1] = checkCommand(command, function(message)
      say(where .. ": " .. message)
    end)
  end
  return checked
end

-- A site file's contents: one site, or a list of them.
function M.checkSites(value, path)
  local sites = {}
  local file = shortPath(tostring(path))
  if type(value) ~= "table" then
    layer.problem(file .. ": holds neither a site nor a list of sites")
    return sites
  end
  local single = isObject(value) and next(value) ~= nil
  for i, site in ipairs(single and { value } or value) do
    local where = place(single and "the site" or ("site " .. i), isObject(site) and site.name or nil)
    sites[#sites + 1] = checkSite(site, function(message)
      layer.problem(("%s, %s: %s"):format(file, where, message))
    end)
  end
  return sites
end

-- A file that does not parse is said by readJSONC, and gives no sites.
function M.readSites(path)
  local value = layer.readJSONC(path)
  if value == nil then return {} end
  return M.checkSites(value, path)
end

-- Every *.json and *.jsonc file in the folder, in name order. A Lua file
-- there is said rather than passed over, so a site that stopped being read
-- does not just vanish.
function M.sitesFrom(dir)
  local out = {}
  if not dir then return out end
  local ok, iter, dirObj = pcall(hs.fs.dir, dir)
  if not ok or not iter then return out end

  local names = {}
  for entry in iter, dirObj do
    if entry:sub(1, 1) ~= "." and (entry:match("%.jsonc?$") or entry:match("%.lua$")) then
      names[#names + 1] = entry
    end
  end
  table.sort(names)

  for _, entry in ipairs(names) do
    local path = dir .. "/" .. entry
    if entry:match("%.lua$") then
      layer.problem(("%s is not read: a site file is JSON, %s"):format(shortPath(path),
        (entry:gsub("%.lua$", ".json"))))
    else
      for _, site in ipairs(M.readSites(path)) do out[#out + 1] = site end
    end
  end
  return out
end

-- A slash ends a when clause's /pattern/, so one in a site's pattern is
-- escaped the way a clause writes it.
local function escapeSlashes(pattern)
  return (pattern:gsub("%%?/", "%%/"))
end

-- From sites already checked. `frontPage(ctx)` is the page in front as a
-- url subject, or nil.
--
-- A site's commands are about a page, and the page need not be the one in
-- front: each takes a tab, so on a tab row whose URL matches it is a cmd+k
-- verb for that tab, while run from the root, the context picker or the
-- palette it takes the page in front and asks nothing. The condition is on
-- each menu and on the tab, never on the command, which would hide it from
-- a tab row while another page is in front.
function M.siteCommands(sites, frontPage)
  local commands = {}
  for _, site in ipairs(sites) do
    local pattern = escapeSlashes(site.match)
    local onPage = { when = "url =~ /" .. pattern .. "/" }
    for _, c in ipairs(site.commands) do
      local command, args = "browser.js", { js = c.js }
      if c.keys then command, args = "browser.keys", { keys = c.keys } end
      args.url, args.app = "${input:tab.value}", "${input:tab.tabIn}"
      commands[#commands + 1] = {
        id       = "browser.site." .. slug(site.name) .. "." .. slug(c.title),
        title    = c.title,
        category = site.name,
        -- The page in front is context, as much as a Finder selection is.
        menus    = { root = onPage, context = onPage, commandPalette = onPage },
        rank     = 1,
        inputs   = { {
          id = "tab", description = "Which tab",
          -- `value` is the row's own URL; `url` would be the page in front.
          picker = { when = "viewItem == 'url' && tabIn && value =~ /" .. pattern .. "/" },
          preferCurrent = true,
          current = function(ctx)
            local page = frontPage and frontPage(ctx)
            if page and tostring(page.value):find(site.match) then return page end
          end,
        } },
        command  = command,
        args     = args,
      }
    end
  end
  return commands
end

----------------------------------------------------------------------

-- Asked through osascript in a process of its own, never hs.osascript:
-- that waits on Hammerspoon's main thread for every Apple Event, and a
-- busy browser -- or one with hundreds of tabs -- froze all of
-- Hammerspoon for as long as the browser took to answer.
--
-- So the picker only ever reads the last answer. A stale one starts a
-- fresh ask, and the open picker is rebuilt when it lands.
M.staleSeconds   = 2
M.timeoutSeconds = 5

local answers = {}   -- app name -> { front =, tabs =, time = }
local pending = {}

-- "recent": the tabs last active first, by the time Chromium records in its
-- session file, the rest after them in the browser's own order -- which is
-- all of them where there is no file. Anything else: the browser's order.
function M.orderTabs(tabs, order)
  local out, index = {}, {}
  for i, tab in ipairs(tabs or {}) do out[i], index[tab] = tab, i end
  if order ~= "recent" then return out end
  table.sort(out, function(a, b)
    local sa, sb = a.lastActive or 0, b.lastActive or 0
    if sa ~= sb then return sa > sb end
    return index[a] < index[b]
  end)
  return out
end

-- One script for the front tab and every tab, so one process per ask.
-- `URL of every tab of w` is one Apple Event per window; asking each tab
-- for its URL and title was two per tab.
local function script(app)
  local front, title = "active tab of front window", "title"
  if M.safari[app] then front, title = "front document", "name" end

  -- The separator is made before the tell block: inside it `tab` names the
  -- browser's own tab class, not the character, and the script fails.
  return ([[
    set sep to character id 9
    set nl to character id 10
    set out to ""
    tell application %q
      if (count of windows) is 0 then return ""
      set f to %s
      set out to (URL of f) & sep & (%s of f) & nl
      repeat with w in windows
        set us to URL of every tab of w
        set ts to %s of every tab of w
        repeat with i from 1 to count of us
          set out to out & (item i of us) & sep & (item i of ts) & nl
        end repeat
      end repeat
    end tell
    return out
  ]]):format(app, front, title, title)
end

local function parse(out)
  local front, tabs = nil, {}
  for line in tostring(out):gmatch("[^\n]+") do
    local url, title = line:match("^(.-)\t(.*)$")
    if url and url ~= "" then
      local entry = { url = url, title = (title ~= "" and title) or url }
      if front then tabs[#tabs + 1] = entry else front = entry end
    end
  end
  return front, tabs
end

function M.ask(app)
  if not M.isBrowser(app) or pending[app] then return end
  pending[app] = true

  local task, watchdog
  task = layer and layer.tools.run("/usr/bin/osascript", { "-e", script(app) }, function(code, stdout, stderr)
    pending[app] = nil
    if watchdog then watchdog.dispose() end
    -- A failed ask keeps the last good answer rather than blanking it.
    if code ~= 0 then
      M.reportRefusal(app, stderr)
      return
    end

    local front, tabs = parse(stdout)
    local previous = answers[app]
    answers[app] = { front = front, tabs = tabs, time = os.time(), raw = stdout }
    -- Only a change redraws, or an open picker is rebuilt -- losing
    -- its selection -- every time the answer goes stale.
    if previous and previous.raw == stdout then return end
    if M.onAnswer then M.onAnswer(app) end
  end)

  if not task then
    pending[app] = nil
    return
  end

  -- A browser that never answers would otherwise stay pending for good.
  watchdog = layer.after(M.timeoutSeconds, function()
    if pending[app] then
      pending[app] = nil
      task:terminate()
    end
  end)
end

-- -1743 is macOS refusing Hammerspoon permission to control the browser.
-- Nothing else says so -- tabs and site commands just never appear -- so
-- it is said once per browser, with where to allow it.
local refused = {}

function M.reportRefusal(app, stderr)
  local text = tostring(stderr or "")
  if refused[app] then return end
  refused[app] = true
  if layer then layer.log.w("asking " .. tostring(app) .. " for its tabs failed: " .. text) end
  if text:find("-1743", 1, true) then
    hs.alert.show("Allow Hammerspoon to control " .. tostring(app)
                  .. ": System Settings > Privacy & Security > Automation", 6)
  end
end

-- Seconds a session folder is left to settle before it is read: Chromium
-- writes several records in a burst.
M.sessionDelay = 1

function M.forget()
  answers, pending, refused = {}, {}, {}
  if M.session then M.session.forget() end
end

-- Brings forward the tab showing `url`, in whichever window it is, and
-- says whether there was one.
function M.switchScript(app, url)
  local quoted = url:gsub("\\", "\\\\"):gsub('"', '\\"')
  local select = "set active tab index of w to i"
  if M.safari[app] then select = "set current tab of w to tab i of w" end
  return ([[
    set target to "%s"
    tell application %q
      repeat with w in windows
        set us to URL of every tab of w
        repeat with i from 1 to count of us
          if item i of us is target then
            %s
            set index of w to 1
            activate
            return "found"
          end if
        end repeat
      end repeat
    end tell
    return "missing"
  ]]):format(quoted, app, select)
end

local function answer(app)
  if not app or not M.isBrowser(app) then return nil end
  local hit = answers[app]
  if not hit or os.time() - hit.time > M.staleSeconds then M.ask(app) end
  return hit
end

-- The front tab's URL and title, or nil when the frontmost app is not a
-- browser, or has not answered yet.
-- Asked of the browser, which is current to the moment; the session file,
-- a few seconds behind, when the browser has not answered.
-- `cachedOnly` reads what is already known, asking nothing: for ordering
-- rows, where the context capture has asked already.
function M.frontTab(app, cachedOnly)
  local hit
  if cachedOnly then hit = answers[app] else hit = answer(app) end
  if hit and hit.front then return hit.front end
  local _, front = M.sessionTabs(app)
  return front
end

-- Every open tab of a browser. A running Chromium browser's come from its
-- session file, which needs no permission and says when each was last
-- active. Otherwise the browser is asked -- only the one in front: asking
-- every installed browser means launching the ones that are closed.
-- `cachedOnly` reads the last answer without asking again. A browser not
-- in front is never asked from a picker: the first ask of a browser brings
-- up macOS's permission prompt, which takes focus and closes the launcher.
function M.tabs(app, cachedOnly)
  local fromFile = M.sessionTabs(app)
  if fromFile then return fromFile end
  local hit
  if cachedOnly then hit = answers[app] else hit = answer(app) end
  return hit and hit.tabs or {}
end

-- The browser in front, then every browser that has answered and not quit
-- since, and every running Chromium browser, whose tabs its session file
-- gives. Never hs.application.get, which walks every running app per name
-- -- a quarter of a second for the nine names here, paid again on every
-- redraw of the recent picker; a bundle id is looked up directly.
function M.runningBrowsers(front)
  local names, others, seen = {}, {}, {}
  if M.isBrowser(front) then
    names[1] = front
    seen[front] = true
  end
  for name in pairs(answers) do
    if not seen[name] then
      others[#others + 1] = name
      seen[name] = true
    end
  end
  for name in pairs(M.chromiumProfiles or {}) do
    if not seen[name] and M.isRunning(name) then others[#others + 1] = name end
  end
  table.sort(others)
  for _, name in ipairs(others) do names[#names + 1] = name end
  return names
end

----------------------------------------------------------------------
-- HISTORY AND BOOKMARKS
--
-- Chromium keeps both on disk in formats anyone can read: history in
-- SQLite, bookmarks as JSON. No extension, no debugging port, no
-- native messaging host.
----------------------------------------------------------------------

M.profiles = {
  { name = "Brave",   dir = "BraveSoftware/Brave-Browser/Default" },
  { name = "Chrome",  dir = "Google/Chrome/Default" },
  { name = "Edge",    dir = "Microsoft Edge/Default" },
  { name = "Vivaldi", dir = "Vivaldi/Default" },
  { name = "Arc",     dir = "Arc/User Data/Default" },
}

local support = os.getenv("HOME") .. "/Library/Application Support/"

-- Where each Chromium-family browser keeps its session, and its bundle id,
-- to ask whether it is running without the window search a lookup by name
-- does.
M.chromiumProfiles = {
  ["Brave Browser"]  = { dir = "BraveSoftware/Brave-Browser/Default", bundle = "com.brave.Browser" },
  ["Google Chrome"]  = { dir = "Google/Chrome/Default",               bundle = "com.google.Chrome" },
  ["Microsoft Edge"] = { dir = "Microsoft Edge/Default",              bundle = "com.microsoft.edgemac" },
  ["Vivaldi"]        = { dir = "Vivaldi/Default",                     bundle = "com.vivaldi.Vivaldi" },
  ["Arc"]            = { dir = "Arc/User Data/Default",               bundle = "company.thebrowser.Browser" },
}

function M.sessionDir(app)
  local profile = M.chromiumProfiles[app]
  return profile and (support .. profile.dir .. "/Sessions") or nil
end

function M.isRunning(app)
  local profile = M.chromiumProfiles[app]
  if not (profile and hs.application.applicationsForBundleID) then return false end
  local ok, running = pcall(hs.application.applicationsForBundleID, profile.bundle)
  return ok and type(running) == "table" and #running > 0
end

-- The running app by that name: by bundle id where it is known, else
-- matched among the running apps. Never hs.application.get, which goes on
-- to search every window's title when the name misses.
function M.runningApp(name)
  local profile = M.chromiumProfiles[name]
  if profile and hs.application.applicationsForBundleID then
    local ok, running = pcall(hs.application.applicationsForBundleID, profile.bundle)
    if ok and type(running) == "table" and running[1] then return running[1] end
  end
  local ok, apps = pcall(hs.application.runningApplications)
  for _, app in ipairs(ok and type(apps) == "table" and apps or {}) do
    local named, appName = pcall(function() return app:name() end)
    if named and appName == name then return app end
  end
  return nil
end

-- Every Chromium browser's session folder that exists, read where its newest
-- file changed: at start, when a folder changes, and with history. Whether
-- the browser runs is asked when its tabs are, so a file read before it
-- started is there once it does.
-- A file in a format version the reader does not know is not guessed at: its
-- browser is asked as one without a file is, and that is said once.
function M.readSessions()
  if not M.session then return end
  for app in pairs(M.chromiumProfiles) do
    local dir = M.sessionDir(app)
    local _, unknown
    if dir then _, unknown = M.session.read(dir) end
    if unknown and layer then
      layer.problem(("%s's session file is format version %d, which the tab reader does not know, "
        .. "so its tabs are asked of the browser instead"):format(app, unknown))
    end
  end
end

-- The open tabs as the browser last wrote them, and its front tab, or nil
-- when it is not running -- its file then describes tabs that are gone --
-- or no file was read, so the browser is asked instead. From the last read:
-- never the file itself, which a picker would parse on every build.
function M.sessionTabs(app)
  if not (M.session and M.isRunning(app)) then return nil end
  local dir = M.sessionDir(app)
  local result = dir and M.session.kept(dir)
  if not result or #result.tabs == 0 then return nil end
  return result.tabs, result.front
end

local historyCache = {}
local bookmarkCache = {}

local function profilePath(profile, file)
  local path = support .. profile.dir .. "/" .. file
  return hs.fs.attributes(path) and path or nil
end

-- A row per bookmark or page, made once per list read rather than on every
-- open: the same tables come back until the list is replaced, and only their
-- ctx is the open's. Gather and sections change copies, never these.
local rowsOfList = setmetatable({}, { __mode = "k" })

function M.rowsFor(list, make)
  local rows = rowsOfList[list]
  if not rows then
    rows = {}
    for i, entry in ipairs(list) do rows[i] = make(entry) end
    rowsOfList[list] = rows
  end
  return rows
end

-- Reads the cache and nothing else. Refreshing happens on a timer,
-- never here: this is called while building a picker, and copying a
-- history database costs 10ms at a megabyte but seconds at the few
-- hundred a heavy browser accumulates.
function M.history()
  return historyCache
end

-- A copy or query that never ends would otherwise hold the refresh
-- running, and every later one would be skipped for good.
M.historyTimeoutSeconds = 60

-- The refresh in progress: its tasks, held until each ends, since a task
-- nobody holds can be collected mid-run.
local historyRun

local function abandonHistory(run)
  if historyRun == run then historyRun = nil end
  if run.watchdog then run.watchdog.dispose() end
  for i, task in pairs(run.tasks) do
    run.tasks[i] = nil
    pcall(function() task:terminate() end)
  end
  for _, temp in pairs(run.temps) do os.remove(temp) end
end

-- In processes of their own, since copying a database of a few hundred
-- megabytes takes seconds and Hammerspoon has one thread. The browser
-- holds its history open, so querying in place fails with a locked
-- database whenever it is running; copying first is what every tool that
-- reads these does. Paths go as arguments, never through a shell.
function M.refreshHistory(sqlite, done)
  if not sqlite or historyRun then return false end

  local sources = {}
  for _, profile in ipairs(M.profiles) do
    local path = profilePath(profile, "History")
    if path then sources[#sources + 1] = { profile = profile, path = path } end
  end

  local run = { tasks = {}, temps = {}, rows = {}, left = #sources }
  historyRun = run

  local function merge()
    if historyRun ~= run then return end
    abandonHistory(run)
    local items, seen = {}, {}
    for i, source in ipairs(sources) do
      for _, row in ipairs(run.rows[i] or {}) do
        if type(row) == "table" and row.url and not seen[row.url] then
          seen[row.url] = true
          items[#items + 1] = {
            url = row.url, title = row.title, browser = source.profile.name,
          }
        end
      end
    end
    historyCache = items
    if done then done(items) end
  end

  local function answered(i, rows)
    run.tasks[i] = nil
    if run.temps[i] then
      os.remove(run.temps[i])
      run.temps[i] = nil
    end
    if historyRun ~= run then return end
    run.rows[i] = rows
    run.left = run.left - 1
    if run.left == 0 then merge() end
  end

  local query = ("select url, title from urls where title is not null "
    .. "and title != '' order by last_visit_time desc limit %d;")
    :format(math.floor(tonumber(layer and layer.setting("browser", "historyLimit")) or 0))

  local function start(i, program, callback, args)
    local task = layer and layer.tools.run(program, args, callback)
    run.tasks[i] = task
    if not task then answered(i, {}) end
  end

  for i, source in ipairs(sources) do
    local temp = os.tmpname()
    run.temps[i] = temp
    start(i, "/bin/cp", function(code)
      if historyRun ~= run then return answered(i, {}) end
      if code ~= 0 then return answered(i, {}) end
      start(i, sqlite, function(status, stdout)
        answered(i, status == 0 and M.decodeRows(stdout) or {})
      end, { "-json", temp, query })
    end, { source.path, temp })
  end

  if historyRun ~= run then return true end
  if run.left == 0 then
    merge()
  else
    run.watchdog = layer.after(M.historyTimeoutSeconds, function()
      run.watchdog = nil
      abandonHistory(run)
    end)
  end
  return true
end

local function walkBookmarks(node, out, seen)
  if type(node) ~= "table" then return end

  if node.type == "url" and node.url and not seen[node.url] then
    seen[node.url] = true
    out[#out + 1] = { url = node.url, title = node.name or node.url }
  end

  for _, child in ipairs(node.children or {}) do
    walkBookmarks(child, out, seen)
  end
end

function M.bookmarks()
  return bookmarkCache
end

-- hs.json.decode writes an error to the console for text that is not JSON,
-- even inside pcall, so only text shaped like a whole JSON object or list is
-- decoded: sqlite3 -json prints nothing, not [], for a query with no rows, and
-- a file read while it is being written can end before its last brace.
function M.decodeJSON(text)
  local body = tostring(text or ""):match("^%s*(.-)%s*$")
  local first, last = body:sub(1, 1), body:sub(-1)
  if not ((first == "{" and last == "}") or (first == "[" and last == "]")) then return nil end
  local ok, data = pcall(hs.json.decode, body)
  return ok and type(data) == "table" and data or nil
end

function M.decodeRows(text)
  return M.decodeJSON(text) or {}
end

-- Bookmarks files that did not read, so saying so is once each.
local unreadable = {}

-- Per Bookmarks file: when it was written and its size, and what it held.
local bookmarkFiles = {}

-- nil when the file did not read as bookmarks.
local function readBookmarks(path, profile)
  local entries = {}
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("a")
  handle:close()
  local data = M.decodeJSON(body)
  if not (data and type(data.roots) == "table") then return nil end
  for _, root in pairs(data.roots) do walkBookmarks(root, entries, {}) end
  for _, entry in ipairs(entries) do entry.browser = profile.name end
  return entries
end

-- A file is decoded again only when it was written since, so the list and
-- the rows made from it stay the same tables while nothing changed.
function M.refreshBookmarks()
  local changed, present = false, {}

  for _, profile in ipairs(M.profiles) do
    local path = support .. profile.dir .. "/Bookmarks"
    local attributes = hs.fs.attributes(path)
    if attributes then
      present[path] = true
      local stamp = tostring(attributes.modification) .. ":" .. tostring(attributes.size)
      local kept = bookmarkFiles[path]
      if not kept or kept.stamp ~= stamp then
        local entries = readBookmarks(path, profile)
        if not entries and not unreadable[path] then
          unreadable[path] = true
          layer.log.w(("browser: %s's Bookmarks file did not read as JSON; its last bookmarks are kept")
                      :format(tostring(profile.name)))
        end
        -- Read again only once it is written again.
        bookmarkFiles[path] = { stamp = stamp, entries = entries or (kept and kept.entries) or {} }
        changed = true
      end
    end
  end
  for path in pairs(bookmarkFiles) do
    if not present[path] then
      bookmarkFiles[path] = nil
      changed = true
    end
  end
  if not changed then return bookmarkCache end

  local items, seen = {}, {}
  for _, profile in ipairs(M.profiles) do
    local kept = bookmarkFiles[support .. profile.dir .. "/Bookmarks"]
    for _, entry in ipairs(kept and kept.entries or {}) do
      if not seen[entry.url] then
        seen[entry.url] = true
        items[#items + 1] = entry
      end
    end
  end

  bookmarkCache = items
  return items
end

function M.warm(sqlite)
  M.refreshHistory(sqlite)
  M.refreshBookmarks()
  return M
end

----------------------------------------------------------------------

function M.extension(cl)
  layer = cl
  cl.tools.register("sqlite3", { "/usr/bin/sqlite3" })

  local sessionTimer

  -- Warmed off the startup path: copying a history database and
  -- parsing a bookmarks file is not much, but it is not nothing.
  M.start = function()
    local function refresh()
      pcall(M.warm, cl.tools.path("sqlite3"))
      -- A folder made since start has no watcher; this reads it.
      pcall(M.readSessions)
    end

    -- Once shortly after launch, then on a timer. Both off the path
    -- that builds a picker.
    cl.after(3, refresh)
    cl.every(cl.setting("browser", "historySeconds"), refresh)

    -- Now rather than on that timer: a running browser with no tabs read
    -- would be asked through AppleScript instead.
    M.readSessions()
    for app in pairs(M.chromiumProfiles) do
      local dir = M.sessionDir(app)
      if dir and hs.pathwatcher and hs.fs.attributes(dir) then
        cl.watch(hs.pathwatcher.new(dir, function()
          if sessionTimer then return end
          sessionTimer = cl.after(M.sessionDelay, function()
            sessionTimer = nil
            M.readSessions()
          end)
        end))
      end
    end

    -- Asked on switching to a browser, so the answer is usually in by
    -- the time the launcher opens over it, and on leaving one, since the
    -- tab in front then is the one you were just on.
    cl.watch(hs.application.watcher.new(function(name, event)
      local watcher = hs.application.watcher
      if (event == watcher.activated or event == watcher.deactivated)
         and M.isBrowser(name) then
        M.ask(name)
      elseif event == watcher.terminated and M.isBrowser(name) then
        -- Its tabs went with it.
        answers[name] = nil
      end
    end))
  end

  -- A history refresh still running has temporary copies to remove.
  M.stop = function()
    if historyRun then abandonHistory(historyRun) end
    sessionTimer = nil
    M.forget()
  end

  -- An answer that lands while a picker is open replaces what it showed.
  M.onAnswer = function(app)
    local ctx = M.pendingCtx
    if ctx and ctx.frontmostApp == app then
      local tab = M.frontTab(app)
      if tab then ctx.url, ctx.pageTitle = tab.url, tab.title end
    end
    cl.refresh()
  end

  -- Each part can be switched off in the settings picker; tabs are the one
  -- that asks the browser anything.
  local function on(key) return cl.setting("browser", key) ~= false end

  local function bookmarkRow(mark)
    return {
      label       = mark.title,
      description = "Bookmark -- " .. mark.url,
      keywords    = { mark.url },
      command     = "system.open",
      args        = { target = mark.url, title = mark.title },
      subject     = { kind = "url", value = mark.url, name = mark.title },
      -- Below apps and commands (0.1): there are hundreds, and above
      -- them they filled the root before anything was typed.
      rank        = 0.11,
    }
  end

  local function historyRow(page)
    return {
      label       = page.title,
      description = (page.browser or "History") .. " -- " .. page.url,
      keywords    = { page.url },
      command     = "system.open",
      args        = { target = page.url, title = page.title },
      subject     = { kind = "url", value = page.url, name = page.title },
      rank        = 0.06,
    }
  end

  -- The browser that was in front when the picker opened: a site command is
  -- only listed then, and by the time it runs the picker has focus.
  local function frontBrowser(ctx)
    local name = ctx and ctx.frontmostApp
    if not M.isBrowser(name) then
      hs.alert.show("No browser in front")
      return nil
    end
    return name
  end

  local function openURL(url, title, ctx)
    cl.executeCommand("system.open", { target = url, title = title }, ctx)
  end

  -- A fresh table each time: a command's inputs are its own.
  local function urlInput()
    return { { id = "url", picker = { when = "viewItem == 'url'" } } }
  end

  -- A tab, asked from every running browser's tabs, as `recent` lists them.
  local function tabInput()
    return { { id = "url", description = "Which tab",
               picker = { menus = { "recent" }, when = "viewItem == 'url' && tabIn" } } }
  end

  -- The page in front, while a browser is.
  local function frontPage(ctx)
    if ctx and type(ctx.url) == "string" and ctx.url ~= "" then
      return { kind = "url", value = ctx.url, name = ctx.pageTitle, tabIn = ctx.frontmostApp }
    end
  end

  local function queryInput(description)
    return { { id = "query", description = description, picker = { typed = true },
               fromQuery = true, encode = "query" } }
  end

  -- A site's command given a tab that is not the page in front brings that
  -- tab forward first -- the same Apple Events a tab row uses -- and acts
  -- once it is; a tab gone since says so rather than acting on another.
  -- Given the page in front, or nothing, it acts at once.
  local function onTab(args, ctx, act)
    -- The command that finally runs fills its args, from answers in `ctx`.
    local function arg(value) return type(value) == "string" and cl.resolve(value, ctx) or nil end
    local url, app = arg(args.url), arg(args.app)
    if type(url) ~= "string" or url == "" or url == (ctx and ctx.url) or not M.isBrowser(app) then
      local name = frontBrowser(ctx)
      if name then act(name) end
      return
    end
    cl.tools.run("/usr/bin/osascript", { "-e", M.switchScript(app, url) }, function(code, stdout, stderr)
      if code ~= 0 then return M.reportRefusal(app, stderr) end
      if not tostring(stdout):find("found", 1, true) then
        return hs.alert.show("That tab is no longer open")
      end
      act(app)
    end)
  end

  local commands = {
    { id = "browser.keys", title = "Press a site's keys", menus = {},
      run = function(args, ctx)
        onTab(args, ctx, function(name)
        local mods, key = cl.chord(args.keys)
        if not key then return end
        -- Secure Input drops the keystroke without a sound, so it is said.
        local secure = cl.extension("secureinput")
        if secure and secure.warn(tostring(args.keys) .. " was not pressed", ctx) then return end
        local app = M.runningApp(name)
        if app then app:activate() end
        -- Once the picker has closed and the browser is key again; sooner and
        -- the keystroke lands in the picker.
        cl.after(0.1, function() hs.eventtap.keyStroke(mods, key, 0) end)
        end)
      end },

    -- In the tab, through osascript in a process of its own. The browser has
    -- to allow JavaScript from Apple Events, which is off by default, so a
    -- refusal says where to switch it on.
    { id = "browser.js", title = "Run JavaScript in the page", menus = {},
      run = function(args, ctx)
        if type(args.js) ~= "string" then return end
        onTab(args, ctx, function(name)
        local js = (args.js:gsub("\\", "\\\\"):gsub('"', '\\"'))
        local source
        if M.safari[name] then
          source = ('tell application %q to do JavaScript "%s" in front document'):format(name, js)
        else
          source = ('tell application %q to execute active tab of front window javascript "%s"')
                   :format(name, js)
        end
        local where = M.safari[name] and "the Develop menu" or "View > Developer"
        cl.tools.run("/usr/bin/osascript", { "-e", source }, function(code, _, stderr)
          if code ~= 0 then
            hs.alert.show("Allow JavaScript from Apple Events in " .. name .. ", " .. where)
            cl.log.e("browser.js in " .. name .. " -> " .. tostring(stderr))
          end
        end)
        end)
      end },

    -- Opening a tab's URL makes a second copy of it. The tab is looked up by
    -- URL when picked rather than kept by index, since tabs move and close
    -- between the answer and the pick; one no longer open is opened instead.
    { id = "browser.tab", title = "Go to tab", menus = {},
      run = function(args, ctx)
        local function openInstead() openURL(args.url, args.title, ctx) end
        if not M.isBrowser(args.app) or type(args.url) ~= "string" then
          return openInstead()
        end
        local task = cl.tools.run("/usr/bin/osascript", { "-e", M.switchScript(args.app, args.url) },
          function(code, stdout, stderr)
            if code ~= 0 then
              M.reportRefusal(args.app, stderr)
              return openInstead()
            end
            if not tostring(stdout):find("found", 1, true) then openInstead() end
          end)
        if not task then openInstead() end
      end },

    -- Verbs every URL has, whatever produced it. Anything more specific --
    -- cloning a repository, say -- belongs to whichever extension knows what
    -- that URL means.
    { id = "browser.goToTab", title = "Go to tab",
      menus = { ["view/item/context"] = { when = "tabIn" }, commandPalette = true }, inputs = tabInput(),
      run = function(args, ctx)
        local url = args.url
        if type(url) ~= "table" then return end
        cl.executeCommand("browser.tab", { url = url.value, app = url.tabIn, title = url.name }, ctx)
      end },
    { id = "browser.openInNewTab", title = "Open in new tab",
      menus = { ["view/item/context"] = { when = "tabIn" }, commandPalette = true }, inputs = tabInput(),
      run = function(args, ctx)
        if type(args.url) == "table" then openURL(args.url.value, args.url.name, ctx) end
      end },
    { id = "browser.openInBrowser", title = "Open in browser",
      menus = { ["view/item/context"] = { when = "!tabIn" } }, inputs = urlInput(),
      run = function(args, ctx)
        if type(args.url) == "table" then openURL(args.url.value, args.url.name, ctx) end
      end },
    { id = "browser.copyURL", title = "Copy URL",
      menus = { ["view/item/context"] = true, commandPalette = true, context = { when = "url" } },
      inputs = { { id = "url", description = "Which page",
                   picker = { menus = { "recent" }, when = "viewItem == 'url'" },
                   current = frontPage, preferCurrent = true } },
      run = function(args, ctx)
        if type(args.url) == "table" then
          cl.executeCommand("system.copy", { text = args.url.value }, ctx)
        end
      end },
  }

  local sites = M.readSites(M.sitesFile)
  for _, site in ipairs(M.sitesFrom(cl.userDir and (cl.userDir .. "/sites"))) do
    sites[#sites + 1] = site
  end
  for _, command in ipairs(M.siteCommands(sites, frontPage)) do commands[#commands + 1] = command end

  -- Searches that take what you typed: reached with "?" and the text, with
  -- a prefix of their own, or offered when nothing else matches.
  commands[#commands + 1] = {
    id = "browser.searchWeb", title = "Search the web for “${query}”", prefix = "search ",
    icon = "$(search)", menus = { "commandPalette" },
    inputs = queryInput("Search the web"),
    run = function(_, ctx)
      openURL(cl.setting("browser", "searchURL"), "Search the web", ctx)
    end,
  }
  commands[#commands + 1] = {
    id = "browser.searchYouTube", title = "Search YouTube for “${query}”", prefix = "youtube ",
    icon = "$(play-circle)", menus = { "commandPalette" },
    inputs = queryInput("Search YouTube"),
    command = "system.open",
    args = { target = "https://www.youtube.com/results?search_query=${query}",
             title = "Search YouTube" },
  }

  return {
    name  = "browser",
    rank  = 0.86,
    -- Its capture reads frontmostApp.
    after = { "ambient" },
    optionalExtensionDependencies = { "secureinput" },
    -- The front tab is context, so it belongs where context belongs.
    -- Tabs are nouns you go to, hence the root as well.
    menus = { "root", "context", "commandPalette", "recent" },

    commands = commands,

    settings = {
      tabs      = { type = "boolean", description = "Open tabs", default = true },
      tabOrder  = { type = "string", description = "Order tabs by", default = "recent",
                    enum = { "recent", "browser" },
                    enumDescriptions = { "When each was last active, from the browser's session file",
                                         "The browser's own order" } },
      bookmarks = { type = "boolean", description = "Bookmarks", default = true },
      history   = { type = "boolean", description = "History",   default = true },
      recentTabs     = { type = "integer", default = 10,
                         description = "How many tabs the recent picker lists" },
      historyLimit   = { type = "integer", default = 300,
                         description = "How many pages of history are read from each browser" },
      historySeconds = { type = "integer", default = 120,
                         description = "Seconds between reading history and bookmarks again" },
      searchURL      = { type = "string", default = "https://search.brave.com/search?q=${query}",
                         description = "Where searching the web goes; ${query} is what you typed" },
    },

    -- The page in front, for `when` clauses like `url =~ /youtube%.com/`.
    -- From the last answer, so building a context never waits on a browser.
    capture = function(ctx)
      local tab = M.frontTab(ctx.frontmostApp)
      if tab then ctx.url, ctx.pageTitle = tab.url, tab.title end
      -- Kept, so an answer that lands after the picker opened can fill in
      -- the context its rows are rebuilt with; otherwise a site's commands
      -- would stay hidden until the launcher is opened again.
      if M.isBrowser(ctx.frontmostApp) then M.pendingCtx = ctx end
    end,

    subjects = function(ctx)
      local tab = M.frontTab(ctx.frontmostApp)
      if not tab then return {} end

      return {
        {
          kind  = "url",
          value = tab.url,
          name  = tab.title,
          label = "This page",
        },
      }
    end,

    items = function(ctx, opts)
      local rows = {}
      -- A question asking from `recent` alone -- which tab -- lists what that
      -- picker would, whichever picker it was asked from.
      local asked = opts and opts.menus
      local fromRecent = type(asked) == "table" and #asked == 1 and asked[1] == "recent"
      local menu = fromRecent and "recent" or ctx.activeView

      -- The context picker is about the app in front: with no browser there,
      -- tabs, bookmarks and history are not its context.
      if menu == "context" and not M.isBrowser(ctx.frontmostApp) then return rows end

      -- The recent picker is opened from anywhere, so it lists the tabs of
      -- every running browser; elsewhere only the browser in front is asked.
      local browsers
      if menu == "recent" then
        browsers = M.runningBrowsers(ctx.frontmostApp)
      else
        browsers = M.isBrowser(ctx.frontmostApp) and { ctx.frontmostApp } or {}
      end

      if on("tabs") then
        local all = {}
        for _, app in ipairs(browsers) do
          for _, tab in ipairs(M.tabs(app, app ~= ctx.frontmostApp)) do
            all[#all + 1] = { url = tab.url, title = tab.title, app = app }
          end
        end
        local order = cl.setting("browser", "tabOrder")
        local ordered = M.orderTabs(all, order)
        -- In a browser, the tab you are on is the one you least want: it goes
        -- last, so the first is the tab you were on before it, as alt-tab
        -- puts the previous window first.
        local current = order == "recent" and M.isBrowser(ctx.frontmostApp)
                        and M.frontTab(ctx.frontmostApp, true)
        if current then
          local others, onIt = {}, {}
          for _, tab in ipairs(ordered) do
            if tab.app == ctx.frontmostApp and tab.url == current.url then
              onIt[#onIt + 1] = tab
            else
              others[#others + 1] = tab
            end
          end
          for _, tab in ipairs(onIt) do others[#others + 1] = tab end
          ordered = others
        end
        local limit = menu == "recent" and cl.setting("browser", "recentTabs")
        for _, tab in ipairs(ordered) do
          if limit and #rows >= limit then break end
          rows[#rows + 1] = {
            label       = tab.title,
            description = "Tab -- " .. tab.url,
            keywords    = { tab.url },
            command     = "browser.tab",
            args        = { url = tab.url, app = tab.app, title = tab.title },
            ctx         = ctx,
            subject     = { kind = "url", value = tab.url, name = tab.title, tabIn = tab.app },
            -- Below projects, apps and windows: in the root, tabs led the list
            -- before anything was typed, and typing rarely means a tab.
            rank        = 0.34,
          }
        end
      end

      -- Recent is about what you were doing: tabs, not every page you have
      -- kept or visited. The context picker takes all of them, with the
      -- recent tabs its first section.
      if menu == "recent" then return rows end

      -- Bookmarks before history: you kept these on purpose.
      if on("bookmarks") then
        for _, row in ipairs(M.rowsFor(M.bookmarks(), bookmarkRow)) do
          row.ctx = ctx
          rows[#rows + 1] = row
        end
      end

      if on("history") then
        for _, row in ipairs(M.rowsFor(M.history(), historyRow)) do
          row.ctx = ctx
          rows[#rows + 1] = row
        end
      end

      return rows
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
