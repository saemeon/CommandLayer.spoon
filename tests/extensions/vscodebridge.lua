-- CommandLayer.spoon/tests/extensions/vscodebridge.lua
-- The vscodebridge extension's checks.

local T = ...
local check, stub = T.check, T.stub
local off = T.layer()
local cl = T.layer({ ["vscodebridge.enabled"] = true })
local M = cl.modules.vscodebridge

-- VS Code's extensions folder, as fixtures in a folder of the check's own.
local folder = os.tmpname() .. "-vscode-extensions"
os.execute(("mkdir -p %q"):format(folder))
stub(M, "extensionsPath", folder)
local function writeList(text)
  local handle = assert(io.open(folder .. "/extensions.json", "w"))
  handle:write(text)
  handle:close()
end
local looked = 0
local realInstalled = M.installed
stub(M, "installed", function() looked = looked + 1; return realInstalled() end)

local function bridgeRows(kernel, menus)
  local ctx, found = kernel.buildContext(), {}
  for _, row in ipairs(kernel.gather(ctx, { menus = menus })) do
    if tostring(row.command):find("^vscodebridge%.") then found[#found + 1] = row.command end
  end
  for _, row in ipairs(kernel.textRowsFor(ctx, "needle")) do
    if tostring(row.command):find("^vscodebridge%.") then found[#found + 1] = "text " .. row.command end
  end
  table.sort(found)
  return table.concat(found, " ")
end
local absent = bridgeRows(off, { "root", "commandPalette" })
local shown = bridgeRows(cl, { "commandPalette" })
check("the bridge's rows are there whenever it is switched on, nothing looked for, the searches as text commands "
        .. "too, and none while off",
      absent == "" and looked == 0
      and shown == "text vscodebridge.findInFiles text vscodebridge.quickOpen "
        .. "vscodebridge.findInFiles vscodebridge.quickOpen vscodebridge.runCommand vscodebridge.runTask",
      absent .. " | " .. shown .. " | looked " .. looked)

-- Enough JSON for these arguments, keys sorted, as hs.json is not in the harness.
local function toJSON(value)
  if type(value) == "string" then return '"' .. value:gsub('[\\"]', "\\%0") .. '"' end
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  if value[1] ~= nil then
    for i, item in ipairs(value) do parts[i] = toJSON(item) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do parts[#parts + 1] = toJSON(key) .. ":" .. toJSON(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function percent(text)
  return (text:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end
stub(hs.json, "encode", toJSON)
stub(hs.json, "decode", function(text)
  local value = cl.decodeJSONC(text)
  if value == nil then error("not JSON") end
  return value
end)
local urls, opened = {}, {}
stub(hs.task, "new", function(program, done, _, args)
  if program == "/usr/bin/open" then
    urls[#urls + 1] = args and args[#args]
    opened[#opened + 1] = done
  end
  return { start = function(t) return t end, terminate = function() end }
end)
stub(cl.tools.paths, "open", "/usr/bin/open")
local alerts = {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
local vscodeInstalled = true
stub(hs.application, "pathForBundleID", function(id)
  return vscodeInstalled and id == M.vscodeBundleID and "/Applications/Visual Studio Code.app" or nil
end)

local zen = { vscodeCommand = "workbench.action.toggleZenMode" }
local problemsBefore = #cl.getProblems()
vscodeInstalled = false
cl.executeCommand("vscodebridge.runCommand", zen, {})
local noVSCode = #urls == 0 and alerts[1] == "VS Code is not installed"
vscodeInstalled = true
cl.executeCommand("vscodebridge.runCommand", zen, {})
local nothing = #urls == 0 and alerts[2] == M.NOT_INSTALLED
writeList("{ not json")
cl.executeCommand("vscodebridge.runCommand", zen, {})
local notJSON = #urls == 0 and alerts[3] == M.NOT_INSTALLED and #cl.getProblems() == problemsBefore
check("run with VS Code not installed, it says so and sends nothing; with the bridge in neither VS Code's list "
        .. "nor its folder, or a list that is not JSON, it says how to install it, and no problem",
      noVSCode and nothing and notJSON and #alerts == 3 and looked == 2,
      table.concat(alerts, " | ") .. " / looked " .. looked)

os.execute(("mkdir -p %q"):format(folder .. "/local.command-layer-1.0.0"))
cl.executeCommand("vscodebridge.runCommand", zen, {})
local byFolder = #urls == 1 and #alerts == 3
os.execute(("rm -rf %q"):format(folder .. "/local.command-layer-1.0.0"))
writeList('[{"identifier":{"id":"ms-python.python"},"version":"1.0.0"},'
  .. '{"identifier":{"id":"local.command-layer"},"version":"1.0.0",'
  .. '"location":{"$mid":1,"fsPath":"/repo/vscode/command-layer-extension","scheme":"file"}}]')
cl.executeCommand("vscodebridge.runCommand", zen, {})
local byList = #urls == 2 and #alerts == 3
local lines, restore = T.capturingPrint()
if opened[2] then opened[2](1, "", "LSOpenURLsWithRole() failed") end
restore()
check("a folder of its own, or an entry in extensions.json as Install from Location writes, is installed and the "
        .. "link is sent; open failing says so",
      byFolder and byList and alerts[4] == "Could not open the VS Code bridge's link" and #lines == 1,
      tostring(alerts[4]) .. " / " .. #urls .. " sent")

urls = {}
local typed = "a&b +c%${clipboard}"
cl.executeCommand("vscodebridge.findInFiles", { query = typed }, { clipboard = "SECRET" })
cl.executeCommand("vscodebridge.quickOpen", { query = "main.lua" }, {})
cl.executeCommand("vscodebridge.runTask", { label = "npm: build" }, {})
cl.executeCommand("vscodebridge.runCommand", zen, {})
os.execute(("rm -rf %q"):format(folder))
local base = "vscode://local.command-layer/run?"
local find = base .. "command=workbench.action.findInFiles&args="
             .. percent(percent('[{"query":"a&b +c%${clipboard}","triggerSearch":true}]'))
check("Find in files opens the extension's URI through system.open, its JSON arguments encoded twice, "
        .. "the text as typed",
      urls[1] == find and not tostring(urls[1]):find("SECRET", 1, true), tostring(urls[1]))
check("Go to file sends its text as quick open's argument, Run task a task, Run command an id with no arguments",
      urls[2] == base .. "command=workbench.action.quickOpen&args=" .. percent(percent('["main.lua"]'))
      and urls[3] == base .. "task=npm%3A%20build"
      and urls[4] == base .. "command=workbench.action.toggleZenMode",
      table.concat({ tostring(urls[2]), tostring(urls[3]), tostring(urls[4]) }, " | "))

-- The owner's rule: nothing may need the extension in VS Code but these rows.
local mentions = {}
for _, path in ipairs(T.sourceFiles({ "extensions", "views" })) do
  if path ~= "extensions/vscodebridge.lua" and T.readSource(path):find("local.command-layer", 1, true) then
    mentions[#mentions + 1] = path
  end
end
check("no other extension or view reaches for the Command Layer extension in VS Code",
      #mentions == 0, table.concat(mentions, ", "))
