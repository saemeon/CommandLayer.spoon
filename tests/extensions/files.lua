-- CommandLayer.spoon/tests/extensions/files.lua
-- The files extension's checks.

local T = ...
local check = T.check
local cl = T.layer()


local function offered(subject)
  local found = {}
  for _, verb in ipairs(cl.itemActions(subject, cl.contextFromKeys())) do
    if verb.command then found[verb.command] = verb end
    found[verb.label] = (found[verb.label] or 0) + 1
  end
  return found
end
local onFile = offered({ kind = "file", path = "/a/b.txt" })
local onFolder = offered({ kind = "folder", path = "/a/dir" })
local onProject = offered({ kind = "project", path = "/a/repo" })
check("cmd+k on a file, a folder or a project offers the path commands with it given",
      onFile["files.openInTerminal"] and onFile["files.openInTerminal"].args.target.path == "/a/b.txt"
      and onFolder["files.revealInFinder"] and onProject["files.copyPath"]
      and onProject["files.openInEditor"])
check("and no extension offers a copy of its own",
      onProject["Open in terminal"] == 1 and onFolder["Open in terminal"] == 1
      and onFile["Open in editor"] == 1 and onProject["Copy path"] == 1,
      ("%s / %s"):format(tostring(onProject["Open in terminal"]), tostring(onFolder["Open in terminal"])))

-- Everything that requires the terminal goes with it too.
local noTerminal = T.layer({ ["terminal.enabled"] = false, ["git.enabled"] = false, ["brew.enabled"] = false,
                             ["lazygit.enabled"] = false, ["tasks.enabled"] = false })
local function reaches(layer, id)
  local ctx = layer.contextFromKeys()
  local verb, row = false, false
  for _, action in ipairs(layer.itemActions({ kind = "folder", path = "/a/dir" }, ctx)) do
    if action.command == id then verb = true end
  end
  for _, found in ipairs(layer.gather(ctx, { menus = { "root" } })) do
    if found.command == id then row = true end
  end
  return verb, row
end
local verbOn, rowOn = reaches(cl, "files.openInTerminal")
local verbOff, rowOff = reaches(noTerminal, "files.openInTerminal")
local revealOff = reaches(noTerminal, "files.revealInFinder")
check("while the terminal extension is off, Open in terminal is no root row and no cmd+k verb; the rest stay",
      verbOn and rowOn and not verbOff and not rowOff and revealOff,
      ("on: verb %s row %s / off: verb %s row %s / reveal off %s"):format(tostring(verbOn), tostring(rowOn),
        tostring(verbOff), tostring(rowOff), tostring(revealOff)))
-- With no Finder selection: cmd+. lists the verbs on that selection.
local inPicker = false
for _, menu in ipairs({ "root", "commandPalette", "context", "recent", "files" }) do
  for _, row in ipairs(cl.gather({}, { menus = { menu } })) do
    if row.command == "files.open" then inPicker = menu end
  end
end
check("Open is offered on a file's cmd+k, and on no folder and in no picker's own rows",
      onFile["files.open"] and onFile["files.open"].args.file.path == "/a/b.txt"
      and not onFolder["files.open"] and not inPicker,
      ("on file %s, on folder %s, in a picker %s"):format(tostring(onFile["files.open"] ~= nil),
        tostring(onFolder["files.open"] ~= nil), tostring(inPicker)))

