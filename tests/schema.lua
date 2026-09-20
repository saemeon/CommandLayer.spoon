-- CommandLayer.spoon/tests/schema.lua
-- One schema for every spec: what is wrong in an extension, a command, an
-- input, a picker, a section or a setting is a problem naming it.

local T = ...
local check, group = T.check, T.group
-- Every shipped extension on, so the rows checked are every shipped one's.
local cl = T.layer(T.everyExtensionOn)

local function write(path, text)
  local handle = assert(io.open(path, "w"))
  handle:write(text)
  handle:close()
end

local function messages(l)
  local out = {}
  for _, p in ipairs(l.problems) do out[#out + 1] = p.file .. ": " .. p.message end
  return table.concat(out, " | ")
end

local function reports(l, wanted)
  local text = messages(l)
  for _, piece in ipairs(wanted) do
    if not text:find(piece, 1, true) then return false, "missing: " .. piece end
  end
  return true
end

group("specs")
do
  local dir = os.tmpname() .. "-schema"
  os.execute(("mkdir -p %q %q"):format(dir .. "/extensions", dir .. "/views"))
  write(dir .. "/extensions/badspec.lua", [[
return { extension = function()
  return {
    menue = { "root" },
    rank = "high",
    settings = {
      count = { type = "number", default = 1, minimum = 1, markdownDescription = "How **many**", order = 2 },
      limit = { type = "number", default = 500, maximum = 100, description = "At most", order = 1 },
      style = { type = "string", default = "plain", pattern = "^%a+$" },
      old = { type = "boolean", default = false, deprecationMessage = "Use count instead" },
    },
    commands = {
      { id = "badspec.untitled", run = function() end },
      { id = "badspec.wrong", title = 5, run = function() end },
      { id = "badspec.nothing", title = "Nothing" },
      { id = "badspec.go", title = "Go", command = "no.such.command" },
      { id = "badspec.ask", title = "Ask", run = function() end, when = "a &&",
        menus = { root = { when = "(", whne = "x" } }, after = "later",
        inputs = { { id = "q", type = "promptString", options = {}, from = { "root" } },
                   { picker = { typed = true } },
                   { id = "code", picker = { typed = true }, pattern = "[" },
                   { id = "twice", picker = { typed = true }, command = "badspec.ask" },
                   { id = "odd", picker = { when = "viewItem ==", placeholder = "Which", kind = "grid", typed = "yes" } },
                   { id = "typing", fromQuery = true, picker = { options = { "a" } } } } },
    },
  }
end }
]])
  -- Code that would build a picker, were it run.
  write(dir .. "/views/oldview.lua", [[
return function()
  return { name = "oldview", menus = { "root" }, build = function() return {} end }
end
]])
  write(dir .. "/views/unloadable.lua", "this is not lua\n")
  write(dir .. "/settings.json", [[
{ "badspec.style": "not plain!", "badspec.old": true, "badspec.count": 0, "badspec.limit": 50,
  "views": [ { "name": "badview", "refetch": true, "kind": "grid", "placeholdr": "Search", "parent": "nowhere",
               "compact": "yes", "menus": [ "root", 3 ], "empty": 5, "build": "rows", "onLeave": "stop",
               "sections": [ { "from": "nosuchext" }, { "limit": 2 }, { "view": "badview" } ] } ] }
]])

  local bad = T.loadKernel()
  bad.userDir = dir
  bad.setup()

  check("an extension's spec is checked: a field it cannot have, a value of the wrong type", reports(bad, {
          'extension badspec: "menue" is not a field of an extension',
          'extension badspec: "rank" should be a number, not string' }))
  check("a command needs an id, a title and something to run, and names only commands there are", reports(bad, {
          'extension badspec: command "badspec.untitled": "title" is required',
          'extension badspec: command "badspec.wrong": "title" should be a string, not number',
          'extension badspec: command "badspec.nothing": needs "run" or "command"',
          'extension badspec: command "badspec.go": "command" names no command "no.such.command"' }))
  check("what a command does after it runs is close, keepOpen or back, and an input's pattern is a pattern",
        reports(bad, {
          'command "badspec.ask": "after" should be one of close, keepOpen, back',
          'command "badspec.ask": input "code": "[" is not a pattern' }))
  check("a when clause on a command or one of its menus that does not parse is a problem", reports(bad, {
          'command "badspec.ask": "when" "a &&" does not parse',
          'command "badspec.ask": menu "root": "when" "(" does not parse',
          'command "badspec.ask": menu "root": "whne" is not a field of a menu entry' }))
  check("an input needs an id, and a picker or a command; its old fields say where they went", reports(bad, {
          'command "badspec.ask": input "q": "type" is not a field of an input: use "picker", or "command"',
          'command "badspec.ask": input "q": "options" is not a field of an input: goes in "picker"',
          'command "badspec.ask": input "q": "from" is not a field of an input: goes in "picker" as "menus"',
          'command "badspec.ask": input "q": needs "picker" or "command"',
          'command "badspec.ask": input "twice": has both "picker" and "command"',
          'command "badspec.ask": input 2: "id" is required' }))
  check("an input's picker holds a question's fields only, each checked, and fromQuery needs it typed", reports(bad, {
          'command "badspec.ask": input "odd": "picker": "placeholder" is not a field of a question',
          'command "badspec.ask": input "odd": "picker": "when" "viewItem ==" does not parse',
          'command "badspec.ask": input "odd": "picker": "kind" should be one of search',
          'command "badspec.ask": input "odd": "picker": "typed" should be a boolean, not string',
          'command "badspec.ask": input "typing": "fromQuery" needs a picker with "typed": true' }))
  check("a picker in settings is checked, its parent and sections naming what there is", reports(bad, {
          '"views": badview: "placeholdr" is not a field of a picker',
          '"views": badview: "refetch" is not a field of a picker: use "kind": "search"',
          '"views": badview: "kind" should be one of list, search',
          '"views": badview: "compact" should be a boolean, not string',
          '"views": badview: "empty" should be a string, not number',
          '"views": badview: "menus" item 2 should be a string, not number',
          '"views": badview: "parent" names no picker "nowhere"',
          '"views": badview: section 2: needs "from" or "view"',
          '"views": a section of badview names no extension "nosuchext"',
          '"views": the sections of badview lead back to it' }))
  check("a picker's code fields are gone, each saying what took its place", reports(bad, {
          '"views": badview: "build" is not a field of a picker: a picker is data: an extension feeds its menus',
          '"views": badview: "onLeave" is not a field of a picker: an extension feeding its menus hears left(ctx)' }))
  check("a Lua file in the user folder's views/ is a problem, once each, and never run", (function()
          local ok, why = reports(bad, {
            "views/oldview.lua is not read: a picker is declared in settings.json's views, and an extension feeds its menus",
            "views/unloadable.lua is not read: " })
          if not ok then return false, why end
          local count = 0
          for _, p in ipairs(bad.problems) do
            if p.message:find("views/oldview.lua", 1, true) then count = count + 1 end
          end
          return count == 1 and bad.viewNamed("oldview") == nil, ("%d problems, picker %s"):format(count,
                 tostring(bad.viewNamed("oldview") ~= nil))
        end)())
  check("a setting's declaration is checked, its default against itself", reports(bad, {
          'extension badspec: setting "limit": its default should be at most 100' }))
  check("minimum, maximum and pattern hold a setting's value, and a deprecated one says so", reports(bad, {
          '"badspec.count" should be at least 1',
          '"badspec.style" should match "^%a+$"',
          '"badspec.old" is deprecated: Use count instead' }))
  check("Default Settings orders by order, prefers markdownDescription, and marks what is deprecated", (function()
          local text = bad.modules.workbench.defaultSettingsText()
          local count = text:find('"badspec.count"', 1, true)
          local limit = text:find('"badspec.limit"', 1, true)
          local old = text:find('"badspec.old"', 1, true)
          -- limit, count, old: by order first, which is not the alphabet's.
          return count ~= nil and limit ~= nil and old ~= nil and limit < count and count < old
                 and text:find("// How **many**", 1, true) ~= nil
                 and text:find("// Deprecated: Use count instead", 1, true) ~= nil
        end)())

  os.execute(("rm -rf %q"):format(dir))
end

group("rows")
check("every row the shipped extensions give has a row's fields, and nothing else", (function()
        local found = {}
        local ctx = T.context()
        for _, menu in ipairs({ "root", "commandPalette", "recent", "context" }) do
          for _, row in ipairs(cl.gather(cl.argContext(ctx, { activeView = menu }), { menus = { menu } })) do
            for _, message in ipairs(cl.checkRow(row)) do
              found[#found + 1] = tostring(row.label) .. ": " .. message
            end
          end
        end
        return #found == 0, table.concat(found, " | ", 1, math.min(#found, 6))
      end)())
check("and a row that is not one is found", (function()
        local text = table.concat(cl.checkRow({ text = "an old name", run = "nope" }), " | ")
        return text:find('"text" is not a field of a row', 1, true) ~= nil
               and text:find('needs "label"', 1, true) ~= nil
               and text:find('"run" should be a function, not string', 1, true) ~= nil, text
      end)())
