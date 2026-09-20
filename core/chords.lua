-- Reading a chord from the way it is written, and the keybindings in effect.

local M = ...

----------------------------------------------------------------------
-- CHORDS
--
-- Written the way you would say one: "cmd+space", "alt+o". Nothing is
-- implied -- a profile that means cmd has to say cmd.
----------------------------------------------------------------------

local MODIFIERS = {
  cmd = "cmd", command = "cmd",
  ctrl = "ctrl", control = "ctrl",
  alt = "alt", opt = "alt", option = "alt",
  shift = "shift",
  fn = "fn",
}

-- All four at once, as a remapped caps lock presses them: no app binds the
-- combination, so a global chord on it takes nothing from anyone.
local HYPER = { "cmd", "alt", "ctrl", "shift" }

local function addModifier(mods, name)
  if name == "hyper" then
    for _, mod in ipairs(HYPER) do mods[#mods + 1] = mod end
  else
    mods[#mods + 1] = MODIFIERS[name] or name
  end
end

-- Exactly one key. A mistyped modifier is otherwise a second key, and
-- whichever came last wins -- "cmmd+k" would bind a bare k, which inside
-- the layer swallows every k you type into the search field.
local function chord(spec)
  if type(spec) == "string" then
    local mods, key = {}, nil
    for word in spec:gmatch("[^+]+") do
      local part = word:match("^%s*(.-)%s*$"):lower()
      if MODIFIERS[part] or part == "hyper" then
        addModifier(mods, part)
      elseif key then
        return nil
      else
        key = part
      end
    end
    if not key then return nil end
    return mods, key
  end

  -- { { "cmd" }, "space" }, as hs.hotkey.bind takes it; hs.hotkey has no
  -- hyper, so it is spelled out here too.
  if type(spec) == "table" and spec[2] then
    if type(spec[1]) ~= "table" then return spec[1], spec[2] end
    local mods = {}
    for _, mod in ipairs(spec[1]) do addModifier(mods, mod) end
    return mods, spec[2]
  end

  return nil
end

M.chord = chord

-- One spelling per chord, modifiers sorted, so "Shift+Cmd+P" and
-- "cmd+shift+p" are one key to bind and to resolve. Nil when unreadable.
function M.chordId(spec)
  local mods, key = chord(spec)
  if not key then return nil end
  local seen, sorted = {}, {}
  for _, mod in ipairs(mods) do
    if not seen[mod] then
      seen[mod] = true
      sorted[#sorted + 1] = mod
    end
  end
  table.sort(sorted)
  sorted[#sorted + 1] = key
  return table.concat(sorted, "+")
end

-- A chord as keybindings.json writes it, from what a key press held: the
-- modifiers in VS Code's order, hyper for all four, and the key as
-- hs.keycodes names it, which is what binding it reads back. fn is left
-- out: macOS sets it for the arrows and function keys on their own.
local WRITTEN_ORDER = { "ctrl", "shift", "alt", "cmd" }

function M.chordText(flags, key)
  if type(key) ~= "string" or key == "" then return nil end
  flags = type(flags) == "table" and flags or {}
  local parts = {}
  if flags.ctrl and flags.shift and flags.alt and flags.cmd then
    parts[1] = "hyper"
  else
    for _, mod in ipairs(WRITTEN_ORDER) do
      if flags[mod] then parts[#parts + 1] = mod end
    end
  end
  parts[#parts + 1] = key:lower()
  return table.concat(parts, "+")
end

-- What the search field needs while the layer is open. A binding in the
-- modal takes the key before the field sees it, so binding one of these
-- makes typing, deleting, moving the caret or pasting stop working.
-- Arrows up and down, return, tab and escape are the picker's, not text.
local CARET_KEYS = { left = true, right = true, home = true, ["end"] = true }
local DELETE_KEYS = { delete = true, backspace = true, forwarddelete = true }
local EDITING_COMMANDS = { a = true, c = true, v = true, x = true, z = true }

function M.editsText(spec)
  local mods, key = chord(spec)
  if not key then return false end
  local has = {}
  for _, mod in ipairs(mods) do has[mod] = true end
  if has.ctrl or has.fn then return false end
  if CARET_KEYS[key] then return true end
  if DELETE_KEYS[key] then return true end
  -- Typed characters, a capital included.
  if (#key == 1 or key == "space") and not has.cmd and not has.alt then return true end
  -- Select all, copy, paste, cut, undo, and redo with shift.
  return has.cmd and not has.alt and #key == 1 and EDITING_COMMANDS[key] == true
         and (not has.shift or key == "z")
end

-- What entering lands on, overridable from the profile. Declared here
-- because loadSettings runs before anything binds or opens.
M.defaultView = "root"

-- What the actions control opens for the highlighted row.
M.actionsView = "actions"

----------------------------------------------------------------------
-- KEYBINDINGS
----------------------------------------------------------------------

-- The kernel binds no chord of its own: which keys move, open and act is a
-- preference, and lives in keybindings files -- the shipped
-- config/defaultKeybindings.jsonc, then the profile's keybindings.json.
-- Arrows, return and escape are the chooser's without any binding.
M.keybindings = {}

-- Compared as read rather than as written, so removing "Cmd+K" removes
-- the default "cmd+k".
local function sameChord(a, b)
  local idA, idB = M.chordId(a), M.chordId(b)
  if not (idA and idB) then return a == b end
  return idA == idB
end

-- In order, so a removal only takes out what came before it -- the
-- defaults, and whatever the profile wrote above it -- and an entry added
-- after a removal survives it, as in VS Code's keybindings.json.
function M.effectiveKeybindings()
  local list = {}
  for _, entry in ipairs(M.keybindings) do
    local command = type(entry) == "table" and entry.command
    local removed = type(command) == "string" and command:match("^%-(.+)$")
    if removed then
      local kept = {}
      for _, earlier in ipairs(list) do
        if not (earlier.command == removed
                and (entry.key == nil or sameChord(earlier.key, entry.key))) then
          kept[#kept + 1] = earlier
        end
      end
      list = kept
    elseif type(entry) == "table" then
      -- Kept even without a readable command, so setup can log it.
      list[#list + 1] = entry
    end
  end
  return list
end

-- The first chord bound to each command without a `when`, for its row. Built
-- once per list rather than looked up per command per open. Kept against
-- the list and its length, so an entry added or removed shows at once;
-- keybindingsChanged forgets it outright, for a list read again.
local firstChords, firstChordsOf, firstChordsCount

function M.firstChords()
  if firstChords and firstChordsOf == M.keybindings and firstChordsCount == #M.keybindings then
    return firstChords
  end
  local map = {}
  for _, entry in ipairs(M.effectiveKeybindings()) do
    local id = entry.command
    if type(id) == "string" and type(entry.key) == "string" and not entry.when and map[id] == nil then
      map[id] = entry.key
    end
  end
  firstChords, firstChordsOf, firstChordsCount = map, M.keybindings, #M.keybindings
  return map
end

function M.keybindingsChanged()
  firstChords = nil
end

-- An entry that enters the layer: global, and opening the default view.
function M.entersLayer(entry)
  if not (type(entry) == "table" and entry.global == true and entry.command == "quickOpen") then
    return false
  end
  local args = type(entry.args) == "table" and entry.args or {}
  return args.view == nil and args.query == nil
end

function M.keybindingsFor(name)
  local chords = {}
  for _, entry in ipairs(M.effectiveKeybindings()) do
    if entry.command == name and entry.key ~= nil then
      chords[#chords + 1] = entry.key
    end
  end
  return chords
end
