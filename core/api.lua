-- What a plugin is given instead of the kernel.

local M = ...

local ownerOf, track, DONE = M.ownerOf, M.track, M.nothingToDispose

M.apiVersion = 0

----------------------------------------------------------------------
-- WHAT EACH KIND OF PLUGIN MAY READ
--
-- Read through to the kernel when asked rather than copied when made, so a
-- value that changes -- the log level, a stubbed function -- is current.
----------------------------------------------------------------------

local SHARED = { "apiVersion", "log", "resolve", "when", "tools" }

local ALLOWED = {
  extension = {
    "logLevels", "logLevel", "setLogLevel",
    "appearance", "userDir", "ambientSubjects", "itemActions",
    "buildContext", "argContext", "contextKeys", "setContext", "itemContextKey", "themeIconProvider",
    "executeCommand", "getCommand", "itemInputOf",
    "setting", "inspectSetting", "refresh", "chord", "editsText", "chordText",
    "after", "every", "watch", "extension", "cached", "problem", "getProblems", "performance",
    "profile", "profileNames", "profileFile", "shippedFile", "reload",
    "decodeJSONC", "encodeJSON", "editJSONC", "removeJSONCElement", "appendJSONCElement",
    "settingsWritten", "keybindingsWritten",
    "lastUsed", "removeRecentlyUsed", "clearRecentlyUsed",
    "getViews", "getKeybindings", "getSettingOwners", "settingBefore", "displayNameOf",
  },
  presenter = { "setting", "inspectSetting", "appearance" },
  matcher   = {},
  ranker    = { "setting", "rowKey" },
}

