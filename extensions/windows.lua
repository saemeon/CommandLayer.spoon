-- Windows: the ones open, front to back -- an alt-tab inside the launcher --
-- and what can be done to one: focus, close, minimise, and moving it, which
-- the tool `windows.provider` names does.
--
-- Windows on another Space may be missing. Seeing those takes private
-- window-server APIs, which is what AltTab uses.
--
-- A command taking a window asks which when picked from search, has one
-- already on a window row's cmd+k, and run by a chord or by id takes the
-- window that was in front, captured when the layer opened -- by the time
-- you choose, the picker has focus and the window you meant does not.

local M = {}

local HAMMERSPOON = "org.hammerspoon.Hammerspoon"

local layer

local icons = {}

local function iconFor(bundleID)
  if not bundleID then return nil end
  if icons[bundleID] == nil then
    icons[bundleID] = hs.image.imageFromAppBundle(bundleID) or false
  end
  return icons[bundleID] or nil
end

-- What `windows.source` names. Each asks every app for its windows on
-- Hammerspoon's one thread, so a list is read when rows are built, never at
-- start and never watched.
M.sources = {
  -- Not hs.window.allWindows: it asks every running app, background services
  -- too, and one busy with the keyboard -- Karabiner's core service -- takes
  -- its 1.5 s accessibility timeout to answer while a picker is on screen. So
  -- every window on screen, whatever its app, and every window of the apps in
  -- the Dock, minimised or on another Space.
  all     = function()
    local windows, seen = {}, {}
    local function add(win)
      local ok, id = pcall(function() return win:id() end)
      if ok and id and not seen[id] then
        seen[id] = true
        windows[#windows + 1] = win
      end
    end
    for _, win in ipairs(hs.window.orderedWindows() or {}) do add(win) end
    for _, app in ipairs(hs.application.runningApplications() or {}) do
      if app:kind() == 1 then
        local ok, owned = pcall(function() return app:allWindows() end)
        for _, win in ipairs(ok and type(owned) == "table" and owned or {}) do add(win) end
      end
    end
    return windows
  end,
  ordered = function() return hs.window.orderedWindows() end,
  visible = function() return hs.window.visibleWindows() end,
}
local SOURCES = { "all", "ordered", "visible" }

-- Front to back by the window server's order of ids, which costs little
-- beside the lists. It is private to Hammerspoon, so without it a list keeps
-- its own order; a window not in it -- minimised, on another Space -- follows
-- the rest in the list's order.
local function frontToBack(windows)
  local lookup = hs.window._orderedwinids
  local ok, ids = false, nil
  if type(lookup) == "function" then ok, ids = pcall(lookup) end
  if not ok or type(ids) ~= "table" then return windows end
  local place = {}
  for i, id in ipairs(ids) do place[id] = i end
  local keyed = {}
  for i, win in ipairs(windows) do
    local known, id = pcall(function() return win:id() end)
    keyed[i] = { win = win, place = known and place[id] or math.huge, index = i }
  end
  table.sort(keyed, function(a, b)
    if a.place ~= b.place then return a.place < b.place end
    return a.index < b.index
  end)
  local out = {}
  for i, entry in ipairs(keyed) do out[i] = entry.win end
  return out
end

-- Every title and owning app is an accessibility call. nil for Hammerspoon's
-- own windows.
local function describe(win)
  local id = win:id()
  if not id then return nil end
  local app = win:application()
  local bundleID = app and app:bundleID()
  if bundleID == HAMMERSPOON then return nil end
  return { id = id, app = (app and app:name()) or "", bundleID = bundleID,
           title = win:title() or "", win = win }
end

-- Reading the windows taking this long says in the console what took it.
M.slowSeconds = 0.25

-- The lists read for this open, by source, until a turn later: the sections
-- of one open each gather windows, each view through a context of its own.
local listings, listingTimer = {}, nil

-- The window objects last listed, by id.
local byId = {}

function M.forget()
  if listingTimer then listingTimer.dispose() end
  listings, listingTimer = {}, nil
end

-- What windows.sourceByPicker names for the picker gathering, else
-- windows.source. A name that is not a source is a problem at setup, and here
-- the default.
function M.sourceFor(ctx)
  local byPicker = layer.setting("windows", "sourceByPicker")
  local chosen = type(byPicker) == "table" and ctx and ctx.activeView and byPicker[ctx.activeView]
  if chosen and M.sources[chosen] then return chosen end
  local source = layer.setting("windows", "source")
  return M.sources[source] and source or "ordered"
end

function M.start()
  if not layer then return M end
  local provider = M.provider
  if provider and not provider.always then
    local installed = provider.installed(layer) == true
    layer.setContext("windowProviderInstalled", installed)
    if not installed then
      layer.problem(("windows.provider is %q, which is not installed, so no window moves are offered")
                    :format(provider.name))
    end
  end
  return M
end

function M.stop()
  M.forget()
  byId, icons = {}, {}
  return M
end

function M.windows(ctx)
  local source = M.sourceFor(ctx)
  if listings[source] then return listings[source] end
  -- Every read below waits on an app answering; one busy app holds up the
  -- open, and the kernel's slow line cannot say which app it was.
  local clock = hs.timer.secondsSinceEpoch
  local started = clock()
  local ok, windows = pcall(M.sources[source])
  if not ok then layer.log.e("windows: the " .. source .. " list -> " .. tostring(windows)) end
  windows = ok and type(windows) == "table" and windows or {}
  if source ~= "ordered" then windows = frontToBack(windows) end
  local listed = clock()

  local out, limit = {}, layer.setting("windows", "limit")
  local slowest, slowestApp = 0, nil
  byId = {}
  for _, win in ipairs(windows) do
    if #out >= limit then break end
    -- A window that cannot be read is skipped, not the rest after it.
    local before = clock()
    local read, entry = pcall(describe, win)
    local took = clock() - before
    if took > slowest then slowest, slowestApp = took, read and entry and entry.bundleID or "a window not listed" end
    if read and entry then
      out[#out + 1] = entry
      byId[entry.id] = win
    end
  end
  local total = clock() - started
  if total >= M.slowSeconds then
    layer.log.w(("windows: reading the %s list took %.0f ms: %.0f ms listing, the slowest window %.0f ms (%s)")
                :format(source, total * 1000, (listed - started) * 1000, slowest * 1000, tostring(slowestApp)))
  end
  listings[source] = out
  if not listingTimer then
    listingTimer = layer.after(0, function() listings, listingTimer = {}, nil end)
  end
  return out
end

-- The window object last listed, not hs.window.get: that walks every window
-- of every app to find one id, which was the wait between picking a window
-- and seeing it come forward. An id not listed -- one in a keybinding --
-- still falls back to the search.
function M.window(id)
  return byId[id] or hs.window.get(id)
end

-- `target` is a window subject -- carrying the window object itself when it
-- came from what was in front -- or a bare id.
local function withWindow(target, fn)
  local win
  if type(target) == "table" then
    win = target.window or (target.id and M.window(target.id))
  else
    win = target and M.window(target)
  end
  if not win then
    hs.alert.show("That window is gone")
    return
  end
  fn(win)
end

----------------------------------------------------------------------
-- MOVING ONE
----------------------------------------------------------------------

-- x, y, w, h in fractions of the screen.
local LAYOUTS = {
  { title = "Maximise",        unit = { 0,    0,    1,    1    }, icon = "$(screen-full)" },
  { title = "Left half",       unit = { 0,    0,    0.5,  1    }, icon = "$(layout-sidebar-left)" },
  { title = "Right half",      unit = { 0.5,  0,    0.5,  1    }, icon = "$(layout-sidebar-right)" },
  { title = "Top half",        unit = { 0,    0,    1,    0.5  } },
  { title = "Bottom half",     unit = { 0,    0.5,  1,    0.5  } },
  { title = "Left third",      unit = { 0,    0,    1/3,  1    } },
  { title = "Middle third",    unit = { 1/3,  0,    1/3,  1    } },
  { title = "Right third",     unit = { 2/3,  0,    1/3,  1    } },
  { title = "Left two thirds", unit = { 0,    0,    2/3,  1    } },
  { title = "Top left",        unit = { 0,    0,    0.5,  0.5  } },
  { title = "Top right",       unit = { 0.5,  0,    0.5,  0.5  } },
  { title = "Bottom left",     unit = { 0,    0.5,  0.5,  0.5  } },
  { title = "Bottom right",    unit = { 0.5,  0.5,  0.5,  0.5  } },
  { title = "Centre",          unit = { 0.15, 0.1,  0.7,  0.8  } },
}

-- Chromium and Electron apps -- Brave, VS Code, Slack -- turn on
-- AXEnhancedUserInterface once anything on the machine uses accessibility,
-- and while it is on the app animates every frame change itself, so a
-- layout lands late. Off for the move, and back on after.
local function withoutEnhancedUI(win, fn)
  local app = win:application()
  local ax = app and hs.axuielement and hs.axuielement.applicationElement(app)
  local was = ax and ax:attributeValue("AXEnhancedUserInterface")
  if was then ax:setAttributeValue("AXEnhancedUserInterface", false) end
  local ok, err = pcall(fn)
  if was then ax:setAttributeValue("AXEnhancedUserInterface", true) end
  if not ok then error(err, 0) end
end

local function duration()
  return (layer.setting("windows", "animationDuration"))
end

local function place(win, unit)
  if not win then
    hs.alert.show("No window")
    return
  end
  withoutEnhancedUI(win, function()
    win:moveToUnit({ x = unit[1], y = unit[2], w = unit[3], h = unit[4] }, duration())
  end)
end

local function toScreen(win, direction)
  if not win then
    hs.alert.show("No window")
    return
  end

  local screen = win:screen()
  local target = (direction == "next") and screen:next() or screen:previous()
  if target and target ~= screen then
    withoutEnhancedUI(win, function()
      win:moveToScreen(target, false, true, duration())
    end)
  end
end

----------------------------------------------------------------------
-- WHO MOVES IT
----------------------------------------------------------------------

-- A provider is data: for each move, by our name -- a layout by the slug of
-- its title, nextScreen, previousScreen, fullScreen -- the tool's own
-- action, and `send`, how an action reaches the tool. A move a provider has
-- no action for is no command while that provider is chosen: nothing does
-- it another way. Layouts in windows.layouts map by name, so a layout of
-- your own reaches another tool only under a name listed here.
--
-- Centre is 70% by 80% of the screen. Raycast's and Rectangle's Center keep
-- the window's size, which is another move, so neither is mapped to it.
--
-- `frontWindow`: the tool moves the window in front, so a window chosen
-- from the list is focused first.
local function grid(rows, cols, x, y, w, h)
  return { "--grid", ("%d:%d:%d:%d:%d:%d"):format(rows, cols, x, y, w, h) }
end

M.providers = {
  hammerspoon = {
    title = "Hammerspoon",
    installed = function() return true end,
    always = true,
    -- Every layout, by its unit.
    layoutUnits = true,
    actions = { nextScreen = "next", previousScreen = "previous", fullScreen = "fullScreen" },
    send = function(_, action, target)
      if type(action) == "table" then return place(target.window, action) end
      if action == "fullScreen" then return target.window:toggleFullScreen() end
      return toScreen(target.window, action)
    end,
  },

  -- Raycast's Window Management commands, by their deeplinks.
  raycast = {
    title = "Raycast",
    installed = function(cl)
      local raycast = cl.extension("raycast")
      return raycast ~= nil and raycast.installed() == true
    end,
    frontWindow = true,
    actions = {
      maximise = "maximize",
      leftHalf = "left-half", rightHalf = "right-half", topHalf = "top-half", bottomHalf = "bottom-half",
      leftThird = "first-third", middleThird = "center-third", rightThird = "last-third",
      leftTwoThirds = "first-two-thirds", rightTwoThirds = "last-two-thirds",
      topLeft = "top-left-quarter", topRight = "top-right-quarter",
      bottomLeft = "bottom-left-quarter", bottomRight = "bottom-right-quarter",
      nextScreen = "next-display", previousScreen = "previous-display",
      fullScreen = "toggle-fullscreen",
    },
    send = function(cl, action, _, ctx)
      return cl.executeCommand("raycast.open",
        { target = "raycast://extensions/raycast/window-management/" .. action }, ctx)
    end,
  },

  -- Rectangle's URL scheme. It has no full screen.
  rectangle = {
    title = "Rectangle",
    bundleID = "com.knollsoft.Rectangle",
    installed = function()
      return hs.application.pathForBundleID(M.providers.rectangle.bundleID) ~= nil
    end,
    frontWindow = true,
    actions = {
      maximise = "maximize",
      leftHalf = "left-half", rightHalf = "right-half", topHalf = "top-half", bottomHalf = "bottom-half",
      leftThird = "first-third", middleThird = "center-third", rightThird = "last-third",
      leftTwoThirds = "first-two-thirds", rightTwoThirds = "last-two-thirds",
      topLeft = "top-left", topRight = "top-right", bottomLeft = "bottom-left", bottomRight = "bottom-right",
      nextScreen = "next-display", previousScreen = "previous-display",
    },
    send = function(cl, action, _, ctx)
      return cl.executeCommand("system.open", { target = "rectangle://execute-action?name=" .. action }, ctx)
    end,
  },

  -- yabai -m window [id] <action>. A grid is rows:cols:x:y:w:h, which
  -- yabai applies to a floating window.
  yabai = {
    title = "yabai",
    installed = function(cl) return cl.tools.path("yabai") ~= nil end,
    actions = {
      maximise = grid(1, 1, 0, 0, 1, 1),
      leftHalf = grid(1, 2, 0, 0, 1, 1), rightHalf = grid(1, 2, 1, 0, 1, 1),
      topHalf = grid(2, 1, 0, 0, 1, 1), bottomHalf = grid(2, 1, 0, 1, 1, 1),
      leftThird = grid(1, 3, 0, 0, 1, 1), middleThird = grid(1, 3, 1, 0, 1, 1),
      rightThird = grid(1, 3, 2, 0, 1, 1),
      leftTwoThirds = grid(1, 3, 0, 0, 2, 1), rightTwoThirds = grid(1, 3, 1, 0, 2, 1),
      topLeft = grid(2, 2, 0, 0, 1, 1), topRight = grid(2, 2, 1, 0, 1, 1),
      bottomLeft = grid(2, 2, 0, 1, 1, 1), bottomRight = grid(2, 2, 1, 1, 1, 1),
      centre = grid(10, 20, 3, 1, 14, 8),
      nextScreen = { "--display", "next" }, previousScreen = { "--display", "prev" },
      fullScreen = { "--toggle", "native-fullscreen" },
    },
    send = function(cl, action, target, ctx, title)
      local cmd = { "yabai", "-m", "window" }
      if target.id then cmd[#cmd + 1] = tostring(target.id) end
      for _, arg in ipairs(action) do cmd[#cmd + 1] = arg end
      return cl.executeCommand("shell.run", { cmd = cmd, title = title }, ctx)
    end,
  },

  -- aerospace <subcommand> [--window-id id] <rest>. A tiling manager: it
  -- moves a window between monitors and into full screen, and has no halves
  -- or thirds, so no layout is offered.
  aerospace = {
    title = "AeroSpace",
    installed = function(cl) return cl.tools.path("aerospace") ~= nil end,
    actions = {
      nextScreen = { "move-node-to-monitor", "--wrap-around", "next" },
      previousScreen = { "move-node-to-monitor", "--wrap-around", "prev" },
      fullScreen = { "macos-native-fullscreen" },
    },
    send = function(cl, action, target, ctx, title)
      local cmd = { "aerospace", action[1] }
      if target.id then
        cmd[#cmd + 1] = "--window-id"
        cmd[#cmd + 1] = tostring(target.id)
      end
      for i = 2, #action do cmd[#cmd + 1] = action[i] end
      return cl.executeCommand("shell.run", { cmd = cmd, title = title }, ctx)
    end,
  },
}

for name, provider in pairs(M.providers) do provider.name = name end

M.DEFAULT_PROVIDER = "hammerspoon"

-- The window a move was given, or with none -- or an app, the one in
-- front -- the window in front.
local function windowOf(subject, ctx)
  if type(subject) ~= "table" or subject.kind == "app" then
    return ctx and ctx.focusedWindow or hs.window.focusedWindow()
  end
  return subject.window or (subject.id and M.window(subject.id))
end

function M.send(provider, action, subject, ctx, title)
  if not provider.installed(layer) then
    hs.alert.show(provider.title .. " is not installed")
    layer.log.w(("windows.provider is %q, which is not installed"):format(provider.name))
    return
  end
  local win = windowOf(subject, ctx)
  if not win then
    hs.alert.show("No window")
    return
  end
  if provider.frontWindow and type(subject) == "table" and subject.kind == "window" and not subject.window then
    win:focus()
  end
  local ok, id = pcall(function() return win:id() end)
  return provider.send(layer, action, { window = win, id = ok and id or nil }, ctx, title)
end

----------------------------------------------------------------------

function M.extension(cl)
  layer = cl

  -- cmd+k on the app in front moves its focused window at once, without
  -- asking which.
  cl.itemContextKey("isFrontmostApp", function(subject, ctx)
    return subject.kind == "app" and ctx ~= nil and subject.name == ctx.frontmostApp
  end)

  -- Close, minimise and the moves take the window you were in on enter, and
  -- cmd+k on a window row is how to choose another. Focusing the window you
  -- were in would do nothing, so focus always asks.
  local function takesWindow(preferCurrent, onFrontApp)
    return {
      id = "window", description = "Which window",
      picker = { when = onFrontApp and "viewItem == 'window' || isFrontmostApp" or "viewItem == 'window'",
                 menus = { "windows" } },
      preferCurrent = preferCurrent or nil,
      current = function(ctx)
        local win = ctx and ctx.focusedWindow
        if not win then return nil end
        local ok, id = pcall(function() return win:id() end)
        -- The focused window is the front app's, already captured: asking the
        -- window would be a call per row built.
        return { kind = "window", id = ok and id or nil, window = win, app = ctx.frontmostApp }
      end,
    }
  end

  -- Acting on the window you were in, so context actions while there is one.
  local inContext = { root = true, commandPalette = true, context = { when = "focusedWindow" } }

  cl.tools.register("yabai", { "/opt/homebrew/bin/yabai", "/usr/local/bin/yabai" })
  cl.tools.register("aerospace", { "/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace" })

  -- Read as the extension is set up, as the layouts are: a change applies on
  -- reload. Until this spec is returned its declared default is not known,
  -- so nil is that default. A value outside the enum is a problem already,
  -- and moves nothing.
  local provider = M.providers[cl.setting("windows", "provider") or M.DEFAULT_PROVIDER]
  M.provider = provider

  -- Checked here: a declared setting's type says "an object", not what its
  -- values may be.
  local byPicker = cl.setting("windows", "sourceByPicker")
  if type(byPicker) == "table" then
    for picker, source in pairs(byPicker) do
      if not M.sources[source] then
        cl.problem(("windows.sourceByPicker: %q for picker %q is not all, ordered or visible")
                   :format(tostring(source), tostring(picker)))
      end
    end
  end

  -- A tool of another's is found at start, so until then, and while it is
  -- missing, its moves are no rows.
  local function whenInstalled(clause)
    if not provider or provider.always then return clause end
    return clause and ("windowProviderInstalled && " .. clause) or "windowProviderInstalled"
  end

  -- "Left two thirds" -> "leftTwoThirds"
  local function slug(title)
    local out = ""
    for word in title:gmatch("%w+") do
      out = out .. (out == "" and word:lower()
                    or word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return out
  end

  local function move(id, title, icon, action, when)
    return {
      id = "windows." .. id, title = title, category = "Window", icon = icon,
      menus = inContext, inputs = { takesWindow(true, true) },
      when = whenInstalled(when),
      run = function(args, ctx) return M.send(provider, action, args.window, ctx, "Window: " .. title) end,
    }
  end

  -- Commands are made from the layouts as the extension is set up, so a
  -- changed list applies on reload.
  local layouts = cl.setting("windows", "layouts")
  if type(layouts) ~= "table" then layouts = LAYOUTS end

  local moves = {}
  for i, layout in ipairs(layouts) do
    local unit = type(layout) == "table" and layout.unit
    local valid = type(layout) == "table" and type(layout.title) == "string"
                  and type(unit) == "table" and #unit == 4
    for n = 1, 4 do valid = valid and type(unit[n]) == "number" end
    if not valid then
      cl.problem(("layout %d needs a title and a unit of four numbers"):format(i))
    elseif provider then
      local name = slug(layout.title)
      local action = provider.layoutUnits and unit or provider.actions[name]
      if action then moves[#moves + 1] = move(name, layout.title, layout.icon or "$(layout)", action) end
    end
  end
  -- Another screen is only worth offering when there is one.
  for _, spec in ipairs({
    { "nextScreen", "Next screen", "$(arrow-right)", "screenCount > 1" },
    { "previousScreen", "Previous screen", "$(arrow-left)", "screenCount > 1" },
    { "fullScreen", "Full screen", "$(screen-full)" },
  }) do
    local action = provider and provider.actions[spec[1]]
    if action then moves[#moves + 1] = move(spec[1], spec[2], spec[3], action, spec[4]) end
  end

  local commands = {
    { id = "windows.focus", title = "Focus", category = "Window", icon = "$(window)",
      menus = { "root", "commandPalette" }, inputs = { takesWindow(false) },
      run = function(args) withWindow(args.window, function(w) w:focus() end) end },
    { id = "windows.close", title = "Close", category = "Window", icon = "$(chrome-close)",
      menus = inContext, inputs = { takesWindow(true) }, targetName = "${input:window.app}",
      run = function(args) withWindow(args.window, function(w) w:close() end) end },
    { id = "windows.minimize", title = "Minimise", category = "Window",
      icon = "$(chrome-minimize)", targetName = "${input:window.app}",
      menus = inContext, inputs = { takesWindow(true) },
      run = function(args) withWindow(args.window, function(w) w:minimize() end) end },
  }
  for _, command in ipairs(moves) do commands[#commands + 1] = command end

  return {
    name  = "windows",
    -- A little ahead of an app or a bookmark that also matches "left".
    rank  = 0.43,
    menus = { "root", "recent", "windows" },
    optionalExtensionDependencies = { "raycast" },

    settings = {
      provider = { type = "string", default = M.DEFAULT_PROVIDER,
        enum = { "hammerspoon", "raycast", "rectangle", "yabai", "aerospace" },
        enumDescriptions = {
          "Hammerspoon's own hs.window: every layout, other screens and full screen",
          "Raycast's Window Management, by deeplink",
          "Rectangle, by its URL scheme; no full screen",
          "yabai -m window: its grid for layouts, other displays and native full screen",
          "AeroSpace: other monitors and native full screen, no layouts",
        },
        description = "What moves windows: a move the tool has no action for is not offered, "
                   .. "and nothing is offered while the tool is not installed; applies on reload" },
      -- ordered by default because every open of the root lists windows, and the
      -- fuller list costs more; recent, opened on purpose, is where it belongs.
      source = { type = "string", default = "ordered",
        enum = SOURCES,
        enumDescriptions = {
          "Every window on screen and every window of the apps in the Dock, minimised or on another Space, "
            .. "front to back; about 40 ms",
          "hs.window.orderedWindows(): visible standard windows in their own front-to-back order; about 40 ms",
          "hs.window.visibleWindows(): visible windows, front to back; about 20 ms",
        },
        description = "Which windows are listed, read as a picker lists them, once per open; "
                   .. "windows.sourceByPicker chooses another for a picker" },
      sourceByPicker = { type = "object", default = { recent = "all" },
        description = "A source for a picker, by the picker's name -- { \"root\": \"ordered\", "
                   .. "\"recent\": \"all\" } -- each all, ordered or visible; a picker not named "
                   .. "uses windows.source" },
      limit = { type = "integer", default = 50,
        description = "At most this many windows listed" },
      -- A launcher should feel instant.
      animationDuration = { type = "number", default = 0,
        description = "Seconds a window takes to move" },
      layouts = { type = "array", default = LAYOUTS,
        description = "Window layouts: a title, and a unit of x, y, width and height "
                   .. "in fractions of the screen, which another provider takes by the title's "
                   .. "name where it has that layout; applies on reload" },
    },

    capture = function(ctx)
      ctx.focusedWindow = hs.window.focusedWindow()
      ctx.screenCount = #hs.screen.allScreens()
    end,

    commands = commands,

    items = function(ctx)
      -- The window you were in when the layer opened goes last, so the first
      -- is the one before it, as alt-tab puts the previous window first.
      local current
      if ctx and ctx.focusedWindow then
        local ok, id = pcall(function() return ctx.focusedWindow:id() end)
        current = ok and id or nil
      end

      local rows, last = {}, nil
      for _, w in ipairs(M.windows(ctx)) do
        local text = w.title ~= "" and w.title or w.app
        local subject = { kind = "window", id = w.id, app = w.app, name = text }
        local row = {
          label       = text,
          description = "Window -- " .. w.app,
          command     = "windows.focus",
          args        = { window = subject },
          subject     = subject,
          iconPath    = iconFor(w.bundleID),
          ctx         = ctx,
        }
        if current and w.id == current then last = row else rows[#rows + 1] = row end
      end
      if last then rows[#rows + 1] = last end
      return rows
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
