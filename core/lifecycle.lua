-- Bringing the layer up and down: setup, start, stop, the entry chord, and
-- the public layer init.lua is given.

local M = ...

local modal = M.modal

-- The shipped defaults, then the active profile's files over them, applied
-- and then checked, so a picker a profile adds is a picker.
function M.loadSettings()
  local folders = M.profileFolders(M.profile)
  local defaults = M.readJSONC(M.SPOON_DIR .. "config/defaults.jsonc") or {}
  local settings, files = defaults, {}
  for i, folder in ipairs(folders) do
    local path = folder .. "/settings.json"
    local data
    if i == #folders then data = M.userSettings else data = M.readJSONC(path) end
    if type(data) == "table" then
      settings = M.mergeSettings(settings, data)
      files[#files + 1] = { path = path, data = data }
    end
  end
  M.applySettings(settings)
  local viewFiles = {}
  for _, file in ipairs(files) do
    M.checkSettings(file.data, file.path, defaults)
    for _, spec in ipairs(type(file.data.views) == "table" and file.data.views or {}) do
      if type(spec) == "table" and type(spec.name) == "string" then viewFiles[spec.name] = file.path end
    end
  end
  M.checkSpecs(viewFiles)
  return M
end

----------------------------------------------------------------------
-- SETUP
--
-- Loading defines things and touches nothing. Reading folders is I/O and
-- binding a chord claims a system-wide key, so both wait for start() --
-- which is what SPOONS.md asks of a Spoon, and what lets a caller set
-- profile and userDir in between.
----------------------------------------------------------------------

local ready = false

local function phase(name, fn)
  local stop = M.span("setup." .. name)
  fn()
  stop()
end

local function setup()
  M.userDir = M.userDir or M.defaultUserDir()
  M.profile = M.chooseProfile()

  -- The profile's own settings.json: what a setting reports as set, and
  -- where a switch is written.
  local mine = M.readJSONC(M.profileDir() .. "/settings.json")
  M.userSettings = type(mine) == "table" and mine or {}

  M.registerControls()
  phase("presenters", M.loadPresenters)
  phase("extensions", M.loadExtensions)
  phase("matchers", M.loadMatchers)
  phase("rankers", M.loadRankers)
  phase("viewFiles", M.noticeViewFiles)
  phase("textCommandViews", M.registerTextCommandViews)

  -- Last, so the settings beat every default declared above.
  phase("settings", M.loadSettings)
  phase("keybindings", function()
    M.loadKeybindings()
    M.addHotkeys(M.hotkeyMapping)
  end)

  phase("binding", M.bindKeybindings)

  -- Chords come from keybindings alone, so there is one place to look.
  for _, spec in ipairs(M.views) do
    if spec.key then
      M.problem("picker " .. tostring(spec.name),
        ("key %q is not read; bind it in keybindings.json: "
         .. "{ \"key\": %q, \"command\": \"quickOpen\", \"args\": { \"view\": %q } }")
        :format(tostring(spec.key), tostring(spec.key), tostring(spec.name)))
    end
  end
end

function M.setup()
  if ready then return M end
  ready = true
  M.traced("setup", nil, setup)
  return M
end

-- SPOONS.md's: { enter = "alt+space" } or { enter = { { "alt" }, "space" } }
-- is a global keybinding entering the layer, in place of the ones before it.
function M.bindHotkeys(mapping)
  if type(mapping) ~= "table" then return M end
  for name, key in pairs(mapping) do M.hotkeyMapping[name] = key end
  if ready then
    M.addHotkeys(mapping)
    for _, entry in ipairs(M.effectiveKeybindings()) do
      if M.keybindingSource(entry) == "bindHotkeys" then M.checkKeybinding(entry, "bindHotkeys") end
    end
    if M.globalKeybindingsBound() then M.bindGlobalKeybindings() end
  end
  return M
end

function M.start()
  M.setup()

  -- Each subsystem starts on its own. One that throws during start would
  -- otherwise take the whole init.lua with it and leave no Hammerspoon
  -- at all -- a malformed Spotlight predicate is enough. Degrade, log,
  -- keep going.
  local function safely(label, fn)
    local ok, err = pcall(fn)
    if not ok then
      M.log.e(label .. " failed to start: " .. tostring(err))
    end
    return ok
  end

  M.traced("start", nil, function()
    -- Catches anything installed somewhere the candidate lists do not
    -- name. Asynchronous, so a slow login shell never delays the layer.
    if M.loginShellLookup() then phase("tools", function() safely("tools", M.tools.refresh) end) end

    -- In dependency order, each guarded on its own.
    safely("extensions", M.startExtensions)

    -- Before the problems, so a key that could not be bound is one of them.
    phase("globalKeybindings", function() safely("global keybindings", M.bindGlobalKeybindings) end)

    phase("problems", function() safely("problems", M.reportProblems) end)
  end)

  return M
end

function M.stop()
  modal:exit()
  M.unbindGlobalKeybindings()
  M.stopExtensions()
  return M
end

----------------------------------------------------------------------
-- THE PUBLIC LAYER
--
-- What init.lua holds and the console reaches: starting and stopping,
-- choosing a profile first, and running a command.
----------------------------------------------------------------------

local PUBLIC = { start = true, stop = true, bindHotkeys = true, executeCommand = true,
                 setLogLevel = true, apiVersion = true }
local SETTABLE = { profile = true, userDir = true }

M.public = setmetatable({}, {
  __index = function(_, key)
    if PUBLIC[key] or SETTABLE[key] then return M[key] end
    if key == "problems" then return M.getProblems() end
    error(("CommandLayer: %s is not public"):format(tostring(key)), 2)
  end,
  __newindex = function(_, key, value)
    if SETTABLE[key] then M[key] = value return end
    error(("CommandLayer: %s cannot be set"):format(tostring(key)), 2)
  end,
})

----------------------------------------------------------------------
-- RELOADING
----------------------------------------------------------------------

-- Stopped, what setup made undone, and started again, so every file is read
-- anew without hs.reload, which restarts the rest of Hammerspoon's
-- configuration too. The profile chosen and what hs.settings records stay.
function M.reload(opts)
  if type(opts) == "table" and opts.ifChanged and not M.profileFilesChanged() then return false end
  M.stop()
  M.unloadPlugins()
  for _, list in ipairs({ M.keybindings, M.problems }) do
    for i = #list, 1, -1 do list[i] = nil end
  end
  M.keybindingsChanged()
  for name in pairs(M.prefixes) do M.prefixes[name] = nil end
  M.unbindKeybindings()
  M.session.pendingEntries = {}
  ready = false
  M.start()
  return true
end
