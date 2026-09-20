-- CommandLayer.spoon/tests/extensions/editor.lua
-- The editor extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()

local spawned = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done }
  function t.start(self) return self end
  function t.terminate() end
  spawned[#spawned + 1] = t
  return t
end)
stub(hs.alert, "show", function() end)
-- Paths of their own, so what is installed on this machine changes nothing.
stub(cl.tools.paths, "code", "/fake/code")
stub(cl.tools.paths, "zed", "/fake/zed")
stub(cl.tools.paths, "open", "/usr/bin/open")

local function opened(args, editor)
  cl.tools.overrides.editor = editor
  local before = #spawned
  cl.executeCommand("editor.open", args, {})
  cl.tools.overrides.editor = nil
  if #spawned == before then return "nothing" end
  local t = spawned[#spawned]
  return t.program .. " " .. table.concat(t.args, " ")
end

local PATH = "/a/b c.lua"
local atLine = opened({ target = PATH, line = 12 })
local plain = opened({ target = PATH })
local asText = opened({ target = PATH, line = "7" })
local notLine = opened({ target = PATH, line = "0" }) .. " / " .. opened({ target = PATH, line = "x" })
check("VS Code opens a file at a line with --goto, and without a line as a path",
      atLine == "/fake/code --goto /a/b c.lua:12" and plain == "/fake/code /a/b c.lua"
      and asText == "/fake/code --goto /a/b c.lua:7"
      and notLine == "/fake/code /a/b c.lua / /fake/code /a/b c.lua",
      table.concat({ atLine, plain, asText, notLine }, " | "))

local zed, open = opened({ target = PATH, line = 12 }, "zed"), opened({ target = PATH, line = 12 }, "open")
check("Zed is given path:line, and open, which has no way to a line, the path alone",
      zed == "/fake/zed /a/b c.lua:12" and open == "/usr/bin/open /a/b c.lua", zed .. " | " .. open)

local REMOTE = "ssh-remote+box"
local folder = opened({ target = "/srv/app", remote = REMOTE })
local remoteLine = opened({ target = "/srv/app/a.lua", remote = REMOTE, line = 3 })
local window = opened({ remote = REMOTE })
check("a remote opens in VS Code with --remote and its authority, with a path there, and at a line",
      folder == "/fake/code --remote ssh-remote+box /srv/app"
      and remoteLine == "/fake/code --remote ssh-remote+box --goto /srv/app/a.lua:3"
      and window == "/fake/code --remote ssh-remote+box",
      table.concat({ folder, remoteLine, window }, " | "))

local zedRemote = opened({ target = "/srv/app", remote = REMOTE }, "zed")
local openRemote = opened({ target = "/srv/app", remote = REMOTE }, "open")
check("and an editor with no remotes opens nothing, rather than that path on this machine",
      zedRemote == "nothing" and openRemote == "nothing", zedRemote .. " | " .. openRemote)
