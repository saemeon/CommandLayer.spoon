-- CommandLayer.spoon/tests/extensions/terminal.lua
-- The terminal extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.terminal

local spawned = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done }
  function t.start(self) return self end
  function t.terminate() end
  spawned[#spawned + 1] = t
  return t
end)
local alerts = {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
local waited = 0
stub(hs.osascript, "applescript", function() waited = waited + 1; return true, "", {} end)
-- Paths of their own, so what is installed on this machine changes nothing.
stub(cl.tools.paths, "osascript", "/usr/bin/osascript")
stub(cl.tools.paths, "open", "/usr/bin/open")
stub(cl.tools.paths, "wezterm", "/fake/wezterm")
-- WezTerm running unless a check says otherwise, and never the machine's own.
local wezRunning, lookedUp, fronted = true, {}, {}
stub(hs.application, "applicationsForBundleID", function(id)
  lookedUp[#lookedUp + 1] = id
  return wezRunning and { {} } or {}
end)
stub(hs.application, "launchOrFocusByBundleID", function(id) fronted[#fronted + 1] = id; return true end)

local function withSettings(settings, fn)
  local saved = cl.userSettings
  cl.userSettings = settings
  fn()
  cl.userSettings = saved
end

local function args(task) return table.concat(task and task.args or {}, " | ") end

-- A value holding quotes, a backslash and a template of its own.
local ctx = { clipboard = [[it's "x" \ ${frontmostApp}]], frontmostApp = "Finder" }
cl.executeCommand("terminal.run", { cmd = "echo ${clipboard}", target = "/a b" }, ctx)
local script = spawned[#spawned]
local expected = [[
tell application "Terminal"
  activate
  do script "cd '/a b' && echo 'it'\\''s \"x\" \\ ${frontmostApp}'"
end tell]]
check("by default a command runs in Terminal.app through do script, in osascript's own process, nothing waiting",
      cl.setting("terminal", "application") == "terminal"
      and script ~= nil and script.program == "/usr/bin/osascript" and script.args[1] == "-e"
      and script.args[2] == expected and #script.args == 2 and waited == 0 and #alerts == 0,
      script and tostring(script.args[2]))

local before = #spawned
local lines, restore = T.capturingPrint()
if script and script.done then
  script.done(1, "", "execution error: Not authorized to send Apple events to Terminal. (-1743)")
end
restore()
check("Terminal.app refusing Automation says where to allow it, logs, and tries no other way",
      #alerts == 1 and alerts[1] == M.AUTOMATION and alerts[1]:find("Privacy & Security > Automation", 1, true)
      and (lines[1] or ""):match("^%[commandlayer%].*%-1743") ~= nil and #spawned == before,
      tostring(alerts[1]) .. " / " .. tostring(lines[1]) .. " / " .. (#spawned - before) .. " started")

lines, restore = T.capturingPrint()
cl.executeCommand("terminal.run", { cmd = "false", title = "Fail" }, {})
local failing = spawned[#spawned]
if failing ~= script and failing.done then failing.done(1, "", "execution error: syntax error (-2740)") end
restore()
check("any other failure is a failure, not a missing permission",
      #alerts == 2 and alerts[2] == "Failed: Fail" and #lines == 1, tostring(alerts[2]))

withSettings({ ["terminal.application"] = "wezterm", ["terminal.shell"] = "/bin/zsh" }, function()
  cl.executeCommand("terminal.run", { cmd = { "git", "-C", "${finderSelection}", "log" }, target = "/a b" },
                    { finderSelection = "/it's" })
end)
local wez = spawned[#spawned]
check("in WezTerm a command runs through cli spawn in a login shell, each word quoted, the window kept open",
      wez.program == "/fake/wezterm"
      and args(wez) == table.concat({ "cli", "spawn", "--cwd", "/a b", "--", "/bin/zsh", "-lc",
                                      "'git' '-C' '/it'\\''s' 'log'\nexec '/bin/zsh' -l" }, " | "),
      args(wez))

withSettings({ ["terminal.application"] = "wezterm", ["terminal.shell"] = "/bin/zsh" }, function()
  cl.executeCommand("terminal.run", { cmd = "lazygit", target = "/repo", keepOpen = false }, {})
end)
local interactive = spawned[#spawned]
check("with keepOpen false the window goes when the command ends",
      interactive.args[#interactive.args] == "lazygit", args(interactive))

lines, restore = T.capturingPrint()
if wez.done then wez.done(0, "", "") end
if interactive.done then interactive.done(1, "", "failed to connect to Socket") end
restore()
check("WezTerm is judged running by bundle id, and brought forward once cli spawn succeeds, not when it fails",
      lookedUp[1] == "com.github.wez.wezterm" and #fronted == 1 and fronted[1] == "com.github.wez.wezterm"
      and #lines == 1,
      table.concat(fronted, " ") .. " / " .. tostring(lookedUp[1]))

wezRunning = false
local startedBefore = #spawned
withSettings({ ["terminal.application"] = "wezterm", ["terminal.shell"] = "/bin/zsh" }, function()
  cl.executeCommand("terminal.run", { cmd = "htop", target = "/a b" }, {})
  cl.executeCommand("terminal.open", { target = "/a/dir", newWindow = true }, {})
end)
wezRunning = true
local launchedRun, launchedOpen = spawned[startedBefore + 1], spawned[startedBefore + 2]
check("with WezTerm not running it is started through open, start --cwd, a command after --",
      #spawned == startedBefore + 2
      and launchedRun.program == "/usr/bin/open"
      and args(launchedRun) == table.concat({ "-na", "WezTerm", "--args", "start", "--cwd", "/a b",
                                              "--", "/bin/zsh", "-lc", "htop\nexec '/bin/zsh' -l" }, " | ")
      and launchedOpen.program == "/usr/bin/open"
      and args(launchedOpen) == "-na | WezTerm | --args | start | --cwd | /a/dir",
      args(launchedRun) .. " / " .. args(launchedOpen))

cl.executeCommand("terminal.open", { target = "/a/dir" }, {})
local plain = spawned[#spawned]
withSettings({ ["terminal.application"] = "wezterm" }, function()
  cl.executeCommand("terminal.open", { target = "/a/dir" }, {})
end)
local chosen = spawned[#spawned]
check("a folder opens in the terminal chosen: Terminal.app through open, WezTerm through cli spawn",
      plain.program == "/usr/bin/open" and args(plain) == "-a | Terminal | /a/dir"
      and chosen.program == "/fake/wezterm" and args(chosen) == "cli | spawn | --cwd | /a/dir",
      args(plain) .. " / " .. args(chosen))

stub(cl.tools.candidates, "kitty", { "/nonexistent/kitty" })
cl.tools.forget()
before = #spawned
lines, restore = T.capturingPrint()
withSettings({ ["terminal.application"] = "kitty" }, function()
  cl.executeCommand("terminal.run", { cmd = "ls" }, {})
end)
restore()
check("a terminal chosen that is not installed is said so, and none other is used",
      #spawned == before and alerts[#alerts] == "kitty is not installed" and #lines == 1,
      tostring(alerts[#alerts]))
cl.tools.forget()
