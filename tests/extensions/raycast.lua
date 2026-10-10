-- CommandLayer.spoon/tests/extensions/raycast.lua
-- The raycast extension's checks.

local T = ...
local check = T.check
local cl = T.layer({ ["raycast.enabled"] = true })
local M = cl.modules.raycast

local command = cl.getCommand("raycast.open")
check("raycast.open is a command that is never a row",
      command ~= nil and type(command.run) == "function" and next(command.menus) == nil)

local opened, installed = {}, M.installed
local savedOpen = hs.urlevent.openURL
hs.urlevent.openURL = function(url) opened[#opened + 1] = url end
M.installed = function() return true end
local saved = cl.userSettings
cl.userSettings = { ["raycast.commands"] = {
  { title = "Mine", url = "raycast://extensions/me/mine?x=1" },
} }
local rows
for _, ext in ipairs(cl.extensions) do
  if ext.name == "raycast" then rows = ext.items({}) end
end
cl.userSettings = saved
M.installed = installed
local row = rows and rows[1]
if row then cl.executeCommand(row.command, { target = row.args.target, fallbackText = "a b" }, {}) end
hs.urlevent.openURL = savedOpen

check("its rows are the raycast.commands setting, each opening its deeplink",
      rows ~= nil and #rows == 1 and row.label == "Mine" and row.command == "raycast.open"
      and opened[1] == "raycast://extensions/me/mine?x=1&fallbackText=a%20b",
      tostring(opened[1]))

do
  local R = cl.modules.raycast
  local header = R.scriptHeader("#!/bin/bash\n# @raycast.schemaVersion 1\n# @raycast.title Hello there\n"
    .. "// @raycast.packageName Demo\necho hi\n")
  check("a script command's header reads as Raycast reads it, in any comment style",
        header and header.title == "Hello there" and header.packageName == "Demo"
        and R.scriptHeader("#!/bin/sh\necho no title\n") == nil)

  local folder = os.tmpname() .. "-scripts"
  os.execute(("mkdir -p %q"):format(folder))
  local function write(name, text)
    local handle = assert(io.open(folder .. "/" .. name, "w"))
    handle:write(text)
    handle:close()
  end
  write("say-hello.sh", "#!/bin/bash\n# @raycast.title Say hello\n# @raycast.packageName Demo\necho hello\n")
  write("plain.sh", "#!/bin/bash\necho not a script command\n")
  local savedInstalled = R.installed
  R.installed = function() return true end
  local savedSettings = cl.userSettings
  cl.userSettings = { ["raycast.scriptDirectories"] = { folder } }
  local inScripts, inPalette = {}, {}
  for _, row in ipairs(cl.gather({ activeView = "scripts" }, { menus = { "scripts" } })) do
    if row.command == "raycast.open" then inScripts[#inScripts + 1] = row end
  end
  for _, row in ipairs(cl.gather({ activeView = "palette" }, { menus = { "commandPalette" } })) do
    if row.command == "raycast.open" and row.label == "Say hello" then inPalette[#inPalette + 1] = row end
  end
  cl.userSettings = savedSettings
  R.installed = savedInstalled
  os.execute(("rm -rf %q"):format(folder))
  check("each script command in raycast.scriptDirectories is a row in scripts, run through Raycast by its "
          .. "file's name; a file with no title is not, and none is in the palette",
        #inScripts == 1 and inScripts[1].label == "Say hello"
        and inScripts[1].args.target == "raycast://script-commands/say-hello" and #inPalette == 0,
        ("%d in scripts, %d in palette"):format(#inScripts, #inPalette))
end
