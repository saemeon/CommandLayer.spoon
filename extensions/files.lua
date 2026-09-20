-- CommandLayer.spoon/extensions/files.lua
-- Recent files, file search, and what can be done with a file.
--
-- Its rows are on its own `files` menu, not the root: a picker of every
-- file you could mean belongs behind the `files ` prefix.

local M = {}

local layer

----------------------------------------------------------------------
-- RECENT FILES
--
-- Spotlight already records kMDItemLastUsedDate for everything, so the
-- list of things you had open is a query rather than something to track.
-- The window is kept short so the result set stays small enough to order
-- here, which matters because not every attribute is actually sortable
-- by Spotlight -- the sort descriptor is a hint, not a guarantee.
----------------------------------------------------------------------

local recentFiles = {}
local watching

local function setting(key)
  return layer and layer.setting("files", key)
end

local function expand(path)
  return (tostring(path):gsub("^~", os.getenv("HOME") or ""))
end

local function fileModify(items, add)
  for _, item in ipairs(items) do
    local path = item.kMDItemPath
    -- Folders are excluded here rather than in the predicate: keeping the
    -- query to one clause keeps it parseable, and this costs nothing.
    if path and item.kMDItemContentType ~= "public.folder" then
      if add then
        recentFiles[path] = tonumber(item.kMDItemLastUsedDate) or 0
      else
        recentFiles[path] = nil
      end
    end
  end
end

local function onFiles(_, _, info)
  if not info then return end
  if info.kMDQueryUpdateAddedItems   then fileModify(info.kMDQueryUpdateAddedItems,   true)  end
  if info.kMDQueryUpdateChangedItems then fileModify(info.kMDQueryUpdateChangedItems, true)  end
  if info.kMDQueryUpdateRemovedItems then fileModify(info.kMDQueryUpdateRemovedItems, false) end
end

function M.start()
  if watching or not layer then return M end

  -- NSPredicate, not mdfind. `$time.today(-7)` is Spotlight's own query
  -- language and NSMetadataQuery does not implement it -- it threw on
  -- the unknown selector and took the whole config down with it. A date
  -- literal here is CAST(<seconds>, "NSDate"), counted from NSDate's
  -- reference date of 2001-01-01 rather than the Unix epoch.
  local NSDATE_EPOCH = 978307200
  local cutoff = os.time() - (setting("fileWindowDays") * 86400) - NSDATE_EPOCH

  local query = string.format(
    [[ kMDItemLastUsedDate >= CAST(%d, "NSDate") ]], cutoff)

  watching = layer.watch(hs.spotlight.new()
    :queryString(query)
    :callbackMessages("didUpdate", "inProgress")
    :setCallback(onFiles)
    :sortDescriptors({ { key = "kMDItemLastUsedDate", ascending = false } })
    :searchScopes({ os.getenv("HOME") }))

  return M
end

----------------------------------------------------------------------
-- ICONS
--
-- Every icon is an image made on the main thread, and a search gives up to
-- searchLimit paths. A file whose icon is its type's is drawn once per
-- extension and shared; anything else -- a folder, an app, a name with no
-- extension -- is drawn for its own path. Either way a list loads at most
-- iconRows icons, and a row past them has its type's icon if one is kept,
-- else none.
----------------------------------------------------------------------

-- Packages Finder draws with an icon of their own.
local OWN_ICON = { app = true, prefpane = true, bundle = true, framework = true, workflow = true,
                   photoslibrary = true, saver = true, plugin = true, appex = true }

local typeIcons = {}

function M.iconBudget()
  return { left = math.max(0, math.floor(tonumber(setting("iconRows")) or 0)) }
end

