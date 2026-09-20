-- CommandLayer.spoon/tests/extensions/finder.lua
-- The finder extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.finder

local finder
for _, ext in ipairs(cl.extensions) do
  if ext.name == "finder" then finder = ext end
end
if not (finder and finder.capture) then
  check("finder extension is registered", false)
  return
end

local saved = { new = hs.task.new, doAfter = hs.timer.doAfter,
                applescript = hs.osascript.applescript,
                front = hs.application.frontmostApplication,
                refresh = cl.refresh }
local front, spawned, blocking, refreshed, finish = "Finder", 0, 0, 0, nil
local watchdogs = 0

-- Other extensions' captures may start tasks of their own; only the one
-- asking Finder is counted.
hs.task.new = function(_, callback, _, args)
  local mine = args and type(args[2]) == "string"
               and args[2]:find('tell application "Finder"', 1, true)
  if mine then
    spawned = spawned + 1
    finish = callback
  end
  return { start = function(t) return t end, terminate = function() end,
           setInput = function() end, closeInput = function() end }
end
hs.timer.doAfter = function(seconds)
  if seconds == M.timeoutSeconds then watchdogs = watchdogs + 1 end
  return { stop = function() end }
end
hs.osascript.applescript = function()
  blocking = blocking + 1
  return false
end
hs.application.frontmostApplication = function()
  return { name = function() return front end,
           bundleID = function() return nil end }
end
cl.refresh = function() refreshed = refreshed + 1 end
M.forget()

local first = cl.buildContext()
check("building a context in Finder runs no AppleScript on the main thread",
      blocking == 0 and spawned == 1 and first.finderSelection == "",
      ("%d blocking, %d reads"):format(blocking, spawned))
check("the read has a watchdog, held until the read answers",
      watchdogs == 1 and M.watchdog ~= nil and type(M.watchdog.dispose) == "function",
      ("%d watchdogs"):format(watchdogs))

local second = cl.buildContext()
check("no second read starts while one is in flight", spawned == 1,
      tostring(spawned) .. " reads")

if finish then finish(0, "/tmp/finder-check/a.txt\n", "") end
check("an answer fills the context in use and redraws once",
      second.finderSelection == "/tmp/finder-check/a.txt"
      and second.finderSelectionDir == "/tmp/finder-check/"
      and refreshed == 1 and M.watchdog == nil,
      ("%s / %s / %d refreshes"):format(tostring(second.finderSelection),
                                         tostring(second.finderSelectionDir), refreshed))

local third = cl.buildContext()
if finish then finish(0, "/tmp/finder-check/a.txt\n", "") end
check("the next context starts from the answer, and the same answer does not redraw",
      third.finderSelection == "/tmp/finder-check/a.txt"
      and spawned == 2 and refreshed == 1,
      ("%d reads, %d refreshes"):format(spawned, refreshed))

local fourth = cl.buildContext()
if finish then finish(0, "/tmp/finder-check/a.txt\n/tmp/finder-check/b dir/\n", "") end
local list = fourth.finderSelectedFiles or {}
check("every item selected is in finderSelectedFiles, the first still finderSelection, and a new list redraws",
      #list == 2 and list[1] == "/tmp/finder-check/a.txt" and list[2] == "/tmp/finder-check/b dir/"
      and fourth.finderSelection == "/tmp/finder-check/a.txt" and refreshed == 2
      and cl.when("finderSelectedFiles", fourth),
      ("%d files, %s, %d refreshes"):format(#list, tostring(list[2]), refreshed))

front = "TextEdit"
local elsewhere = cl.buildContext()
check("with another app in front Finder is not asked and nothing leaks",
      spawned == 3 and elsewhere.finderSelection == ""
      and elsewhere.finderSelectionDir == "" and elsewhere.finderSelectedFiles == nil,
      ("%d reads, %s"):format(spawned, tostring(elsewhere.finderSelection)))

front = "Finder"
local fifth = cl.buildContext()
if finish then finish(1, "", "execution error") end
local scoped = {}
finder.scope({ kind = "file", path = "/x/y.txt" }, scoped)
check("a failed read leaves finderSelectedFiles unset, not an empty list; a file row scopes it to that file",
      fifth.finderSelectedFiles == nil and not cl.when("finderSelectedFiles", fifth)
      and type(scoped.finderSelectedFiles) == "table" and #scoped.finderSelectedFiles == 1
      and scoped.finderSelectedFiles[1] == "/x/y.txt",
      tostring(fifth.finderSelectedFiles))

M.forget()
hs.task.new, hs.timer.doAfter = saved.new, saved.doAfter
hs.osascript.applescript = saved.applescript
hs.application.frontmostApplication = saved.front
cl.refresh = saved.refresh
