-- CommandLayer.spoon/tests/performance.lua
-- Where the time goes: spans, the line per open and keystroke, the setting,
-- and a budget for rows through the whole pick path.

local T = ...
local check, group, stub = T.check, T.group, T.stub
local cl = T.layer()

-- A clock that moves only when a check moves it.
local now = 0
local function steppedClock()
  stub(cl, "clock", function() return now end)
end

local function hookCounting(step)
  return function()
    now = now + step
    return { { label = "Row after " .. step } }
  end
end

-- The lines the logger wrote while fn ran, at the level given, not seen by
-- the log trap.
local function linesWritten(level, fn)
  local lines, restore = T.capturingPrint()
  local before = cl.logLevel
  cl.setLogLevel(level)
  local ok, err = pcall(fn)
  cl.setLogLevel(before)
  restore()
  if not ok then error(err, 0) end
  return lines
end

local function find(lines, pattern)
  for _, line in ipairs(lines) do
    if line:find(pattern) then return line end
  end
end

cl.register({ name = "test-slow", menus = { "test-perf" }, items = hookCounting(400) })
cl.register({ name = "test-quick", menus = { "test-perf" }, items = hookCounting(5) })
cl.view({ name = "test-perf", menus = { "test-perf" } })

group("the line per open")
do
  steppedClock()
  stub(cl, "matchers", T.substringOnly())
  local picker
  local lines = linesWritten("debug", function() picker = T.openRecorded("test-perf") end)
  local open = find(lines, "open test%-perf %d+ms first:")
  check("an open writes one line naming what took its time, the slow extension first",
        open ~= nil and open:find("gather 405 (test-slow 400, test-quick 5", 1, true) ~= nil
        and open:find("draw", 1, true) ~= nil and open:find("· 2 rows", 1, true) ~= nil,
        open or table.concat(lines, " | "))
  check("and the extension over slowMilliseconds is a warning naming it",
        find(lines, "slow: gather%.test%-slow took 400 ms") ~= nil, table.concat(lines, " | "))

  local typed = linesWritten("debug", function() picker.type("row") end)
  local line = find(typed, "keystroke test%-perf %d+ms:")
  check("a keystroke writes a line of its own: matching, ranking, drawing",
        line ~= nil and line:find("match 0 (substring 0)", 1, true) ~= nil
        and line:find("rank 0", 1, true) ~= nil and line:find("draw 0", 1, true) ~= nil
        and not line:find("first", 1, true),
        line or table.concat(typed, " | "))

  local quiet = linesWritten("warning", function() picker.type("ro") end)
  check("at warning, a keystroke under slowMilliseconds writes nothing", #quiet == 0, table.concat(quiet, " | "))

  local figures = cl.performance()
  check("the first open is kept apart from later ones",
        figures["open.test-perf.first"] and figures["open.test-perf.first"].max == 405
        and figures["open.test-perf"] == nil)

  local background = linesWritten("warning", function()
    local stop = cl.span("task.test-tool")
    now = now + 900
    stop()
  end)
  local task = cl.performance()["task.test-tool"]
  check("a slow task, off the main thread, is recorded but is no warning",
        #background == 0 and task ~= nil and task.max == 900, table.concat(background, " | "))
end

group("aggregates")
do
  steppedClock()
  local api = cl.pluginAPI("extension", "developer")
  api.performance({ reset = true })
  for _, step in ipairs({ 10, 30, 20 }) do
    local stop = cl.span("test.aggregate")
    now = now + step
    stop()
  end
  local f = api.performance()["test.aggregate"]
  check("cl.performance gives count, total, max, last, median and p90 per span name",
        f ~= nil and f.count == 3 and f.total == 60 and f.max == 30 and f.last == 20
        and f.median == 20 and f.p90 == 30,
        f and ("%d %d %d %d %s %s"):format(f.count, f.total, f.max, f.last, tostring(f.median), tostring(f.p90)))
  f.count = 99
  check("a copy: changing it changes nothing recorded", api.performance()["test.aggregate"].count == 3)
  local recent = cl.recentSpans()
  check("the latest spans are kept in order", #recent == 3 and recent[3].ms == 20, tostring(#recent))
  cl.configurePerformance({ keep = 2 })
  local kept = cl.recentSpans()
  cl.span("test.aggregate")()
  local after = cl.recentSpans()
  check("and no more than keep of them", #kept == 2 and kept[2].ms == 20 and #after == 2 and after[1].ms == 20,
        #kept .. " then " .. #after)
  cl.configurePerformance({ keep = 200 })
end

group("recording off")
do
  steppedClock()
  cl.configurePerformance({ slowMilliseconds = 0 })
  local picker
  local lines = linesWritten("trace", function()
    picker = T.openRecorded("test-perf")
    picker.type("row")
    cl.span("test.off")()
  end)
  local timing = {}
  for _, line in ipairs(lines) do
    if line:find("%d ?ms") then timing[#timing + 1] = line end
  end
  check("with slowMilliseconds 0 nothing is recorded, and no timing is logged even at trace",
        next(cl.performance()) == nil and #timing == 0, table.concat(timing, " | "))
  cl.configurePerformance({ slowMilliseconds = 250 })

  local folder = os.tmpname() .. "-performance-off"
  os.execute(("mkdir -p %q"):format(folder))
  local handle = assert(io.open(folder .. "/settings.json", "w"))
  handle:write('{ "performance": { "slowMilliseconds": 0 } }')
  handle:close()
  local off = T.loadKernel()
  off.userDir = folder
  off.setup()
  check("0 in settings.json forgets what setup recorded before the settings were read",
        next(off.performance()) == nil and #off.getProblems() == 0)

  cl.checkSettings({ performance = { slowMs = 3, keep = -1 } }, "test-performance-problems/settings.json",
                   cl.readJSONC(cl.SPOON_DIR .. "config/defaults.jsonc"))
  local named = {}
  for _, p in ipairs(cl.getProblems()) do
    if p.file:find("test-performance-problems", 1, true) then named[#named + 1] = p.message end
  end
  check("a performance key that is not a setting, or a value that is not a number 0 or more, is a problem",
        #named == 2, table.concat(named, " | "))
end

----------------------------------------------------------------------
-- A BUDGET
--
-- Coarse on purpose: the whole of it takes about 10 ms of CPU time here, and
-- one loop over every row inside another took 360, so the budget sits well
-- clear of both. os.clock is CPU time, which another process running does
-- not add to.
----------------------------------------------------------------------

local BUDGET_MS = 80
local ROWS = 3000

group("a budget")
do
  local rows = {}
  for i = 1, ROWS do
    rows[i] = { label = ("Budget row %d %s"):format(i, i % 7 == 0 and "seven" or "other"),
                subject = { kind = "budget", id = i } }
  end
  cl.register({ name = "test-budget", menus = { "test-budget" }, items = function()
    local out = {}
    for i, row in ipairs(rows) do out[i] = { label = row.label, subject = row.subject } end
    return out
  end })
  cl.view({ name = "test-budget", menus = { "test-budget" } })
  stub(cl, "matchers", T.substringOnly())

  local started = os.clock()
  local picker = T.openRecorded("test-budget")
  local opened = #(picker.shown or {})
  picker.type("seven")
  local narrowed = #(picker.shown or {})
  picker.type("row 1")
  local spent = (os.clock() - started) * 1000
  check(("%d rows gathered, matched, ranked and drawn three times in under %d ms"):format(ROWS, BUDGET_MS),
        spent < BUDGET_MS and opened > 0 and narrowed > 0 and #picker.shown > 0,
        ("%.0f ms, %d / %d / %d rows"):format(spent, opened, narrowed, #(picker.shown or {})))
end
