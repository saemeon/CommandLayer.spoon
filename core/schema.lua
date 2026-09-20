-- One schema for every spec: the fields each kind may hold, their types,
-- the values allowed and what they must name. Checked at setup, so a mistake
-- in an extension, a picker, a settings file or a keybinding is a problem
-- shown to the person, as VS Code checks a manifest. Rows are checked only by
-- the harness: they are made as a picker opens, too late for a problem to be
-- shown.

local M = ...

local problem = M.problem

----------------------------------------------------------------------
-- VALUES
----------------------------------------------------------------------

local function article(word)
  return word:match("^[aeiou]") and "an" or "a"
end

-- Against a JSON type, as a settings file is written.
local function wrongType(value, expected)
  local actual = M.jsonType(value)
  if actual == expected then return nil end
  -- {} is how an empty list decodes, too.
  if type(value) == "table" and next(value) == nil
     and (expected == "array" or expected == "object") then return nil end
  if expected == "integer" and math.type(value) == "integer" then return nil end
  return ("should be %s %s, not %s"):format(article(expected), expected, actual)
end

-- Against Lua types, as a spec is written: one name, or a list of them.
local function wrongLuaType(value, expected)
  local names = type(expected) == "table" and expected or { expected }
  for _, name in ipairs(names) do
    if name == "any" or type(value) == name then return nil end
  end
  local words = {}
  for i, name in ipairs(names) do words[i] = article(name) .. " " .. name end
  return ("should be %s, not %s"):format(table.concat(words, " or "), type(value))
end

