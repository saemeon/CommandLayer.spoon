-- CommandLayer.spoon/tests/extensions/quicklinks.lua
-- The quicklinks extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.quicklinks

-- The extension's own API, since the commands are built from the setting
-- when the spec is.
local api = cl.pluginAPI("extension", "quicklinks")
local saved = cl.userSettings
cl.userSettings = { ["quicklinks.links"] = {
  { title = "Search Mine", url = "https://example.com/?q=${query}", prefix = "mine " },
  { title = "Home", url = "https://example.com/" },
} }
local mine = M.extension(api)
-- Gathered after the setting is gone: the rows keep the links read with the commands.
cl.userSettings = {}
local rows = mine.items({})
local shipped = M.extension(api)
cl.userSettings = saved

local searches = {}
for _, c in ipairs(mine.commands) do
  if c.id ~= "quicklinks.copyURL" then searches[#searches + 1] = c end
end
check("quicklinks come from the quicklinks.links setting, read once for commands and rows alike, "
      .. "and the shipped searches without it",
      #searches == 1 and searches[1].id == "quicklinks.searchMine"
      and searches[1].prefix == "mine " and #rows == 1 and rows[1].label == "Home"
      and #shipped.commands == #M.defaults + 1,
      ("%d / %d"):format(#searches, #shipped.commands))
check("a search opens its URL with what was typed, and a bookmark opens its own",
      searches[1] and searches[1].command == "system.open"
      and searches[1].args.target == "https://example.com/?q=${query}"
      and searches[1].inputs[1].fromQuery == true
      and rows[1] and rows[1].command == "system.open"
      and rows[1].args.target == "https://example.com/")

local copied
local savedClipboard = hs.pasteboard.setContents
hs.pasteboard.setContents = function(text) copied = text end
local offered
for _, verb in ipairs(cl.itemActions(rows[1] and rows[1].subject or {}, {})) do
  if verb.command == "quicklinks.copyURL" then offered = verb end
end
if offered then cl.executeCommand(offered.command, offered.args, {}) end
hs.pasteboard.setContents = savedClipboard
check("cmd+k on a quicklink copies its URL",
      offered ~= nil and offered.label == "Copy URL" and copied == "https://example.com/",
      tostring(copied))
