-- CommandLayer.spoon/tests/extensions/help.lua
-- The help extension's rows: the ? picker's list of pickers and the ways to them.

local T = ...
local check = T.check
local cl = T.layer()

local rows = cl.rowsOfView("help", T.context())
local function rowOpening(name)
  for _, row in ipairs(rows) do
    if row.submenu == name then return row end
  end
end

local context, palette = rowOpening("context"), rowOpening("palette")
check("a picker with no title reads as its placeholder filled from the context, never the template",
      context ~= nil and context.label == "Actions -- Finder"
      and context.subject.kind == "view" and context.subject.name == "context",
      tostring(context and context.label))

check("a picker's row says every way to it, and ? does not list itself",
      palette ~= nil and palette.description:find("type '>'", 1, true) ~= nil
      and palette.description:find("cmd+o", 1, true) ~= nil and rowOpening("help") == nil,
      tostring(palette and palette.description))
