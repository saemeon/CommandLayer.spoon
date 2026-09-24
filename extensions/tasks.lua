-- The tasks in tasks.json beside the active profile's settings.json, in VS
-- Code's shape, each run in the terminal through terminal.run.
--
-- A task using ${input:id} asks through that input first, and is a command of
-- its own for it, since a command's inputs are declared when it is
-- registered: made at setup, so an input changed since needs a reload.

local M = {}

M.FILE = "tasks.json"
M.TEMPLATE = '{\n  "version": "2.0.0",\n  "tasks": [\n  ]\n}\n'

local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Each literal part quoted and every ${...} left bare: terminal.run quotes
-- what it fills in, and a value landing inside quotes of ours would be
-- unquoted by them.
local function quoteWord(word)
  local parts, at = {}, 1
  while true do
    local s, e = word:find("%${[^}]*}", at)
    if not s then break end
    if s > at then parts[#parts + 1] = quote(word:sub(at, s - 1)) end
    parts[#parts + 1] = word:sub(s, e)
    at = e + 1
  end
  if at <= #word or #parts == 0 then parts[#parts + 1] = quote(word:sub(at)) end
  return table.concat(parts)
end

-- VS Code writes an argument as a string, or as { value, quoting }.
local function words(task)
  local out = {}
  for _, arg in ipairs(type(task.args) == "table" and task.args or {}) do
    if type(arg) == "table" then arg = arg.value end
    out[#out + 1] = tostring(arg)
  end
  return out
end

-- Why a task cannot run, or nil. A terminal runs shell and process tasks;
-- the rest need VS Code.
function M.mistake(task)
  if type(task) ~= "table" then return "is not an object" end
  if type(task.label) ~= "string" or task.label == "" then return "has no label" end
  if task.type ~= "shell" and task.type ~= "process" then
    return ("has type %s; only shell and process run here"):format(tostring(task.type))
  end
  if type(task.command) ~= "string" or task.command == "" then return "has no command" end
  if task.args ~= nil and type(task.args) ~= "table" then return "has args that are not a list" end
  return nil
end

-- A shell task's command is shell text as its author wrote it, with each
-- argument a quoted word after it; a process task is words alone.
function M.runArgs(task)
  local cmd
  if task.type == "process" then
    cmd = { task.command }
    for _, word in ipairs(words(task)) do cmd[#cmd + 1] = word end
  else
    cmd = task.command
    for _, word in ipairs(words(task)) do cmd = cmd .. " " .. quoteWord(word) end
  end
  local options = type(task.options) == "table" and task.options or {}
  local cwd = nil
  if type(options.cwd) == "string" and options.cwd ~= "" then
    cwd = (options.cwd:gsub("^~", os.getenv("HOME") or "~"))
  end
  return { cmd = cmd, target = cwd, title = "Task: " .. task.label }
end

-- The launcher's own pickers a `command` input may name, since VS Code has
-- none that answers with a path. The answer is the picked row's path.
M.PICKERS = {
  ["tasks.pickFolder"] = { when = "viewItem == 'folder' || viewItem == 'project'", menus = { "recent", "files" } },
  ["tasks.pickFile"]   = { when = "viewItem == 'file'", menus = { "files", "recent" } },
}

-- One of tasks.json's inputs as a command's input, or nil and why not.
function M.input(spec)
  if type(spec) ~= "table" then return nil, "is not an object" end
  if type(spec.id) ~= "string" or spec.id == "" then return nil, "has no id" end
  local description = type(spec.description) == "string" and spec.description or spec.id
  if spec.type == "promptString" then
    -- The field shows what is typed, so a password would be on screen.
    if spec.password then return nil, "is a password prompt, which the picker cannot hide" end
    return { id = spec.id, description = description, default = spec.default, picker = { typed = true } }
  elseif spec.type == "pickString" then
    if type(spec.options) ~= "table" or spec.options[1] == nil then return nil, "has no options" end
    local options = {}
    for _, option in ipairs(spec.options) do
      if type(option) == "table" then
        options[#options + 1] = { label = tostring(option.label or option.value), value = option.value }
      else
        options[#options + 1] = tostring(option)
      end
    end
    return { id = spec.id, description = description, default = spec.default, picker = { options = options } }
  elseif spec.type == "command" then
    if type(spec.command) ~= "string" or spec.command == "" then return nil, "has no command" end
    local picker = M.PICKERS[spec.command]
    if picker then
      return { id = spec.id, description = description,
               picker = { when = picker.when, menus = { table.unpack(picker.menus) } } }
    end
    return { id = spec.id, command = spec.command, args = spec.args }
  end
  return nil, ("has type %s; only promptString, pickString and command are asked here"):format(tostring(spec.type))
end

-- The ${input:id}s a task uses, in the order they first appear, as VS Code
-- asks them.
function M.inputIds(task)
  local ids, seen = {}, {}
  local function scan(text)
    if type(text) ~= "string" then return end
    for id in text:gmatch("%${input:([^}]+)}") do
      if not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  scan(task.command)
  for _, word in ipairs(words(task)) do scan(word) end
  scan(type(task.options) == "table" and task.options.cwd or nil)
  return ids
end

-- The command a task with inputs runs as: its label, made an id.
function M.taskCommand(label)
  local out = ""
  for word in tostring(label):gmatch("%w+") do
    out = out .. (out == "" and word:lower() or word:sub(1, 1):upper() .. word:sub(2):lower())
  end
  return out ~= "" and "tasks.run." .. out or nil
end

function M.commandLine(task)
  local line = { task.command }
  for _, word in ipairs(words(task)) do line[#line + 1] = word end
  return table.concat(line, " ")
end

function M.extension(cl)
  -- Decoded again only when the file's time or size moves, so an open costs
  -- a stat.
  local read = {}

  local function tasks()
    local path = cl.profileFile(M.FILE)
    local attributes = hs.fs.attributes(path)
    local stamp = attributes and (tostring(attributes.modification) .. ":" .. tostring(attributes.size)) or nil
    if read.path == path and read.stamp == stamp then return read.tasks, read.inputs end

    local list, labels, inputsOf = {}, {}, {}
    local data = stamp and cl.readJSONC(path) or nil
    if type(data) == "table" and type(data.tasks) ~= "table" then
      cl.problem(path .. " has no tasks list")
    elseif type(data) == "table" then
      local declared = {}
      if data.inputs ~= nil and type(data.inputs) ~= "table" then
        cl.problem(path .. " has inputs that are not a list")
      end
      for i, spec in ipairs(type(data.inputs) == "table" and data.inputs or {}) do
        local input, mistake = M.input(spec)
        if input and declared[input.id] then input, mistake = nil, "has the id of an earlier input" end
        if input then
          declared[input.id] = input
        else
          cl.problem(("%s: input %d %s, so it was left out"):format(path, i, mistake))
        end
      end
      for i, task in ipairs(data.tasks) do
        local mistake = M.mistake(task)
        if not mistake and labels[task.label] then mistake = "has the label of an earlier task" end
        local inputs = {}
        if not mistake then
          for _, id in ipairs(M.inputIds(task)) do
            if not declared[id] then
              mistake = ("uses ${input:%s}, which inputs does not declare"):format(id)
              break
            end
            inputs[#inputs + 1] = declared[id]
          end
        end
        if not mistake and inputs[1] and not M.taskCommand(task.label) then
          mistake = "has inputs and a label without a letter or digit"
        end
        if mistake then
          cl.problem(("%s: task %d %s, so it was left out"):format(path, i, mistake))
        else
          labels[task.label] = true
          list[#list + 1] = task
          if inputs[1] then inputsOf[task.label] = inputs end
        end
      end
    end
    read = { path = path, stamp = stamp, tasks = list, inputs = inputsOf }
    return list, inputsOf
  end

  local function named(label)
    for _, task in ipairs((tasks())) do
      if task.label == label then return task end
    end
  end

  -- A subject answers with its path, so ${input:folder} is the folder.
  local function answers(args)
    local out = {}
    for id, value in pairs(args or {}) do
      if type(value) == "table" then value = value.path or value.value end
      out[id] = value
    end
    return out
  end

  -- The commands for tasks with inputs, as tasks.json said at setup.
  local commands, made = {}, {}
  local offered = {}
  local contextMenu = cl.setting("tasks", "contextMenu")
  for _, label in ipairs(type(contextMenu) == "table" and contextMenu or {}) do offered[label] = false end

  local _, inputsAtSetup = tasks()
  local labelsAtSetup = {}
  for label in pairs(inputsAtSetup) do labelsAtSetup[#labelsAtSetup + 1] = label end
  table.sort(labelsAtSetup)
  for _, label in ipairs(labelsAtSetup) do
    local id, inputs = M.taskCommand(label), inputsAtSetup[label]
    if made[id] then
      cl.problem(("tasks %s and %s make the same command, %s; the second was left out"):format(made[id], label, id))
    else
      made[id] = label
      local takesThing = cl.itemInputOf({ inputs = inputs }) ~= nil
      if offered[label] ~= nil then offered[label] = takesThing end
      local asked = {}
      for _, input in ipairs(inputs) do asked[input.id] = true end
      commands[#commands + 1] = {
        id = id, title = label, category = "Tasks", icon = "$(play)",
        -- On cmd+k only when the person asks for it: a task is theirs, and a
        -- verb on every folder is a lot to give one.
        menus = { ["view/item/context"] = offered[label] and true or { when = "false" } },
        inputs = inputs,
        run = function(args, ctx)
          local task = named(label)
          if not task then
            hs.alert.show("No task named " .. label)
            return
          end
          for _, input in ipairs(M.inputIds(task)) do
            if not asked[input] then
              hs.alert.show(("tasks.json changed since the layer started; reload to run %s"):format(label))
              return
            end
          end
          cl.executeCommand("terminal.run", M.runArgs(task), cl.argContext(ctx or {}, answers(args)))
        end,
      }
    end
  end
  for label, takes in pairs(offered) do
    if not takes then
      cl.problem(("tasks.contextMenu names %s, which is no task taking a folder or file"):format(label))
    end
  end

  -- A task with inputs runs through its own command, which asks them; one
  -- that has gained inputs since setup has none yet.
  local function runTask(task, args, ctx)
    local _, inputsOf = tasks()
    if not inputsOf[task.label] then
      cl.executeCommand("terminal.run", M.runArgs(task), ctx)
    elseif made[M.taskCommand(task.label)] == task.label then
      local given = {}
      for k, v in pairs(args or {}) do if k ~= "task" then given[k] = v end end
      cl.executeCommand(M.taskCommand(task.label), given, ctx)
    else
      hs.alert.show(("tasks.json changed since the layer started; reload to run %s"):format(task.label))
    end
  end

  -- The label is the argument, as VS Code's Run Task takes it, so a
  -- keybinding can name one task -- and give its inputs beside it.
  table.insert(commands, 1, {
    id = "tasks.runTask", title = "Run Task", category = "Tasks", icon = "$(play)",
    menus = { "commandPalette" },
    inputs = { {
      id = "task", description = "Task",
      picker = { options = function()
        local options = {}
        for _, task in ipairs((tasks())) do
          options[#options + 1] = { label = task.label, description = M.commandLine(task), value = task.label }
        end
        return options
      end },
    } },
    run = function(args, ctx)
      local task = named(args.task)
      if not task then
        hs.alert.show("No task named " .. tostring(args.task))
        return
      end
      runTask(task, args, ctx)
    end })

  commands[#commands + 1] = {
    id = "tasks.openUserTasks", title = "Open User Tasks", category = "Tasks", icon = "$(gear)",
    menus = { "commandPalette" },
    run = function(_, ctx)
      local path = cl.profileFile(M.FILE, M.TEMPLATE)
      if path then cl.executeCommand("editor.open", { target = path, title = path }, ctx) end
    end }

  return {
    displayName = "Tasks",
    description = "The tasks in tasks.json beside settings.json, run in the terminal",
    menus       = { "root" },
    rank        = 0.29,
    extensionDependencies = { "terminal" },

    settings = {
      contextMenu = { type = "array", default = {},
                      description = "Tasks, by label, that cmd+k offers on the folder, project or file they take; "
                                    .. "applies on reload" },
    },

    commands = commands,

    items = function(ctx)
      local rows = {}
      for _, task in ipairs((tasks())) do
        rows[#rows + 1] = {
          label       = task.label,
          description = "Task",
          detail      = M.commandLine(task),
          icon        = "$(play)",
          command     = "tasks.runTask",
          args        = { task = task.label },
          subject     = { kind = "task", label = task.label },
          ctx         = ctx,
        }
      end
      return rows
    end,
  }
end

return M
