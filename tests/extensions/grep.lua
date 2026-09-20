-- CommandLayer.spoon/tests/extensions/grep.lua
-- The grep extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.grep

local spec
for _, ext in ipairs(cl.extensions) do
  if ext.name == "grep" then spec = ext end
end
if not (spec and spec.search) then
  check("grep extension is registered", false)
  return
end

local HOME = os.getenv("HOME") or ""
local ROOT = "/tmp/grep-check/"

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function shown(args)
  local out = {}
  for i, arg in ipairs(args or {}) do out[i] = arg == M.CAPPED and "<CAPPED>" or tostring(arg) end
  return table.concat(out, " ")
end

local function labels(rows)
  local out = {}
  for i, r in ipairs(rows or {}) do out[i] = tostring(r.label) end
  return table.concat(out, " | ")
end

local spawned = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done, terminated = 0 }
  function t.start(self) return self end
  function t.terminate(self) self.terminated = self.terminated + 1 end
  spawned[#spawned + 1] = t
  return t
end)
-- Paths of their own, so what is installed on this machine changes nothing.
stub(cl.tools.paths, "rg", "/fake/rg")
stub(cl.tools.paths, "zsh", "/bin/zsh")
-- Matching through fzf would be one more task here, and one never answered.
stub(cl.tools.paths, "fzf", nil)
stub(cl.tools.candidates, "fzf", { "/nonexistent/fzf" })
-- VS Code's recent folders on this machine must never be what a check sees.
stub(cl.modules.vscode, "recentProjects", function() return {} end)

local realSetting = cl.setting
local function withSetting(key, value, fn)
  cl.setting = function(ext, name, ...)
    if ext == "grep" and name == key then return value, "settings.json" end
    return realSetting(ext, name, ...)
  end
  fn()
  cl.setting = realSetting
end

-- What a row answered with nothing to pick says: disabled, runs nothing, and
-- kept by the matcher whatever was typed.
local function isNotice(r)
  return type(r) == "table" and r.enabled == false and r.command == nil and r.run == nil
         and r.alwaysShow == true and r.keywords == nil
end

