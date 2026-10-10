-- CommandLayer.spoon/tests/extensions/yabai.lua
-- The yabai extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer({ ["yabai.enabled"] = true })
local M = cl.modules.yabai

local spaces = M.parse({ { index = 2, label = "code", display = 1 }, { index = 1, label = "", ["has-focus"] = true },
                         { label = "no index" } })
check("yabai's spaces read in order, an empty label as none, the focused one marked",
      #spaces == 2 and spaces[1].index == 1 and spaces[1].focused and spaces[1].label == nil
      and spaces[2].label == "code")

stub(cl.tools.paths, "yabai", "/opt/homebrew/bin/yabai")
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
local listing = taskWith("-m query")
if listing then listing.complete(0, '[{"index":1,"label":"web","display":1}]', "") end
local row
for _, r in ipairs(cl.gather({}, { menus = { "root" } })) do
  if r.command == "yabai.focusSpace" then row = r end
end
if row then cl.runRow(row) end
check("a space is a root row, and picking it focuses that space through yabai",
      row and row.label == "Space 1 -- web" and table.concat(tasks[#tasks].args, " ") == "-m space --focus 1",
      row and row.label)
