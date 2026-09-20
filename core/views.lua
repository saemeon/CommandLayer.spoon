-- Opening a declared view and building its rows, and the cmd+k panel for a
-- highlighted row.

local M = ...

local session = M.session
local createPicker = M.createPicker
local modal = M.modal
local pickerOptions = M.pickerOptions
local showView = M.showView
local pushView = M.pushView
local currentPicker = M.activePicker
local topView = M.topView
local buildContext = M.buildContext
local gather = M.gather
local actionPicker = M.actionPicker

----------------------------------------------------------------------
-- VIEWS
----------------------------------------------------------------------

-- A placeholder or empty message is a template filled from the context:
-- "Actions -- ${frontmostApp}", as settings write it.
local function textFor(value, ctx)
  if type(value) == "string" and value:find("${", 1, true) then
    return M.resolve(value, ctx or {})
  end
  return value
end

-- ${subject:label}, ${subject:path}: a field of the subject a picker was given.
-- `label` is the label of the row it was given for, when the subject has none.
M.registerTemplateVariable("subject", function(ctx, rest)
  local subject = ctx and ctx.subject
  local value = type(subject) == "table" and subject[rest] or nil
  if value == nil and rest == "label" then value = ctx and ctx.subjectLabel end
  if value == nil or type(value) == "table" then return "" end
  return tostring(value)
end)

-- A picker given a subject -- cmd+k's, given the highlighted row's -- has it in
-- the context its rows are built in, as `subject`, and the row's label as
-- `subjectLabel`. Picking hands a subject back the same way, as an answer.
local function given(ctx, opts)
  if not (opts and opts.subject) then return ctx end
  return M.argContext(ctx, { subject = opts.subject, subjectLabel = opts.label })
end

-- Made on first use so a view that is never opened costs nothing, and
-- so a view added after start still gets one. A view names its
-- presenter; one that does not gets the profile's default.
local function pickerFor(spec)
  if not spec.picker then
    -- compact is for a view about one thing -- the cmd+k panel -- which
    -- reads better small and follows the profile's action size.
    local a = M.appearance
    local width = spec.width or (spec.compact and a.actionWidth) or nil
    local rows  = spec.rows  or (spec.compact and a.actionRows)  or nil
    spec.picker = createPicker(spec.presenter, pickerOptions(width, rows))
  end
  return spec.picker
end

local function titleOf(spec, ctx)
  if spec.title then return spec.title end
  return textFor(spec.placeholder, ctx) or spec.name
end