local opened = {}
local terminal = cl.getCommand("terminal.open")
local real = terminal and terminal.run
if terminal then terminal.run = function(args) opened[#opened + 1] = args.target end end
cl.executeCommand("files.openInTerminal", { target = { kind = "file", path = "/a/b.txt" } }, {})
cl.executeCommand("files.openInTerminal", { target = { kind = "folder", path = "/a/dir" } }, {})
cl.executeCommand("files.openInTerminal", { target = { kind = "file", path = "/a/Selected/" } }, {})
if terminal then terminal.run = real end
check("the terminal opens in a file's folder, or in the folder itself",
      table.concat(opened, " ") == "/a /a/dir /a/Selected/", table.concat(opened, " "))

local function inContext(ctx)
  for _, row in ipairs(cl.gather(ctx, { menus = { "context" } })) do
    if row.command == "files.revealInFinder" then return true end
  end
  return false
end
local input = cl.itemInputOf(cl.getCommand("files.revealInFinder"))
local current = input and input.current({ finderSelection = "/x/y" })
check("with Finder in front they are context actions on its selection, and not otherwise",
      inContext({ finderSelection = "/x/y" }) and not inContext({ finderSelection = "" })
      and current ~= nil and current.path == "/x/y" and input.preferCurrent == true)

-- A search gives up to searchLimit paths, and every icon is an image made on
-- the main thread.
do
  local files, spec = cl.modules.files, nil
  for _, ext in ipairs(cl.extensions) do
    if ext.name == "files" then spec = ext end
  end
  local byPath, byType = 0, 0
  local saved = { forFile = hs.image.iconForFile, forType = hs.image.iconForFileType, new = hs.task.new }
  hs.image.iconForFile = function(path) byPath = byPath + 1; return { path = path } end
  hs.image.iconForFileType = function(kind) byType = byType + 1; return { kind = kind } end
  local finish
  hs.task.new = function(_, complete)
    finish = complete
    return { start = function(t) return t end, terminate = function() end }
  end
  local kinds = { ".txt", ".md", ".PDF", ".app", "", ".lua" }
  local function search(folder)
    local lines, rows = {}, nil
    for i = 1, 200 do lines[i] = ("/%s/file%d%s"):format(folder, i, kinds[i % #kinds + 1]) end
    finish = nil
    spec.search("file", {}, function(found) rows = found end)
    if finish then finish(0, table.concat(lines, "\n"), "") end
    return rows or {}
  end
  files.stop()
  local first = search("one")
  local loadedFirst = byPath + byType
  byPath, byType = 0, 0
  local second = search("two")
  hs.image.iconForFile, hs.image.iconForFileType, hs.task.new = saved.forFile, saved.forType, saved.new
  files.stop()
  -- Row 200 is a .PDF, 196 has no extension, 195 is an app.
  check("a search loads at most iconRows icons, and a row past them has its type's icon if one is kept",
        #first == 200 and loadedFirst == 20 and first[1].iconPath ~= nil
        and first[200].iconPath ~= nil and first[196].iconPath == nil and first[195].iconPath == nil,
        ("%d rows, %d icons loaded"):format(#first, loadedFirst))
  check("and a type's icon is kept for the next search, where only paths with icons of their own load",
        #second == 200 and byType == 0 and byPath == 20 and rawequal(second[200].iconPath, first[200].iconPath),
        ("%d by type, %d by path"):format(byType, byPath))
end

-- Several words: every one in the name, each tool doing the AND itself.
do
  local files = cl.modules.files
  local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for i = 1, #a do
      if a[i] ~= b[i] then return false end
    end
    return true
  end
  local function shown(args) return table.concat(args or {}, " | ") end

  local two = { query = " alpha  beta ", root = "/r" }
  local mdfind = files.searchArgs("mdfind", two)
  check("two words ask mdfind for a name clause each, joined by &&, and one word keeps -name",
        same(mdfind, { "-onlyin", "/r", 'kMDItemFSName == "*alpha*"cd && kMDItemFSName == "*beta*"cd' })
        and same(files.searchArgs("mdfind", { query = "alpha", root = "/r" }), { "-onlyin", "/r", "-name", "alpha" }),
        shown(mdfind))

  local predicate = files.namePredicate({ [[a"b\c*d]], "it's" })
  check("a quote, a backslash and a star in a word are escaped in the predicate",
        predicate == [[kMDItemFSName == "*a\"b\\c\*d*"cd && kMDItemFSName == "*it's*"cd]], predicate)

  local fd = files.searchArgs("fd", { query = "-alpha beta gamma", root = "/r" })
  check("fd is given --and for every word after the first, and the first after --",
        same(fd, { "--type", "f", "--hidden", "--fixed-strings", "--exclude", ".git",
                   "--and=beta", "--and=gamma", "--", "-alpha", "/r" }), shown(fd))

  local find = files.searchArgs("find", { query = "alpha b*[c]?", root = "/r" })
  check("find is given an -iname per word, a glob character in one taken literally",
        same(find, { "/r", "-iname", "*alpha*", "-iname", [[*b\*\[c]\?*]] }), shown(find))

  local blank = { query = "   ", root = "/r" }
  check("a blank query asks no tool",
        files.searchArgs("mdfind", blank) == nil and files.searchArgs("fd", blank) == nil
        and files.searchArgs("find", blank) == nil)

  local saved = cl.tools.paths.mdfind
  cl.tools.paths.mdfind = "/usr/bin/mdfind"
  local provider, bin, args = cl.tools.pick("files", two)
  cl.tools.paths.mdfind = saved
  check("file search asks mdfind with that predicate",
        provider ~= nil and provider.name == "mdfind" and bin == "/usr/bin/mdfind" and same(args, mdfind),
        shown(args))
end