function M.iconFor(path, budget)
  -- "name.ext", not a hidden file's leading dot.
  local ext = path:match("[^/]%.(%w+)$")
  ext = ext and ext:lower()
  local shared = ext and not OWN_ICON[ext]
  if shared and typeIcons[ext] then return typeIcons[ext] end
  if budget.left <= 0 then return nil end
  budget.left = budget.left - 1
  if shared and hs.image.iconForFileType then
    typeIcons[ext] = hs.image.iconForFileType(ext)
    return typeIcons[ext]
  end
  return hs.image.iconForFile(path)
end

function M.stop()
  if watching then
    watching.dispose()
    watching = nil
  end
  recentFiles = {}
  typeIcons = {}
  return M
end

-- Recently used files, newest first.
function M.recent()
  local list = {}
  for path, used in pairs(recentFiles) do
    list[#list + 1] = {
      path = path,
      used = used,
      name = path:match("([^/]+)$") or path,
    }
  end

  table.sort(list, function(a, b) return a.used > b.used end)

  local limit = setting("fileLimit")
  while #list > limit do table.remove(list) end
  return list
end

----------------------------------------------------------------------
-- SEARCH
--
-- Every word typed has to be in the name, in any order, and each tool is
-- asked to do the AND itself.
----------------------------------------------------------------------