-- A picker's own rows: plain strings, or { label, description, iconPath,
-- value }, a function of the context and the answers so far giving them. The
-- default first, where VS Code preselects it.
local function optionRows(spec, ctx, args)
  local options = spec.options
  if type(options) == "function" then options = options(ctx, args) end
  local rows = {}
  for _, o in ipairs(type(options) == "table" and options or {}) do
    if type(o) ~= "table" then o = { label = tostring(o), value = o } end
    local row = M.normaliseRow({ label = o.label, description = o.description, iconPath = o.iconPath,
                                 value = o.value, ctx = ctx })
    if spec.default ~= nil and o.value == spec.default then
      table.insert(rows, 1, row)
    else
      rows[#rows + 1] = row
    end
  end
  return rows
end

-- A question that answers with what was typed; with nothing typed, its
-- default. The reason what was typed will not do is said while typing, so it
-- is read before enter is pressed.
local function typedQuery(spec, ctx, opts)
  local answering = opts.answering
  return function(query, present)
    if query == "" then
      if spec.default == nil then return present({}) end
      return present({ M.normaliseRow({ label = tostring(spec.default), description = "Default",
                                        value = spec.default, ctx = ctx }) })
    end
    local why = answering and answering.input and M.inputProblem(answering.input, query, ctx, opts.args)
    present({ M.normaliseRow({ label = query, description = why or spec.description or "Use this",
                               value = query, ctx = ctx }) })
  end
end

-- What a picker gathers, then a row for each picker declared under it.
-- Those rows open rather than run, so a menu tree is declarations all the
-- way down and no level is built before it is opened. A picker given as a
-- spec -- a command's question -- has no name: its rows are those its `when`
-- holds for, then its options.
local function buildRows(spec, ctx, args)
  local items = {}

  if spec.command then
    -- Typing fills the row in afresh (commandQuery in the stack).
    local command = M.getCommand(spec.command)
    items = command and { M.textRow(command, ctx, "") } or {}
  elseif spec.kind == "item" then
    -- Given nothing, an item picker has nothing to offer, and says so.
    local subject = ctx and ctx.subject
    items = type(subject) == "table" and M.itemActions(subject, ctx) or {}
  elseif spec.when ~= nil then
    items = M.rowsForItemInput(spec, ctx)
  elseif spec.name then
    -- Which picker asks, for an extension or a `when` that differs by one.
    items = gather(M.argContext(ctx, { activeView = spec.name }), { menus = spec.menus })
  end
  for _, row in ipairs(optionRows(spec, ctx, args)) do items[#items + 1] = row end

  for _, child in ipairs(M.views) do
    if spec.name and child.parent == spec.name then
      local typed = M.prefixesOf(child)[1]
      items[#items + 1] = {
        label       = titleOf(child) .. " \u{25B8}",
        description = child.description
                      or (typed and ("Menu -- or type '" .. typed .. "'"))
                      or "Menu",
        submenu = child.name,
        ctx     = ctx,
        rank    = child.rank or 0.1,
        subject = { kind = "view", name = child.name },
        icon    = child.icon,
      }
      M.normaliseRow(items[#items])
    end
  end

  -- In a view with `pickerRows` -- the entry picker -- every picker reached
  -- by a prefix is a row too, so "sett" finds Settings without knowing its
  -- prefix. Picking one types the prefix, exactly as typing it would. A text
  -- command's own prefix view is left out: the command is already a row.
  if spec.pickerRows then
    for _, child in ipairs(M.views) do
      local typed = M.prefixesOf(child)[1]
      if typed and child ~= spec and not child.parent and not child.command then
        items[#items + 1] = {
          -- Its title or its name, not its placeholder: "Actions -- Finder"
          -- is what the context picker says once open, and "context" typed
          -- would not find it.
          label        = child.title or M.displayNameOf(child.name),
          description  = "Picker -- type '" .. typed .. "'",
          submenu      = child.name,
          submenuQuery = typed,
          ctx          = ctx,
          rank         = 0.14,
          subject      = { kind = "view", name = child.name },
          icon         = child.icon,
        }
        M.normaliseRow(items[#items])
      end
    end
  end

  return items
end

-- Counted, because an extension may ask for a refresh from inside building
-- rows -- a cache that answers at once calls back straight away -- and a
-- refresh from there rebuilds the rows, which asks again, until the stack
-- runs out and takes Hammerspoon with it.
local function rowsFor(spec, ctx, args)
  session.buildingRows = (session.buildingRows or 0) + 1
  local ok, rows = pcall(buildRows, spec, ctx, args)
  session.buildingRows = session.buildingRows - 1
  if not ok then error(rows, 0) end
  return rows
end

M.rowsOfView = function(name, ctx)
  local spec = M.viewNamed(name)
  return spec and rowsFor(spec, ctx or buildContext()) or {}
end

session.rowsOfView = M.rowsOfView

-- A level drawing `spec` in `ctx`, its rows built; nil and what to say when
-- the picker has nothing to show and says so. Where it goes on the stack, and
-- what its placeholder reads, are the caller's.
local function levelOf(spec, ctx, opts)
  local items = rowsFor(spec, ctx, opts.args)
  if spec.empty and #items == 0 then return nil, textFor(spec.empty, ctx) end

  return {
    name        = spec.name,
    startQuery  = opts.query,
    ctx         = ctx,
    picker      = spec.name and pickerFor(spec) or actionPicker(),
    items       = items,
    rebuild     = function() return rowsFor(spec, ctx, opts.args) end,
    command     = spec.command,
    rowsForQuery = spec.typed and typedQuery(spec, ctx, opts) or nil,
    answers     = spec.answers ~= false and not opts.answering,
    answering   = opts.answering,
    args        = opts.args,
    search      = spec.search,
    kind        = spec.kind,
    minQuery    = spec.minQuery,
    debounce    = spec.debounce,
    menus       = { menus = spec.menus, activeView = spec.name },
    recentlyUsed = spec.recentlyUsed,
    sections    = spec.sections,
    textCommands = spec.textCommands,
  }
end

local function openNow(name, opts)
  opts = opts or {}
  local spec = M.viewNamed(name)
  if not spec then
    hs.alert.show("No such view: " .. tostring(name))
    return
  end

  local ctx = given(session.outsideContext or buildContext(), opts)
  local level, empty = levelOf(spec, ctx, opts)
  if not level then
    modal:exit()
    hs.alert.show(empty)
    return
  end

  level.placeholder, level.crumb = textFor(spec.placeholder, ctx), spec.title
  showView(level)
end

-- opts.query starts the field with text, opts.subject and opts.label give the
-- picker a subject. Traced from here to its rows on screen, which is the time
-- entering the layer takes.
function M.open(name, opts)
  return M.traced("open", tostring(name), openNow, name, opts)
end

-- Opens a declared view over the current one, in the context the layer
-- was entered with: a fresh one built now would find Hammerspoon in
-- front. The placeholder is the path down to it, so a level deep in a
-- tree still says where it is.
--
-- opts.ctx overrides that context, opts.query starts the field with text,
-- opts.subject and opts.label give the picker a subject, and opts.byPrefix is
-- the prefix it was reached by, which then has to stay in front. Returns false
-- when it did not open, so a caller can carry on where it was.
--
-- A spec in place of a name is a picker of its own, a command's question:
-- opts.placeholder says what it asks, opts.args are the answers so far, and
-- opts.answering is the command it answers, so a pick gives it an answer
-- rather than running the row. It never switches on a prefix.
local function pushNow(target, opts)
  opts = opts or {}
  local spec = type(target) == "table" and target or M.viewNamed(target)
  if not spec then
    hs.alert.show("No such view: " .. tostring(target))
    return false
  end

  local parent = topView()
  local ctx = given(opts.ctx or (parent and parent.ctx) or buildContext(), opts)
  local level, empty = levelOf(spec, ctx, opts)

  -- Unlike open, this stays: the level you came from is still there.
  if not level then
    hs.alert.show(empty)
    return false
  end

  local crumb = opts.placeholder and (parent and parent.crumb) or titleOf(spec, ctx) or ""
  if not opts.placeholder and parent and parent.crumb then
    crumb = parent.crumb .. " \u{25B8} " .. crumb
  end

  level.prefix = type(opts.byPrefix) == "string" and opts.byPrefix or nil
  level.placeholder, level.crumb = opts.placeholder or crumb, crumb
  pushView(level)
  return true
end

function M.push(target, opts)
  local label = type(target) == "table" and (target.name or "question") or tostring(target)
  return M.traced("open", label, pushNow, target, opts)
end

session.push = M.push

-- What a chord bound to a view does. A view with a prefix is a mode of the
-- entry picker, the way Cmd+Shift+P is Quick Open with ">" typed: the chord opens
-- that picker with the prefix already in the field, so deleting the prefix
-- leaves you in the entry picker rather than closing anything.
function M.quickOpen(name)
  local spec = M.viewNamed(name)
  local prefix = spec and M.prefixesOf(spec)[1]
  if prefix and name ~= M.defaultView then
    return M.open(M.defaultView, { query = prefix })
  end
  return M.open(name)
end

-- A text command may have a prefix of its own -- "youtube lofi" -- and that
-- is a view holding the one command, so aliases, `?` and the prefix
-- machinery treat it like any other picker. It goes with the extension
-- whose command it holds.
M.registerTextCommandViews = function()
  for _, command in ipairs(M.getCommands()) do
    if command.prefix and M.textInputOf(command) then
      M.view({
        name        = command.id,
        extension   = command.extension,
        title       = M.commandTitle(command, nil),
        prefix      = command.prefix,
        placeholder = M.commandTitle(command, nil),
        answers     = false,
        command     = command.id,
      })
      if command.extension ~= nil then
        local name, extension = command.id, command.extension
        M.trackRegistration(extension, function()
          local view = M.viewNamed(name)
          if view and view.extension == extension then M.removeView(name) end
        end)
      end
    end
  end
end

----------------------------------------------------------------------
-- ACTIONS FOR THE SELECTED ROW
--
-- cmd+k asks the highlighted row what it is and offers what can be done
-- with it, rather than making every verb its own entry in the root list.
----------------------------------------------------------------------

local function itemActions(subject, ctx)
  local items = {}

  -- A command taking a thing -- an input whose picker has a `when` -- is a
  -- verb on every row that thing could be, with the row already given: VS
  -- Code's view/item/context menu, from the declaration that also lets the
  -- command ask for one when it is run from search. A `view/item/context`
  -- entry in its menus narrows that with a `when` of its own, over the same
  -- row.
  local scoped = M.itemContext(subject, ctx)
  for _, command in ipairs(M.getCommands()) do
    local input = M.itemInputOf(command)
    local entry = type(command.menus) == "table" and command.menus["view/item/context"]
    local narrowed = type(entry) ~= "table" or entry.when == nil or M.when(entry.when, scoped)
    if input and narrowed and M.when(command.when, ctx) and M.when(input.picker.when, scoped) then
      local row = M.commandRow(command, ctx)
      -- In a menu about one thing, the verb alone reads better -- but the
      -- category is still what the command is called elsewhere, so it is
      -- matched as a keyword: typing "git" on a repository keeps Pull and
      -- Fetch rather than emptying the panel.
      row.label = command.title
      if type(command.category) == "string" and command.category ~= "" then
        row.keywords = { command.category }
      end
      M.normaliseRow(row)
      row.args = { [input.id] = subject }
      -- Remembered per kind of row it is offered on (rowKey).
      row.subject.viewItem = subject.kind
      items[#items + 1] = M.nameTarget(row, command)
    end
  end

  return items
end

M.itemActions = itemActions

-- The row is checked here rather than in the view, so a row with nothing
-- to act on says so without opening an empty level. What opens is a view
-- like any other, which a profile can point elsewhere.
local function showItemActions()
  local picker = currentPicker()
  if not (picker and picker.selected) then return end

  local item = picker.selected()
  if not item or not item.subject then
    hs.alert.show("No actions for this row")
    return
  end

  -- A command that acts on what is in front when picked opens its choice
  -- instead: enter takes the window you were in, cmd+k asks which.
  local command = type(item.command) == "string" and M.getCommand(item.command)
  local input = command and M.itemInputOf(command)
  if input and input.preferCurrent then
    local ask = {}
    for k, v in pairs(item) do ask[k] = v end
    ask.args = {}
    for k, v in pairs(item.args or {}) do
      if k ~= input.id then ask.args[k] = v end
    end
    M.collectArguments(ask)
    return
  end

  M.push(M.actionsView, { ctx = item.ctx, subject = item.subject, label = item.label })
end

M.showItemActions = showItemActions
