-- CommandLayer.spoon/tests/extensions/rerun.lua
-- The rerun extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.rerun

local heard = {}
cl.registerCommand("test.checkout", { title = "Checkout", menus = {},
  run = function(args) heard[#heard + 1] = tostring(args.branch) end })

local ext
for _, e in ipairs(cl.extensions) do
  if e.name == "rerun" then ext = e end
end

M.recent = {}
ext.picked({ command = "test.checkout", args = { branch = "main" }, label = "Git: Checkout…" })
ext.picked({ command = "quickOpen.showActions", label = "actions" })
ext.picked({ command = "test.checkout", args = { branch = "feature" }, label = "Git: Checkout…" })
ext.picked({ command = "test.checkout", args = { branch = "main" }, label = "Git: Checkout…" })
local order = {}
for _, entry in ipairs(M.recent) do order[#order + 1] = entry.args.branch end
check("a picked command is kept with its arguments, latest first, once; a picker control is not",
      table.concat(order, " ") == "main feature", table.concat(order, " "))

cl.executeCommand("rerun.last", {}, {})
local options = cl.getCommand("rerun.recent").inputs[1].picker.options({})
cl.executeCommand("rerun.recent", { entry = options[2].value }, {})
check("Rerun last command runs the latest again with its arguments, and a recent one is chosen by its row",
      table.concat(heard, " ") == "main feature" and options[1].label == "Git: Checkout…"
      and options[1].description == "main",
      table.concat(heard, " ") .. " / " .. tostring(options[1].description))

M.recent = {}
local said
local savedAlert = hs.alert.show
hs.alert.show = function(text) said = text end
cl.executeCommand("rerun.last", {}, {})
hs.alert.show = savedAlert
local empty = cl.getCommand("rerun.recent").inputs[1].picker.options({})
check("with nothing run yet, it says so, and the list is one row that cannot be picked",
      said == "Nothing has been run yet" and #empty == 1 and empty[1].enabled == false, tostring(said))
