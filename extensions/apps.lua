-- Every installed application, and which you used most recently.
--
-- A live hs.spotlight query keeps itself current and hands back the
-- bundle id, which is the only identity the catalogue and the running
-- process agree on -- VS Code is "Visual Studio Code" to one and "Code"
-- to the other. Empty if Spotlight indexing is off.

local M = {}

local layer

local byName   = {}   -- display name -> { name, path, bundleID, icon }
local byBundle = {}   -- bundle id    -> the same entry
local sorted   = {}
local dirty    = true

local watcher, spotlight

local function setting(key)
  return (layer.setting("apps", key))
end

local function expand(path)
  return (path:gsub("^~", os.getenv("HOME")))
end

-- Recorded here, against the rule of dispatching to what already keeps a
-- thing: no tool keeps an app-activation history, and it is what finds an
-- app you quit by a name you forgot. macOS's own recents list is a binary
-- .sfl2 plist that is version-fragile to parse.
local SETTINGS_KEY = "commandlayer.appMRU"

-- Entries are { name = , id = }; older settings held bare strings, which
-- are read as name-only and rewritten on first touch.
local mru = {}

local function loadMRU()
  local list = {}
  for _, entry in ipairs(hs.settings.get(SETTINGS_KEY) or {}) do
    if type(entry) == "string" then
      list[#list + 1] = { name = entry }
    elseif type(entry) == "table" and entry.name then
      list[#list + 1] = entry
    end
  end
  return list
end

local function ignored(name)
  for _, other in ipairs(setting("ignoreApps") or {}) do
    if other == name then return true end
  end
  return false
end

local function touch(name, id)
  if not name or name == "" then return end
  if ignored(name) then return end

  for i, existing in ipairs(mru) do
    if (id and existing.id == id) or existing.name == name then
      table.remove(mru, i)
      break
    end
  end

  table.insert(mru, 1, { name = name, id = id })

  local limit = setting("mruLimit")
  while #mru > limit do
    table.remove(mru)
  end

  hs.settings.set(SETTINGS_KEY, mru)
end

-- Returns apps in most-recently-used order, marking which are running.
function M.apps()
  local running = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 then
      running[app:bundleID() or app:name()] = app
    end
  end

  local items = {}
  for _, entry in ipairs(mru) do
    local key = entry.id or entry.name
    items[#items + 1] = {
      name    = entry.name,
      id      = entry.id,
      running = running[key] ~= nil,
      app     = running[key],
    }
    running[key] = nil
  end

  -- Anything running that the MRU has not seen yet.
  for key, app in pairs(running) do
    items[#items + 1] = {
      name    = app:name(),
      id      = app:bundleID() or key,
      running = true,
      app     = app,
    }
  end

  return items
end

local function modify(items, add)
  for _, item in ipairs(items) do
    local path = item.kMDItemPath
    local name = item.kMDItemDisplayName
                 or (path and hs.fs.displayName(path))
                 or (path and path:match("([^/]+)%.app$"))

    if name then
      name = name:gsub("%.app$", "", 1)
      local id = item.kMDItemCFBundleIdentifier

      if add then
        local app = { name = name, path = path, bundleID = id }
        byName[name] = app
        if id then byBundle[id] = app end
      else
        byName[name] = nil
        if id then byBundle[id] = nil end
      end
      dirty = true
    end
  end
end

-- All three kinds of change can arrive in either message, so check for
-- each of them every time.
local function onUpdate(_, _, info)
  if not info then return end
  if info.kMDQueryUpdateAddedItems   then modify(info.kMDQueryUpdateAddedItems,   true)  end
  if info.kMDQueryUpdateChangedItems then modify(info.kMDQueryUpdateChangedItems, true)  end
  if info.kMDQueryUpdateRemovedItems then modify(info.kMDQueryUpdateRemovedItems, false) end
end

function M.start()
  if watcher or not layer then return M end

  mru = loadMRU()

  -- Two independent things: the watcher records what you use, the
  -- Spotlight query records what you have.
  watcher = layer.watch(hs.application.watcher.new(function(name, event, app)
    if event == hs.application.watcher.activated then
      touch(name, app and app:bundleID())
    end
  end))

  -- Makes hs.application's name lookups consult Spotlight too, so
  -- launching by name finds apps outside the usual directories.
  hs.application.enableSpotlightForNameSearches(true)

  local scopes = {}
  for _, path in ipairs(setting("searchPaths") or {}) do
    scopes[#scopes + 1] = expand(path)
  end

  spotlight = layer.watch(hs.spotlight.new()
    :queryString([[ (kMDItemContentType = "com.apple.application-bundle") ]])
    :callbackMessages("didUpdate", "inProgress")
    :setCallback(onUpdate)
    :searchScopes(scopes))

  return M
end

function M.stop()
  for _, d in ipairs({ watcher or false, spotlight or false }) do
    if d then d.dispose() end
  end
  watcher, spotlight = nil, nil
  byName, byBundle, sorted, dirty = {}, {}, {}, true
  return M
end

-- Re-sorted only when Spotlight says something changed.
function M.all()
  if dirty then
    sorted = {}
    for _, app in pairs(byName) do sorted[#sorted + 1] = app end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    dirty = false
  end
  return sorted
end

function M.get(nameOrID)
  if not nameOrID then return nil end
  return byBundle[nameOrID] or byName[nameOrID]
end

-- Resolved on first use and kept on the entry.
function M.icon(app)
  if app.icon == nil then
    app.icon = (app.bundleID and hs.image.imageFromAppBundle(app.bundleID))
               or (app.path and hs.image.iconForFile(app.path))
               or false
  end
  return app.icon or nil
end

-- A running app by bundle id, else by name among the running apps. Never
-- hs.application.get: a name matching no app sends it on to search every
-- window's title, which takes about a second.
function M.running(id, name)
  if id and hs.application.applicationsForBundleID then
    local found = hs.application.applicationsForBundleID(id)
    if found and found[1] then return found[1] end
  end
  if name then
    for _, app in ipairs(hs.application.runningApplications() or {}) do
      if app:name() == name then return app end
    end
  end
  return nil
end

-- Judged by the context the layer was entered with: once a picker is up,
-- Hammerspoon is the app in front.
function M.inFront(app, ctx)
  if type(ctx) == "table" and ctx.frontmostAppID then return ctx.frontmostAppID == app:bundleID() end
  if type(ctx) == "table" and ctx.frontmostApp then return ctx.frontmostApp == app:name() end
  local front = hs.application.frontmostApplication()
  return front ~= nil and front:bundleID() == app:bundleID() and front:name() == app:name()
end

function M.extension(cl)
  layer = cl
  cl.tools.register("open", { "/usr/bin/open" })

  -- Three identities, tried best first. The bundle id is the only one that
  -- always works: an app's display name and its running-process name can
  -- differ (VS Code is "Visual Studio Code" to Spotlight and "Code" to
  -- NSRunningApplication), and launching by the wrong one fails silently.
  local function open(args, ctx)
    if args.id and hs.application.launchOrFocusByBundleID(args.id) then return end

    local target = cl.resolve(args.target, ctx)
    if not target or target == "" then
      hs.alert.show("No such application")
      return
    end

    if hs.application.launchOrFocus(target) then return end

    -- Launch Services knows about apps neither lookup found. The callback
    -- matters: without it a failure is silent.
    cl.tools.run(cl.tools.path("open") or "/usr/bin/open", { "-a", target }, function(code, _, stderr)
      if code ~= 0 then
        hs.alert.show("Could not open " .. tostring(args.name or target))
        cl.log.e("open -a " .. tostring(target) .. " -> " .. tostring(stderr))
      end
    end)
  end

  -- The names an app is known by beside the one shown -- VS Code is "Code"
  -- running and Visual Studio Code.app on disk -- and its bundle id.
  local function namesOf(label, app)
    local names, seen = {}, { [label] = true }
    local function add(name)
      if type(name) == "string" and name ~= "" and not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
    add(app.name)
    add(type(app.path) == "string" and app.path:match("([^/]+)%.app/?$") or nil)
    add(app.id)
    return names
  end

  local function appRow(ctx, label, description, app, icon)
    return {
      label       = label,
      description = description,
      keywords    = namesOf(label, app),
      command     = "apps.open",
      args        = { id = app.id, target = app.path or app.name, name = app.name },
      subject     = { kind = "app", name = app.name, id = app.id, path = app.path },
      iconPath    = icon,
      ctx         = ctx,
    }
  end

  -- The app you were in as the layer opened; never Hammerspoon itself.
  local function frontApp(ctx)
    local id = ctx and ctx.frontmostAppID
    if id and id ~= "org.hammerspoon.Hammerspoon" then
      return { kind = "app", id = id, name = ctx.frontmostApp }
    end
  end

  -- The running apps by bundle id and name, read once per context a clause is
  -- asked in -- a question lists every app row -- never per row.
  local runningIn = setmetatable({}, { __mode = "k" })
  cl.itemContextKey("appRunning", function(subject, ctx)
    local set = ctx and runningIn[ctx]
    if not set then
      set = {}
      for _, app in ipairs(hs.application.runningApplications() or {}) do
        local bundle, name = app:bundleID(), app:name()
        if bundle then set[bundle] = true end
        if name then set[name] = true end
      end
      if ctx then runningIn[ctx] = set end
    end
    return (subject.id ~= nil and set[subject.id]) or (subject.name ~= nil and set[subject.name]) or false
  end)

  -- A verb on an app row's cmd+k. One doing something other than what picking
  -- the row does is a palette row too, asking which app; with `current` it
  -- takes the app you were in, and is in cmd+. for that app.
  local function verb(id, title, run, opts)
    opts = opts or {}
    local menus = { ["view/item/context"] = opts.when and { when = opts.when } or true }
    if opts.searchable then
      menus.commandPalette = true
      if opts.current then menus.context = { when = "frontmostAppID" } end
    end
    return {
      id = "apps." .. id, title = title, category = "App",
      menus = menus,
      inputs = { { id = "app", description = "Which app",
                   picker = { menus = { "root" }, when = opts.asks or "viewItem == 'app'" },
                   current = opts.current, preferCurrent = opts.current ~= nil } },
      run = function(args, ctx)
        if type(args.app) == "table" then run(args.app, ctx) end
      end,
    }
  end

  return {
    name     = "apps",
    rank     = 0.29,
    menus = { "root", "commandPalette", "recent" },

    settings = {
      searchPaths = { type = "array",
        default = { "/Applications", "/System/Applications", "~/Applications",
                    "/System/Library/CoreServices/Applications",
                    "/Applications/Xcode.app/Contents/Applications" },
        description = "The folders apps are listed from" },
      mruLimit = { type = "integer", default = 30,
        description = "How many apps to remember having used" },
      ignoreApps = { type = "array", default = { "Hammerspoon", "loginwindow" },
        description = "Apps never recorded as used" },
      confirmQuit = { type = "boolean", default = true,
        description = "Ask before quitting an app" },
    },

    commands = {
      { id = "apps.open", title = "Open app", menus = {}, run = open },

      verb("launchOrFocus", "Launch or focus", function(app, ctx)
        cl.executeCommand("apps.open", { id = app.id, target = app.path or app.name, name = app.name }, ctx)
      end),
      (function()
        local quit = verb("quit", "Quit", function(app)
          local running = M.running(app.id, app.name)
          if running then running:kill() else hs.alert.show("Not running") end
        end, { searchable = true, asks = "viewItem == 'app' && appRunning", current = frontApp })
        quit.targetName = "${input:app.name}"
        quit.confirm = function(args)
          if cl.setting("apps", "confirmQuit") == false then return nil end
          local name = type(args.app) == "table" and args.app.name
          return name and ("Quit " .. name .. "?") or "Quit this app?"
        end
        return quit
      end)(),
      -- For a key more than a row: args = { app = { id = "com.apple.Terminal" } }.
      verb("toggle", "Toggle", function(app, ctx)
        local running = M.running(app.id, app.name)
        if not running then
          cl.executeCommand("apps.open", { id = app.id, target = app.path or app.name, name = app.name }, ctx)
        elseif M.inFront(running, ctx) then
          running:hide()
        else
          running:activate()
        end
      end),
      verb("hide", "Hide", function(app)
        local running = M.running(app.id, app.name)
        if running then running:hide() end
      end, { searchable = true, asks = "viewItem == 'app' && appRunning", current = frontApp }),
      verb("revealInFinder", "Reveal in Finder", function(app, ctx)
        cl.executeCommand("system.reveal", { target = app.path }, ctx)
      end, { when = "path", searchable = true, asks = "viewItem == 'app' && path" }),
    },

    items = function(ctx)
      local items = {}
      -- In recent, only apps you used, below the projects, tabs and windows
      -- that recent is mostly for; never the whole catalogue.
      local recentOnly = ctx.activeView == "recent"

      -- Used first, and dedup keeps the first, so the catalogue below
      -- never repeats one of these under its other name.
      for _, a in ipairs(M.apps()) do
        local known = M.get(a.id) or M.get(a.name)
        local row = appRow(ctx, (known and known.name) or a.name,
          a.running and "App -- running" or "App -- recent",
          { id = a.id, path = known and known.path, name = a.name },
          known and M.icon(known) or nil)
        row.rank = recentOnly and 0.14 or 0.57
        items[#items + 1] = row
      end

      if recentOnly then return items end

      for _, app in ipairs(M.all()) do
        items[#items + 1] = appRow(ctx, app.name, "App",
          { id = app.bundleID, path = app.path, name = app.name }, M.icon(app))
      end
      return items
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
