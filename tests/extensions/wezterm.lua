-- CommandLayer.spoon/tests/extensions/wezterm.lua
-- The wezterm extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer({ ["wezterm.enabled"] = true })
local M = cl.modules.wezterm

local panes = M.parse({ { pane_id = 3, title = "zsh", cwd = "file://host/Users/me/Git" },
                        { pane_id = 7, title = "lazygit" }, { title = "no id" } })
check("wezterm cli list's panes read as rows' data, the folder without its file:// host",
      #panes == 2 and panes[1].pane == 3 and panes[1].cwd == "/Users/me/Git" and panes[2].cwd == nil)

local activated = 0
stub(hs.application, "applicationsForBundleID", function(id)
  return id == M.bundleID and { { activate = function() activated = activated + 1 end } } or {}
end)
stub(cl.tools.paths, "wezterm", "/opt/homebrew/bin/wezterm")
local tasks = {}
stub(hs.task, "new", function(_, complete, _, args)
  tasks[#tasks + 1] = { complete = complete, args = args }
  return { start = function(t) return t end, terminate = function() end }
end)
stub(cl, "refresh", function() end)
cl.gather({}, { menus = { "root" } })
local function taskWith(words)
  for _, t in ipairs(tasks) do
    if table.concat(t.args or {}, " "):find(words, 1, true) then return t end
  end
end
local listing = taskWith("cli list")
if listing then listing.complete(0, '[{"pane_id":3,"title":"zsh","cwd":"file://h/Users/me"}]', "") end
local row
for _, r in ipairs(cl.gather({}, { menus = { "root" } })) do
  if r.command == "wezterm.focusPane" then row = r end
end
if row then cl.runRow(row) end
local focus = tasks[#tasks]
if focus then focus.complete(0, "", "") end
check("a pane is a root row, and picking it activates that pane and brings WezTerm forward",
      row and row.label == "zsh" and focus and table.concat(focus.args, " ") == "cli activate-pane --pane-id 3"
      and activated == 1, row and row.label)
