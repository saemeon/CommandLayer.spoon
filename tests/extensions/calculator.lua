-- CommandLayer.spoon/tests/extensions/calculator.lua
-- The calculator extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.calculator

for input, want in pairs({
  ["2+2"] = "2+2", ["10 / 4"] = "10 / 4", ["2^10"] = "2^10",
  ["(3+4)*2"] = "(3+4)*2", ["sqrt(16)"] = "sqrt(16)", ["2+2="] = "2+2", ["-5"] = "-5",
}) do
  check(("%s is worth asking bc about"):format(input), M.expression(input) == want,
        tostring(M.expression(input)))
end
for _, input in ipairs({
  "safari", "5", "log", "", "hello world", "17 % 5", "quit", "while (1) {}",
  "os.exit()", "print('x')", "2+2; os.execute('touch /tmp/pwned')", "x=2+2",
}) do
  check(("%q is not sent to bc"):format(input), M.expression(input) == nil,
        tostring(M.expression(input)))
end
for out, want in pairs({
  ["2.50000000000000000000\n"] = "2.5", ["1024\n"] = "1024", ["4.00000000000000000000\n"] = "4",
  ["-.50000000000000000000\n"] = "-0.5", ["12345\\\n67890\n"] = "1234567890",
  [".00000000000000000000\n"] = "0",
}) do
  check(("bc's %q reads %s"):format(out, want), M.format(out) == want, tostring(M.format(out)))
end
check("output that is not a number reads as nothing",
      M.format("") == nil and M.format("Parse error: bad expression\n") == nil)

local tasks, refreshes = {}, 0
local saved = { new = hs.task.new, path = cl.tools.path, refresh = cl.refresh }
-- Input reaches bc as a file a shell redirects, so the stub reads the file.
hs.task.new = function(program, done, _, args)
  -- Only bc's: another extension's capture may start a task of its own.
  if program ~= "/bin/sh" or args[5] ~= "/fake/bc" then return saved.new(program, done, _, args) end
  local handle = io.open(args[4], "r")
  local t = { shell = program, program = args[5], args = { table.unpack(args, 6) }, done = done,
              input = handle and handle:read("a") }
  if handle then handle:close() end
  function t.start(self) return self end
  function t.terminate() t.terminated = true; done(15, "", "") end
  tasks[#tasks + 1] = t
  return t
end
cl.tools.path = function(name)
  if name == "bc" then return "/fake/bc" end
  return saved.path(name)
end
cl.refresh = function() refreshes = refreshes + 1 end
cl.stopRunning("calculator")
M.forget()

local ctx = cl.buildContext()
local before = cl.queryItems(ctx, "10 / 4")
local asked = tasks[1]
cl.queryItems(ctx, "10 / 4")
local asksWhileWaiting = #tasks
if asked then asked.done(0, "2.50000000000000000000\n", "") end
local answers = cl.queryItems(ctx, "10 / 4")
check("a sum is asked of bc -l in a task, on its input, and shows nothing until it answers",
      #before == 0 and asked ~= nil and asked.program == "/fake/bc" and asked.args[1] == "-l"
      and asked.input == "10 / 4\n" and asksWhileWaiting == 1,
      asked and tostring(asked.input) or "not asked")
check("bc's answer redraws the picker, and the sum is then a row that copies it",
      refreshes == 1 and #answers == 1 and answers[1].label == "2.5"
      and answers[1].command == "system.copy" and answers[1].args.text == "2.5" and #tasks == 1,
      ("%d refreshes, %d rows, %d tasks"):format(refreshes, #answers, #tasks))

local asksBefore = #tasks
local plain = #cl.queryItems(ctx, "safari") + #cl.queryItems(ctx, "5")
check("ordinary text starts no task and produces no row", #tasks == asksBefore and plain == 0)

cl.queryItems(ctx, "2+")
local refused = tasks[#tasks]
if refused then refused.done(2, "", "Parse error: bad expression\n") end
local afterError = cl.queryItems(ctx, "2+")
check("an expression bc refuses gives no row, and is not asked again",
      #tasks == asksBefore + 1 and #afterError == 0 and refreshes == 1,
      ("%d tasks, %d rows"):format(#tasks - asksBefore, #afterError))

cl.queryItems(ctx, "1+1")
local older = tasks[#tasks]
cl.queryItems(ctx, "1+2")
local newer = tasks[#tasks]
if newer then newer.done(0, "3\n", "") end
local three = cl.queryItems(ctx, "1+2")
local asksAgain = #tasks
cl.queryItems(ctx, "1+1")
check("typing on terminates the unfinished ask, whose end is not taken for an answer",
      older ~= newer and older.terminated == true and #three == 1 and three[1].label == "3"
      and #tasks == asksAgain + 1, tostring(older.terminated))

local copy
for _, row in ipairs(answers[1] and cl.itemActions(answers[1].subject, ctx) or {}) do
  if row.command == "calculator.copy" then copy = row end
end
check("an answer offers Copy on cmd+k", copy ~= nil and copy.args.number.value == "2.5")

hs.task.new, cl.tools.path, cl.refresh = saved.new, saved.path, saved.refresh
cl.stopRunning("calculator")
M.forget()
