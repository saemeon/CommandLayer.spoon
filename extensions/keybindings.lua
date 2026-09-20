-- VS Code's keyboard shortcuts editor's verbs on a keybinding row, under its
-- own ids: Remove Keybinding, and Change Keybinding, which takes the new
-- chord as it is pressed.

local M = {}

-- Until a capture ends every key press goes to it, so one left waiting gives
-- the keyboard back on its own.
M.captureSeconds = 10

-- A keybinding's own fields, in the order VS Code writes them.
local ENTRY_FIELDS = { "key", "command", "when", "args", "global", "repeat" }

function M.extension(cl)
  local capture

  ----------------------------------------------------------------------
  -- WRITING
  --
  -- As VS Code's keyboard shortcuts editor writes: into the active profile's
  -- own keybindings.json, in its text, so comments and layout survive.
  ----------------------------------------------------------------------

  local function readText(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("a")
    handle:close()
    return text
  end

  -- profileFile makes a missing file with its folders -- a shipped profile's
  -- own under the user folder is not there until a first change -- and one
  -- that is there is written over.
  local function writeOwn(name, text)
    local path = cl.profileFile(name)
    local handle = io.open(path, "r")
    if not handle then return cl.profileFile(name, text) ~= nil end
    handle:close()
    handle = io.open(path, "w")
    if not handle then return false end
    handle:write(text)
    handle:close()
    return true
  end

  -- One spelling per chord, so "Shift+Cmd+P" and "cmd+shift+p" are one key.
  local function chordId(spec)
    local mods, key = cl.chord(spec)
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

  -- The last element of `list` written as `entry` is: an identical one before
  -- it is the same keybinding, and removing either leaves the other. JSON
  -- encodes with sorted keys, so equal values encode alike.
  local function indexIn(list, entry)
    for i = #list, 1, -1 do
      local candidate, same = list[i], type(list[i]) == "table"
      for _, field in ipairs(ENTRY_FIELDS) do
        same = same and cl.encodeJSON(candidate[field]) == cl.encodeJSON(entry[field])
      end
      if same then return i end
    end
  end

  local function refused(why)
    hs.alert.show(why == "not a list" and "keybindings.json should be a list of keybindings" or tostring(why))
    return false
  end

  -- `edit(text, list)` gives the new text, or nil and why not. Read from disk
  -- at the moment of writing, so a hand edit since is kept; refused while the
  -- file does not parse, since an edit needs to know where things are.
  local function writeKeybindings(edit)
    local path = cl.profileFile("keybindings.json")
    local text = readText(path)
    if not text or not text:find("%S") then text = "[\n]\n" end
    local list = cl.decodeJSONC(text)
    if list == nil then return refused("keybindings.json does not parse, so it was not changed") end
    local edited, why = edit(text, list)
    if not edited then return refused(why) end
    if not writeOwn("keybindings.json", edited) then
      cl.problem(path .. " could not be written")
      return false
    end
    cl.keybindingsWritten()
    return true
  end

  -- The person's own entry goes from their file; any other is taken out by a
  -- removal naming its key after it, which is all a file can do to another's.
  -- `entry` is a copy from getKeybindings, whose source says which.
  local function withoutEntry(text, list, entry)
    if entry.source == "user" then
      local index = type(list) == "table" and list[1] ~= nil and indexIn(list, entry)
      if not index then return nil, "That keybinding is no longer in keybindings.json" end
      return cl.removeJSONCElement(text, {}, index)
    elseif entry.source == "default" or entry.source == "profile" then
      if type(entry.key) ~= "string" or type(entry.command) ~= "string" then
        return nil, "A keybinding without a key and a command cannot be removed"
      end
      return cl.appendJSONCElement(text, {}, { key = entry.key, command = "-" .. entry.command }, ENTRY_FIELDS)
    elseif entry.source == "bindHotkeys" then
      return nil, "That keybinding is init.lua's bindHotkeys; change it there"
    end
    return nil, "That keybinding is in no file"
  end

  function M.removeKeybinding(entry)
    if type(entry) ~= "table" then return false end
    return writeKeybindings(function(text, list) return withoutEntry(text, list, entry) end)
  end

  -- Remove, then the same entry on `key` after the removal, so the removal
  -- cannot take it out too.
  function M.changeKeybinding(entry, key)
    if type(entry) ~= "table" then return false end
    if not chordId(key) then return refused(("%q is not a key"):format(tostring(key))) end
    if chordId(key) == chordId(entry.key) then return true end
    if cl.editsText(key) then
      local who = entry.global == true and "every app" or "the search field"
      return refused(("%s: %s needs this key to edit text"):format(key, who))
    end
    return writeKeybindings(function(text, list)
      local removed, why = withoutEntry(text, list, entry)
      if not removed then return nil, why end
      local changed = {}
      for _, field in ipairs(ENTRY_FIELDS) do changed[field] = entry[field] end
      changed.key = key
      return cl.appendJSONCElement(removed, {}, changed, ENTRY_FIELDS)
    end)
  end

  ----------------------------------------------------------------------
  -- THE PICKER
  ----------------------------------------------------------------------

  local function stopCapture()
    local c = capture
    if not c then return end
    capture = nil
    if c.tap then c.tap.dispose() end
    if c.timer then c.timer.dispose() end
    hs.alert.closeSpecific(c.alert)
  end

  -- Going back draws the list as it was built; asked again once it is on
  -- screen, it is built from the keybindings as they now are.
  local function redraw()
    cl.after(0, function() cl.refresh() end)
  end

  local function reopen(subject)
    if type(subject.view) == "string" then cl.executeCommand("quickOpen", { view = subject.view }) end
  end

  -- Started once the layer has closed: while it is open, its own chords are
  -- the modal's, which takes a bound key before an event tap sees it.
  local function capturePress(subject)
    stopCapture()
    local c = {}
    capture = c
    local name = subject.key and ("the keys for " .. tostring(subject.key)) or "the new keys"
    c.alert = hs.alert.show("Press " .. name .. ", or escape", M.captureSeconds)

    local tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
      if capture ~= c then return false end
      local key = hs.keycodes.map[event:getKeyCode()]
      local flags = event:getFlags() or {}
      stopCapture()
      local bare = not (flags.cmd or flags.alt or flags.ctrl or flags.shift)
      -- Written and bound a turn later: macOS switches off an event tap
      -- whose callback keeps it waiting.
      cl.after(0, function()
        if not (key == "escape" and bare) then
          local chord = cl.chordText(flags, key)
          if chord then
            M.changeKeybinding(subject.entry, chord)
          else
            hs.alert.show("That key has no name to write")
          end
        end
        reopen(subject)
      end)
      -- The chord is the answer, not something for the app in front.
      return true
    end)
    c.tap = cl.watch(tap)
    c.timer = cl.after(M.captureSeconds, function()
      if capture == c then stopCapture() end
    end)
  end

  M.stop = function()
    if capture then hs.alert.closeSpecific(capture.alert) end
    capture = nil
  end

  local function keybindingInput(description)
    return { { id = "keybinding", description = description,
               picker = { when = "viewItem == 'keybinding'" } } }
  end

  -- VS Code's Source column.
  local SOURCES = { default = "Default", user = "User", profile = "Profile", bindHotkeys = "init.lua bindHotkeys" }

  local function commandTitle(entry, command)
    if not command then return tostring(entry.command) end
    local title = tostring(command.title):gsub("%${query}", "…")
    if command.category then title = command.category .. ": " .. title end
    -- Every quickOpen entry is the same command; which picker it opens is
    -- what tells them apart.
    if entry.opens then title = title .. " -- " .. tostring(entry.opens) end
    return title
  end

  return {
    displayName = "Keyboard Shortcuts",
    description = "Every keybinding in effect, in the Keyboard Shortcuts picker, removed or changed in "
                  .. "keybindings.json",
    menus       = { "keybindings" },

    -- As VS Code's Keyboard Shortcuts editor lists them. Picking one runs its
    -- command; cmd+k offers what can be done to the keybinding itself.
    items = function(ctx)
      local rows = {}
      for _, entry in ipairs(cl.getKeybindings()) do
        local command = type(entry.command) == "string" and cl.getCommand(entry.command) or nil
        local key = tostring(entry.key)

        local detail = { SOURCES[entry.source] or "No file" }
        if entry.global == true then detail[#detail + 1] = "in every app" end
        if type(entry.when) == "string" and entry.when ~= "" then detail[#detail + 1] = "when " .. entry.when end
        if not command then detail[#detail + 1] = "no such command" end

        rows[#rows + 1] = {
          label       = commandTitle(entry, command),
          description = key,
          detail      = table.concat(detail, ", "),
          keywords    = { key, tostring(entry.command) },
          -- A command that is not registered has nothing to run.
          command     = command and entry.command or nil,
          args        = command and type(entry.args) == "table" and entry.args or nil,
          ctx         = ctx,
          -- The entry, since removing or changing it is told by it which file
          -- it came from; its source is part of what it is, so the same chord
          -- in two files is two rows. `view` is where a verb that closes the
          -- layer comes back to.
          subject     = { kind = "keybinding", id = key .. " " .. tostring(entry.command) .. " "
                                                    .. tostring(entry.when or "") .. " " .. tostring(entry.source),
                          key = entry.key, command = entry.command, when = entry.when,
                          source = entry.source, entry = entry, view = "keybindings" },
        }
      end
      return rows
    end,

    commands = {
      { id = "keybindings.editor.removeKeybinding", title = "Remove Keybinding",
        icon = "$(trash)", menus = { ["view/item/context"] = true },
        targetName = "${input:keybinding.key}", after = "back",
        inputs = keybindingInput("Remove keybinding"),
        run = function(args)
          if M.removeKeybinding(args.keybinding.entry) then redraw() end
        end },

      { id = "keybindings.editor.defineKeybinding", title = "Change Keybinding…",
        icon = "$(edit)", menus = { ["view/item/context"] = true },
        inputs = keybindingInput("Change keybinding"),
        run = function(args) capturePress(args.keybinding) end },
    },
  }
end

return M