local function oneOf(value, options)
  local names = {}
  for _, option in ipairs(options) do
    if option == value then return nil end
    names[#names + 1] = tostring(option)
  end
  return "should be one of " .. table.concat(names, ", ")
end

-- VS Code's contributes.configuration: `enum`, else `type` or the type of the
-- default, then `minimum`, `maximum` and `pattern` -- a Lua pattern, as `=~`
-- takes.
local function againstDeclaration(value, decl)
  if type(decl.enum) == "table" then return oneOf(value, decl.enum) end
  local expected = decl.type
  if expected == nil and decl.default ~= nil then expected = M.jsonType(decl.default) end
  local why = type(expected) == "string" and wrongType(value, expected) or nil
  if why then return why end
  if type(value) == "number" then
    if type(decl.minimum) == "number" and value < decl.minimum then
      return ("should be at least %s"):format(decl.minimum)
    end
    if type(decl.maximum) == "number" and value > decl.maximum then
      return ("should be at most %s"):format(decl.maximum)
    end
  end
  if type(value) == "string" and type(decl.pattern) == "string" then
    local ok, found = pcall(string.find, value, decl.pattern)
    if ok and not found then return ("should match %q"):format(decl.pattern) end
  end
  return nil
end

local function whenProblem(text)
  if type(text) ~= "string" then return "should be a string, not " .. type(text) end
  if text == "" then return nil end
  local why = M.whenError(text)
  return why and ("%q does not parse: %s"):format(text, why) or nil
end

----------------------------------------------------------------------
-- THE SCHEMAS
--
-- A kind is { what, description, fields, check }. A field is { type,
-- description, required, enum, items, list = kind, map = kind, label, check },
-- and may say what it names: command, view or presenter. `items` is the Lua
-- type of each element of a list. `inFiles = false` is a field the layer
-- sets, or never reads, so a settings file does not offer it. `when` is a
-- string that parses as a when clause.
--
-- The descriptions are the reference: docs/api.md and the JSON Schemas in
-- config/ are generated from them by tests/reference.lua.
----------------------------------------------------------------------

local S, N, B, F, T, ANY, WHEN = "string", "number", "boolean", "function", "table", "any", "when"

-- A list of menu names, or a table from a name to true or { when }.
local function checkMenus(menus, report)
  for key, entry in pairs(menus) do
    if type(key) ~= "string" then
      if type(entry) ~= "string" then
        report(("menu %s should be a name, not %s"):format(tostring(key), type(entry)))
      end
    elseif type(entry) == "table" then
      for name in pairs(entry) do
        if name ~= "when" then
          report(("menu %q: %q is not a field of a menu entry"):format(key, tostring(name)))
        end
      end
      local why = entry.when ~= nil and whenProblem(entry.when)
      if why then report(("menu %q: \"when\" %s"):format(key, why)) end
    elseif entry ~= true then
      report(("menu %q should be true or { when }"):format(key))
    end
  end
end

local function named(kind, key)
  return function(item, i)
    if type(item) == "table" and item[key] ~= nil then return ("%s %q"):format(kind, tostring(item[key])) end
    return ("%s %d"):format(kind, i)
  end
end

local SCHEMAS = {}

SCHEMAS.setting = {
  what = "a setting",
  description = "A setting an extension, presenter or ranker declares, as VS Code's "
                .. "contributes.configuration does. It is read with cl.setting and written in "
                .. "settings.json as \"<name>.<key>\".",
  fields = {
    type = { type = S, enum = { "boolean", "number", "integer", "string", "array", "object", "null" },
             description = "The JSON type of the value." },
    default = { type = ANY, description = "The value while no settings file sets one." },
    description = { type = S, description = "What the setting does, in plain text." },
    markdownDescription = { type = S,
                            description = "What the setting does, in Markdown; shown instead of description." },
    enum = { type = T, description = "The values allowed." },
    enumDescriptions = { type = T, items = S, description = "What each value in enum means, in the same order." },
    minimum = { type = N, description = "The smallest number allowed." },
    maximum = { type = N, description = "The largest number allowed." },
    pattern = { type = S, description = "A Lua pattern a string value must match." },
    deprecationMessage = { type = S,
                           description = "Marks the setting as on its way out, and says what to use instead." },
    order = { type = N, description = "Where the setting stands among its owner's: lower first, then by key." },
  },
  check = function(decl, report)
    if type(decl.pattern) == "string" and not pcall(string.find, "", decl.pattern) then
      report(("%q is not a pattern"):format(decl.pattern))
    elseif decl.default ~= nil then
      local why = againstDeclaration(decl.default, decl)
      if why then report("its default " .. why) end
    end
  end,
}

-- A question's picker holds these and nothing else: what a picker declared
-- in settings may hold -- a prefix, sections -- means nothing to a question.
local QUESTION_FIELDS = {
  options = function(v) return wrongLuaType(v, { T, F }) end,
  menus = function(v)
    if type(v) ~= "table" then return wrongLuaType(v, T) end
    for i, item in ipairs(v) do
      if type(item) ~= S then return ("item %d should be a string, not %s"):format(i, type(item)) end
    end
    return nil
  end,
  when = whenProblem,
  kind = function(v) return oneOf(v, { "search" }) end,
  search = function(v) return wrongLuaType(v, F) end,
  typed = function(v) return wrongLuaType(v, B) end,
}

local function checkQuestion(picker, report)
  for key, v in pairs(picker) do
    local why = QUESTION_FIELDS[key] and QUESTION_FIELDS[key](v)
    if not QUESTION_FIELDS[key] then
      report(('"picker": %q is not a field of a question'):format(tostring(key)))
    elseif why then
      report(('"picker": %q %s'):format(key, why))
    end
  end
end

SCHEMAS.input = {
  what = "an input",
  -- Fields that were an input's, and what to write instead.
  replaced = {
    type = 'use "picker", or "command"',
    options = 'goes in "picker"',
    when = 'goes in "picker"',
    search = 'goes in "picker"',
    from = 'goes in "picker" as "menus"',
  },
  description = "What a command asks for before it runs, as VS Code's tasks.json declares inputs: "
                .. "a picker that asks it, or a command whose result answers it. The answer is "
                .. "args[id], and ${input:id} in a template.",
  fields = {
    id = { type = S, required = true, description = "The name the answer is given under." },
    picker = { type = T, check = checkQuestion,
               description = "The picker that asks it, whose row picked -- its value, else its subject -- "
                             .. "is the answer: options, strings or { label, description, iconPath, value }, "
                             .. "or a function (ctx, args) giving them; when, a clause over a row -- viewItem "
                             .. "is its subject kind -- taking the rows it holds for from menus (every menu "
                             .. "when absent), which also makes the command a verb on those rows' cmd+k; "
                             .. "kind \"search\" with search(query, ctx, args, done), asking again as you "
                             .. "type; typed = true, answered by what was typed." },
    description = { type = S, description = "The prompt shown while asking." },
    default = { type = ANY, description = "Offered first: what a typed picker answers with nothing "
                                          .. "typed, the first of a picker's options." },
    current = { type = F, description = "function(ctx): what is in front, answering the input "
                                        .. "without asking when the command is run by id." },
    preferCurrent = { type = B, description = "Answer with current when the command's row is picked "
                                              .. "too, asking only when nothing is in front." },
    fromQuery = { type = B, description = "Answered by what was typed, so the command runs straight "
                                          .. "from the search field; its picker is typed." },
    encode = { type = S, description = "How typed text is encoded before it fills a template: query "
                                       .. "for a URL's query string." },
    command = { type = S, command = true,
                description = "The command whose result answers the input, as VS Code's command input; "
                              .. "instead of picker." },
    args = { type = T, description = "The args that command is run with." },
    pattern = { type = S, description = "A Lua pattern a typed answer must match; one that does not keeps "
                                        .. "the prompt open, saying so." },
    validate = { type = F, description = "function(value, ctx, args): why the answer will not do, as text, "
                                         .. "keeping the prompt open; nil when it will." },
  },
  check = function(input, report)
    if input.picker == nil and input.command == nil then
      report('needs "picker" or "command"')
    elseif input.picker ~= nil and input.command ~= nil then
      report('has both "picker" and "command"')
    end
    if input.fromQuery and not (type(input.picker) == "table" and input.picker.typed == true) then
      report('"fromQuery" needs a picker with "typed": true')
    end
    if type(input.pattern) == "string" and not pcall(string.find, "", input.pattern) then
      report(("%q is not a pattern"):format(input.pattern))
    end
  end,
}

SCHEMAS.command = {
  what = "a command",
  description = "A verb with a stable id, contributed by an extension and always run by id.",
  fields = {
    id = { type = S, required = true, description = "Dotted, and starting with the extension's name: git.clone." },
    title = { type = S, required = true, description = "What its row reads; ${query} shows what was typed." },
    category = { type = S, description = "Groups the command: its row reads Category: Title, and the "
                                         .. "category is matched too." },
    icon = { type = S, description = "A ThemeIcon, $(name)." },
    run = { type = F, description = "function(args, ctx): what the command does." },
    command = { type = S, command = true, description = "Another command to run instead." },
    args = { type = T, description = "The args given to command; their templates are filled from the context." },
    inputs = { type = T, list = "input", label = named("input", "id"),
               description = "What the command asks for before it runs." },
    menus = { type = T, check = checkMenus,
              description = "Where the command is a row: a list of menu names, or a table from a name "
                            .. "to true or { when }. { \"commandPalette\" } when absent; {} is no row." },
    when = { type = WHEN, description = "Hides the command while it does not hold." },
    enablement = { type = WHEN,
                   description = "Shows the command as Unavailable, and refuses it, while it does not hold." },
    prefix = { type = { S, T }, items = S,
               description = "Typing this opens a picker holding the command alone; a list gives several." },
    rank = { type = N, description = "How particular the command is to now, 0..1, for the specificity ranker." },
    after = { type = S, enum = { "close", "keepOpen", "back" },
              description = "What the picker does once the command has run: close the layer (when absent), "
                            .. "keepOpen and redraw where it was picked, or go back a level from there." },
    targetName = { type = { S, F },
                   description = "Names what the command acts on in its row, Title -- target: a template filled "
                                 .. "from the context and the answers -- ${input:window.app} -- counting what "
                                 .. "a preferCurrent input takes; or a function (args, ctx). Nothing when empty." },
    confirm = { type = { S, F },
                description = "Asked, yes or no, once every input is answered and before it runs: a template "
                              .. "filled like targetName, or a function (args, ctx) returning the question, "
                              .. "or nil to run without asking." },
  },
  check = function(command, report)
    if command.run == nil and command.command == nil then report('needs "run" or "command"') end
  end,
}

SCHEMAS.extension = {
  what = "an extension",
  description = "One file in extensions/, returning a module whose extension(cl) gives this spec. "
                .. "Every field but name is optional.",
  fields = {
    name = { type = S, required = true, description = "The extension's name, which is its file's." },
    displayName = { type = S, description = "What a person reads; the name capitalised when absent." },
    description = { type = S, description = "What the extension is for; heads its part of Default Settings." },
    menus = { type = T, items = S, description = "The menus its items feed." },
    rank = { type = N, description = "How particular its rows are to now, 0..1, for the specificity ranker." },
    before = { type = { S, T }, items = S, description = "Extensions it runs before, in capture, gather and search." },
    after = { type = { S, T }, items = S, description = "Extensions it runs after." },
    extensionDependencies = { type = T, items = S,
                              description = "Extensions it cannot work without: it is dropped while "
                                            .. "one is not loaded." },
    optionalExtensionDependencies = { type = T, items = S,
                                      description = "Extensions it uses when they are loaded, and starts after." },
    commands = { type = T, list = "command", label = named("command", "id"),
                 description = "The commands it contributes." },
    settings = { type = T, map = "setting", description = "The settings it declares, by key." },
    exports = { type = T, description = "What cl.extension(name) gives an extension declaring this one a dependency." },
    items = { type = F, description = "function(ctx, opts): its rows, the nouns." },
    subjects = { type = F, description = "function(ctx): what is in front of you, as subjects." },
    query = { type = F, description = "function(query, ctx): rows made from what was typed." },
    search = { type = F, description = "function(query, ctx, done): rows found by asking again as you "
                                       .. "type, in a picker whose kind is search; returns a function that stops it." },
    capture = { type = F, description = "function(ctx): fields it adds to the context." },
    scope = { type = F, description = "function(subject, scoped, ctx): how a subject narrows the context's fields." },
    picked = { type = F, description = "function(item, ctx): told of every pick once it is recorded." },
    left = { type = F, description = "function(ctx): told when a level its rows feed comes off the stack -- back, "
                                     .. "closed, or replaced -- never when a level opens over it, so it can stop "
                                     .. "what it started for that picker; activeView in ctx is the picker left." },
  },
}

SCHEMAS.section = {
  what = "a section",
  description = "A few rows from one extension or picker, shown before anything is typed, the first "
                .. "labelled. It needs from or view.",
  fields = {
    from = { type = S, description = "The extension whose rows it takes, in the order the extension gave them." },
    view = { type = S, description = "The picker whose opening rows it takes, instead." },
    limit = { type = N, description = "How many rows it takes." },
    title = { type = S, description = "The label on its first row; the extension's display name when absent." },
    exclude = { type = T, items = S, description = "Extensions whose rows are left out before the limit is taken." },
  },
  check = function(section, report)
    if section.from == nil and section.view == nil then report('needs "from" or "view"') end
  end,
}

SCHEMAS.view = {
  what = "a picker",
  -- Fields that were a picker's, and what to write instead.
  replaced = {
    refetch = 'use "kind": "search"',
    fallbacks = 'use "textCommands": "fallback"',
    build = "a picker is data: an extension feeds its menus",
    onQuery = "a picker is data: an extension feeds its menus",
    onLeave = "an extension feeding its menus hears left(ctx)",
  },
  description = "A picker: how it is reached, where its rows come from, and a few flags. Declared in "
                .. "settings.json's views; an extension feeds its menus.",
  fields = {
    name = { type = S, required = true,
             description = "The picker's name, which keybindings, prefixes and sections refer to." },
    title = { type = S, description = "Names the picker in its parent, in the breadcrumb and in ?." },
    icon = { type = S, description = "A ThemeIcon, $(name), for its row." },
    description = { type = S, description = "What the picker is for." },
    key = { type = S, inFiles = false,
            description = "Not read: a picker's chord is a quickOpen entry in keybindings.json." },
    placeholder = { type = S, description = "The search field's placeholder, filled from the context." },
    empty = { type = S, description = "What it says when it has nothing to show, filled like placeholder." },
    prefix = { type = { S, T }, items = S,
               description = "Typed text starting with this opens the picker; a list gives several." },
    parent = { type = S, view = true, description = "The picker it is a row in, reading Title ▸." },
    menus = { type = T, items = S, description = "The menus its rows come from." },
    sections = { type = T, list = "section", label = function(_, i) return ("section %d"):format(i) end,
                 description = "What it opens on before anything is typed: a few rows from each, then the rest." },
    command = { type = S, check = function(id, report)
                  local command = M.getCommand(id)
                  if not (command and M.textInputOf(command)) then
                    report(('"command" names no command taking text %q'):format(id))
                  end
                end,
                description = "A command taking text -- an input with fromQuery -- the picker holds alone: its "
                              .. "row, with what is typed filled in." },
    presenter = { type = S, presenter = true,
                  description = "The presenter that draws it; the profile's presenter when absent." },
    answers = { type = B, description = "Whether typing offers answers and switches on a prefix; "
                                        .. "true when absent, false in the cmd+k panel." },
    compact = { type = B, description = "Drawn at appearance's actionWidth and actionRows." },
    textCommands = { type = S, enum = { "fallback", "first" },
                     description = "Offers every command that takes text, with what was typed filled in: "
                                   .. "fallback when nothing matched; first while text is typed, ranked by "
                                   .. "use, before the picker's own rows that match. None when absent." },
    pickerRows = { type = B, description = "Makes every picker with a prefix a row too, which types the prefix." },
    kind = { type = S, enum = { "list", "search", "item" },
             description = "list narrows the rows it gathered as you type; search asks the extensions' "
                           .. "search hooks again instead; item offers the verbs on the subject it is "
                           .. "given, as cmd+k does. list when absent." },
    recentlyUsed = { type = N, description = "Puts this many rows picked most lately first, also while typing." },
    minQuery = { type = N, description = "In a search picker, the fewest characters that search; 2 when absent." },
    debounce = { type = N,
                 description = "In a search picker, the seconds typing pauses before a search; 0.15 when absent." },
    extension = { type = S, inFiles = false,
                  description = "Set by the layer: the extension whose command a prefix picker holds." },
  },
}

SCHEMAS.row = {
  what = "a row",
  description = "What a picker shows, in VS Code's quick pick names. Rows are made as a picker "
                .. "opens, so only the harness checks them.",
  fields = {
    label = { type = S,
              description = "The first line; a leading $(name) is its icon. Every row but a separator has one." },
    description = { type = S, description = "The start of the second line." },
    detail = { type = S, description = "The rest of the second line." },
    iconPath = { type = ANY, description = "An image, or $(name)." },
    icon = { type = ANY, description = "A ThemeIcon, $(name)." },
    command = { type = S, description = "The command picking it runs." },
    args = { type = T, description = "The args that command is run with." },
    run = { type = F, description = "function(ctx): what picking it does, instead of a command." },
    subject = { type = T,
                description = "What the row is, { kind, ... }: what cmd+k offers verbs for, and frecency remembers." },
    when = { type = WHEN, description = "Hides the row while it does not hold." },
    rank = { type = N, description = "How particular the row is to now, 0..1." },
    keywords = { type = T, items = S,
                 description = "A list of words the row is also found by, beside its label -- a URL, a bundle "
                               .. "id -- matched up to 160 characters, and graded below a match in the label." },
    alwaysShow = { type = B,
                   description = "Kept whatever is typed, as VS Code's QuickPickItem.alwaysShow: no matcher "
                                 .. "drops it, and with text typed it follows the ranked rows, in the order given." },
    submenu = { type = S, description = "The picker picking it opens over the current one." },
    submenuQuery = { type = S, description = "The text that picker opens with, as if typed." },
    keepOpen = { type = B,
                 description = "Picking it runs its action and redraws the picker, rather than closing the layer." },
    enabled = { type = B, description = "false shows the row as Unavailable, and refuses it." },
    value = { type = ANY, description = "In a command's question, what picking it answers; the row's subject "
                                        .. "when absent." },
    source = { type = S, description = "Set by the layer: the extension the row came from, which sections select on." },
    kind = { type = S, enum = { "separator" }, description = "separator makes the row a label for the row after it." },
    ctx = { type = T, description = "The context the row was made in." },
  },
  check = function(row, report)
    if row.kind ~= "separator" and type(row.label) ~= "string" then report('needs "label"') end
  end,
}

M.schemas = SCHEMAS

-- The layer's own lists an extension reads, each entry a copy holding these
-- fields and no other: getViews, getKeybindings, getSettingOwners. What rows
-- are built from has to stay put while the layer changes around it.
M.listShapes = {
  view = {
    description = "What cl.getViews() gives for each declared picker.",
    fields = {
      name = { type = S, description = "The picker's name." },
      kind = { type = S, description = "list, search or item." },
      title = { type = S, description = "Its title, when it declares one." },
      icon = { type = S, description = "Its ThemeIcon, $(name), when it declares one." },
      description = { type = S, description = "What it is for, when it says." },
      placeholder = { type = S, description = "Its placeholder as written, a template not yet filled." },
      empty = { type = S, description = "What it says with nothing to show, as written." },
      prefixes = { type = T, description = "A list of the prefixes that open it, its own before a profile's aliases." },
      parent = { type = S, description = "The picker it is a row in." },
      menus = { type = T, description = "A list of the menus its rows come from." },
      presenter = { type = S, description = "The presenter it names." },
      extension = { type = S, description = "The extension whose command a prefix picker holds." },
    },
  },
  keybinding = {
    description = "What cl.getKeybindings() gives for each keybinding in effect, after removals.",
    fields = {
      key = { type = S, description = "The chord, as written." },
      command = { type = S, description = "The command it runs." },
      args = { type = T, description = "A copy of the args it runs the command with." },
      when = { type = S, description = "The clause it applies under." },
      global = { type = B, description = "Whether it works in every app." },
      ["repeat"] = { type = B, description = "Whether holding the key runs it again, as written." },
      source = { type = S, description = "Where it came from: default, user, defaultProfile, profile or "
                                         .. "bindHotkeys; absent for one no file gave." },
      opens = { type = S, description = "The picker a quickOpen entry opens." },
    },
  },
  settingOwner = {
    description = "What cl.getSettingOwners() gives for each extension, presenter and ranker declaring settings.",
    fields = {
      name = { type = S, description = "Its name, which its settings are written under: <name>.<key>." },
      kind = { type = S, description = "extension, presenter or ranker." },
      displayName = { type = S, description = "What a person reads." },
      description = { type = S, description = "What it is for." },
      registered = { type = B, description = "For an extension, whether it is running now; one switched off is "
                                             .. "still listed." },
      menus = { type = T, description = "For an extension, a sorted list of the menus its rows and commands "
                                        .. "declare, which its <name>.menus setting is written over; absent for "
                                        .. "none." },
      settings = { type = T,
                   description = "A copy of each setting it declares, by key, as the spec setting describes." },
    },
  },
}

-- The kernel's own settings: the keys config/defaults.jsonc has, which is
-- where their defaults are. `fields` are what a views entry may hold beyond
-- a picker's own.
M.kernelSettings = {
  views = { type = "array",
            description = "Pickers, merged by name: an entry changes the fields it names, and a new name adds one.",
            fields = { enabled = { type = B, description = "false removes the picker." } } },
  matchers = { type = "array",
               description = "The matchers used, in the order tried: the first that takes a query decides "
                             .. "which rows stay, and one not named does not run." },
  rankers = { type = "object",
              description = "Each ranker's weight. Every ranker scores a row 0..1, so its weight is the "
                            .. "whole of how much it counts; one at 0 records nothing." },
  appearance = { type = "object",
                 description = "What every picker shares. A presenter's own options are its settings.",
                 properties = {
                   dark = { type = "boolean", description = "Dark pickers." },
                   width = { type = "number", description = "A picker's width, in percent of the screen's." },
                   rows = { type = "number", description = "How many rows a picker shows at once." },
                   maxRows = { type = "number",
                               description = "The most rows a picker is handed; everything is still "
                                             .. "matched and ranked, only drawing is capped." },
                   actionWidth = { type = "number",
                                   description = "The cmd+k panel's width, in percent of the screen's." },
                   actionRows = { type = "number", description = "How many rows the cmd+k panel shows at once." },
                 } },
  useDefaultProfile = { type = "object",
    description = "In a profile other than default: what it takes from the default profile, as VS Code's "
                  .. "\"Use Default Profile\" does.",
    properties = {
      keybindings = { type = "boolean",
                      description = "The default profile's keybindings.json, before this profile's own." },
    } },
  prefixes = { type = "object",
               description = "Prefixes of your own, added to a picker's by its name: { \"recent\": \"r \" }." },
  aliases = { type = "object",
              description = "Aliases of your own, a string or a list, by command id: { \"windows.leftHalf\": \"lh\" }. "
                            .. "Typed as the whole query, ignoring case, an alias puts its command's row first, "
                            .. "whatever the rankers score." },
  tools = { type = "object", description = "Where tools are, and which provider does a job.",
            properties = {
              paths = { type = "object", description = "Where a tool is: { \"code\": \"/opt/local/bin/code\" }." },
              use = { type = "object", description = "Which provider does a job: { \"editor\": \"zed\" }." },
              loginShell = { type = "boolean",
                             description = "Whether start asks a login shell once for tools the known paths missed." },
            } },
  defaultView = { type = "string", description = "The picker entering the layer opens." },
  actionsView = { type = "string", description = "The picker cmd+k opens for the highlighted row." },
  presenter = { type = "string", description = "The presenter drawing a picker that names none." },
  logLevel = { type = "string",
               description = "How much the layer writes to the Hammerspoon console, in VS Code's level names." },
  performance = { type = "object",
                  description = "Where the time goes: a line per open and keystroke at debug, every span at "
                                .. "trace, and \"Developer: Show Performance\".",
                  properties = {
                    slowMilliseconds = { type = "number",
                                         description = "A span or a whole open taking this long is a warning; "
                                                       .. "0 records nothing." },
                    keep = { type = "number", description = "How many of the latest spans are kept." },
                  } },
}

----------------------------------------------------------------------
-- CHECKING ONE
----------------------------------------------------------------------

local function validate(kind, value, report)
  local schema = SCHEMAS[kind]
  if type(value) ~= "table" then
    return report(("should be a table, not %s"):format(type(value)))
  end

  for key in pairs(value) do
    if schema.fields[key] == nil then
      local instead = schema.replaced and schema.replaced[key]
      report(("%q is not a field of %s%s"):format(tostring(key), schema.what, instead and (": " .. instead) or ""))
    end
  end

  for key, field in pairs(schema.fields) do
    local v, label = value[key], ("%q"):format(key)
    if v == nil then
      if field.required then report(label .. " is required") end
    elseif field.type == WHEN then
      local why = whenProblem(v)
      if why then report(label .. " " .. why) end
    else
      local why = wrongLuaType(v, field.type)
                  or (field.enum and oneOf(v, field.enum))
                  or (field.command and not M.knowsCommand(v) and ("names no command %q"):format(v))
                  or (field.view and not M.viewNamed(v) and ("names no picker %q"):format(v))
                  or (field.presenter and not M.presenters[v] and ("names no presenter %q"):format(v))
      if why then
        report(label .. " " .. why)
      else
        if field.items and type(v) == "table" then
          for i, item in ipairs(v) do
            local itemWhy = wrongLuaType(item, field.items)
            if itemWhy then report(("%s item %d %s"):format(label, i, itemWhy)) end
          end
        end
        if field.list then
          for i, item in ipairs(v) do
            local prefix = field.label(item, i) .. ": "
            validate(field.list, item, function(message) report(prefix .. message) end)
          end
        end
        if field.map then
          for name, item in pairs(v) do
            local prefix = ("%s %q: "):format(field.map, tostring(name))
            validate(field.map, item, function(message) report(prefix .. message) end)
          end
        end
        if field.check then field.check(v, report) end
      end
    end
  end

  if schema.check then schema.check(value, report) end
end

-- A section names an extension or a picker there is, and following the
-- pickers sections name never comes back to where it started.
local function checkSections(spec, report)
  for _, section in ipairs(type(spec.sections) == "table" and spec.sections or {}) do
    if type(section) == "table" then
      if type(section.view) == "string" and not M.viewNamed(section.view) then
        report(("a section of %s names no picker %q"):format(spec.name, section.view))
      elseif type(section.from) == "string" and not M.declaredExtensions[section.from] then
        report(("a section of %s names no extension %q"):format(spec.name, section.from))
      end
    end
  end

  local visited = {}
  local function leadsBack(name)
    local view = M.viewNamed(name)
    for _, section in ipairs(view and type(view.sections) == "table" and view.sections or {}) do
      local next = type(section) == "table" and section.view
      if next == spec.name then return true end
      if next and not visited[next] then
        visited[next] = true
        if leadsBack(next) then return true end
      end
    end
    return false
  end
  if leadsBack(spec.name) then
    report(("the sections of %s lead back to it"):format(spec.name))
  end
end

-- Everything registered by setup. `viewFiles` names the settings file a
-- picker was written in, for its problems to name.
function M.checkSpecs(viewFiles)
  viewFiles = viewFiles or {}

  for _, ext in ipairs(M.extensions) do
    local where = "extension " .. tostring(ext.name)
    validate("extension", ext, function(message) problem(where, message) end)
  end

  for _, spec in ipairs(M.views) do
    local file = viewFiles[spec.name]
    local where = file or ("picker " .. tostring(spec.name))
    local prefix = file and ('"views": ' .. tostring(spec.name) .. ": ") or ""
    validate("view", spec, function(message) problem(where, prefix .. message) end)
    if type(spec.name) == "string" then
      local referencePrefix = file and '"views": ' or ""
      checkSections(spec, function(message) problem(where, referencePrefix .. message) end)
    end
  end

  local owners = {}
  for name, presenter in pairs(M.presenters) do
    owners[#owners + 1] = { where = "presenter " .. name, settings = presenter.settings }
  end
  for _, ranker in ipairs(M.rankers) do
    owners[#owners + 1] = { where = "ranker " .. tostring(ranker.name), settings = ranker.settings }
  end
  for _, owner in ipairs(owners) do
    if type(owner.settings) == "table" then
      for key, decl in pairs(owner.settings) do
        local prefix = ("setting %q: "):format(tostring(key))
        validate("setting", decl, function(message) problem(owner.where, prefix .. message) end)
      end
    end
  end
end

-- What is wrong with a row, for the harness.
function M.checkRow(row)
  local found = {}
  validate("row", row, function(message) found[#found + 1] = message end)
  return found
end

----------------------------------------------------------------------
-- SETTINGS FILES
--
-- Against the keys config/defaults.jsonc has, the declared settings, and the
-- pickers, rankers, matchers and presenters that are loaded. A problem is
-- reported and the file still applies, as VS Code underlines a setting it
-- does not know and reads the rest.
----------------------------------------------------------------------

local function checkExtensionSetting(file, label, name, key, value)
  local ext = M.declaredExtensions[name]
  local owner = ext or M.pluginWithSettings(name)
  if not owner then
    return problem(file, ("%q: there is no extension %q"):format(label, name))
  end
  local why
  if key == "enabled" and ext then
    why = wrongType(value, "boolean")
  elseif key == "menus" and ext then
    why = wrongType(value, "object")
    if not why then
      local menus = {}
      for _, view in ipairs(M.views) do
        for _, menu in ipairs(type(view.menus) == "table" and view.menus or {}) do menus[menu] = true end
      end
      for menu, on in pairs(value) do
        if type(on) ~= "boolean" then
          problem(file, ("%q should be true or false"):format(label .. "." .. tostring(menu)))
        elseif not menus[menu] then
          problem(file, ("%q: no picker lists the menu %q"):format(label, tostring(menu)))
        end
      end
    end
  else
    local decl = type(owner.settings) == "table" and owner.settings[key]
    if type(decl) ~= "table" then
      return problem(file, ("%q is not a setting of %s"):format(label, M.displayNameOf(name)))
    end
    if type(decl.deprecationMessage) == "string" then
      problem(file, ("%q is deprecated: %s"):format(label, decl.deprecationMessage))
    end
    why = againstDeclaration(value, decl)
  end
  if why then problem(file, ("%q %s"):format(label, why)) end
end

-- Keys that were settings, and what took their place.
local REPLACED = {
  hotkeys = function(value, file)
    local chord = type(value) == "table" and type(value.enter) == "string" and value.enter or "alt+space"
    local entry = ('{ "key": %q, "command": "quickOpen", "global": true }'):format(chord)
    local shipped
    for _, default in ipairs(M.readJSONC(M.SPOON_DIR .. "config/defaultKeybindings.jsonc") or {}) do
      if M.entersLayer(default) and M.chordId(default.key) ~= M.chordId(chord) then shipped = default.key end
    end
    local removal = shipped and (', after { "key": %q, "command": "-quickOpen" }'):format(shipped) or ""
    problem(file, ('"hotkeys" is not a setting: the entry chord is a global keybinding, '
                   .. "%s in keybindings.json%s"):format(entry, removal))
  end,
}

local function isNamed(list, name)
  for _, item in ipairs(list) do
    if item.name == name then return true end
  end
  return false
end

-- After the settings apply, so a picker a profile adds is a picker.
function M.checkSettings(data, file, defaults)
  for key, value in pairs(data) do
    local name, rest
    if type(key) == "string" then name, rest = key:match("^([^%.]+)%.(.+)$") end
    -- Where an editor finds config/settings.schema.json.
    if key == "$schema" then
      local why = wrongType(value, "string")
      if why then problem(file, ("\"$schema\" %s"):format(why)) end
    elseif REPLACED[key] then
      REPLACED[key](value, file)
    elseif name then
      checkExtensionSetting(file, key, name, rest, value)
    elseif defaults[key] ~= nil then
      local why = wrongType(value, M.jsonType(defaults[key]))
      if why then problem(file, ("%q %s"):format(tostring(key), why)) end
    else
      problem(file, ("%q is not a setting"):format(tostring(key)))
    end
  end

  if type(data.logLevel) == "string" then
    local why = oneOf(data.logLevel, M.logLevels)
    if why then problem(file, ("\"logLevel\" %s"):format(why)) end
  end

  -- The kernel's own keys are those defaults.jsonc has; a presenter's are
  -- its settings.
  local known = type(defaults.appearance) == "table" and defaults.appearance or {}
  for key in pairs(type(data.appearance) == "table" and data.appearance or {}) do
    if known[key] == nil then
      problem(file, ("%q is not a setting"):format("appearance." .. tostring(key)))
    end
  end

  local measured = type(defaults.performance) == "table" and defaults.performance or {}
  for key, value in pairs(type(data.performance) == "table" and data.performance or {}) do
    local label = "performance." .. tostring(key)
    if measured[key] == nil then
      problem(file, ("%q is not a setting"):format(label))
    elseif type(value) ~= "number" or value < 0 then
      problem(file, ("%q should be a number, 0 or more"):format(label))
    end
  end

  for name in pairs(type(data.prefixes) == "table" and data.prefixes or {}) do
    if not M.viewNamed(name) then
      problem(file, ("\"prefixes\": there is no picker %q"):format(tostring(name)))
    end
  end

  for id, alias in pairs(type(data.aliases) == "table" and data.aliases or {}) do
    local strings = type(alias) == "string" or M.isList(alias)
    for _, each in ipairs(type(alias) == "table" and alias or {}) do
      if type(each) ~= "string" then strings = false end
    end
    if not M.knowsCommand(id) then
      problem(file, ("\"aliases\": there is no command %q"):format(tostring(id)))
    elseif not strings then
      problem(file, ("%q should be a string or a list of strings"):format("aliases." .. tostring(id)))
    end
  end

  -- A picker's fields and sections are checked with every picker, in checkSpecs.
  for i, spec in ipairs(type(data.views) == "table" and data.views or {}) do
    if type(spec) ~= "table" or type(spec.name) ~= "string" then
      problem(file, ("\"views\": entry %d has no name"):format(i))
    end
  end

  for _, key in ipairs({ "defaultView", "actionsView" }) do
    if type(data[key]) == "string" and not M.viewNamed(data[key]) then
      problem(file, ("%q: there is no picker %q"):format(key, data[key]))
    end
  end
  for _, spec in ipairs(type(data.views) == "table" and data.views or {}) do
    if type(spec) == "table" and spec.enabled == false then
      for _, key in ipairs({ "defaultView", "actionsView" }) do
        if spec.name == M[key] then
          problem(file, ("\"views\": %s is removed, and %s still names it"):format(tostring(spec.name), key))
        end
      end
    end
  end
  if type(data.presenter) == "string" and not M.presenters[data.presenter] then
    problem(file, ("\"presenter\": there is no presenter %q"):format(data.presenter))
  end
  for name, weight in pairs(type(data.rankers) == "table" and data.rankers or {}) do
    if not isNamed(M.rankers, name) then
      problem(file, ("\"rankers\": there is no ranker %q"):format(tostring(name)))
    elseif type(weight) ~= "number" then
      problem(file, ("%q should be a number"):format("rankers." .. tostring(name)))
    end
  end
  if M.isList(data.matchers) then
    for _, name in ipairs(data.matchers) do
      if not isNamed(M.loadedMatchers or M.matchers, name) then
        problem(file, ("\"matchers\": there is no matcher %q"):format(tostring(name)))
      end
    end
  end
end

----------------------------------------------------------------------
-- KEYBINDINGS
----------------------------------------------------------------------

local KEYBINDING_FIELDS = {
  key = "The chord: modifiers and one key joined by +, as cmd+shift+p; hyper is cmd+alt+ctrl+shift. "
        .. "A key the search field needs to edit text -- a letter, space, backspace, left, cmd+a, "
        .. "cmd+v -- is a problem and is not bound.",
  global = "Whether the key works in every app, while the layer is closed too, rather than only "
           .. "while it is open. A global key's when is checked against a context made when it is "
           .. "pressed. { \"key\": \"alt+space\", \"command\": \"quickOpen\", \"global\": true } "
           .. "enters the layer.",
  command = "The command it runs. -id removes the entries before it for that command: only "
            .. "those for key when one is named, every one otherwise.",
  args = "The args the command is run with; quickOpen takes { view, query }.",
  when = "The entry applies only while this holds, checked when the key is pressed against the "
         .. "picker on screen, with activeView, hasQuery (text in the field after any prefix) and "
         .. "viewItem (the highlighted row's kind). Of the entries on one key the last whose when "
         .. "and whose command's enablement hold runs.",
  ["repeat"] = "Whether holding the key runs the command again as the key repeats; true when "
               .. "absent for quickOpen.selectNext and quickOpen.selectPrevious.",
}
M.keybindingFields = KEYBINDING_FIELDS

-- What can be told of one entry wherever it stands in the list. Whether
-- the picker a quickOpen names exists waits for removals: a profile may
-- remove a picker and the default chord that opens it together.
function M.checkKeybinding(entry, file)
  if type(entry) ~= "table" then return problem(file, "an entry is not an object") end
  local command = entry.command
  local label = type(entry.key) == "string" and entry.key or tostring(command)
  for field in pairs(entry) do
    if not KEYBINDING_FIELDS[field] then
      problem(file, ("%s: %q is not a field of a keybinding"):format(label, tostring(field)))
    end
  end
  if type(command) ~= "string" or command == "" then
    return problem(file, ("%s has no command"):format(label))
  end
  local removed = command:match("^%-(.+)$")
  if not M.knowsCommand(removed or command) then
    problem(file, ("%s: there is no command %q"):format(label, removed or command))
  end
  if entry.key ~= nil or not removed then
    local _, key = M.chord(entry.key)
    if not key then
      problem(file, ("%q is not a key"):format(tostring(entry.key)))
    elseif not removed and M.editsText(entry.key) then
      local who = entry.global == true and "every app" or "the search field"
      problem(file, ("%s: %s needs this key to edit text, so it is not bound"):format(label, who))
    end
  end
  if entry.global ~= nil and type(entry.global) ~= "boolean" then
    problem(file, ("%s: \"global\" should be a boolean, not %s"):format(label, M.jsonType(entry.global)))
  end
  if entry.when ~= nil and entry.when ~= ""
     and (type(entry.when) ~= "string" or M.whenError(entry.when)) then
    problem(file, ("%s: the when clause %q does not parse"):format(label, tostring(entry.when)))
  end
  if entry["repeat"] ~= nil and type(entry["repeat"]) ~= "boolean" then
    problem(file, ("%s: \"repeat\" should be a boolean, not %s"):format(label, M.jsonType(entry["repeat"])))
  end
end

-- Two entries on one key in one file with the same when, the later applying
-- wherever the earlier does: the later always wins, so the earlier can never
-- run. A global entry applies everywhere; one that is not only while the
-- layer is open, so a global one before it still runs while it is closed.
-- Across files, a later entry beating an earlier one is how a profile
-- changes a default.
function M.checkKeybindingCollisions(entries, fileOf)
  local seen = {}
  for _, entry in ipairs(entries) do
    local id = type(entry) == "table" and M.chordId(entry.key)
    if id then
      local file = fileOf(entry)
      local when = type(entry.when) == "string" and entry.when:match("^%s*(.-)%s*$") or ""
      local slot = file .. "\0" .. id .. "\0" .. when
      seen[slot] = seen[slot] or {}
      local earlier
      for i = #seen[slot], 1, -1 do
        local candidate = seen[slot][i]
        if entry.global == true or candidate.global ~= true then
          earlier = candidate
          break
        end
      end
      if earlier then
        problem(file, ("%s is bound to %s and to %s with no when to tell them apart, so only %s runs")
                      :format(tostring(entry.key), tostring(earlier.command), tostring(entry.command),
                              tostring(entry.command)))
      end
      table.insert(seen[slot], entry)
    end
  end
end
