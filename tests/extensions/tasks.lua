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
