-- CommandLayer.spoon/tests/extensions/ssh.lua
-- The ssh extension's checks, against config files written here.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.ssh

local parsed = M.parse([[
# Host commented
Host box web
  HostName box.example.com
  User me
  HostName ignored.example.com
Host=quoted "two words" *.internal !bad -oProxyCommand=x
    User=other
Host box
  User later
Match host something
  User matched
Host tail
]])
local names = {}
for i, host in ipairs(parsed) do names[i] = host.name end
check("the ssh config gives its concrete hosts in order, the first HostName and User counting, as ssh reads it",
      table.concat(names, " ") == "box web quoted tail"
      and parsed[1].hostName == "box.example.com" and parsed[1].user == "me"
      and parsed[2].hostName == "box.example.com" and parsed[3].user == "other"
      and parsed[4].user == nil,
      table.concat(names, " ") .. " / " .. tostring(parsed[1] and parsed[1].user)
        .. " / " .. tostring(parsed[4] and parsed[4].user))

local folder = os.tmpname() .. "-ssh"
os.execute(("mkdir -p %q"):format(folder))
local config = folder .. "/config"
local function write(text)
  local handle = io.open(config, "w")
  handle:write(text)
  handle:close()
end
write("Host alpha\n  HostName alpha.example.com\n  User me\n")

local mtime, reads = 100, 0
local attributes, open = hs.fs.attributes, io.open
stub(M, "configPath", config)
stub(hs.fs, "attributes", function(path, key)
  if path == config then
    if not mtime then return nil end
    return key and mtime or { modification = mtime }
  end
  return attributes(path, key)
end)
stub(io, "open", function(path, mode)
  if path == config and (mode == nil or mode:sub(1, 1) == "r") then reads = reads + 1 end
  return open(path, mode)
end)
local watched, changed, settle
stub(hs, "pathwatcher", { new = function(path, fn)
  watched, changed = path, fn
  return { start = function(w) return w end, stop = function() end }
end })
stub(hs.timer, "doAfter", function(_, fn) settle = fn; return { stop = function() end } end)
-- Whether the change started the settling timer, which is then run: any
-- timer started before it is another extension's.
local function change(path)
  settle = nil
  changed({ path })
  local fn = settle
  settle = nil
  if fn then fn() end
  return fn ~= nil
end
local ctx = cl.buildContext()
-- The context without the terminal extension's key, as while it is off.
local bare = {}
for key, value in pairs(ctx) do bare[key] = value end
bare.terminalAvailable = nil
local function hostRows(from)
  local rows = {}
  for _, row in ipairs(cl.gather(from or ctx, { menus = { "root" } })) do
    if row.source == "ssh" then rows[#rows + 1] = row end
  end
  return rows
end

M.forget()
M.start()
local readAtStart = reads
local first, again = hostRows(), hostRows()
local readByPicker = reads - readAtStart
local inEditor = hostRows(bare)
local ignored = not change(folder .. "/known_hosts")
local heard = change(config)
local unchangedReads = reads
write("Host beta\n")
mtime = 200
change(config)
local rewritten = hostRows()
mtime = nil
change(config)
local removed = hostRows()
M.stop()
cl.stopRunning("ssh")
M.forget()
os.execute(("rm -rf %q"):format(folder))

local row = first[1]
check("a host is a root row connecting to it, read at start: a picker reads no file",
      #first == 1 and #again == 1 and row.label == "SSH: alpha"
      and row.description == "SSH host -- me@alpha.example.com"
      and row.command == "ssh.connect" and row.subject.kind == "sshHost" and row.subject.host == "alpha"
      and readAtStart == 1 and readByPicker == 0 and watched == folder,
      ("%d rows, %s, %d reads at start, %d by the picker, watching %s"):format(#first,
        tostring(row and row.description), readAtStart, readByPicker, tostring(watched)))
-- A subtitle is never matched, so "ssh" would find no host without this.
check("a host is found by typing ssh, and by the address it stands for", (function()
        local matchers = cl.matchers
        cl.matchers = T.substringOnly()
        local byName, byAddress = {}, {}
        cl.rankItems({ row }, "ssh", function(out) byName = out end)
        cl.rankItems({ row }, "alpha.example.com", function(out) byAddress = out end)
        cl.matchers = matchers
        return #byName == 1 and #byAddress == 1,
               ("%d for ssh, %d for the address"):format(#byName, #byAddress)
      end)())

check("and a change naming the config reads it again only when it was written since; gone, no hosts",
      ignored and heard and unchangedReads == 1 and reads == 2
      and #rewritten == 1 and rewritten[1].label == "SSH: beta" and #removed == 0,
      ("ignored %s, %d reads unchanged, %d reads, %s, %d after removal"):format(tostring(ignored),
        unchangedReads, reads, tostring(rewritten[1] and rewritten[1].label), #removed))

local spawned = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done }
  function t.start(self) return self end
  function t.terminate() end
  spawned[#spawned + 1] = t
  return t
end)
stub(hs.alert, "show", function() end)
stub(cl.tools.paths, "osascript", "/usr/bin/osascript")
stub(cl.tools.paths, "code", "/fake/code")

local host = { kind = "sshHost", name = "alpha", host = "alpha" }
cl.executeCommand("ssh.connect", { host = host }, {})
local script = spawned[#spawned]
cl.executeCommand("ssh.connectInEditor", { host = host }, {})
local editor = spawned[#spawned]
local before = #spawned
cl.executeCommand("ssh.connect", { host = { kind = "sshHost", host = "-oProxyCommand=x" } }, {})
cl.executeCommand("ssh.connectInEditor", { host = "bad*" }, {})
local refused = #spawned == before

check("Connect in terminal runs ssh <host> through terminal.run: Terminal.app's do script, each word quoted",
      script ~= nil and script.program == "/usr/bin/osascript"
      and (script.args[2] or ""):find("&& 'ssh' 'alpha'\"", 1, true) ~= nil,
      script and tostring(script.args[2]))
check("Connect in editor opens a remote window through editor.open: code --remote ssh-remote+<host>",
      editor ~= nil and editor ~= script and editor.program == "/fake/code"
      and table.concat(editor.args, " ") == "--remote ssh-remote+alpha",
      editor and (editor.program .. " " .. table.concat(editor.args, " ")))
check("and a name that is an option or a pattern is handed to neither", refused, (#spawned - before) .. " started")

local function offers(subject, id, from)
  for _, action in ipairs(cl.itemActions(subject, from or ctx)) do
    if action.command == id then return true end
  end
  return false
end
local remote = { kind = "remoteProject", name = "app", path = "/srv/app", host = "alpha" }
check("cmd+k on a host offers both, on a remote project Connect in terminal to its host, on a project neither",
      offers(host, "ssh.connect") and offers(host, "ssh.connectInEditor")
      and offers(remote, "ssh.connect") and not offers(remote, "ssh.connectInEditor")
      and not offers({ kind = "project", name = "x", path = "/x" }, "ssh.connect"))
check("without the terminal a host row connects in the editor, and cmd+k offers no Connect in terminal",
      inEditor[1] ~= nil and inEditor[1].command == "ssh.connectInEditor"
      and not offers(host, "ssh.connect", bare) and offers(host, "ssh.connectInEditor", bare),
      tostring(inEditor[1] and inEditor[1].command))
