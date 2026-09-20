-- CommandLayer.spoon/tests/extensions/projects.lua
-- The projects extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()

stub(cl.modules.vscode, "recentProjects", function()
  return {
    { path = "/Users/me/app", name = "app" },
    { path = "/srv/app", name = "app", remote = "box", authority = "ssh-remote+box" },
    { path = "/Users/me/app", name = "app", remote = "me@web", authority = "ssh-remote+7b7d" },
  }
end)
local spawned = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done }
  function t.start(self) return self end
  function t.terminate() end
  spawned[#spawned + 1] = t
  return t
end)
stub(cl.tools.paths, "code", "/fake/code")

local function projectRows(view)
  local ctx = cl.buildContext()
  ctx.activeView = view
  local rows = {}
  for _, row in ipairs(cl.gather(ctx, { menus = { view } })) do
    if row.source == "projects" then rows[#rows + 1] = row end
  end
  return rows
end

local recent, root = projectRows("recent"), projectRows("root")
local here, box, web = recent[1], recent[2], recent[3]
local rootRemote = 0
for _, row in ipairs(root) do
  if row.subject.kind == "remoteProject" then rootRemote = rootRemote + 1 end
end
check("VS Code's recent folders on SSH hosts are projects, each host's path its own, in VS Code's order",
      #recent == 3 and here.subject.kind == "project"
      and box.subject.kind == "remoteProject" and box.subject.host == "box"
      and box.description == "Project on box -- /srv/app"
      and web.subject.kind == "remoteProject" and web.subject.host == "me@web"
      and rootRemote == 2,
      ("%d recent, %d remote in the root, %s"):format(#recent, rootRemote, tostring(box and box.description)))

local opened
if box then
  cl.executeCommand(box.command, box.args, {})
  local t = spawned[#spawned]
  opened = t and (t.program .. " " .. table.concat(t.args, " "))
end
check("and one opens as a remote window through editor.open: code --remote <authority> <path>",
      box ~= nil and box.command == "editor.open" and opened == "/fake/code --remote ssh-remote+box /srv/app",
      tostring(opened))

-- What another extension is given, not the module's own function.
local listed = cl.extensionNamed("projects").exports.projects()
local remoteListed = false
for _, p in ipairs(listed) do
  if p.authority then remoteListed = true end
end
local saved = cl.userSettings
cl.userSettings = { ["projects.remoteProjects"] = false }
local switchedOff = projectRows("recent")
cl.userSettings = saved
check("the projects list others read stays local, and projects.remoteProjects off leaves remote rows out",
      #listed >= 1 and not remoteListed and #switchedOff == 1 and switchedOff[1].subject.kind == "project",
      ("%d listed, remote %s, %d rows off"):format(#listed, tostring(remoteListed), #switchedOff))
