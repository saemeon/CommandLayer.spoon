-- Asking for what a command is missing, and running a command by its id.

local M = ...

local session = M.session

----------------------------------------------------------------------
-- ARGUMENTS
--
-- An action can declare what it is missing, and the layer goes and
-- collects it before dispatching -- VS Code's `inputs`:
--
--   inputs = {
--     { id = "repo", description = "Repository", picker = { kind = "search", search = fn } },
--     { id = "dir",  description = "Clone into", picker = { options = fn } },
--     { id = "note", description = "Name", default = "notes", picker = { typed = true } },
--     { id = "q",    description = "Search", encode = "query", picker = { typed = true } },
--     { id = "branch", command = "some.command", args = { ... } },
--   }
--
-- Options may be strings, as VS Code's pickString's are, and `default` is
-- tasks.json's; `command` is its command input.
--
-- It is what lets a command be globally available while still operating
-- on an object: "Git clone" needs a repository, but it can go and find
-- one rather than waiting for you to have highlighted it.
--
-- Each argument is a view on the stack, so escape backs out one answer
-- at a time rather than abandoning the whole flow.
----------------------------------------------------------------------

-- The picker an input names, answering with the row picked -- its `value`,
-- else its subject. Copied, because the default and the prompt are the
-- input's, and the spec is the command's to keep.
function M.pickerOfInput(input)
  local spec = {}
  for k, v in pairs(type(input.picker) == "table" and input.picker or {}) do spec[k] = v end
  if spec.typed or spec.options ~= nil then spec.default = input.default end
  if spec.typed then spec.description = input.description end
  return spec
end

-- "Clone into (2/2)": where a flow of several questions stands, as VS Code's
-- multi-step input says it.
local function pushArgumentView(parent, spec, step, steps)
  local asked = spec.description or spec.id
  if steps and steps > 1 then asked = ("%s (%d/%d)"):format(asked, step, steps) end
  session.push(M.pickerOfInput(spec), { ctx = parent.ctx, placeholder = asked, args = parent.args,
                                        answering = { parent = parent, input = spec } })
end

local function pushConfirmView(parent, question)
  session.push({ options = { { label = "Yes", value = true }, { label = "No", value = false } } },
               { ctx = parent.ctx, placeholder = question, answering = { parent = parent, confirm = true } })
end

-- VS Code's `command` input, as tasks.json has it: answered by running the
-- command it names and taking what that returns, before anything is asked.
M.answerCommandInputs = function(inputs, args, ctx)
  for _, input in ipairs(type(inputs) == "table" and inputs or {}) do
    if args[input.id] == nil and input.command ~= nil and input.picker == nil then
      local _, value = M.executeCommand(input.command, input.args, ctx)
      args[input.id] = value ~= nil and value or ""
    end
  end
end

local function collectArguments(parent)
  local command = type(parent.command) == "string" and M.getCommand(parent.command) or nil
  local inputs = M.inputsOf(parent) or {}
  if not command then return false end

  parent.args = parent.args or {}
  parent.pickedDepth = parent.pickedDepth or #session.stack
  M.answerCommandInputs(inputs, parent.args, parent.ctx)

  local unanswered, first = 0, nil
  for _, spec in ipairs(inputs) do
    if parent.args[spec.id] == nil then
      unanswered = unanswered + 1
      first = first or spec
    end
  end
  if first then
    -- Counted at the first question: what was given, or taken from what is in
    -- front, is no step.
    parent.steps = parent.steps or unanswered
    pushArgumentView(parent, first, parent.steps - unanswered + 1, parent.steps)
    return true
  end

  local question = not parent.confirmed and M.confirmText(command, parent.args, parent.ctx)
  if question then
    pushConfirmView(parent, question)
    return true
  end

  return false
end

M.collectArguments = collectArguments
session.collect = collectArguments

----------------------------------------------------------------------
-- RUNNING A COMMAND BY ID
----------------------------------------------------------------------

-- The open layer's context before a fresh one: built now, it would find
-- Hammerspoon in front, and a control pressed on every keystroke would
-- run every capture each time. Returns true and what the command returned,
-- or false when there is no such command.
function M.executeCommand(id, args, ctx)
  local command = type(id) == "string" and M.getCommand(id) or nil
  if not command then
    M.log.w("no command named '" .. tostring(id) .. "'")
    return false
  end

  args = type(args) == "table" and args or {}
  local top = M.topView and M.topView()
  ctx = ctx or (top and top.ctx) or M.buildContext()

  -- From outside the layer, a view the command opens is shown in this
  -- context rather than capturing a second.
  local function run(runArgs)
    if top then return M.runCommand(id, runArgs, ctx) end
    local outer = session.outsideContext
    session.outsideContext = ctx
    local results = table.pack(pcall(M.runCommand, id, runArgs, ctx))
    session.outsideContext = outer
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
  end

  -- Lua asking for nothing runs where it is: a control acts on the picker
  -- on screen, and closing the layer first would take that picker away.
  if command.run and not command.inputs and not command.confirm and not command.after then
    return run(args)
  end

  -- Copied: collecting writes answers into the row's args.
  local item = M.commandRow(command, ctx)
  item.args = {}
  for k, v in pairs(args) do item.args[k] = v end

  M.answerCommandInputs(command.inputs, item.args, ctx)

  -- Run by id -- a chord, a call -- an input with `current` is answered by
  -- what is in front, as VS Code's commands act on the active editor.
  -- Picked from a list, the same command asks.
  for _, input in ipairs(command.inputs or {}) do
    if item.args[input.id] == nil and type(input.current) == "function" then
      local ok, value = pcall(input.current, ctx)
      if ok and value ~= nil then item.args[input.id] = value end
    end
  end

  local asks = M.confirmText(command, item.args, ctx) ~= nil
  for _, input in ipairs(command.inputs or {}) do
    if item.args[input.id] == nil then asks = true end
  end
  if asks then
    if top then
      collectArguments(item)
    else
      local pending = session.pendingEntries
      pending[#pending + 1] = function() collectArguments(item) end
      session.modal:enter()
    end
    return true
  end

  -- Only a command that is a row has a ranking to feed.
  if M.hasMenus(command.menus) then M.remember(item) end
  if not top then return run(item.args) end
  local ran, result
  M.runAfter(command, #session.stack, function() ran, result = run(item.args) end)
  return ran, result
end

-- Commands whose result is being worked out right now: one whose template
-- asks for itself gets nothing, rather than recursing until Lua gives up.
local runningForTemplate = {}

-- ${command:id} in a template: what that command returns.
M.registerTemplateVariable("command", function(ctx, rest)
  if runningForTemplate[rest] then return "" end
  runningForTemplate[rest] = true
  local ok, ran, value = pcall(M.executeCommand, rest, nil, ctx)
  runningForTemplate[rest] = nil
  return (ok and ran and value ~= nil) and tostring(value) or ""
end)
