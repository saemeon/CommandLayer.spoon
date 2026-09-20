-- The command registry, command rows, and running a command or a row.

local M = ...

----------------------------------------------------------------------
-- COMMANDS
--
-- Verbs with a stable id, as VS Code registers them. What a picker
-- scrapes at runtime -- menu items, apps, tabs -- stays a plain row and
-- reaches a command by calling it with args.
----------------------------------------------------------------------

local list, byId = {}, {}

-- A command either runs Lua, `run(args, ctx)`, or runs another command
-- with args of its own, `command` and `args` -- as a keybinding does, and
-- as a destination such as system.open is reached. `inputs` are what it
-- asks for first.
function M.registerCommand(id, spec)
  local command = {}
  for k, v in pairs(type(spec) == "table" and spec or {}) do command[k] = v end

  if type(id) ~= "string" or id == "" or type(command.title) ~= "string"
     or not (type(command.run) == "function" or type(command.command) == "string") then
    M.log.w("command '" .. tostring(id)
          .. "' needs a title, and a run or a command to run")
    return false
  end

  command.id = id
  command.menus = M.menusOfCommand(command)

  local existing = byId[id]
  byId[id] = command
  if existing then
    for i, other in ipairs(list) do
      if other == existing then list[i] = command end
    end
  else
    list[#list + 1] = command
  end
  return true
end

function M.getCommand(id)
  return byId[id]
end

function M.unregisterCommand(id, command)
  local existing = byId[id]
  if not existing or (command and existing ~= command) then return false end
  byId[id] = nil
  for i, other in ipairs(list) do
    if other == existing then table.remove(list, i) break end
  end
  return true
end

-- A copy, so a caller sorting or filtering it cannot reorder the rows.
function M.getCommands()
  local out = {}
  for i, command in ipairs(list) do out[i] = command end
  return out
end

-- For wherever a person reads it; an internal name like "appmenus" is not
-- a label.
local function capitalised(name)
  return (tostring(name):gsub("^%l", string.upper))
end

-- Dropped first, so an extension registered again under the same name
-- does not keep a command it no longer declares.
M.registerExtensionCommands = function(ext)
  local kept = {}
  for _, command in ipairs(list) do
    if command.extension == ext.name then
      byId[command.id] = nil
    else
      kept[#kept + 1] = command
    end
  end
  list = kept

  -- Taken from the spec now, so a command's row names its extension
  -- without asking the extension registry.
  local displayName = type(ext.displayName) == "string" and ext.displayName ~= ""
                      and ext.displayName or capitalised(ext.name)

  local prefix = tostring(ext.name) .. "."
  for _, spec in ipairs(type(ext.commands) == "table" and ext.commands or {}) do
    local id = type(spec) == "table" and spec.id
    -- One without these is not registered, and the schema says why.
    local shaped = type(id) == "string" and type(spec.title) == "string"
                   and (type(spec.run) == "function" or type(spec.command) == "string")
    if shaped and id:sub(1, #prefix) ~= prefix then
      M.problem("extension " .. tostring(ext.name),
        ("command %q is outside its namespace %q; skipped"):format(id, prefix))
    elseif shaped then
      local owned = {}
      for k, v in pairs(spec) do owned[k] = v end
      owned.extension = ext.name
      owned.extensionDisplayName = displayName
      M.registerCommand(id, owned)
    end
  end
end

----------------------------------------------------------------------
-- MENUS
----------------------------------------------------------------------

-- `menus` is a list of names, or VS Code's shape: a table from a menu's
-- name to `true` or `{ when = "..." }`, so a command can be in the palette
-- always and in the root only in one situation.
-- VS Code's view/item/context is cmd+k's menu about one row, built from the
-- input whose picker has a `when`; no picker lists it.
local ITEM_MENU = "view/item/context"

local function onMenu(own, wanted, ctx)
  if not wanted then return true end

  local function listed(name, entry)
    if name == ITEM_MENU then return false end
    if type(entry) == "table" and entry.when and not M.when(entry.when, ctx or {}) then
      return false
    end
    for _, want in ipairs(wanted) do
      if name == want then return true end
    end
    return false
  end

  if own[1] ~= nil then
    for _, name in ipairs(own) do
      if listed(name) then return true end
    end
    return false
  end
  for name, entry in pairs(own) do
    if type(name) == "string" and entry and listed(name, entry) then return true end
  end
  return false
end

M.onMenu = onMenu

function M.menusOfCommand(spec)
  return spec.menus or { "commandPalette" }
end

local function declares(own, name)
  if own[1] ~= nil then
    for _, each in ipairs(own) do
      if each == name then return true end
    end
    return false
  end
  return own[name] ~= nil and own[name] ~= false
end

-- A person's `<ext>.menus` setting, a menu's name to true or false, over what
-- the extension declares. settings.lua loads later and registers the reader.
local readMenuOverrides = function() return nil end

function M.registerMenuOverrides(fn)
  readMenuOverrides = fn
end

-- onMenu, with the owner's setting applied: a menu set false is not wanted,
-- and one set true is -- unless the owner declares that menu, when its own
-- `when` still decides. `cache`, one table per gather, keeps a setting from
-- being read per row.
function M.onOwnMenu(own, owner, wanted, ctx, cache)
  if not wanted then return true end
  local forced
  if owner and cache and cache[owner] ~= nil then
    forced = cache[owner] or nil
  elseif owner then
    local value = readMenuOverrides(owner)
    forced = type(value) == "table" and next(value) ~= nil and value or nil
    if cache then cache[owner] = forced or false end
  end
  if not forced then return onMenu(own, wanted, ctx) end

  local rest = {}
  for _, name in ipairs(wanted) do
    if forced[name] == true and not declares(own, name) then return true end
    if forced[name] ~= false then rest[#rest + 1] = name end
  end
  return #rest > 0 and onMenu(own, rest, ctx)
end

-- A command with no picker menu is only called, bound, or offered on cmd+k,
-- never a row.
function M.hasMenus(menus)
  if type(menus) ~= "table" then return false end
  for key, value in pairs(menus) do
    local name = type(key) == "string" and key or value
    if name ~= ITEM_MENU and value then return true end
  end
  return false
end

----------------------------------------------------------------------
-- COMMAND ROWS
----------------------------------------------------------------------

-- The same row whether gathered into a picker or built to collect a
-- command's arguments, so both are remembered under one key.
-- "Search YouTube for “${query}”" names the text a command was given, or an
-- ellipsis while there is none.
local function titleOf(command, text)
  local shown = (text and text ~= "") and text or "…"
  return (command.title:gsub("%${query}", (shown:gsub("%%", "%%%%"))))
end

M.commandTitle = titleOf

-- "Git: Clone…", as VS Code's palette writes it: the category is part of
-- what is matched, so typing "git" finds every Git command.
local function labelOf(command, text)
  local title = titleOf(command, text)
  if type(command.category) == "string" and command.category ~= "" then
    return command.category .. ": " .. title
  end
  return title
end

-- The first chord bound to the command, where it is: a row is where a
-- shortcut is learned. Read from the effective list, so a rebind shows.
local function chordFor(id)
  return M.firstChords()[id]
end

local function subTextOf(command)
  local source = command.extension
                 and (command.extensionDisplayName or capitalised(command.extension)) or nil
  local chord = chordFor(command.id)
  if source and chord then return source .. "  --  " .. chord end
  return chord or source
end

-- The answers a row stands for: what it was given, and what an input that
-- prefers what is in front would take when picked.
local function answersOf(command, args, ctx)
  local answers = {}
  for k, v in pairs(args or {}) do answers[k] = v end
  for _, input in ipairs(type(command.inputs) == "table" and command.inputs or {}) do
    if answers[input.id] == nil and input.preferCurrent and type(input.current) == "function" then
      local ok, value = pcall(input.current, ctx)
      if ok then answers[input.id] = value end
    end
  end
  return answers
end

-- A template filled from the context and the answers, or a function of them;
-- nothing, or only spaces, is no text.
local function textFrom(value, answers, ctx)
  local text
  if type(value) == "function" then
    local ok, result = pcall(value, answers, ctx or {})
    text = ok and result or nil
  elseif type(value) == "string" then
    text = M.resolve(value, M.argContext(ctx or {}, answers))
  end
  if type(text) ~= "string" or not text:find("%S") then return nil end
  return text
end

-- "Window: Close -- Notes": a destructive verb says what it will act on, so
-- enter is never a guess.
function M.nameTarget(row, command)
  if not (command and command.targetName) then return row end
  local target = textFrom(command.targetName, answersOf(command, row.args, row.ctx), row.ctx)
  if target then row.label = row.label .. " -- " .. target end
  return row
end

function M.confirmText(command, args, ctx)
  if not (command and command.confirm) then return nil end
  return textFrom(command.confirm, args or {}, ctx)
end

-- Why an answer will not do, or nil: `pattern` as a setting's is, and
-- `validate(value, ctx, args)` returning the reason.
function M.inputProblem(input, value, ctx, args)
  if type(input) ~= "table" then return nil end
  if type(input.pattern) == "string" and type(value) == "string" then
    local ok, found = pcall(string.find, value, input.pattern)
    if ok and not found then
      return ("%s should match %s"):format(input.description or input.id or "The answer", input.pattern)
    end
  end
  if type(input.validate) == "function" then
    local ok, why = pcall(input.validate, value, ctx or {}, args or {})
    if not ok then
      M.log.e("input '" .. tostring(input.id) .. "' validate -> " .. tostring(why))
      return "Could not check that answer"
    end
    if type(why) == "string" and why ~= "" then return why end
  end
  return nil
end

local function commandRow(command, ctx, text)
  local row = {
    label       = labelOf(command, text),
    description = subTextOf(command),
    command     = command.id,
    ctx         = ctx,
    rank        = command.rank,
    subject     = { kind = "command", id = command.id },
    icon        = command.icon,
  }
  if M.normaliseRow then M.normaliseRow(row) end
  -- VS Code's `enablement`: while it does not hold the command is still a
  -- row, greyed out and refused when picked -- where `when` would hide it.
  if command.enablement and not M.when(command.enablement, ctx or {}) then
    row.enabled = false
    row.description = "Unavailable" .. (row.description and ("  --  " .. row.description) or "")
  end
  return M.nameTarget(row, command)
end

M.commandRow = commandRow

----------------------------------------------------------------------
-- COMMANDS THAT TAKE TEXT
--
-- An input with fromQuery = true is answered by what was typed, so a
-- command like a web search runs straight from the field instead of
-- asking again after it is picked.
----------------------------------------------------------------------

local function textInput(command)
  local inputs = command.inputs
  for _, input in ipairs(type(inputs) == "table" and inputs or {}) do
    if input.fromQuery then return input end
  end
  return nil
end

M.textInputOf = textInput

-- The input through which a command takes a thing: its picker's `when` is a
-- clause over a row.
function M.itemInputOf(command)
  local inputs = command and command.inputs
  for _, input in ipairs(type(inputs) == "table" and inputs or {}) do
    if type(input.picker) == "table" and input.picker.when ~= nil then return input end
  end
  return nil
end

-- With text, the input is answered -- encoded the way collecting it would
-- have been, since it goes into a URL just the same. Without, picking the
-- row asks for it as usual.
local function textRow(command, ctx, text)
  local row = commandRow(command, ctx, text)
  local input = textInput(command)
  -- Text that will not do is left unanswered, so picking asks and says why.
  if input and text and text ~= "" and not M.inputProblem(input, text, ctx) then
    local value = text
    if input.encode == "query" then value = hs.http.encodeForQuery(text) end
    row.args = { [input.id] = value }
  end
  return row
end

M.textRow = textRow

function M.textRowsFor(ctx, text)
  local rows = {}
  for _, command in ipairs(list) do
    if textInput(command) and M.when(command.when, ctx) then
      rows[#rows + 1] = textRow(command, ctx, text)
    end
  end
  return rows
end

----------------------------------------------------------------------
-- RUNNING
----------------------------------------------------------------------

-- One alert however a command or a row was reached: a failure looks the
-- same once the layer has closed.
function M.reportFailure(id, title, err)
  hs.alert.show("Could not run " .. tostring(title or id or "that"))
  if id then
    M.log.e("command '" .. tostring(id) .. "' -> " .. tostring(err))
  else
    M.log.e("row '" .. tostring(title) .. "' -> " .. tostring(err))
  end
end

-- What a row picked asks for: its command's inputs.
function M.inputsOf(item)
  local command = type(item.command) == "string" and byId[item.command]
  return command and command.inputs or nil
end

-- Runs one with what it was given, asking nothing. A command that runs
-- another is followed; a chain that comes back to itself stops.
local following = {}

function M.runCommand(id, args, ctx, title)
  local command = type(id) == "string" and byId[id] or nil
  if not command then
    hs.alert.show("Unknown command: " .. tostring(id))
    M.log.w("no command named '" .. tostring(id) .. "'")
    return false
  end
  args = args or {}
  local scoped = M.argContext(ctx or {}, args)
  if command.run then
    local ok, result = pcall(command.run, args, scoped)
    if not ok then
      M.reportFailure(id, title or command.title, result)
      return true
    end
    return true, result
  end
  if following[id] then
    M.log.e("command '" .. id .. "' leads back to itself")
    return false
  end
  following[id] = true
  local ok, ran, result = pcall(M.runCommand, command.command, command.args, scoped, title or command.title)
  following[id] = nil
  if not ok then
    M.reportFailure(id, title or command.title, ran)
    return true
  end
  return ran, result
end

-- A row runs its own `run(ctx)`, or the command it names with its args. A
-- row need not run anything -- a heading, or a leaf a view shows for
-- reading -- and picking one closes the layer without throwing.
function M.runRow(item)
  if type(item) ~= "table" then return end
  local ctx = item.ctx or {}
  if type(item.run) == "function" then
    -- The layer has already closed by now, so a row that throws would
    -- otherwise fail with nothing on screen at all.
    local ok, err = pcall(item.run, M.argContext(ctx, item.args))
    if not ok then M.reportFailure(nil, item.label, err) end
  elseif type(item.command) == "string" then
    M.runCommand(item.command, item.args, ctx, item.label)
  end
end

function M.knowsCommand(command)
  return type(command) == "string" and M.getCommand(command) ~= nil
end
