-- CommandLayer.spoon/tests/extensions/vscode.lua
-- The vscode extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.vscode

local vscode, ctx = M, cl.buildContext()

local fromMenu = vscode.openRecentFrom({ menus = { File = { items = {
  { id = "file.new" },
  { id = "submenuitem.recent", submenu = { items = {
    { id = "openRecentFolder",    uri = { scheme = "file", path = "/Users/me/newest" } },
    { id = "openRecentWorkspace", uri = { scheme = "file", path = "/Users/me/team.code-workspace" } },
    { id = "openRecentFile",      uri = { scheme = "file", path = "/Users/me/notes.md" } },
    { id = "openRecentFolder",    uri = { scheme = "vscode-remote", authority = "ssh-remote+box",
                                          path = "/srv/app" } },
    { id = "openRecentFolder",    uri = { scheme = "file", path = "/Users/me/older/" } },
  } } },
} } } })
check("VS Code's Open Recent list gives its folders and workspaces in order, not its files",
      #fromMenu == 4 and fromMenu[1].path == "/Users/me/newest"
      and fromMenu[2].name == "team" and fromMenu[2].workspace == true
      and fromMenu[3].remote == "box" and fromMenu[4].path == "/Users/me/older",
      tostring(#fromMenu))

-- Remote - SSH's hex-encoded host, as it writes one with a user in it.
local hostJSON = '{"hostName":"box.example.com","user":"me"}'
local hexHost = hostJSON:gsub(".", function(c) return ("%02x"):format(c:byte()) end)
local savedDecode = hs.json.decode
hs.json.decode = function(text)
  if text == hostJSON then return { hostName = "box.example.com", user = "me" } end
  return savedDecode(text)
end
local remotes = vscode.openRecentFrom({ items = {
  { id = "openRecentFolder", uri = { scheme = "vscode-remote", authority = "ssh-remote+box", path = "/srv/app" } },
  { id = "openRecentFolder", uri = { scheme = "vscode-remote", authority = "ssh-remote+web", path = "/srv/app" } },
  { id = "openRecentFolder", uri = { scheme = "vscode-remote", authority = "ssh-remote+" .. hexHost,
                                     path = "/home/me/x" } },
  { id = "openRecentFolder", uri = { scheme = "file", path = "/srv/app" } },
} })
hs.json.decode = savedDecode
check("a remote recent keeps its authority for code --remote, the same path on another host is its own, "
        .. "and a hex-encoded host reads as user@host",
      #remotes == 4 and remotes[1].authority == "ssh-remote+box" and remotes[2].remote == "web"
      and remotes[3].remote == "me@box.example.com" and remotes[3].authority == "ssh-remote+" .. hexHost
      and remotes[4].authority == nil and remotes[4].remote == nil,
      ("%d, %s"):format(#remotes, tostring(remotes[3] and remotes[3].remote)))

local reads, mtime, looked = 0, 100, 0
local storageFolder = os.tmpname() .. "-globalStorage"
os.execute(("mkdir -p %q"):format(storageFolder))
local storage = storageFolder .. "/storage.json"
local handle = io.open(storage, "w")
handle:write("{}")
handle:close()
local saved = { decode = hs.json.decode, attributes = hs.fs.attributes, path = vscode.menubarPath,
                pathwatcher = hs.pathwatcher, doAfter = hs.timer.doAfter }
vscode.menubarPath = storage
hs.fs.attributes = function(path, key)
  if path == storage then
    looked = looked + 1
    return key and mtime or { modification = mtime }
  end
  return saved.attributes(path, key)
end
hs.json.decode = function()
  reads = reads + 1
  return { lastKnownMenubarData = { { id = "openRecentFolder",
                                      uri = { scheme = "file", path = "/p/" .. reads } } } }
end
local watched, changed, settle
hs.pathwatcher = { new = function(path, fn)
  watched, changed = path, fn
  return { start = function(w) return w end, stop = function() end }
end }
hs.timer.doAfter = function(_, fn) settle = fn; return { stop = function() end } end
local function settled()
  local fn = settle
  settle = nil
  if fn then fn() end
  return fn ~= nil
end
vscode.forget()
vscode.start()
local lookedAtStart = looked
local first = vscode.recentProjects()[1]
local cached = vscode.recentProjects()[1]
local lookedByPicker = looked - lookedAtStart
changed({ "/somewhere/globalStorage/state.vscdb" })
local ignored = not settled()
changed({ storage })
local unchangedSettled = settled()
local readsUnchanged = reads
mtime = 200
changed({ storage })
settled()
local rewritten = vscode.recentProjects()[1]
vscode.stop()
cl.stopRunning("vscode")
hs.json.decode, hs.fs.attributes, vscode.menubarPath = saved.decode, saved.attributes, saved.path
hs.pathwatcher, hs.timer.doAfter = saved.pathwatcher, saved.doAfter
vscode.forget()
os.execute(("rm -rf %q"):format(storageFolder))
check("recent projects are VS Code's list as read at start: a picker looks at no file",
      first and first.path == "/p/1" and cached and cached.path == "/p/1"
      and lookedByPicker == 0 and watched == storageFolder,
      ("%s %s, %d looks from a picker, watching %s"):format(tostring(first and first.path),
        tostring(cached and cached.path), lookedByPicker, tostring(watched)))
check("and a change naming storage.json reads it again, decoding only a file written since",
      ignored and unchangedSettled and readsUnchanged == 1
      and rewritten and rewritten.path == "/p/2" and reads == 2,
      ("ignored %s, %d reads unchanged, %s, %d reads"):format(tostring(ignored), readsUnchanged,
        tostring(rewritten and rewritten.path), reads))

-- The Command Layer extension in VS Code is the bridge's; nothing here may
-- need it.
local palette = cl.gather(ctx, { menus = { "commandPalette" } })
local menuRow, needsHandler = false, nil
for _, row in ipairs(palette) do
  if row.command == "vscode.commandPalette" then menuRow = true end
end
for _, command in ipairs(cl.getCommands()) do
  local target = command.extension == "vscode" and command.args and command.args.target
  if type(target) == "string" and target:find("local.command-layer", 1, true) then
    needsHandler = command.id
  end
end
check("the palette has VS Code's menu commands, and no command needs an extension in VS Code",
      menuRow and needsHandler == nil, tostring(needsHandler))

local opened, alerts = {}, {}
local restore = { new = hs.task.new, alert = hs.alert.show }
hs.task.new = function(_, _, _, args)
  opened[#opened + 1] = args and args[1]
  return { start = function(t) return t end, terminate = function() end }
end
hs.alert.show = function(message) alerts[#alerts + 1] = message end

cl.executeCommand("vscode.cloneRepository", { repository = "https%3A%2F%2Fgithub.com%2Fa%2Fb" })
local cloned = opened[#opened]
cl.executeCommand("vscode.openSetting", { setting = "editor.fontSize" })
local setting = opened[#opened]
cl.executeCommand("vscode.openAtLine",
                  { target = { kind = "file", path = "/Users/me/my project/a#b.lua" }, line = "12:5" })
local atLine = opened[#opened]
local before = #opened
cl.executeCommand("vscode.openAtLine",
                  { target = { kind = "file", path = "/Users/me/a.lua" }, line = "twelve" })
local refused = #opened == before and (alerts[#alerts] or ""):find("line", 1, true) ~= nil
hs.task.new, hs.alert.show = restore.new, restore.alert

check("Clone repository hands the URL to VS Code's own Git extension",
      cloned == "vscode://vscode.git/clone?url=https%3A%2F%2Fgithub.com%2Fa%2Fb", tostring(cloned))
check("Open setting hands the id to VS Code's settings editor",
      setting == "vscode://settings/editor.fontSize", tostring(setting))
check("Open file at line opens a vscode://file URL at the position, the path percent-encoded",
      atLine == "vscode://file/Users/me/my%20project/a%23b.lua:12:5", tostring(atLine))
check("and a line that is not a number opens nothing, saying so", refused,
      tostring(opened[#opened]) .. " / " .. tostring(alerts[#alerts]))

local function offers(subject, id)
  for _, v in ipairs(cl.itemActions(subject, ctx)) do
    if v.command == id then return v end
  end
end
local onFile = offers({ kind = "file", path = "/a/b.lua" }, "vscode.openAtLine")
check("cmd+k on a file offers Open file at line with the file given, and not on a folder",
      onFile ~= nil and onFile.args.target.path == "/a/b.lua"
      and offers({ kind = "folder", path = "/a" }, "vscode.openAtLine") == nil)

local asked, selected, activated, lookups = {}, {}, 0, 0
local app = {
  activate = function() activated = activated + 1 end,
  selectMenuItem = function(_, path) selected[#selected + 1] = table.concat(path, " > "); return true end,
}
local running = true
local savedApp = { forBundle = hs.application.applicationsForBundleID, get = hs.application.get,
                   doAfter = hs.timer.doAfter, alert = hs.alert.show }
hs.application.applicationsForBundleID = function(id)
  asked[#asked + 1] = id
  return running and { app } or {}
end
hs.application.get = function() lookups = lookups + 1 end
hs.timer.doAfter = function(_, fn) fn(); return { stop = function() end } end
local told = {}
hs.alert.show = function(message) told[#told + 1] = message end
cl.executeCommand("vscode.toggleTerminal")
running = false
cl.executeCommand("vscode.commandPalette")
hs.application.applicationsForBundleID, hs.application.get = savedApp.forBundle, savedApp.get
hs.timer.doAfter, hs.alert.show = savedApp.doAfter, savedApp.alert
check("a menu command selects its item in VS Code's menu bar, finding VS Code by bundle id",
      selected[1] == "View > Terminal" and #selected == 1 and activated == 1
      and asked[1] == "com.microsoft.VSCode" and lookups == 0,
      ("%s, %d asked, %d lookups"):format(tostring(selected[1]), #asked, lookups))
check("and says so when VS Code is not running",
      #asked == 2 and (told[#told] or ""):find("not running", 1, true) ~= nil, tostring(told[#told]))

local savedPath = cl.tools.path
local codeInstalled = true
cl.tools.path = function(name)
  if name == "code" then return codeInstalled and "/fake/code" or nil end
  return savedPath(name)
end
local project = { kind = "project", path = "/tmp/x" }
local onProject, onNewWindow = offers(project, "vscode.open"), offers(project, "vscode.openInNewWindow")
local onFolder = offers({ kind = "folder", path = "/tmp/x" }, "vscode.open")
codeInstalled = false
local withoutCLI = offers({ kind = "project", path = "/tmp/y" }, "vscode.open")
codeInstalled = true
local launched
local restoreNew = hs.task.new
hs.task.new = function(program, _, _, args)
  launched = program .. " " .. table.concat(args, " ")
  return { start = function(t) return t end, terminate = function() end }
end
if onNewWindow then cl.executeCommand("vscode.openInNewWindow", onNewWindow.args) end
hs.task.new, cl.tools.path = restoreNew, savedPath
check("a project gets the VS Code verbs where the CLI is, and a folder or no CLI does not",
      onProject ~= nil and onProject.label == "Open in VS Code" and onNewWindow ~= nil
      and onFolder == nil and withoutCLI == nil
      and launched == "/fake/code --new-window /tmp/x",
      tostring(launched))
