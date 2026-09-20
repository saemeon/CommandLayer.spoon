-- CommandLayer.spoon/tests/extensions/zoxide.lua
-- The zoxide extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.zoxide

local ran = {}
local saved = { new = hs.task.new, path = cl.tools.path, settings = cl.userSettings,
                attributes = hs.fs.attributes }
-- The harness's own stub opens a path to see whether it exists, and a
-- directory opens too, so it calls every folder a file.
hs.fs.attributes = function(path)
  local out = io.popen(("test -d %q && echo dir || (test -e %q && echo file)"):format(path, path))
  local kind = out:read("a")
  out:close()
  if kind:find("dir", 1, true) then return { mode = "directory" } end
  if kind:find("file", 1, true) then return { mode = "file" } end
  return nil
end
hs.task.new = function(_, callback, _, args)
  ran[#ran + 1] = { args = args, done = callback }
  return { start = function(t) return t end, terminate = function() end,
           setInput = function() end, closeInput = function() end }
end
cl.tools.path = function(name)
  if name == "zoxide" then return "/fake/zoxide" end
  return saved.path(name)
end
cl.stopRunning("zoxide")
M.forget()

local dir = os.tmpname() .. "-zoxide"
os.execute(("mkdir -p %q/one/.git %q/two"):format(dir, dir))
local file = dir .. "/one/notes.txt"
local handle = io.open(file, "w")
handle:write("x")
handle:close()

local ext
for _, e in ipairs(cl.extensions) do
  if e.name == "zoxide" then ext = e end
end

M.refresh()
if ran[#ran] then ran[#ran].done(0, dir .. "/one/\n" .. dir .. "/two\n") end
local texts = {}
for _, row in ipairs(cl.gather(cl.buildContext(), { menus = { "files" } })) do
  if row.source == "zoxide" then texts[#texts + 1] = row.label end
end
check("zoxide's folders are rows in files, in its order", table.concat(texts, " ") == "one two",
      table.concat(texts, " "))

local found
local searchCtx = cl.buildContext()
local stop = ext.search(" code  TWO ", searchCtx, function(rows) found = rows end)
local search = ran[#ran]
if search then search.done(0, dir .. "/two/\n", "") end
check("typing in files asks zoxide for the folders matching the words, and they open",
      search and table.concat(search.args, " ") == "query --list code TWO" and type(stop) == "function"
      and found and #found == 1 and found[1].subject.path == dir .. "/two"
      and found[1].command == "system.open" and found[1].args.target == dir .. "/two",
      search and table.concat(search.args, " "))

local capped
cl.userSettings = { ["zoxide.searchLimit"] = 1 }
ext.search("o", searchCtx, function(rows) capped = rows end)
cl.userSettings = saved.settings
if ran[#ran] then ran[#ran].done(0, dir .. "/one\n" .. dir .. "/two\n", "") end
check("and no more of them than searchLimit", capped and #capped == 1, capped and tostring(#capped))

local before = #ran
ext.picked({ subject = { kind = "folder", path = dir .. "/one" } })
ext.picked({ subject = { kind = "file", path = file },
             command = "system.open", args = { target = file } })
ext.picked({ label = "Open in terminal", command = "files.openInTerminal",
             args = { target = { kind = "folder", path = dir .. "/two" } } })
local added = {}
for i = before + 1, #ran do added[#added + 1] = table.concat(ran[i].args, " ") end
check("opening a folder tells zoxide, whichever way it was opened; a file does not",
      table.concat(added, " | ") == "add " .. dir .. "/one | add " .. dir .. "/two",
      table.concat(added, " | "))

local asked = #ran
for i = before + 1, #ran do ran[i].done(0, "", "") end
ext.items(cl.buildContext())
check("and zoxide is asked again once it has counted one", #ran == asked + 1
      and ran[#ran].args[1] == "query", tostring(#ran - asked) .. " asks")
ran[#ran].done(0, dir .. "/one/\n" .. dir .. "/two\n")

cl.userSettings = { ["zoxide.learn"] = false }
local beforeOff = #ran
ext.picked({ subject = { kind = "folder", path = dir .. "/one" } })
cl.userSettings = saved.settings
check("with learn switched off, zoxide is not told", #ran == beforeOff,
      tostring(#ran - beforeOff) .. " asks")

local projects = cl.modules.projects
local listed
if projects and projects.forget then
  cl.userSettings = { ["projects.useEditorRecents"] = false }
  projects.forget()
  projects.projects()
  if ran[#ran] then ran[#ran].done(0, dir .. "/two\n" .. dir .. "/one\n") end
  listed = projects.projects()
  cl.userSettings = saved.settings
  projects.forget()
end
local paths = {}
for _, p in ipairs(listed or {}) do paths[#paths + 1] = p.path end
check("projects come from zoxide's list, git repositories only",
      #paths == 1 and paths[1] == dir .. "/one", table.concat(paths, " "))

os.execute(("rm -rf %q"):format(dir))
hs.task.new, cl.tools.path = saved.new, saved.path
hs.fs.attributes = saved.attributes
cl.stopRunning("zoxide")
cl.stopRunning("projects")
M.forget()
