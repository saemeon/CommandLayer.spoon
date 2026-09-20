-- CommandLayer.spoon/tests/extensions/brew.lua
-- The brew extension's checks.

local T = ...
local check = T.check
local cl = T.layer()

local ran = {}
cl.registerCommand("terminal.run", { title = "spy", menus = {}, run = function(args, ctx)
  local words = {}
  for i, word in ipairs(args.cmd) do words[i] = cl.resolve(word, ctx) end
  ran[#ran + 1] = { cmd = words, target = args.target, title = args.title, keepOpen = args.keepOpen }
end })

local function shown(run)
  if not run then return "nothing" end
  return ("%s @ %s (%s)"):format(table.concat(run.cmd, "|"), tostring(run.target), tostring(run.title))
end

local verbs, lines = { "update", "upgrade", "outdated", "doctor", "cleanup" }, {}
for i, verb in ipairs(verbs) do
  cl.executeCommand("brew." .. verb, {}, {})
  lines[i] = shown(ran[i])
end
check("Update, Upgrade, Outdated, Doctor and Cleanup run brew in the terminal, which keeps its window",
      #ran == 5 and lines[1] == "brew|update @ nil (Brew: Update)"
      and lines[2] == "brew|upgrade @ nil (Brew: Upgrade)" and lines[3] == "brew|outdated @ nil (Brew: Outdated)"
      and lines[4] == "brew|doctor @ nil (Brew: Doctor)" and lines[5] == "brew|cleanup @ nil (Brew: Cleanup)"
      and ran[2].keepOpen == nil,
      table.concat(lines, " / "))

cl.executeCommand("brew.install", { query = "wget two" }, {})
cl.executeCommand("brew.search", { query = "ripgrep" }, {})
cl.executeCommand("brew.info", { query = "it's" }, {})
check("install, search and info give brew what was typed as one word",
      shown(ran[6]) == "brew|install|wget two @ nil (Brew: install)"
      and shown(ran[7]) == "brew|search|ripgrep @ nil (Brew: search)"
      and shown(ran[8]) == "brew|info|it's @ nil (Brew: info)",
      shown(ran[6]) .. " / " .. shown(ran[7]) .. " / " .. shown(ran[8]))

local reached = {}
for i, text in ipairs({ "brew install wget", "brew search rg", "brew info jq" }) do
  local view, prefix = cl.viewForPrefix(text)
  reached[i] = tostring(view) .. "=" .. tostring(prefix)
end
local rows = {}
for _, row in ipairs(cl.textRowsFor({}, "wget")) do
  if row.command == "brew.install" then rows[#rows + 1] = row end
end
check("each has a prefix of its own, and is a text command",
      reached[1] == "brew.install=brew install " and reached[2] == "brew.search=brew search "
      and reached[3] == "brew.info=brew info " and #rows == 1,
      table.concat(reached, " / ") .. " / " .. #rows)

local inRoot = {}
for _, row in ipairs(cl.gather(cl.contextFromKeys(), { menus = { "root" } })) do
  if row.command then inRoot[row.command] = true end
end
check("every Homebrew command is a root row as well as a palette row, so typing brew finds them",
      inRoot["brew.update"] and inRoot["brew.cleanup"] and inRoot["brew.install"] and inRoot["brew.info"])