function M.words(query)
  local out = {}
  for word in tostring(query or ""):gmatch("%S+") do out[#out + 1] = word end
  return out
end

-- Spotlight's query language, where a backslash escapes a quote, a
-- backslash or its wildcard. mdfind parses a malformed predicate without
-- complaint and only finds nothing, so the text is built here, in one place.
function M.namePredicate(words)
  local clauses = {}
  for i, word in ipairs(words) do
    clauses[i] = ('kMDItemFSName == "*%s*"cd'):format((word:gsub('[\\"*]', "\\%0")))
  end
  return table.concat(clauses, " && ")
end

-- find's -iname is a glob, so a typed star or bracket is taken literally.
local function globWord(word)
  return "*" .. word:gsub("[%*%?%[\\]", "\\%0") .. "*"
end

function M.searchArgs(tool, o)
  local words = M.words(o.query)
  if #words == 0 then return nil end

  if tool == "mdfind" then
    if #words == 1 then return { "-onlyin", o.root, "-name", words[1] } end
    return { "-onlyin", o.root, M.namePredicate(words) }
  end

  if tool == "fd" then
    local args = { "--type", "f", "--hidden", "--fixed-strings", "--exclude", ".git" }
    for i = 2, #words do args[#args + 1] = "--and=" .. words[i] end
    -- A word starting with a dash is a pattern, not an option.
    args[#args + 1] = "--"
    args[#args + 1] = words[1]
    args[#args + 1] = o.root
    return args
  end

  local args = { o.root }
  for _, word in ipairs(words) do
    args[#args + 1] = "-iname"
    args[#args + 1] = globWord(word)
  end
  return args
end

function M.extension(cl)
  layer = cl

  cl.tools.register("mdfind", { "/usr/bin/mdfind" })
  cl.tools.register("find", { "/usr/bin/find" })
  cl.tools.register("fd", { "/opt/homebrew/bin/fd", "/usr/local/bin/fd" })

  cl.tools.provide("files", {
    { name = "mdfind", bin = "mdfind", args = function(o) return M.searchArgs("mdfind", o) end },
    { name = "fd", bin = "fd", args = function(o) return M.searchArgs("fd", o) end },
    { name = "find", bin = "find", args = function(o) return M.searchArgs("find", o) end },
  })

  -- A file, a folder or a project -- from file search, zoxide, recent
  -- projects. cmd+k on any of them offers these with it given; picked from
  -- search they ask which, or take Finder's selection when it has one. In
  -- cmd+. they are verbs on the selection, which is a subject there.
  local function takesPath(description)
    return {
      id = "target", description = description,
      picker = { when = "viewItem == 'file' || viewItem == 'folder' || viewItem == 'project'",
                 menus = { "files", "recent" } },
      preferCurrent = true,
      current = function(ctx)
        local selection = ctx and ctx.finderSelection
        if selection and selection ~= "" then return { kind = "file", path = selection } end
      end,
    }
  end

  -- Finder writes a folder with a trailing slash; a file row is a file.
  local function folderOf(subject)
    local path = subject.path
    if subject.kind ~= "file" or path:match("/$") then return path end
    return path:match("(.*)/[^/]+$") or path
  end

  local function pathCommand(id, title, icon, run, when)
    return {
      id = "files." .. id, title = title, category = "File", icon = icon, when = when,
      menus = { "root", "commandPalette" },
      inputs = { takesPath(title) },
      run = function(args, ctx)
        local target = args.target
        if type(target) == "table" and type(target.path) == "string" then run(target, ctx or {}) end
      end,
    }
  end

  local commands = {
    pathCommand("openInTerminal", "Open in terminal", "$(terminal)", function(target, ctx)
      cl.executeCommand("terminal.open", { target = folderOf(target) }, ctx)
    end, "terminalAvailable"),
    pathCommand("openInEditor", "Open in editor", "$(code)", function(target, ctx)
      cl.executeCommand("editor.open", { target = target.path }, ctx)
    end),
    pathCommand("revealInFinder", "Reveal in Finder", "$(folder-opened)", function(target, ctx)
      cl.executeCommand("system.reveal", { target = target.path }, ctx)
    end),
    pathCommand("copyPath", "Copy path", "$(copy)", function(target, ctx)
      cl.executeCommand("system.copy", { text = target.path }, ctx)
    end),

    -- Only on cmd+k: from search, picking a file row already opens it.
    { id = "files.open", title = "Open", category = "File",
      menus = { ["view/item/context"] = true },
      inputs = { { id = "file", picker = { when = "viewItem == 'file'" } } },
      run = function(args, ctx)
        local file = args.file
        if type(file) == "table" and type(file.path) == "string" then
          cl.executeCommand("system.open", { target = file.path }, ctx)
        end
      end },
  }

  local function fileItem(ctx, path, budget)
    return {
      label       = path:match("([^/]+)/?$") or path,
      description = path,
      ctx         = ctx,
      command     = "system.open",
      args        = { target = path },
      subject     = { kind = "file", path = path },
      iconPath    = M.iconFor(path, budget),
    }
  end

  return {
    name  = "files",
    menus = { "files" },
    commands = commands,

    settings = {
      fileWindowDays = { type = "integer", default = 7,
        description = "How many days back a file counts as recently used" },
      fileLimit = { type = "integer", default = 25,
        description = "At most this many recent files, before anything is typed" },
      searchLimit = { type = "integer", default = 200,
        description = "At most this many files found by typing" },
      searchRoot = { type = "string", default = "~",
        description = "The folder file search looks in" },
      iconRows = { type = "integer", default = 20,
        description = "At most this many icons loaded for one list of files; icons shared by a file type are kept" },
    },

    items = function(ctx)
      local rows, budget = {}, M.iconBudget()
      for _, file in ipairs(M.recent()) do rows[#rows + 1] = fileItem(ctx, file.path, budget) end
      return rows
    end,

    -- Returns how to stop it, so a newer query kills this search rather
    -- than leaving both running.
    search = function(query, ctx, done)
      local _, bin, args = cl.tools.pick("files", {
        query = query,
        root  = expand(cl.setting("files", "searchRoot")),
      })
      if not bin then
        done({})
        return
      end

      local limit = cl.setting("files", "searchLimit")
      local task = cl.tools.run(bin, args, function(_, stdout)
        local rows, budget = {}, M.iconBudget()
        for line in tostring(stdout):gmatch("[^\r\n]+") do
          if #rows >= limit then break end
          rows[#rows + 1] = fileItem(ctx, line, budget)
        end
        done(rows)
      end)

      if not task then
        done({})
        return
      end
      return function() task:terminate() end
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
