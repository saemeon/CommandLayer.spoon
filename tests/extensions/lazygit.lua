-- CommandLayer.spoon/tests/extensions/lazygit.lua
-- The lazygit extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()

local ran, alerts = {}, {}
cl.registerCommand("terminal.run", { title = "spy", menus = {},
                                     run = function(args) ran[#ran + 1] = args end })
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
local installed = "/fake/lazygit"
local realPath = cl.tools.path
stub(cl.tools, "path", function(name)
  if name == "lazygit" then return installed end
  return realPath(name)
end)

local function offered(subject)
  for _, row in ipairs(cl.itemActions(subject, cl.buildContext())) do
    if row.command == "lazygit.open" then return true end
  end
  return false
end
check("Open in lazygit is on a project's and a folder's cmd+k, not a file's",
      offered({ kind = "project", path = "/tmp/p" }) and offered({ kind = "folder", path = "/tmp/f" })
      and not offered({ kind = "file", path = "/tmp/f/x.txt" }))

cl.executeCommand("lazygit.open", { folder = { kind = "folder", path = "/tmp/a b" } }, {})
local run = ran[1]
check("it runs lazygit in the folder, in the terminal, with no window kept once lazygit is quit",
      #ran == 1 and #run.cmd == 1 and run.cmd[1] == "lazygit" and run.target == "/tmp/a b"
      and run.keepOpen == false and run.title == "Open in lazygit",
      run and (tostring(run.cmd and run.cmd[1]) .. " @ " .. tostring(run.target) .. " " .. tostring(run.keepOpen)))

installed = nil
cl.executeCommand("lazygit.open", { folder = { kind = "project", path = "/tmp/p" } }, {})
check("without lazygit nothing runs, and it says so",
      #ran == 1 and alerts[#alerts] == "lazygit not found", tostring(alerts[#alerts]))