local placed = { subject = { kind = "folder", path = ROOT } }
local answers = {}
local function answer(rows) answers[#answers + 1] = rows end

local stop = spec.search("alpha beta", placed, answer)
local first = spawned[1]
check("a search runs rg in the place chosen through zsh, capped at 200 lines, and nothing waits for it",
      first ~= nil and first.program == "/bin/zsh" and #answers == 0 and type(stop) == "function"
      and same(first.args, { "-f", "-c", M.CAPPED, "zsh", "200", "/fake/rg", "--max-count", "5",
                             "--max-columns", "200", "--max-columns-preview", "--line-number", "--with-filename",
                             "--no-heading", "--null", "--color", "never", "--smart-case", "--fixed-strings", "--",
                             "alpha beta", ROOT }),
      first and shown(first.args))

if stop then stop() end
if first and first.done then first.done(143, ROOT .. "a.txt\0" .. "1:alpha beta\n", "") end
check("stopping a search ends its process, and what it printed by then is not answered",
      first ~= nil and first.terminated == 1 and #answers == 0,
      ("%s terminated, %d answers"):format(tostring(first and first.terminated), #answers))

spec.search("alpha beta", placed, answer)
local second = spawned[#spawned]
local lines = {}
for i = 1, 250 do lines[i] = ("%ssrc/a:b.lua\0%d:    alpha beta %d  "):format(ROOT, i, i) end
if second and second.done then second.done(0, table.concat(lines, "\n") .. "\n", "") end
local rows = answers[1] or {}
local row = rows[1] or {}
check("a hit is a row opening the editor at its line, named by its path in the place, at most 200",
      #rows == 200 and row.label == "alpha beta 1" and row.description == "src/a:b.lua:1"
      and row.command == "editor.open" and type(row.args) == "table"
      and row.args.target == ROOT .. "src/a:b.lua" and row.args.line == 1
      and type(row.subject) == "table" and row.subject.kind == "file" and rows[200].args.line == 200,
      ("%d rows, %s / %s"):format(#rows, tostring(row.label), tostring(row.description)))

check("every hit names the place searched, shortened with ~",
      row.detail == "/tmp/grep-check" and rows[200].detail == "/tmp/grep-check"
      and M.shorten(HOME .. "/code/x/") == "~/code/x" and M.shorten(HOME) == "~"
      and M.shorten(HOME .. "other") == HOME .. "other",
      tostring(row.detail) .. " / " .. tostring(M.shorten(HOME .. "/code/x/")))

-- A search that runs nothing: the rows it answered.
local function refused(ctx, query)
  local before, got = #spawned, nil
  spec.search(query or "abc", ctx, function(found) got = found end)
  return #spawned == before, got or {}
end

local ranNothing, unplaced = refused({ finderSelectionDir = ROOT })
local unplacedRow = unplaced[1] or {}
local beforeTyping = spec.items({})
local placedHint = spec.items({ subject = { kind = "folder", path = HOME .. "/code" } })
check("without a place chosen nothing runs, even with Finder's folder known, and a row says to choose one",
      ranNothing and #unplaced == 1 and unplacedRow.label == "Choose a place: Search Text in…"
      and isNotice(unplacedRow)
      and #beforeTyping == 1 and beforeTyping[1].label == "Choose a place: Search Text in…",
      labels(unplaced) .. " / " .. labels(beforeTyping))
check("before anything is typed, the picker says where it will search",
      #placedHint == 1 and placedHint[1].label == "Search text in ~/code" and isNotice(placedHint[1]),
      labels(placedHint))

local function finished(code, stdout, stderr, query)
  query = query or "abc"
  local got
  spec.search(query, placed, function(found) got = found end)
  local task = spawned[#spawned]
  if task and task.done then task.done(code, stdout, stderr) end
  return got or {}
end

local none = finished(1, "", "")
check("rg finding nothing is one disabled row naming the place",
      #none == 1 and none[1].label == "No results in /tmp/grep-check" and isNotice(none[1]),
      labels(none))

local warned = {}
stub(cl.log, "w", function(...) warned[#warned + 1] = table.concat({ ... }, " ") end)
local failed = finished(2, "", "rg: regex parse error:\n    more\n")
local partial = finished(2, ROOT .. "a.txt\0" .. "3:abc here\n", "rg: ./secret: Permission denied (os error 13)\n")
local silent = finished(127, "", "")
check("rg failing is a disabled row with its first line of stderr, a warning, and the hits it did find",
      #failed == 1 and failed[1].label == "rg: regex parse error:" and isNotice(failed[1])
      and #partial == 2 and partial[1].label == "abc here"
      and partial[2].label == "rg: ./secret: Permission denied (os error 13)" and isNotice(partial[2])
      and #silent == 1 and silent[1].label == "rg exited with 127"
      and #warned == 3 and warned[1]:find("exit 2: rg: regex parse error:", 1, true) ~= nil,
      ("%s / %s / %s / %d warnings"):format(labels(failed), labels(partial), labels(silent), #warned))

local kept
cl.rankItems({ none[1] }, "abc", function(ranked) kept = ranked end)
check("a row saying why nothing was found survives matching what was typed",
      kept ~= nil and kept[1] == none[1], tostring(kept and #kept))

stub(cl.tools.paths, "rg", nil)
stub(cl.tools.candidates, "rg", { "/nonexistent/rg" })
local noRg, missing = refused(placed)
check("without rg installed nothing runs, and a row says so",
      noRg and labels(missing) == "ripgrep is not installed", labels(missing))
stub(cl.tools.paths, "rg", "/fake/rg")

local view = cl.viewNamed("grep")
local before = #spawned
cl.searchExtensions(placed, { menus = view and view.menus, activeView = "grep" }, "abc", function() end)
check("grep is a picker asking the extension again from three characters typed",
      view ~= nil and view.kind == "search" and view.minQuery == 3 and view.empty == nil and #spawned == before + 1,
      ("%s, %d searches"):format(tostring(view and view.minQuery), #spawned - before))

local function listsGrep(rowsShown)
  for _, r in ipairs(rowsShown or {}) do
    if r.submenu == "grep" or (type(r.subject) == "table" and r.subject.kind == "view" and r.subject.name == "grep")
    then return true end
  end
  return false
end
check("it has no prefix, so neither ? nor the root lists it as a picker to type",
      view ~= nil and #cl.prefixesOf(view) == 0
      and not listsGrep(cl.rowsOfView("help", {})) and not listsGrep(cl.rowsOfView("root", {})))

-- Search Text in…: where, then the picker on that place.
local function offered(subject)
  for _, verb in ipairs(cl.itemActions(subject, {})) do
    if verb.command == "grep.searchIn" then return verb end
  end
end
local onFile = offered({ kind = "file", path = "/a/b.txt" })
check("cmd+k on a file, a folder or a project offers Search Text in…, and not on an app",
      onFile ~= nil and onFile.args.target.path == "/a/b.txt"
      and offered({ kind = "folder", path = "/a/dir" }) ~= nil
      and offered({ kind = "project", path = "/a/repo" }) ~= nil
      and offered({ kind = "app", id = "com.apple.Safari", name = "Safari" }) == nil)

local input = (cl.getCommand("grep.searchIn") or { inputs = {} }).inputs[1] or {}
local places
stub(cl.modules.vscode, "recentProjects", function()
  local list = { { path = "/remote/proj", remote = "host" }, { path = "/w.code-workspace", workspace = true },
                 { path = "/local/proj" }, { path = ROOT } }
  for i = 1, 8 do list[#list + 1] = { path = "/more/" .. i } end
  return list
end)
withSetting("roots", { "~/code", "/abs" }, function()
  places = input.picker and type(input.picker.options) == "function" and input.picker.options({ finderSelectionDir = ROOT }) or {}
end)
stub(cl.modules.vscode, "recentProjects", function() return {} end)
local order = {}
for i, o in ipairs(places) do order[i] = o.label end
local lastPlace = places[#places] or {}
check("asked where, it offers grep.roots, Finder's folder, a few of VS Code's local folders, then Choose…",
      table.concat(order, " | ") == "~/code | /abs | /tmp/grep-check | /local/proj | /more/1 | /more/2 | /more/3 "
                                    .. "| /more/4 | Choose…"
      and places[1].value.path == HOME .. "/code" and places[3].value.path == ROOT
      and type(lastPlace.value) == "function",
      table.concat(order, " | "))

local chosen = { ["1"] = "/tmp/grep-check/one.txt" }
stub(hs.dialog, "chooseFileOrFolder", function(_, _, files, folders) return files and folders and chosen or nil end)
stub(hs.fs, "attributes", function(path, what)
  if what == "mode" then return path == "/tmp/grep-check" and "directory" or "file" end
  return nil
end)
local pickedFile = type(lastPlace.value) == "function" and lastPlace.value() or {}
chosen = { ["1"] = "/tmp/grep-check" }
local pickedFolder = type(lastPlace.value) == "function" and lastPlace.value() or {}
chosen = nil
local cancelled = type(lastPlace.value) == "function" and lastPlace.value() or nil
check("Choose… opens the system dialog for a file or a folder, and cancelling chooses nothing",
      pickedFile.kind == "file" and pickedFile.path == "/tmp/grep-check/one.txt"
      and pickedFolder.kind == "folder" and cancelled == nil,
      tostring(pickedFile.kind) .. " / " .. tostring(pickedFolder.kind))

-- The harness's modal counts an exit and nothing more, so the layer is closed
-- here as Hammerspoon's exit closes it.
local function close() T.layerModal:exited() end

-- The search the picker on screen would run, through the kernel.
local function searchOnScreen()
  local top = cl.topView()
  if not (top and top.name == "grep") then return "on " .. tostring(top and top.name) end
  local count, got = #spawned, {}
  cl.searchExtensions(top.ctx, top.menus, "abc", function(found)
    for _, r in ipairs(found) do got[#got + 1] = r end
  end)
  if #spawned == count then return "nothing ran: " .. labels(got) end
  local args = spawned[#spawned].args
  return args[#args - 1] == "abc" and args[#args] or shown(args)
end

close()
local ranBefore = #spawned
cl.executeCommand("grep.searchIn", {}, {})
local asking = cl.topView()
local askedChoose = false
for _, r in ipairs(asking and asking.items or {}) do
  if r.label == "Choose…" then askedChoose = true end
end
check("from the palette with no place given it asks where, before searching anything",
      asking ~= nil and asking.name ~= "grep" and askedChoose and #spawned == ranBefore,
      tostring(asking and asking.name))

-- From a closed layer, then again from the open one. A place put into a context
-- key would reach every picker opened while it was set.
local keysSet = {}
local realSetContext = cl.setContext
stub(cl, "setContext", function(key, value)
  if value == "/tmp/grep-check/one.txt" or value == HOME then keysSet[#keysSet + 1] = tostring(key) end
  return realSetContext(key, value)
end)
close()
cl.executeCommand("grep.searchIn", { target = { kind = "file", path = "/tmp/grep-check/one.txt" } }, {})
local inFile = searchOnScreen()
local fileRows
spec.search("abc", { subject = { kind = "file", path = "/tmp/grep-check/one.txt" } }, function(found) fileRows = found end)
local fileTask = spawned[#spawned]
if fileTask and fileTask.done then fileTask.done(0, "/tmp/grep-check/one.txt\0" .. "4:abc\n", "") end
cl.executeCommand("grep.searchIn", { target = { kind = "folder", path = HOME } }, {})
local inHome = searchOnScreen()
close()
-- Opened as entering the layer opens it, in a context built afresh, which is
-- where a place left behind as a context key would show.
cl.open("grep")
local afterwards = searchOnScreen()
close()
local fileRow = fileRows and fileRows[1] or {}
check("Search Text in… opens the picker on that file alone, or on that folder",
      inFile == "/tmp/grep-check/one.txt" and inHome == HOME
      and fileRow.description == "one.txt:4" and fileRow.detail == "/tmp/grep-check/one.txt",
      ("%s / %s / %s"):format(inFile, inHome, tostring(fileRow.description)))
check("once the layer is closed the place is gone: the picker opened again asks for one",
      afterwards == "nothing ran: Choose a place: Search Text in…", afterwards)
check("Search Text in… sets no context key: the place is only the subject the grep picker is given",
      #keysSet == 0, table.concat(keysSet, ", "))

-- The cap itself, run as shipped: an endless producer cut at three lines.
local function quoted(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
local capped = T.popen(("/bin/zsh -f -c %s zsh 3 /usr/bin/yes 2>&1; echo \"exit $?\""):format(quoted(M.CAPPED)))
check("the cap ends an endless listing at its limit, and that is no failure", capped == "y\ny\ny\nexit 0\n", capped)

-- And rg's exit passed on, with commands standing in for rg: nothing found is
-- 1, an error 2, and a listing that ends by itself 0.
local function exitOf(producer)
  return T.popen(("/bin/zsh -f -c %s zsh 3 %s >/dev/null 2>&1; echo $?"):format(quoted(M.CAPPED), producer))
end
local codes = { exitOf("/usr/bin/false"), exitOf("/bin/sh -c 'echo x; exit 2'"), exitOf("/bin/echo x") }
check("the cap passes on the producer's exit: 1 for nothing found, 2 for an error, 0 when it finished",
      codes[1] == "1\n" and codes[2] == "2\n" and codes[3] == "0\n", (table.concat(codes, " "):gsub("\n", "")))
