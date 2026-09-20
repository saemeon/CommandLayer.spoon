-- The frontmost app's menu bar, as searchable rows.
--
-- Every app ships a registry of named, invokable actions and it is the
-- menu bar. Reading it walks the accessibility tree, which is slow
-- enough to feel, so it happens on app activation and is cached.

local M = {}

-- A read that has not called back by then is given up on: an app that never
-- answers would otherwise stay "in flight" and never be read again.
M.pendingSeconds = 5

local layer

-- Not cl.cached: a read is started with the app object on activation,
-- whatever the entry's age, and an app that quits is forgotten.
local cache = {}     -- appName -> { items = {...}, time = n }
local pending = {}   -- appName -> when a read in flight started

local watching, selecting

local function setting(key)
  return (layer.setting("appmenus", key))
end

----------------------------------------------------------------------

-- In the order a menu draws them.
local MODIFIERS = { { "ctrl", "⌃" }, { "alt", "⌥" }, { "shift", "⇧" }, { "cmd", "⌘" } }

-- Worked out as the menus are read, so drawing a row only reads a string.
-- A key with no character of its own (an arrow, delete, a function key) is a
-- glyph number, which hs.application.menuGlyphs names.
function M.shortcut(node)
  local key = node.AXMenuItemCmdChar
  if type(key) ~= "string" or key == "" then
    key = (hs.application.menuGlyphs or {})[node.AXMenuItemCmdGlyph]
  end
  if type(key) ~= "string" or key == "" then return nil end

  local held = {}
  for _, name in pairs(type(node.AXMenuItemCmdModifiers) == "table" and node.AXMenuItemCmdModifiers or {}) do
    held[name] = true
  end
  local out = {}
  for _, modifier in ipairs(MODIFIERS) do
    if held[modifier[1]] then out[#out + 1] = modifier[2] end
  end
  return table.concat(out) .. key
end

local function flatten(nodes, trail, out, depth, limits)
  if depth > limits.maxDepth or #out >= limits.maxItems then return end

  for _, node in ipairs(nodes or {}) do
    if #out >= limits.maxItems then return end

    local title = node.AXTitle

    -- Separators have no title. Skip them and anything unnamed.
    if title and title ~= "" and not (depth == 1 and limits.skip[title]) then
      local path = { table.unpack(trail) }
      path[#path + 1] = title

      -- Hammerspoon wraps a node's children in a single-element table.
      local children = node.AXChildren and node.AXChildren[1]

      if children and #children > 0 then
        flatten(children, path, out, depth + 1, limits)
      elseif node.AXEnabled ~= false then
        out[#out + 1] = {
          title    = title,
          path     = path,
          trail    = table.concat(path, " > "),
          shortcut = M.shortcut(node),
        }
      end
    end
  end
end

----------------------------------------------------------------------

-- Reads one app's menus in the background. getMenuItems' asynchronous
-- form matters here: the synchronous one blocks Hammerspoon for as long
-- as the accessibility walk takes, which on a big app is visible.
function M.refresh(app, callback)
  if not app then return end

  local name = app:name()
  if not name then return end
  if pending[name] and os.time() - pending[name] < M.pendingSeconds then return end

  pending[name] = os.time()

  local limits = { maxDepth = setting("maxDepth"), maxItems = setting("maxItems"), skip = {} }
  for _, title in ipairs(setting("skipMenus") or {}) do limits.skip[title] = true end

  app:getMenuItems(function(menus)
    pending[name] = nil

    local items = {}
    if menus then flatten(menus, {}, items, 1, limits) end

    cache[name] = { items = items, time = os.time() }
    if callback then callback(items) end
  end)
end

-- A running app by bundle id, else by name among the running apps; never
-- hs.application.get, which searches every window's title when a name
-- matches no app.
local function runningApp(id, name)
  if id and hs.application.applicationsForBundleID then
    local found = hs.application.applicationsForBundleID(id)
    if found and found[1] then return found[1] end
  end
  for _, app in ipairs(name and hs.application.runningApplications() or {}) do
    if app:name() == name then return app end
  end
  return nil
end

-- Menu items for an app by name. Returns what is cached now, and kicks
-- off a refresh if that is stale or missing -- so the first look at a new
-- app may be empty, and `onReady` hears when its menus arrive, for a picker
-- already open to show them. The app in front is asked for by object, not
-- by name: a name lookup searches every window when it misses.
function M.items(appName, onReady)
  if not appName or appName == "" then return {} end

  local hit = cache[appName]
  if not hit or (os.time() - hit.time) > setting("cacheSeconds") then
    local front = hs.application.frontmostApplication()
    local app = (front and front:name() == appName) and front or runningApp(nil, appName)
    if app then M.refresh(app, onReady) end
  end

  return hit and hit.items or {}
end

function M.forget(appName)
  if appName then cache[appName] = nil else cache = {} end
end

----------------------------------------------------------------------

-- Reading on activation is what makes the cache warm by the time the
-- picker opens.
function M.start()
  if watching or not layer then return M end

  watching = layer.watch(hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      M.refresh(app)
    elseif event == hs.application.watcher.terminated and app then
      M.forget(app:name())
    end
  end))

  M.refresh(hs.application.frontmostApplication())
  return M
end

function M.stop()
  for _, d in ipairs({ watching or false, selecting or false }) do
    if d then d.dispose() end
  end
  watching, selecting = nil, nil
  cache, pending = {}, {}
  return M
end

----------------------------------------------------------------------

function M.extension(cl)
  layer = cl

  local function select(appName, path, appID)
    local app = runningApp(appID, appName)
    if not app then
      hs.alert.show("No longer running: " .. tostring(appName))
      return
    end

    -- The menu bar belongs to whichever app is frontmost, and by now
    -- that is the picker. Bring the app forward, then choose.
    app:activate()
    if selecting then selecting.dispose() end
    selecting = cl.after(0.08, function()
      selecting = nil
      if not app:selectMenuItem(path) then
        hs.alert.show("Menu item unavailable")
      end
    end)
  end

  local takesMenu = { { id = "menu", picker = { when = "viewItem == 'menu'" } } }

  return {
    name  = "appmenus",
    displayName = "App menus",
    rank  = 0,

    -- Not in the root. An app's menus are several hundred rows that
    -- churn completely every time you switch apps, which is the
    -- opposite of what a launcher's first screen should be. The palette
    -- is the drawer for everything; cmd+. is for what applies now.
    -- The root too, where they rank 0 and so only come up once something
    -- is typed: the app's own menu is worth finding from where you start.
    menus = { "root", "commandPalette", "context" },

    settings = {
      -- Three covers "File > Share > Mail"; deeper is mostly font pickers
      -- and recent-file lists.
      maxDepth = { type = "integer", default = 3,
        description = "How deep to follow submenus" },
      -- Apple's is system-wide and already elsewhere in the launcher;
      -- Services is enormous and mostly inapplicable.
      skipMenus = { type = "array", default = { "Apple", "Services" },
        description = "Top-level menus not listed" },
      -- Menus go stale when an app's state changes (Undo, window lists).
      cacheSeconds = { type = "integer", default = 30,
        description = "How long an app's menus are kept before reading them again" },
      maxItems = { type = "integer", default = 400,
        description = "At most this many menu items from one app" },
      shortcuts = { type = "boolean", default = true,
        description = "Each menu item's keyboard shortcut in its subtitle" },
    },

    -- The bridge from scraped rows to the registry: one verb with args, so
    -- a menu item can be bound to a key without being a command itself.
    commands = {
      { id = "appmenus.select", title = "Select menu item", menus = {},
        run = function(args) select(args.app, args.path, args.appID) end },

      { id = "appmenus.runMenuItem", title = "Run menu item",
        menus = { ["view/item/context"] = true }, inputs = takesMenu,
        run = function(args, ctx)
          local menu = args.menu
          if type(menu) ~= "table" then return end
          cl.executeCommand("appmenus.select", { app = menu.app, appID = menu.appID, path = menu.path }, ctx)
        end },

      { id = "appmenus.copyMenuPath", title = "Copy menu path",
        menus = { ["view/item/context"] = true }, inputs = takesMenu,
        run = function(args, ctx)
          if type(args.menu) ~= "table" then return end
          cl.executeCommand("system.copy", { text = args.menu.name }, ctx)
        end },
    },

    items = function(ctx)
      local appName = ctx.frontmostApp
      local rows = {}
      local shortcuts = cl.setting("appmenus", "shortcuts")

      for _, item in ipairs(M.items(appName, function() cl.refresh() end)) do
        rows[#rows + 1] = {
          label       = item.title,
          description = appName .. " -- " .. item.trail,
          detail      = shortcuts and item.shortcut or nil,
          command     = "appmenus.select",
          args        = { app = appName, appID = ctx.frontmostAppID, path = item.path },
          subject     = { kind = "menu", app = appName, appID = ctx.frontmostAppID,
                          name = item.trail, path = item.path },
          ctx         = ctx,
        }
      end

      return rows
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
