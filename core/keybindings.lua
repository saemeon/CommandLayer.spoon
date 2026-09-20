-- Keybindings: the files read in order, removals applied, an entry run.

local M = ...

local modal = M.modal

-- Which file each keybinding came from, for naming it in a problem.
local source = setmetatable({}, { __mode = "k" })

-- What bindHotkeys was given, applied again whenever the files are read again.
M.hotkeyMapping = {}

function M.keybindingSource(entry)
  return source[entry] or "keybindings"
end

-- The default profile's keybindings.json, while another profile is active
-- and says it uses them -- VS Code's "Use Default Profile" for keyboard
-- shortcuts -- else nil. The profile's own come after, so they still win.
function M.defaultProfileKeybindings()
  local use = type(M.settings) == "table" and M.settings.useDefaultProfile
  if type(use) ~= "table" or use.keybindings ~= true or not M.userDir then return nil end
  local own = M.profileFolders(M.profile)
  if own[#own] == M.userDir then return nil end
  return M.userDir .. "/keybindings.json"
end

-- The files in order: the shipped defaults, the default profile's where the
-- active one uses them, then the profile's own.
function M.keybindingFiles()
  local sources = { M.SPOON_DIR .. "config/defaultKeybindings.jsonc" }
  sources[#sources + 1] = M.defaultProfileKeybindings()
  for _, folder in ipairs(M.profileFolders(M.profile)) do
    sources[#sources + 1] = folder .. "/keybindings.json"
  end
  return sources
end

-- A list, not merged: a "-" entry is what removes an earlier one.
function M.loadKeybindings()
  local sources = M.keybindingFiles()
  for _, path in ipairs(sources) do
    local list = M.readJSONC(path)
    if list ~= nil and not M.isList(list) and next(list) ~= nil then
      M.problem(path, "should be a list of keybindings")
    elseif M.isList(list) then
      for _, entry in ipairs(list) do
        M.checkKeybinding(entry, path)
        if type(entry) == "table" then
          M.keybindings[#M.keybindings + 1] = entry
          source[entry] = path
        end
      end
    end
  end
  M.keybindingsChanged()
  return M
end

-- SPOONS.md's bindHotkeys, after every file: `enter` replaces the chords
-- that enter the layer so far, as a removal and an entry of its own would
-- in keybindings.json.
local HOTKEY_COMMANDS = { enter = "quickOpen" }

function M.addHotkeys(mapping)
  local label = "bindHotkeys"
  for name, key in pairs(mapping) do
    local command = HOTKEY_COMMANDS[name]
    if not command then
      M.problem(label, ("%q is not a hotkey; enter is"):format(tostring(name)))
    else
      for _, earlier in ipairs(M.effectiveKeybindings()) do
        if M.entersLayer(earlier) then
          local removal = { key = earlier.key, command = "-" .. command }
          M.keybindings[#M.keybindings + 1] = removal
          source[removal] = label
        end
      end
      local entry = { key = key, command = command, global = true }
      M.keybindings[#M.keybindings + 1] = entry
      source[entry] = label
    end
  end
  M.keybindingsChanged()
end

-- Held, a key runs its entry again only where the entry says so, or where
-- the control it names repeats.
function M.keybindingRepeats(entry)
  if type(entry) ~= "table" then return false end
  if entry["repeat"] ~= nil then return entry["repeat"] == true end
  for _, control in ipairs(M.controls) do
    if control.name == entry.command then return control.repeats == true end
  end
  return false
end

-- An entry that is a problem is left out: one naming nothing would run
-- nothing, and one on a text-editing key would take it from the field.
function M.bindableKeybinding(entry)
  if type(entry) ~= "table" or not M.knowsCommand(entry.command) then return false end
  if not M.chordId(entry.key) or M.editsText(entry.key) then return false end
  if entry.global ~= nil and type(entry.global) ~= "boolean" then return false end
  local view = entry.command == "quickOpen" and type(entry.args) == "table" and entry.args.view
  return view == nil or view == false or M.viewNamed(view) ~= nil
end

-- The keys only a press knows, worked out once for it rather than on every
-- keystroke: the picker on screen, whether anything is typed after its
-- prefix, and what the highlighted row is. With the layer closed, a
-- context of its own.
local function pressContext()
  local top = M.topView()
  if not top then return M.buildContext() end
  local picker, row = M.activePicker(), nil
  if picker and picker.selected then
    local ok, selected = pcall(picker.selected)
    if ok and type(selected) == "table" then row = selected end
  end
  local subject = row and type(row.subject) == "table" and row.subject or nil
  return M.argContext(top.ctx or {}, {
    activeView = top.name,
    hasQuery = (top.query or "") ~= "",
    viewItem = subject and subject.kind or nil,
  })
end

-- Its when, then its command's enablement: a greyed command is not run
-- from a key either, and the key falls to the entry before it. `context`
-- is asked only by an entry with something to check, so a key with none
-- captures nothing to press it.
local function applies(entry, context)
  if entry.when ~= nil and entry.when ~= "" and not M.when(entry.when, context()) then
    return false, "when is false: " .. tostring(entry.when)
  end
  local command = M.getCommand(entry.command)
  if command and command.enablement and not M.when(command.enablement, context()) then
    return false, "not enabled: " .. tostring(command.enablement)
  end
  return true
end

-- VS Code's keyboard shortcuts troubleshooting, as one debug line per press,
-- written only with "logLevel": "debug" as VS Code's is off until toggled:
-- the chord, then each entry on it newest first with the file it came from
-- and why it did not run, until the one that did. A key that does nothing
-- otherwise says nothing, and which of three entries won is not guessable.
local function explain(key, walked, chosen)
  if not M.logs("debug") then return end
  local parts = {}
  for _, step in ipairs(walked) do
    parts[#parts + 1] = ("%s (%s) %s"):format(tostring(step.entry.command),
      tostring(M.keybindingSource and M.keybindingSource(step.entry) or "?"), step.why)
  end
  M.log.d(("key %s -> %s%s"):format(tostring(key),
    chosen and tostring(chosen.command) or "nothing",
    #parts > 0 and (": " .. table.concat(parts, "; ")) or ""))
end

-- As VS Code resolves a key: its entries newest first, so a profile's beats
-- a default, and the first that applies is the one. `global` is a press on
-- the key bound in every app, which only a global entry answers: while the
-- layer is open the modal's key on the same chord shadows it, and that one
-- walks every entry. Returns the entry and the context, if one was made.
function M.resolveKeybinding(key, ctx, global)
  local id = M.chordId(key)
  if not id then return nil end
  local function context()
    ctx = ctx or pressContext()
    return ctx
  end
  local entries, walked = M.effectiveKeybindings(), {}
  for i = #entries, 1, -1 do
    local entry = entries[i]
    if M.chordId(entry.key) == id then
      local ok, why
      if global and entry.global ~= true then
        ok, why = false, "not global, and the layer is closed"
      elseif not M.bindableKeybinding(entry) then
        ok, why = false, "not bound: a problem"
      else
        ok, why = applies(entry, context)
      end
      walked[#walked + 1] = { entry = entry, why = ok and "runs" or why }
      if ok then
        explain(key, walked, entry)
        return entry, ctx
      end
    end
  end
  explain(key, walked, nil)
  return nil, ctx
end

-- What a bound key does. `held` is the key repeating while still down. A
-- context made to resolve it with the layer closed is the one it runs in.
function M.pressKeybinding(key, held, global)
  local entry, ctx = M.resolveKeybinding(key, nil, global)
  if not entry or (held and not M.keybindingRepeats(entry)) then return false end
  return M.executeCommand(entry.command, entry.args, not M.topView() and ctx or nil)
end

----------------------------------------------------------------------
-- BINDING
----------------------------------------------------------------------

-- Checked here as well as when read, so a mistake is reported at start
-- rather than found on the first press of a dead key. An entry added by
-- code rather than read from a file is checked here for the first time.
local function checkBound(entry)
  local file = M.keybindingSource(entry)
  M.checkKeybinding(entry, file)
  if not M.knowsCommand(entry.command) then return end
  local view = entry.command == "quickOpen" and type(entry.args) == "table" and entry.args.view
  if view ~= nil and view ~= false and not M.viewNamed(view) then
    M.problem(file, ("%s: there is no picker %q"):format(tostring(entry.key), tostring(view)))
  end
end

-- hs.hotkey.modal holds what it bound in `keys`; binding a chord again
-- would add a second hotkey beside the first.
function M.unbindKeybindings()
  for _, hotkey in ipairs(modal.keys or {}) do hotkey:delete() end
  modal.keys = {}
end

-- Each key once, however many entries share it: which of them runs is
-- decided when it is pressed, against the picker on screen then. A chord
-- only global entries use is not bound in the modal, where it would
-- shadow the global key for nothing.
function M.bindKeybindings()
  local entries = M.effectiveKeybindings()
  M.checkKeybindingCollisions(entries, M.keybindingSource)
  local keys, order, enters = {}, {}, false
  for _, entry in ipairs(entries) do
    checkBound(entry)
    if M.bindableKeybinding(entry) and entry.global ~= true then
      local id = M.chordId(entry.key)
      if not keys[id] then
        local mods, key = M.chord(entry.key)
        keys[id] = { mods = mods, key = key }
        order[#order + 1] = id
      end
      keys[id].repeats = keys[id].repeats or M.keybindingRepeats(entry)
    end
    enters = enters or (M.entersLayer(entry) and M.bindableKeybinding(entry))
  end
  for _, id in ipairs(order) do
    local bound = keys[id]
    -- No message argument at all: hs.hotkey reads a nil in its place as no
    -- message and shifts the rest down, which ran a press on release and
    -- dropped the repeat.
    modal:bind(bound.mods, bound.key, function() M.pressKeybinding(id) end, nil,
               bound.repeats and function() M.pressKeybinding(id, true) end or nil)
  end
  -- The modal enables its keys as it is entered, so one bound while the
  -- layer is open would stay dead until the next time.
  if M.topView() then
    for _, hotkey in ipairs(modal.keys or {}) do hotkey:enable() end
  end
  if not enters then
    M.problem("keybindings", 'no global keybinding runs quickOpen, so no key opens the layer: '
                             .. '{ "key": "alt+space", "command": "quickOpen", "global": true }')
  end
end

-- Global keys are claimed in start(), not on load or in setup: loading a
-- module should not take a system-wide hotkey, and an hs.reload needs a
-- stop() to give them back. Nil while none are claimed.
local globalHotkeys

function M.unbindGlobalKeybindings()
  for _, hotkey in ipairs(globalHotkeys or {}) do hotkey:delete() end
  globalHotkeys = nil
end

function M.globalKeybindingsBound()
  return globalHotkeys ~= nil
end

-- With hs.hotkey rather than the modal, so they work while the layer is
-- closed. hs.hotkey shadows an enabled key with the one enabled after it, so
-- while the layer is open the modal's key on a shared chord is the one
-- pressed. A key macOS or another app holds does not enable, and says so.
function M.bindGlobalKeybindings()
  M.unbindGlobalKeybindings()
  globalHotkeys = {}
  local keys, order = {}, {}
  for _, entry in ipairs(M.effectiveKeybindings()) do
    if entry.global == true and M.bindableKeybinding(entry) then
      local id = M.chordId(entry.key)
      if not keys[id] then
        local mods, key = M.chord(entry.key)
        keys[id] = { mods = mods, key = key, written = entry.key, file = M.keybindingSource(entry) }
        order[#order + 1] = id
      end
      keys[id].repeats = keys[id].repeats or M.keybindingRepeats(entry)
    end
  end
  for _, id in ipairs(order) do
    local bound = keys[id]
    -- No message argument, as for the modal's keys.
    local hotkey = hs.hotkey.new(bound.mods, bound.key, function() M.pressKeybinding(id, false, true) end, nil,
                                 bound.repeats and function() M.pressKeybinding(id, true, true) end or nil)
    globalHotkeys[#globalHotkeys + 1] = hotkey
    if not hotkey:enable() then
      M.problem(bound.file, ("%s could not be bound: macOS or another app holds it")
                            :format(tostring(bound.written)))
    end
  end
end

----------------------------------------------------------------------
-- WHERE ONE CAME FROM, AND READING THE FILES AGAIN
----------------------------------------------------------------------

-- Where an entry came from, as the keyboard shortcuts editor's Source says:
-- "default" for the shipped file, "user" for the active profile's own file,
-- which a change is written to, "defaultProfile" for the default profile's
-- used by another, "profile" for a shipped profile's, and "bindHotkeys" for
-- init.lua's. Nil for an entry no file or call gave.
function M.keybindingOrigin(entry)
  local path = source[entry]
  if path == nil then return nil end
  if path == "bindHotkeys" then return "bindHotkeys" end
  if path == M.SPOON_DIR .. "config/defaultKeybindings.jsonc" then return "default" end
  if path == M.profileFile("keybindings.json") then return "user" end
  if path == M.defaultProfileKeybindings() then return "defaultProfile" end
  return "profile"
end

-- The files read again and every key bound again, forgetting what they said
-- before. Reading remembers what each file says, so the reload that watches
-- the profile's files takes a write of a plugin's own for no change.
function M.keybindingsWritten()
  for i = #M.keybindings, 1, -1 do M.keybindings[i] = nil end
  for _, path in ipairs(M.keybindingFiles()) do M.forgetProblems(path) end
  M.forgetProblems("keybindings")
  M.forgetProblems("bindHotkeys")
  M.loadKeybindings()
  M.addHotkeys(M.hotkeyMapping)
  M.unbindKeybindings()
  M.bindKeybindings()
  if globalHotkeys then M.bindGlobalKeybindings() end
end

-- Every keybinding in effect as data (M.listShapes.keybinding), a fresh copy
-- per call: its source is worked out from the entry itself, never from what
-- it says, so a copy is all a plugin writing keybindings.json needs.
function M.getKeybindings()
  local out = {}
  for i, entry in ipairs(M.effectiveKeybindings()) do
    out[i] = { key = entry.key, command = entry.command, args = M.copyData(entry.args),
               when = entry.when, global = entry.global, ["repeat"] = entry["repeat"],
               source = M.keybindingOrigin(entry), opens = M.quickOpenTarget(entry) }
  end
  return out
end

----------------------------------------------------------------------
-- RUNNING
----------------------------------------------------------------------

-- One entry on its own, its when and enablement checked as a press would.
-- Logs rather than throws: a typo in a profile should cost one key, not
-- every key bound after it.
function M.runKeybinding(entry)
  if type(entry) ~= "table" then return M.executeCommand(nil) end
  local ctx
  local function context()
    ctx = ctx or pressContext()
    return ctx
  end
  if not applies(entry, context) then return false end
  return M.executeCommand(entry.command, entry.args, not M.topView() and ctx or nil)
end