-- What each member is, for docs/api.md.
local DESCRIPTIONS = {
  apiVersion = "The plugin API's version; 0 while in development.",
  log = "The layer's hs.logger: e for something that failed, w for a mistake found.",
  resolve = "resolve(template, ctx, captures, encode): a template with ${field}, ${input:id}, "
            .. "${config:name.key}, ${env:NAME} and ${command:id} filled in.",
  when = "when(text, ctx): whether a when clause holds; one that does not parse never does.",
  tools = "Binaries: register(name, candidates), provide(capability, providers), path(name) and "
          .. "run(program, args, done, opts). What a plugin registers or runs is undone when it stops.",
  name = "The plugin's own name.",
  problem = "problem(message): a problem shown to the person, under the plugin's name.",
  after = "after(seconds, fn): a timer, stopped when the plugin stops.",
  every = "every(seconds, fn): a repeating timer, stopped when the plugin stops.",
  watch = "watch(watcher): starts anything with start and stop, and stops it when the plugin stops.",
  themeIconProvider = "themeIconProvider(fn): draws the $(name) icons of rows.",
  itemContextKey = "itemContextKey(name, fn): a key a when clause over a row may ask for, fn(subject) "
                   .. "worked out once per row.",
  setContext = "setContext(key, value): a context key every context built afterwards carries; nil removes it.",
  extension = "extension(name): the exports of an extension declared a dependency; nil while it is off.",
  cached = "cached(key, { seconds, refresh, initial, timeout }): the last value at once, refresh(done) "
           .. "asked when it is older than seconds, and the picker redrawn when the answer lands. "
           .. "done(nil) says the call did not work: the last answer stays and the next ask tries again.",
  logLevels = "The log levels, in VS Code's names.",
  logLevel = "The log level in effect.",
  setLogLevel = "setLogLevel(level): the log level, for the session.",
  appearance = "What every picker shares: dark, width, rows, maxRows, actionWidth, actionRows.",
  userDir = "The folder holding the person's own files.",
  ambientSubjects = "ambientSubjects(ctx): what is in front of you, as subjects.",
  itemActions = "itemActions(subject, ctx): the rows cmd+k offers for a subject.",
  buildContext = "buildContext(): a context, every extension's capture run.",
  argContext = "argContext(ctx, args): the context with collected args joined, for filling templates.",
  contextKeys = "contextKeys(ctx): every key readable through a context, sorted, "
                .. "those a scoped copy reads through included.",
  executeCommand = "executeCommand(id, args, ctx): runs a command, asking for what args leaves unanswered.",
  getCommand = "getCommand(id): the registered command.",
  itemInputOf = "itemInputOf(command): the input through which a command takes a thing, "
                .. "its picker's when a clause over a row.",
  setting = "setting(name, key): a setting's value.",
  inspectSetting = "inspectSetting(name, key): a setting's value, and where it came from: "
                   .. "settings.json, profile or default.",
  refresh = "refresh(): redraws the picker on screen, for rows that arrived late.",
  chord = "chord(text): the modifiers and the key a written chord names.",
  editsText = "editsText(chord): whether the search field needs the key to edit text, so no keybinding may "
              .. "take it.",
  shippedFile = "shippedFile(name): the path of a file the Spoon ships in config/, such as defaults.jsonc.",
  decodeJSONC = "decodeJSONC(text): JSON that may hold comments and trailing commas, decoded; nil and why not.",
  encodeJSON = "encodeJSON(value, inline, order): JSON, two-space indented with sorted keys; inline on one line, "
               .. "order the keys written first.",
  editJSONC = "editJSONC(text, path, value): the text with the value at path, a list of keys, replaced where it "
              .. "stands or added after the object's last entry, comments and layout kept; nil value removes the "
              .. "key. Nil and why not.",
  removeJSONCElement = "removeJSONCElement(text, path, index): the text without the list at path's element "
                       .. "index, its line and comment with it. Nil and why not.",
  appendJSONCElement = "appendJSONCElement(text, path, value, order): the text with value added after the last "
                       .. "element of the list at path, order the keys written first. Nil and why not.",
  settingsWritten = "settingsWritten(): after a write to the active profile's settings.json, the layer reads it "
                    .. "again, so a setting reads what was written and the reload watching the folder takes the "
                    .. "write for no change.",
  keybindingsWritten = "keybindingsWritten(): after a write to a keybindings.json, the layer reads every "
                       .. "keybindings file again and binds every key again, so the reload watching the folder "
                       .. "takes the write for no change.",
  getProblems = "getProblems(): a copy of every problem reported.",
  performance = "performance(opts): a copy of the time recorded, by span name: count, total, max, last, "
                .. "median and p90, in milliseconds. { reset = true } clears it after copying.",
  profile = "The profile set before start, a name or a folder; unset, profile.json decides.",
  profileNames = "profileNames(): default, then every profile folder shipped or in the user folder.",
  profileFile = "profileFile(name, initial): the path of the active profile's own file, made with initial "
                .. "if missing; without initial, only the path.",
  reload = "reload(opts): stops the layer and starts it again, every settings, keybindings and plugin file read "
           .. "anew, without restarting the rest of Hammerspoon, and returns whether it did. { ifChanged = true } "
           .. "reloads only when the active profile's settings.json or keybindings.json says something other than "
           .. "what the layer last read or wrote; one that does not parse is a problem, and no change.",
  readJSONC = "readJSONC(path): a JSON file that may hold comments and trailing commas, decoded; nil for a "
              .. "missing file, and for one that does not parse, which is a problem under the extension's name.",
  displayNameOf = "displayNameOf(name): what a person reads for an extension's name.",
  getViews = "getViews(): every declared picker, as the list \"view\" describes; a fresh copy per call.",
  getKeybindings = "getKeybindings(): every keybinding in effect, after removals, as the list \"keybinding\" "
                   .. "describes; a fresh copy per call.",
  getSettingOwners = "getSettingOwners(): every extension, presenter and ranker declaring settings, by display "
                     .. "name, as the list \"settingOwner\" describes; a fresh copy per call.",
  settingBefore = "settingBefore(settings, a, b): whether key a comes before key b, by order, then by key.",
  rowKey = "rowKey(item): a row's identity from one build to the next.",
  lastUsed = "lastUsed(item): when a row was last picked, as the rankers in use say; 0 for never.",
  removeRecentlyUsed = "removeRecentlyUsed(item): every ranker in use forgets a row's picks, so it is "
                       .. "neither recently used nor lifted by them.",
  clearRecentlyUsed = "clearRecentlyUsed(): every ranker in use forgets every pick it recorded.",
  chordText = "chordText(flags, key): a pressed chord as keybindings.json writes it, hyper for all four modifiers.",
}

-- A plugin's `setting` is the value alone, so it can be an argument in the
-- middle of a call -- `math.min(n, cl.setting(...))` -- without a second
-- value slipping in; `inspectSetting` adds where it came from, as VS Code's
-- `inspect` does.
local SETTINGS = {
  setting        = function(name, key) return (M.setting(name, key)) end,
  inspectSetting = function(name, key) return M.setting(name, key) end,
}

----------------------------------------------------------------------
-- WHAT ONLY A PLUGIN'S OWN API CAN DO
----------------------------------------------------------------------

