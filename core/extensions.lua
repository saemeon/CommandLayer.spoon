-- The extension registry, building a context, and gathering rows from it.

local M = ...

local registerExtensionCommands = M.registerExtensionCommands
local commandRow = M.commandRow
local normaliseRow = M.normaliseRow

----------------------------------------------------------------------
-- EXTENSIONS
----------------------------------------------------------------------

M.extensions = {}

-- By extension name, since an extension may name itself differently from its
-- file. `activated` holds every extension that has started.
local moduleFor, activated = {}, {}

-- Every extension ever registered, kept when one is switched off or
-- dropped, so its settings still read as settings.
M.declaredExtensions = {}

-- Invalidated by register, and rebuilt on the next ask.
local sorted

-- Later registrations with the same name replace earlier ones, so
-- reloading a file twice does not duplicate it.
function M.register(ext, module)
  sorted = nil
  M.declaredExtensions[ext.name] = ext
  registerExtensionCommands(ext)
  if module then moduleFor[ext.name] = module end

  for i, existing in ipairs(M.extensions) do
    if existing.name == ext.name then
      M.extensions[i] = ext
      return ext
    end
  end
  M.extensions[#M.extensions + 1] = ext
  return ext
end

local function namesIn(value)
  if type(value) == "string" then return { value } end
  return type(value) == "table" and value or {}
end

-- `before = { "finder" }` and `after = { "ambient" }`, naming extensions
-- that are loaded; one that is not is no constraint. Otherwise by name. A
-- circle is a problem, and those in it follow the rest.
--
-- Cached, because every gather, capture and keystroke asks for this and
-- the answer only changes when something registers. The list is shared:
-- read it, do not sort or append to it.
local function sortedExtensions()
  if sorted then return sorted end

  local byName, edges, waiting = {}, {}, {}
  for _, ext in ipairs(M.extensions) do
    byName[ext.name], edges[ext.name], waiting[ext.name] = ext, {}, 0
  end
  local function edge(first, second)
    if byName[first] and byName[second] and first ~= second and not edges[first][second] then
      edges[first][second] = true
      waiting[second] = waiting[second] + 1
    end
  end
  for _, ext in ipairs(M.extensions) do
    for _, other in ipairs(namesIn(ext.after)) do edge(other, ext.name) end
    for _, other in ipairs(namesIn(ext.before)) do edge(ext.name, other) end
  end

  local function earlier(a, b) return a < b end

  sorted = {}
  local ready = {}
  for name, count in pairs(waiting) do
    if count == 0 then ready[#ready + 1] = name end
  end
  while #ready > 0 do
    table.sort(ready, earlier)
    local name = table.remove(ready, 1)
    sorted[#sorted + 1] = byName[name]
    for second in pairs(edges[name]) do
      waiting[second] = waiting[second] - 1
      if waiting[second] == 0 then ready[#ready + 1] = second end
    end
  end

  if #sorted < #M.extensions then
    local stuck = {}
    for name, count in pairs(waiting) do
      if count > 0 then stuck[#stuck + 1] = name end
    end
    table.sort(stuck, earlier)
    if M.problem then
      M.problem("extensions", "before and after lead in a circle: " .. table.concat(stuck, ", "))
    end
    for _, name in ipairs(stuck) do sorted[#sorted + 1] = byName[name] end
  end
  return sorted
end

M.sortedExtensions = sortedExtensions

----------------------------------------------------------------------
-- MANIFEST
--
-- What an extension says about itself beyond its hooks, as VS Code's
-- package.json does: a display name, and the extensions it requires.
----------------------------------------------------------------------

local function extensionNamed(name)
  for _, ext in ipairs(M.extensions) do
    if ext.name == name then return ext end
  end
end

M.extensionNamed = extensionNamed

-- For wherever a person reads it; an internal name like "appmenus" is not
-- a label.
function M.displayNameOf(name)
  local ext = extensionNamed(name)
  if ext and type(ext.displayName) == "string" and ext.displayName ~= "" then
    return ext.displayName
  end
  return (tostring(name):gsub("^%l", string.upper))
end

local function stopOne(name)
  local module = moduleFor[name]
  if module and type(module.stop) == "function" then
    local ok, err = pcall(module.stop)
    if not ok then
      M.log.e(tostring(name) .. " failed to stop: " .. tostring(err))
    end
  end
  M.stopRunning(name)
end

-- Everything it registered goes with it: commands, the views made for
-- them, and whatever its API recorded.
function M.unregisterExtension(name)
  for i, ext in ipairs(M.extensions) do
    if ext.name == name then
      table.remove(M.extensions, i)
      break
    end
  end
  sorted = nil
  if activated[name] then stopOne(name) end
  registerExtensionCommands({ name = name })
  M.disposeExtension(name)
  moduleFor[name], activated[name] = nil, nil
end

-- VS Code's `extensionDependencies`.
local function dependenciesOf(ext)
  return type(ext.extensionDependencies) == "table" and ext.extensionDependencies or {}
end

-- Those it uses when they are there, started before it all the same.
local function optionalDependenciesOf(ext)
  return type(ext.optionalExtensionDependencies) == "table" and ext.optionalExtensionDependencies or {}
end

-- Repeated until nothing changes: dropping one extension can leave another
-- that required it without its requirement.
function M.resolveRequires()
  local changed = true
  while changed do
    changed = false
    for _, ext in ipairs(M.extensions) do
      for _, need in ipairs(dependenciesOf(ext)) do
        if not extensionNamed(need) then
          M.log.w(("extension '%s' depends on '%s', which is not loaded; skipped")
                :format(tostring(ext.name), tostring(need)))
          M.unregisterExtension(ext.name)
          changed = true
          break
        end
      end
      if changed then break end
    end
  end
  return M
end

-- An extension's requirements before it, otherwise extension order.
function M.startOrder()
  local out, visited = {}, {}
  local function visit(ext)
    if visited[ext.name] then return end
    visited[ext.name] = true
    for _, list in ipairs({ dependenciesOf(ext), optionalDependenciesOf(ext) }) do
      for _, need in ipairs(list) do
        local required = extensionNamed(need)
        if required then visit(required) end
      end
    end
    out[#out + 1] = ext.name
  end
  for _, ext in ipairs(sortedExtensions()) do visit(ext) end
  return out
end

-- Guarded one by one: an extension that throws while starting degrades
-- alone rather than taking the rest down with it.
local function startOne(name)
  activated[name] = true
  local module = moduleFor[name]
  if not (module and type(module.start) == "function") then return end
  local stop = M.span("activate." .. tostring(name))
  local ok, err = pcall(module.start)
  stop()
  if not ok then
    M.log.e(tostring(name) .. " failed to start: " .. tostring(err))
  end
end

function M.startExtensions()
  for _, name in ipairs(M.startOrder()) do
    local ext = extensionNamed(name)
    if ext and not activated[name] then
      startOne(name)
    end
  end
  return M
end

function M.stopExtensions()
  for name in pairs(activated) do stopOne(name) end
  activated = {}
  return M
end

-- What is in front of you, named the same way a highlighted row is, so
-- one set of verbs serves both.
local function ambientSubjects(ctx)
  local subjects = {}

  for _, ext in ipairs(sortedExtensions()) do
    if ext.subjects then
      local stop = M.span("subjects." .. ext.name)
      local ok, produced = pcall(ext.subjects, ctx)
      stop()
      if not ok then
        M.log.e("extension '" .. tostring(ext.name)
              .. "' subjects -> " .. tostring(produced))
      else
        for _, subject in ipairs(produced or {}) do
          subjects[#subjects + 1] = subject
        end
      end
    end
  end

  return subjects
end

M.ambientSubjects = ambientSubjects

-- A subject's own view of the context, so an action written with
-- ${finderSelection} works on any file subject. Inherits the rest.
local function subjectContext(subject, ctx)
  if not subject then return ctx end

  -- Whoever captured a field knows how a subject narrows it.
  local scoped = setmetatable({}, { __index = ctx })

  for _, ext in ipairs(sortedExtensions()) do
    if ext.scope then
      local ok, err = pcall(ext.scope, subject, scoped, ctx)
      if not ok then
        M.log.e("extension '" .. tostring(ext.name)
              .. "' scope -> " .. tostring(err))
      end
    end
  end

  return scoped
end

M.subjectContext = subjectContext

-- Seeds nothing, frontmostApp included. All this owns is the order the
-- captures run in.
local function buildContext()
  local ctx = M.contextFromKeys()

  for _, ext in ipairs(M.sortedExtensions()) do
    if ext.capture then
      local stop = M.span("capture." .. ext.name)
      local ok, err = pcall(ext.capture, ctx)
      stop()
      if not ok then
        M.log.e("extension '" .. tostring(ext.name)
              .. "' capture -> " .. tostring(err))
      end
    end
  end

  return ctx
end

M.buildContext = buildContext

----------------------------------------------------------------------
-- GATHER
----------------------------------------------------------------------

-- Which pickers an extension's rows belong in when it does not say.
local DEFAULT_MENUS = { "root", "commandPalette" }

-- The picker menus an extension's rows and commands declare, a name to true,
-- or nil when it has none: what its `menus` setting is written over. From
-- its spec, so one switched off still says.
function M.declaredMenus(name)
  local ext = M.declaredExtensions[name]
  if type(ext) ~= "table" then return nil end
  local found, any = {}, false
  local function add(menus)
    for key, value in pairs(type(menus) == "table" and menus or {}) do
      local menu = type(key) == "string" and key or value
      if type(menu) == "string" and menu ~= "view/item/context" and value then
        found[menu], any = true, true
      end
    end
  end
  if ext.items or ext.search then add(ext.menus or DEFAULT_MENUS) end
  for _, command in ipairs(type(ext.commands) == "table" and ext.commands or {}) do
    if type(command) == "table" then add(M.menusOfCommand(command)) end
  end
  return any and found or nil
end

-- A view may ask for more than one menu, which is what lets a
-- profile with a single picker hold everything without any extension
-- changing which menus it claims.
local function wantedMenus(opts)
  return opts.menus
end

local function subjectKey(item)
  local s = item.subject
  if not s then return nil end
  -- Bundle id before path before name: recents and the catalogue call
  -- the same app different things, and without this VS Code is listed
  -- twice.
  return (s.kind or "?") .. "\0"
         .. tostring(s.id or s.path or s.url or s.name or item.label)
end

-- One pass over the extensions, in order. The first row for a subject
-- wins, so an extension lists what matters first -- recently used apps,
-- then every app -- and never has to filter one list by the other.
local function gather(ctx, opts)
  opts = opts or {}

  local items, seen = {}, {}
  local wanted = wantedMenus(opts)
  local overrides = {}

  for _, ext in ipairs(sortedExtensions()) do
    if ext.items and M.onOwnMenu(ext.menus or DEFAULT_MENUS, ext.name, wanted, ctx, overrides) then
      local stop = M.span("gather." .. ext.name)
      local ok, produced = pcall(ext.items, ctx, opts)
      stop(ok and type(produced) == "table" and (#produced .. " rows") or nil)
      if not ok then
        M.log.e("extension '" .. tostring(ext.name)
              .. "' items -> " .. tostring(produced))
      else
        for _, item in ipairs(produced or {}) do
          normaliseRow(item)
          local key = subjectKey(item)
          if M.when(item.when, ctx) and (not key or not seen[key]) then
            if key then seen[key] = true end
            -- How specific this row is, unless it said for itself.
            if item.rank == nil then item.rank = ext.rank or 0 end
            -- Which extension it came from, for a view's sections.
            item.source = item.source or ext.name
            items[#items + 1] = item
          end
        end
      end
    end
  end

  -- An empty menus list is a command meant only to be called or bound.
  local stopCommands = M.span("gather.commands")
  local before = #items
  local rankOf = {}
  for _, ext in ipairs(sortedExtensions()) do rankOf[ext.name] = ext.rank end
  for _, command in ipairs(M.getCommands()) do
    if M.hasMenus(command.menus) and M.onOwnMenu(command.menus, command.extension, wanted, ctx, overrides)
       and M.when(command.when, ctx) then
      local item = commandRow(command, ctx)
      local key = subjectKey(item)
      if not seen[key] then
        seen[key] = true
        if item.rank == nil then item.rank = rankOf[command.extension] or 0 end
        item.source = item.source or command.extension
        items[#items + 1] = item
      end
    end
  end
  stopCommands((#items - before) .. " rows")

  return items
end

M.gather = gather

-- What a `when` about one row reads: the row's subject, `viewItem` its kind
-- -- VS Code's name for a tree item's contextValue in view/item/context
-- menus -- and the context behind both.
-- Keys such a clause may ask for that a row does not carry, worked out when
-- asked -- an extension's own context key, for one item: the git
-- extension's `gitRepository` looks for a .git folder. Worked out once per
-- row per context, however many clauses ask.
local itemKeys = {}

function M.itemContextKey(name, fn)
  if type(name) ~= "string" or type(fn) ~= "function" then return false end
  itemKeys[name] = fn
  return true
end

function M.itemContextKeyFunction(name)
  return itemKeys[name]
end

function M.removeItemContextKey(name, fn)
  if itemKeys[name] == nil or (fn and itemKeys[name] ~= fn) then return false end
  itemKeys[name] = nil
  return true
end

function M.itemContext(subject, ctx)
  return setmetatable({ viewItem = subject and subject.kind }, {
    __index = function(t, key)
      if subject and subject[key] ~= nil then return subject[key] end
      local compute = subject and itemKeys[key]
      if compute then
        local ok, value = pcall(compute, subject, ctx)
        value = ok and value or false
        rawset(t, key, value)
        return value
      end
      return ctx and ctx[key]
    end,
  })
end

-- The rows a question's picker with a `when` offers: gathered from the menus
-- it names -- every extension's, when it names none -- and kept where its
-- `when` holds.
function M.rowsForItemInput(spec, ctx)
  local menus = spec.menus
  if type(menus) == "string" then menus = { menus } end
  if type(menus) ~= "table" then
    local seen = {}
    menus = {}
    for _, ext in ipairs(sortedExtensions()) do
      local own = ext.menus or DEFAULT_MENUS
      local names = {}
      if own[1] ~= nil then names = own else for name in pairs(own) do names[#names + 1] = name end end
      for _, name in ipairs(names) do
        if type(name) == "string" and not seen[name] then
          seen[name] = true
          menus[#menus + 1] = name
        end
      end
    end
  end

  local out = {}
  for _, row in ipairs(gather(ctx, { menus = menus })) do
    local subject = row.subject
    if subject and subject.kind ~= "command" and subject.kind ~= "view"
       and M.when(spec.when, M.itemContext(subject, ctx)) then
      out[#out + 1] = row
    end
  end
  return out
end

-- After a pick is recorded, every extension with a `picked` hook hears of
-- it: something that learns from what you open, as zoxide learns folders.
-- One that throws is logged and the rest still hear.
M.notifyPicked = function(item)
  for _, ext in ipairs(sortedExtensions()) do
    if ext.picked then
      local stop = M.span("picked." .. ext.name)
      local ok, err = pcall(ext.picked, item, item.ctx)
      stop()
      if not ok then
        M.log.e("extension '" .. tostring(ext.name)
              .. "' picked -> " .. tostring(err))
      end
    end
  end
end

-- A level off the stack is heard by every extension feeding its menus, so one
-- that started something for that picker stops it. A level with no menus --
-- cmd+k's verbs, a text command's own picker -- has no extension to tell. One
-- that throws is logged and the rest still hear.
function M.notifyLeft(level)
  local opts = type(level) == "table" and level.menus
  local wanted = type(opts) == "table" and opts.menus
  if type(wanted) ~= "table" then return end
  local ctx = level.ctx or {}
  if opts.activeView then ctx = M.argContext(ctx, { activeView = opts.activeView }) end
  for _, ext in ipairs(sortedExtensions()) do
    if ext.left and M.onOwnMenu(ext.menus or DEFAULT_MENUS, ext.name, wanted, ctx) then
      local ok, err = pcall(ext.left, ctx)
      if not ok then
        M.log.e("extension '" .. tostring(ext.name) .. "' left -> " .. tostring(err))
      end
    end
  end
end

-- Rows made *from* what you typed, rather than filtered by it: every
-- other row exists before the query and is narrowed, while a
-- calculation only exists once there is something to calculate.
local function queryItems(ctx, query)
  if not query or query == "" then return {} end

  local items = {}

  for _, ext in ipairs(sortedExtensions()) do
    if ext.query then
      local stop = M.span("query." .. ext.name)
      local ok, produced = pcall(ext.query, query, ctx)
      stop()
      if not ok then
        M.log.e("extension '" .. tostring(ext.name)
              .. "' query -> " .. tostring(produced))
      else
        for _, item in ipairs(produced or {}) do
          normaliseRow(item)
          if M.when(item.when, ctx) then items[#items + 1] = item end
        end
      end
    end
  end

  return items
end

M.queryItems = queryItems

-- Rows found by asking rather than by narrowing, for a view that searches
-- again on every keystroke. A hook answers through `done` whenever it can,
-- and returns how to stop it, so a newer query can end an older search.
function M.searchExtensions(ctx, opts, query, done)
  local wanted = wantedMenus(opts or {})
  if opts and opts.activeView then ctx = M.argContext(ctx, { activeView = opts.activeView }) end
  local stops, started = {}, 0

  for _, ext in ipairs(sortedExtensions()) do
    if ext.search and M.onOwnMenu(ext.menus or DEFAULT_MENUS, ext.name, wanted, ctx) then
      -- To the first answer: a hook may answer again as more arrives.
      local stopSpan = M.span("search." .. ext.name)
      local answered = false
      local ok, stop = pcall(ext.search, query, ctx, function(rows)
        rows = rows or {}
        if stopSpan then
          stopSpan(#rows .. " rows")
          stopSpan = nil
        end
        for _, item in ipairs(rows) do
          normaliseRow(item)
          if item.rank == nil then item.rank = ext.rank or 0 end
        end
        -- No hook says when it has finished, so a caller counts first answers
        -- against how many started to know every one has said something.
        local first = not answered
        answered = true
        done(rows, first)
      end)
      if not ok then
        M.log.e("extension '" .. tostring(ext.name)
              .. "' search -> " .. tostring(stop))
      else
        started = started + 1
        if type(stop) == "function" then stops[#stops + 1] = stop end
      end
    end
  end

  return stops, started
end

M.subjectKey = subjectKey
