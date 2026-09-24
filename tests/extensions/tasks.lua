-- CommandLayer.spoon/tests/extensions/tasks.lua
-- The tasks extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.tasks

local spec
for _, ext in ipairs(cl.extensions) do
  if ext.name == "tasks" then spec = ext end
end
if not (spec and spec.items) then
  check("tasks extension is registered", false)
  return
end

local folder = os.tmpname() .. "-tasks"
os.execute(("mkdir -p %q"):format(folder))
local savedUserDir = cl.userDir
cl.userDir = folder
local path = folder .. "/tasks.json"

local function write(text)
  local handle = assert(io.open(path, "w"))
  handle:write(text)
  handle:close()
end

-- The file's time and size, as the check says they are.
local stamp = 1
local realAttributes = hs.fs.attributes
stub(hs.fs, "attributes", function(p, ...)
  local found = realAttributes(p, ...)
  if p == path and found then return { mode = "file", modification = stamp, size = 10 } end
  return found
end)

local ran, opened = {}, {}
cl.registerCommand("terminal.run", { title = "spy", menus = {}, run = function(args) ran[#ran + 1] = args end })
cl.registerCommand("editor.open", { title = "spy", menus = {}, run = function(args) opened[#opened + 1] = args end })

local function problemsAbout(text)
  local found = {}
  for _, p in ipairs(cl.getProblems()) do
    if (p.file .. " " .. p.message):find(text, 1, true) then found[#found + 1] = p.message end
  end
  return found
end

local function labelsOf(rows, field)
  local out = {}
  for i, row in ipairs(rows) do out[i] = tostring(row[field or "label"]) end
  return table.concat(out, " ")
end

write([[
{
  // As VS Code writes it: comments, and a trailing comma.
  "version": "2.0.0",
  "tasks": [
    { "label": "build", "type": "shell", "command": "make -j4", "args": ["all", "it's"],
      "options": { "cwd": "~/src" } },
    { "label": "serve", "type": "process", "command": "python3",
      "args": ["-m", "http.server", { "value": "8000", "quoting": "escape" }] },
    { "label": "watch", "type": "npm", "script": "watch" },
    { "label": "build", "type": "shell", "command": "echo again" },
    { "type": "shell", "command": "nolabel" },
  ],
}
]])

local rows = spec.items({})
check("each task in the profile's tasks.json is a row running Tasks: Run Task with its label",
      labelsOf(rows) == "build serve" and rows[1].command == "tasks.runTask" and rows[1].args.task == "build"
      and rows[2].args.task == "serve" and rows[1].detail == "make -j4 all it's",
      labelsOf(rows) .. " / " .. tostring(rows[1] and rows[1].detail))

local options = cl.getCommand("tasks.runTask").inputs[1].picker.options()
check("Run Task offers the same tasks, by label",
      labelsOf(options) == "build serve" and labelsOf(options, "value") == "build serve", labelsOf(options))

local mistakes = {
  #problemsAbout(path .. ": task 3 has type npm; only shell and process run here"),
  #problemsAbout(path .. ": task 4 has the label of an earlier task"),
  #problemsAbout(path .. ": task 5 has no label"),
}
check("a task of another type, a label used twice or none is a problem naming tasks.json, and left out",
      mistakes[1] == 1 and mistakes[2] == 1 and mistakes[3] == 1, table.concat(mistakes, " "))

cl.executeCommand("tasks.runTask", { task = "build" }, {})
cl.executeCommand("tasks.runTask", { task = "serve" }, {})
local shell, process = ran[1], ran[2]
check("a shell task runs its command as written, each argument quoted after it, in options.cwd with ~ expanded",
      shell ~= nil and shell.cmd == "make -j4 'all' 'it'\\''s'" and shell.target == os.getenv("HOME") .. "/src"
      and shell.title == "Task: build",
      tostring(shell and shell.cmd) .. " @ " .. tostring(shell and shell.target))
check("a process task runs its command and arguments as words, in the terminal's own folder",
      process ~= nil and type(process.cmd) == "table"
      and table.concat(process.cmd, "|") == "python3|-m|http.server|8000" and process.target == nil,
      process and type(process.cmd) == "table" and table.concat(process.cmd, "|") or "nothing")

local alerts = {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
cl.executeCommand("tasks.runTask", { task = "watch" }, {})
check("a task that is not there runs nothing, and says so",
      #ran == 2 and alerts[#alerts] == "No task named watch", tostring(alerts[#alerts]))

write([[{ "version": "2.0.0", "tasks": [ { "label": "test", "type": "shell", "command": "make test" } ] }]])
local unchanged = labelsOf(spec.items({}))
stamp = 2
local changed = labelsOf(spec.items({}))
check("tasks.json is read again only once its time or size has changed",
      unchanged == "build serve" and changed == "test", unchanged .. " / " .. changed)

write("{ nope")
stamp = 3
local broken = spec.items({})
check("a tasks.json that does not parse is a problem, and no tasks",
      #broken == 0 and #problemsAbout(path .. " does not parse") == 1, labelsOf(broken))

os.remove(path)
local before = #cl.getProblems()
local none = spec.items({})
check("no tasks.json is no tasks, and no problem", #none == 0 and #cl.getProblems() == before)

cl.executeCommand("tasks.openUserTasks", {}, {})
local made = io.open(path, "r")
local text = made and made:read("a") or ""
if made then made:close() end
stamp = 4
local fresh = spec.items({})
check("Open User Tasks makes an empty tasks.json in the profile's folder and opens it in the editor",
      text == M.TEMPLATE and #opened == 1 and opened[1].target == path and #fresh == 0
      and #cl.getProblems() == before,
      tostring(opened[1] and opened[1].target) .. " / " .. text)

cl.userDir = savedUserDir
os.execute(("rm -rf %q"):format(folder))

-- Inputs: a kernel of its own, since the commands for tasks with inputs are
-- made at setup from the tasks.json there.
T.restoreStubs()
do
  local dir = os.tmpname() .. "-task-inputs"
  os.execute(("mkdir -p %q"):format(dir))
  local function put(name, text)
    local handle = assert(io.open(dir .. "/" .. name, "w"))
    handle:write(text)
    handle:close()
  end
  put("settings.json", [[{ "tasks.contextMenu": ["Open in yazi", "deploy"] }]])
  put("tasks.json", [[
{
  "version": "2.0.0",
  "tasks": [
    { "label": "Open in yazi", "type": "process", "command": "yazi", "args": ["${input:folder}"],
      "options": { "cwd": "${input:folder}" } },
    { "label": "Replace in", "type": "shell", "command": "scooter", "args": ["--dir=${input:folder}"] },
    { "label": "deploy", "type": "shell", "command": "make deploy", "args": ["ENV=${input:env}"] },
    { "label": "missing", "type": "shell", "command": "echo ${input:nope}" },
    { "label": "secret", "type": "shell", "command": "echo ${input:pw}" },
  ],
  "inputs": [
    { "id": "folder", "type": "command", "command": "tasks.pickFolder" },
    { "id": "env", "type": "pickString", "description": "Where", "options": ["staging", { "label": "Production", "value": "prod" }] },
    { "id": "pw", "type": "promptString", "password": true },
  ],
}
]])

  local l = T.loadKernel()
  l.userDir = dir
  l.setup()
  T.adopt(l)
  local runs = {}
  l.registerCommand("terminal.run", { title = "spy", menus = {}, run = function(args, ctx)
    local cmd = args.cmd
    if type(cmd) == "table" then
      local words = {}
      for i, word in ipairs(cmd) do words[i] = l.resolve(word, ctx) end
      cmd = table.concat(words, "|")
    end
    -- As terminal.run fills a line: every value single-quoted.
    local line = type(args.cmd) == "string"
                 and l.resolve(args.cmd, ctx, nil, function(v) return "'" .. v:gsub("'", "'\\''") .. "'" end) or nil
    runs[#runs + 1] = { cmd = cmd, line = line,
                        target = args.target and l.resolve(args.target, ctx) or nil }
  end })
  local lines = {}
  for _, p in ipairs(l.getProblems()) do lines[#lines + 1] = p.message end
  local problems = table.concat(lines, " | ")

  local yazi = l.getCommand("tasks.run.openInYazi")
  check("a task using an input is a command of its own, asking tasks.json's inputs in VS Code's shape",
        yazi ~= nil and yazi.inputs[1].id == "folder" and yazi.inputs[1].picker.when ~= nil
        and l.getCommand("tasks.run.deploy").inputs[1].picker.options[2].value == "prod",
        tostring(yazi and yazi.inputs[1].id))

  local offered = {}
  for _, row in ipairs(l.itemActions({ kind = "folder", path = "/a b" }, {})) do offered[#offered + 1] = row.command end
  offered = " " .. table.concat(offered, " ") .. " "
  check("cmd+k on a folder offers a task taking one only when tasks.contextMenu names it",
        offered:find(" tasks.run.openInYazi ", 1, true) ~= nil
        and offered:find(" tasks.run.replaceIn ", 1, true) == nil, offered)

  l.executeCommand("tasks.run.openInYazi", { folder = { kind = "folder", path = "/a b" } }, {})
  check("the picked row's path fills ${input:folder}, in the arguments and in options.cwd",
        runs[1] ~= nil and runs[1].cmd == "yazi|/a b" and runs[1].target == "/a b",
        tostring(runs[1] and runs[1].cmd) .. " @ " .. tostring(runs[1] and runs[1].target))

  l.executeCommand("tasks.runTask", { task = "Replace in", folder = "/x y" }, {})
  check("Run Task passes the inputs given beside the label, and a shell task's argument leaves the input "
        .. "for terminal.run to quote",
        runs[2] ~= nil and runs[2].cmd == "scooter '--dir='${input:folder}"
        and runs[2].line == "scooter '--dir=''/x y'",
        tostring(runs[2] and runs[2].cmd) .. " / " .. tostring(runs[2] and runs[2].line))

  check("an input not declared, a password prompt, and tasks.contextMenu naming a task that takes no folder "
        .. "are problems",
        problems:find("uses ${input:nope}, which inputs does not declare", 1, true) ~= nil
        and problems:find("password prompt", 1, true) ~= nil
        and problems:find("tasks.contextMenu names deploy", 1, true) ~= nil, problems)

  os.execute(("rm -rf %q"):format(dir))
end