-- An error in an extension's callback is logged, never thrown into
-- Hammerspoon's own callback, which would report it without saying whose.
local function guarded(owner, what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    M.log.e(owner.kind .. " '" .. owner.name .. "' " .. what .. " -> " .. tostring(err))
  end
end

-- Several plugins may claim the same binary; it stays registered while any
-- claim does.
local toolClaims = {}

local function toolsFor(owner)
  local own = {}

  function own.register(name, candidates)
    local known = M.tools.candidates[name]
    M.tools.register(name, candidates)
    if M.tools.candidates[name] ~= candidates and known == nil then return DONE end
    toolClaims[name] = (toolClaims[name] or 0) + 1
    return track(owner.registrations, function()
      toolClaims[name] = toolClaims[name] - 1
      if toolClaims[name] <= 0 then
        toolClaims[name] = nil
        M.tools.candidates[name] = nil
      end
    end)
  end

  function own.provide(capability, providers)
    local existing = M.tools.providers[capability]
    if existing ~= nil and existing ~= providers then
      M.problem(owner.kind .. " " .. owner.name,
        ("capability %q is provided already; the first stays"):format(tostring(capability)))
      return DONE
    end
    M.tools.provide(capability, providers)
    return track(owner.registrations, function()
      if M.tools.providers[capability] == providers then M.tools.providers[capability] = nil end
    end)
  end

  -- Ended when the extension stops, and forgotten once it exits.
  function own.run(program, args, done, opts)
    local handle, finished
    local task = M.tools.run(program, args, function(...)
      finished = true
      if handle then owner.running[handle] = nil end
      if done then guarded(owner, "task", done, ...) end
    end, opts)
    if task and not finished then
      handle = track(owner.running, function() task:terminate() end)
    end
    return task
  end

  return setmetatable(own, { __index = function(_, key) return M.tools[key] end })
end

-- Which key an extension set, so switching it off clears only its own.
local contextSetter = {}

local function ownFunctions(owner)
  local name, kind = owner.name, owner.kind
  local where = kind .. " " .. name
  local own = { name = name, tools = toolsFor(owner) }

  function own.problem(message)
    M.problem(where, tostring(message))
  end

  function own.after(seconds, fn)
    local d, fired
    local timer = hs.timer.doAfter(seconds, function()
      fired = true
      if d then owner.running[d] = nil end
      local stop = M.span("timer." .. name)
      guarded(owner, "timer", fn)
      stop()
    end)
    if fired or not timer then return DONE end
    d = track(owner.running, function() timer:stop() end)
    return d
  end

  function own.every(seconds, fn)
    local timer = hs.timer.doEvery(seconds, function()
      local stop = M.span("timer." .. name)
      guarded(owner, "timer", fn)
      stop()
    end)
    if not timer then return DONE end
    return track(owner.running, function() timer:stop() end)
  end

  -- Anything with start and stop: an application watcher, a Spotlight query.
  function own.watch(watcher)
    watcher:start()
    return track(owner.running, function() watcher:stop() end)
  end

  if kind ~= "extension" then return own end

  -- Not the kernel's readJSONC, which is for the settings files: it names the
  -- file as the problem's place, and remembers what it read to tell a change.
  function own.readJSONC(path)
    path = tostring(path)
    local text = M.readText(path)
    if not text then return nil end
    local data, err = M.decodeJSONC(text)
    if data == nil then
      own.problem(("%s does not parse, so it was ignored: %s"):format(path, tostring(err)))
    end
    return data
  end

  function own.themeIconProvider(fn)
    if not M.themeIconProvider(name, fn) then return DONE end
    return track(owner.registrations, function() M.removeThemeIconProvider(name, fn) end)
  end

  function own.itemContextKey(key, fn)
    local existing = M.itemContextKeyFunction(key)
    if existing ~= nil and existing ~= fn then
      own.problem(("item context key %q is registered already; the first stays"):format(tostring(key)))
      return DONE
    end
    if not M.itemContextKey(key, fn) then return DONE end
    return track(owner.registrations, function() M.removeItemContextKey(key, fn) end)
  end

  function own.setContext(key, value)
    if not M.setContext(key, value) then return DONE end
    contextSetter[key] = name
    return track(owner.registrations, function()
      if contextSetter[key] == name then
        contextSetter[key] = nil
        M.setContext(key, nil)
      end
    end)
  end

  -- Another extension's exports, for one declared as a dependency: nil
  -- while that extension is not loaded or switched off.
  function own.extension(other)
    local spec = M.declaredExtensions[name] or {}
    local declared = false
    for _, field in ipairs({ "extensionDependencies", "optionalExtensionDependencies" }) do
      for _, dep in ipairs(type(spec[field]) == "table" and spec[field] or {}) do
        if dep == other then declared = true end
      end
    end
    if not declared then
      error(("extension '%s' asks for '%s' without declaring it a dependency")
            :format(name, tostring(other)), 2)
    end
    local ext = M.extensionNamed(other)
    return ext and ext.exports or nil
  end

  -- Stale-while-revalidate: the last answer at once, and when it is older
  -- than `seconds` -- an empty answer counts -- `refresh(done)` asked once,
  -- the picker redrawn when it lands. A refresh unanswered for `timeout`
  -- seconds is given up.
  --
  -- `done(nil)` says it did not work rather than that there is nothing: the
  -- last good answer stays and the next ask tries again, where an empty one
  -- would have stood for the whole of `seconds`. A gh that failed once left
  -- Git: Clone… with no repositories for five minutes.
  function own.cached(key, opts)
    local entry = owner.caches[key]
    if not entry then
      entry = { stamp = nil }
      owner.caches[key] = entry
    end
    local now = os.time()
    local stale = entry.stamp == nil or now - entry.stamp >= (opts.seconds or 0)
    local pending = entry.started and now - entry.started < (opts.timeout or 60)
    if stale and not pending and type(opts.refresh) == "function" then
      local caches, started = owner.caches, {}
      entry.started, entry.generation = now, started
      local answered
      -- From asking to the answer, which is where a cache's time goes.
      local stopSpan = M.span("cache." .. name .. "." .. tostring(key))
      local ok, err = pcall(opts.refresh, function(value)
        if stopSpan then
          stopSpan()
          stopSpan = nil
        end
        if owner.caches ~= caches or entry.generation ~= started then return end
        entry.started = nil
        if value == nil then return end
        entry.value, entry.stamp = value, os.time()
        if answered ~= nil then M.refresh() end
      end)
      answered = true
      if not ok then
        entry.started, entry.stamp = nil, now
        M.log.e(where .. " cache '" .. tostring(key) .. "' -> " .. tostring(err))
      end
    end
    if entry.value == nil then return opts.initial end
    return entry.value
  end

  return own
end

----------------------------------------------------------------------
-- BUILDING ONE
----------------------------------------------------------------------

local apis = {}

-- Every member each kind is given, { name, description }, by name. The own
-- functions are read from a throwaway owner: making them registers nothing.
function M.apiMembers()
  local out = {}
  for kind, allowed in pairs(ALLOWED) do
    local names = {}
    for _, member in ipairs(SHARED) do names[member] = true end
    for _, member in ipairs(allowed) do names[member] = true end
    local owner = { kind = kind, name = kind, registrations = {}, running = {}, caches = {} }
    for member in pairs(ownFunctions(owner)) do names[member] = true end
    local list = {}
    for member in pairs(names) do list[#list + 1] = { name = member, description = DESCRIPTIONS[member] } end
    table.sort(list, function(a, b) return a.name < b.name end)
    out[kind] = list
  end
  return out
end

-- For the harness: a description naming no member is one left behind.
M.apiDescriptions = DESCRIPTIONS

-- Reading or writing a name outside the list raises: a plugin reaching
-- past its API is a mistake to hear about where it is made.
function M.pluginAPI(kind, name)
  local key = kind .. ":" .. tostring(name)
  if apis[key] then return apis[key] end

  local owner = ownerOf(kind, tostring(name))
  local own = ownFunctions(owner)
  local allowed = {}
  for _, member in ipairs(SHARED) do allowed[member] = true end
  for _, member in ipairs(ALLOWED[kind] or {}) do allowed[member] = true end

  local api = setmetatable({}, {
    __index = function(_, member)
      if own[member] ~= nil then return own[member] end
      if allowed[member] and SETTINGS[member] then return SETTINGS[member] end
      if allowed[member] then return M[member] end
      error(("cl.%s is not part of the %s API"):format(tostring(member), kind), 2)
    end,
    __newindex = function(_, member)
      error(("cl.%s cannot be set by a %s"):format(tostring(member), kind), 2)
    end,
  })
  apis[key] = api
  return api
end
