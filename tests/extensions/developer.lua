-- CommandLayer.spoon/tests/extensions/developer.lua
-- The developer extension's checks.

local T = ...
local check = T.check
local cl = T.layer()


local consoles, realConsole = 0, hs.openConsole
hs.openConsole = function() consoles = consoles + 1 end
cl.executeCommand("developer.showLogs", {})
hs.openConsole = realConsole
check("Show Logs opens Hammerspoon's console", consoles == 1, tostring(consoles))

local before = cl.logLevel
cl.executeCommand("developer.setLogLevel", { level = "debug" })
local level, numeric = cl.logLevel, cl.log.getLogLevel()
cl.setLogLevel(before)
check("Set Log Level applies the level for the session", level == "debug" and numeric == 4,
      tostring(level) .. " " .. tostring(numeric))

local function optionsOf(id, ctx)
  return cl.getCommand(id).inputs[1].picker.options(ctx)
end

do
  local now = 0
  T.stub(cl, "clock", function() return now end)
  cl.performance({ reset = true })
  -- Under slowMilliseconds, which would be a warning for the log trap.
  for name, step in pairs({ ["test.quick"] = 5, ["test.slow"] = 200, ["test.middle"] = 40 }) do
    local stop = cl.span(name)
    now = now + step
    stop()
  end
  local options = optionsOf("developer.showPerformance")
  local labels = {}
  for i, o in ipairs(options) do labels[i] = o.label end
  check("Show Performance lists span names slowest first, with count, median, max and last",
        #options == 3 and labels[1] == "test.slow" and labels[3] == "test.quick"
        and options[1].description == "1× · median 200 ms · max 200 ms · last 200 ms",
        table.concat(labels, ", ") .. " / " .. tostring(options[1] and options[1].description))

  cl.executeCommand("developer.resetPerformance", {}, T.context())
  local cleared = optionsOf("developer.showPerformance")
  check("Reset Performance clears them, and Show Performance says nothing is recorded",
        next(cl.performance()) == nil and #cleared == 1 and cleared[1].value == "",
        tostring(cleared[1] and cleared[1].label))
end

do
  local ctx = { clipboard = "hunter2 is the password", frontmostApp = "Finder",
                pageTitle = string.rep("A long title ", 20), focusedWindow = {} }
  local options = optionsOf("developer.inspectContextKeys", ctx)
  local byKey, leaked = {}, false
  for _, o in ipairs(options) do
    byKey[o.label] = o.description
    if tostring(o.description):find("hunter2", 1, true) or tostring(o.label):find("hunter2", 1, true) then
      leaked = true
    end
  end
  check("Inspect Context Keys lists every key with a short value",
        byKey.frontmostApp == "Finder" and byKey.focusedWindow == "table, 0 entries"
        and utf8.len(byKey.pageTitle) == 61 and byKey.pageTitle:sub(-3) == "…",
        tostring(byKey.pageTitle))
  check("a list of paths reads as how many and their names, as Finder's selection is",
        cl.modules.developer.shortValue("finderSelectedFiles", { "/a/one.txt", "/a/two.txt", "/a/dir/" })
        == "3: one.txt, two.txt, dir",
        cl.modules.developer.shortValue("finderSelectedFiles", { "/a/one.txt", "/a/two.txt", "/a/dir/" }))
  check("and never the clipboard's text, only its length",
        byKey.clipboard == "23 characters" and not leaked, tostring(byKey.clipboard))

  -- The context a row carries is a scoped copy, whose own key is what the
  -- scope added: reading it with pairs alone listed activeView and nothing
  -- else.
  local scoped = cl.argContext(ctx, { activeView = "palette" })
  local through = {}
  for _, o in ipairs(optionsOf("developer.inspectContextKeys", scoped)) do
    through[o.label] = o.description
  end
  check("and, given a scoped context, the keys it reads through as well as its own",
        through.activeView == "palette" and through.frontmostApp == "Finder"
        and through.clipboard == "23 characters",
        table.concat({ tostring(through.activeView), tostring(through.frontmostApp),
                       tostring(through.clipboard) }, " / "))
end
