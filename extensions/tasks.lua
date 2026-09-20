-- The tasks in tasks.json beside the active profile's settings.json, in VS
-- Code's shape, each run in the terminal through terminal.run.

local M = {}

M.FILE = "tasks.json"
M.TEMPLATE = '{\n  "version": "2.0.0",\n  "tasks": [\n  ]\n}\n'

local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
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
    for _, word in ipairs(words(task)) do cmd = cmd .. " " .. quote(word) end
  end
  local options = type(task.options) == "table" and task.options or {}
  local cwd = nil
  if type(options.cwd) == "string" and options.cwd ~= "" then
    cwd = (options.cwd:gsub("^~", os.getenv("HOME") or "~"))
  end
  return { cmd = cmd, target = cwd, title = "Task: " .. task.label }
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
    if read.path == path and read.stamp == stamp then return read.tasks end

    local list, labels = {}, {}
    local data = stamp and cl.readJSONC(path) or nil
    if type(data) == "table" and type(data.tasks) ~= "table" then
      cl.problem(path .. " has no tasks list")
    elseif type(data) == "table" then
      for i, task in ipairs(data.tasks) do
        local mistake = M.mistake(task)
        if not mistake and labels[task.label] then mistake = "has the label of an earlier task" end
        if mistake then
          cl.problem(("%s: task %d %s, so it was left out"):format(path, i, mistake))
        else
          labels[task.label] = true
          list[#list + 1] = task
        end
      end
    end
    read = { path = path, stamp = stamp, tasks = list }
    return list
  end

  local function named(label)
    for _, task in ipairs(tasks()) do
      if task.label == label then return task end
    end
  end

  return {
    displayName = "Tasks",
    description = "The tasks in tasks.json beside settings.json, run in the terminal",
    menus       = { "root" },
    rank        = 0.29,
    extensionDependencies = { "terminal" },

    commands = {
      -- The label is the argument, as VS Code's Run Task takes it, so a
      -- keybinding can name one task.
      { id = "tasks.runTask", title = "Run Task", category = "Tasks", icon = "$(play)",
        menus = { "commandPalette" },
        inputs = { {
          id = "task", description = "Task",
          picker = { options = function()
            local options = {}
            for _, task in ipairs(tasks()) do
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
          cl.executeCommand("terminal.run", M.runArgs(task), ctx)
        end },

      { id = "tasks.openUserTasks", title = "Open User Tasks", category = "Tasks", icon = "$(gear)",
        menus = { "commandPalette" },
        run = function(_, ctx)
          local path = cl.profileFile(M.FILE, M.TEMPLATE)
          if path then cl.executeCommand("editor.open", { target = path, title = path }, ctx) end
        end },
    },

    items = function(ctx)
      local rows = {}
      for _, task in ipairs(tasks()) do
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
