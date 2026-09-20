-- Settings: merging the files, applying them, reading and writing one.

local M = ...

----------------------------------------------------------------------
-- MERGING
----------------------------------------------------------------------

-- Objects merge by key; a list or a plain value replaces. An empty table
-- replaces a list -- "sections": [] clears them -- and changes nothing else.
local function merge(base, over)
  if type(base) ~= "table" or type(over) ~= "table" then return over end
  if M.isList(base) or M.isList(over) then return over end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over) do out[k] = merge(base[k], v) end
  return out
end

-- Pickers by name: an entry changes the fields it names, and one not there
-- yet is added. "enabled": false is kept, for applying to remove.
local function mergeViews(base, over)
  local out, at = {}, {}
  for _, spec in ipairs(base or {}) do
    local copy = {}
    for k, v in pairs(spec) do copy[k] = v end
    out[#out + 1] = copy
    at[copy.name] = #out
  end
  for _, spec in ipairs(over or {}) do
    if type(spec) == "table" and spec.name then
      if at[spec.name] then
        for k, v in pairs(spec) do out[at[spec.name]][k] = v end
      else
        local copy = {}
        for k, v in pairs(spec) do copy[k] = v end
        out[#out + 1] = copy
        at[copy.name] = #out
      end
    end
  end
  return out
end

function M.mergeSettings(base, over)
  local views = mergeViews(base.views, over.views)
  local rest = {}
  for k, v in pairs(over) do
    if k ~= "views" then rest[k] = v end
  end
  local out = merge(base, rest)
  out.views = views
  return out
end

----------------------------------------------------------------------
-- APPLYING
----------------------------------------------------------------------

function M.applySettings(settings)
  M.settings = settings

  -- A text command's own picker is registered already; one named here has the
  -- fields it names changed, and "enabled": false takes it away.
  for _, spec in ipairs(settings.views or {}) do
    local existing = M.viewNamed(spec.name)
    if spec.enabled == false then
      M.removeView(spec.name)
    elseif existing then
      for k, v in pairs(spec) do
        if k ~= "enabled" then existing[k] = v end
      end
      existing.picker = nil
    else
      local copy = {}
      for k, v in pairs(spec) do
        if k ~= "enabled" then copy[k] = v end
      end
      M.view(copy)
    end
  end

  for name, weight in pairs(type(settings.rankers) == "table" and settings.rankers or {}) do
    for _, ranker in ipairs(M.rankers) do
      if ranker.name == name then ranker.weight = weight end
    end
  end

  for key, value in pairs(type(settings.appearance) == "table" and settings.appearance or {}) do
    M.appearance[key] = value
  end

  if type(settings.logLevel) == "string" then M.setLogLevel(settings.logLevel) end
  M.configurePerformance(settings.performance)
  if settings.defaultView then M.defaultView = settings.defaultView end
  if settings.actionsView then M.actionsView = settings.actionsView end
  if settings.presenter then M.defaultPresenter = settings.presenter end

  -- The whole set, in the order tried: a matcher not named does not run.
  M.loadedMatchers = M.loadedMatchers or M.matchers
  if type(settings.matchers) == "table" then
    local byName, kept = {}, {}
    for _, matcher in ipairs(M.loadedMatchers) do byName[matcher.name] = matcher end
    for _, name in ipairs(settings.matchers) do
      if byName[name] then
        kept[#kept + 1] = byName[name]
        byName[name] = nil
      end
    end
    M.matchers = kept
  end

  if type(settings.tools) == "table" then
    M.tools.paths = type(settings.tools.paths) == "table" and settings.tools.paths or {}
    M.tools.overrides = type(settings.tools.use) == "table" and settings.tools.use or {}
  end
  for name, prefix in pairs(type(settings.prefixes) == "table" and settings.prefixes or {}) do
    M.prefixes[name] = prefix
  end

  local off = false
  for key, value in pairs(settings) do
    local name = type(key) == "string" and key:match("^(.+)%.enabled$")
    if name and value == false then
      M.unregisterExtension(name)
      off = true
    end
  end
  -- An extension switched off may be one another requires.
  if off then M.resolveRequires() end
end

-- Whether start asks a login shell once for tools the known paths missed.
function M.loginShellLookup()
  local section = type(M.settings) == "table" and M.settings.tools
  return not (type(section) == "table" and section.loginShell == false)
end

----------------------------------------------------------------------
-- ONE SETTING
--
-- An extension declares `settings = { key = { type, description, default } }`,
-- as VS Code's contributes.configuration does, and reads them with
-- cl.setting. Read at the moment of asking, so a switch flipped in the
-- settings picker applies without a reload.
----------------------------------------------------------------------

-- A presenter or a ranker declaring settings of its own, read under its name.
function M.pluginWithSettings(name)
  local presenter = M.presenters[name]
  if presenter and type(presenter.settings) == "table" then return presenter end
  for _, ranker in ipairs(M.rankers) do
    if ranker.name == name and type(ranker.settings) == "table" then return ranker end
  end
end

local function declared(name, key)
  local owner = M.extensionNamed(name) or M.pluginWithSettings(name)
  local decl = owner and type(owner.settings) == "table" and owner.settings[key]
  return type(decl) == "table" and decl or nil
end

-- "browser.tabOrder", as VS Code writes an extension's setting.
local function lookup(settings, name, key)
  if type(settings) ~= "table" then return nil end
  return settings[name .. "." .. key]
end

-- The value, and where it came from: "settings.json" (the person's own),
-- "profile" (the defaults or a shipped profile), or "default" (declared).
function M.setting(name, key)
  local mine = lookup(M.userSettings, name, key)
  if mine ~= nil then return mine, "settings.json" end
  local profile = lookup(M.settings, name, key)
  if profile ~= nil then return profile, "profile" end
  local decl = declared(name, key)
  if decl then return decl.default, "default" end
  return nil
end

-- ${config:browser.tabs} in a template: an extension's setting.
M.registerTemplateVariable("config", function(_, rest)
  local ext, key = rest:match("^([^%.]+)%.(.+)$")
  local value = ext and M.setting(ext, key)
  return value ~= nil and tostring(value) or ""
end)

-- config.browser.tabOrder in a when clause, as VS Code's config. keys.
M.registerWhenNamespace("config", function(rest)
  local ext, key = rest:match("^([^%.]+)%.(.+)$")
  if not ext then return nil end
  return (M.setting(ext, key))
end)

M.registerMenuOverrides(function(ext) return (M.setting(ext, "menus")) end)

-- After a plugin writes the active profile's settings.json: read again, so a
-- setting reads what was written, and remembered as read, so the reload that
-- watches the profile's folder takes the write for no change.
function M.settingsWritten()
  local data = M.readJSONC(M.profileDir() .. "/settings.json")
  M.userSettings = type(data) == "table" and data or {}
end

----------------------------------------------------------------------
-- WHAT DECLARES SETTINGS
----------------------------------------------------------------------

-- By a declaration's `order`, then by key, as VS Code orders a section.
function M.settingBefore(settings, a, b)
  local function order(key)
    local decl = settings[key]
    return type(decl) == "table" and type(decl.order) == "number" and decl.order or math.huge
  end
  if order(a) ~= order(b) then return order(a) < order(b) end
  return a < b
end

-- Every extension ever registered -- one switched off still has settings
-- -- then every presenter and ranker declaring its own, by display name.
function M.settingOwners()
  local out = {}
  for name, ext in pairs(M.declaredExtensions) do
    out[#out + 1] = { name = name, kind = "extension", settings = ext.settings,
                      description = ext.description, registered = M.extensionNamed(name) ~= nil,
                      displayName = type(ext.displayName) == "string" and ext.displayName
                                    or M.displayNameOf(name) }
  end
  for name, presenter in pairs(M.presenters) do
    if type(presenter.settings) == "table" then
      out[#out + 1] = { name = name, kind = "presenter", settings = presenter.settings,
                        description = presenter.description, displayName = M.displayNameOf(name) }
    end
  end
  for _, ranker in ipairs(M.rankers) do
    if type(ranker.settings) == "table" then
      out[#out + 1] = { name = ranker.name, kind = "ranker", settings = ranker.settings,
                        description = ranker.description, displayName = M.displayNameOf(ranker.name) }
    end
  end
  table.sort(out, function(a, b) return a.displayName:lower() < b.displayName:lower() end)
  return out
end

-- The same, as data (M.listShapes.settingOwner), a fresh copy per call: a
-- declaration changed by whoever reads it would change what the layer checks.
function M.getSettingOwners()
  local out = {}
  for i, owner in ipairs(M.settingOwners()) do
    local menus
    if owner.kind == "extension" then
      local placed = M.declaredMenus(owner.name)
      if placed then
        menus = {}
        for menu in pairs(placed) do menus[#menus + 1] = menu end
        table.sort(menus)
      end
    end
    out[i] = { name = owner.name, kind = owner.kind, displayName = owner.displayName,
               description = type(owner.description) == "string" and owner.description or nil,
               registered = owner.registered, menus = menus,
               settings = type(owner.settings) == "table" and M.copyData(owner.settings) or nil }
  end
  return out
end
