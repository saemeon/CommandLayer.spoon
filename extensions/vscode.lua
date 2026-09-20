-- VS Code from outside it, with nothing installed in it: the CLI, its recent
-- folders, the URLs its own handlers answer, and its menu bar.
--
-- A stock VS Code runs no command id sent from outside: the CLI has no such
-- option, and a `command:` link runs only from content VS Code rendered
-- itself. So a command is reached through the menu item that runs it.

local M = {}

M.storagePath = os.getenv("HOME")
  .. "/Library/Application Support/Code/User/workspaceStorage"

-- VS Code keeps a copy of its menu bar here, rewritten whenever a folder is
-- opened, and its "Open Recent" submenu is the recent list, newest first.
M.menubarPath = os.getenv("HOME")
  .. "/Library/Application Support/Code/User/globalStorage/storage.json"

local layer
local menubar, menubarModified = {}, nil

-- Part of the storage cache's key, so forgetting starts a new entry rather
-- than waiting out the old one.
local generation = 0

function M.forget()
  menubar, menubarModified = {}, nil
  generation = generation + 1
end

----------------------------------------------------------------------

local function unescape(text)
  return (text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

-- Remote - SSH writes a host an authority cannot hold as it is as
-- hex-encoded JSON, {"hostName":"box","user":"me"}; `code --remote` takes
-- the authority either way, but ssh and a person read the host.
function M.remoteHost(host)
  host = tostring(host)
  if #host % 2 == 0 and host:match("^7[bB]%x+$") then
    local text = host:gsub("%x%x", function(hex) return string.char(tonumber(hex, 16)) end)
    local ok, data = pcall(hs.json.decode, text)
    if ok and type(data) == "table" and type(data.hostName) == "string" then
      return (type(data.user) == "string" and (data.user .. "@") or "") .. data.hostName
    end
  end
  return host
end

-- file:///Users/me/project            -> /Users/me/project
-- vscode-remote://ssh-remote+host/srv -> [ssh:host] /srv
local function parseURI(uri, isWorkspace)
  if type(uri) ~= "string" then return nil end

  local path = uri:match("^file://(.+)$")
  if path then
    path = unescape(path):gsub("/$", "")

    -- An untitled multi-root workspace is stored as
    -- .../Code/Workspaces/<id>/workspace.json. It has no name worth
    -- showing and no folder to open, so it is not a project.
    if path:match("/Code/Workspaces/[^/]+/workspace%.json$") then
      return nil
    end

    local name = path:match("([^/]+)$") or path
    -- A saved multi-root workspace is a .code-workspace file; the file
    -- is the thing to open, but its extension is not part of its name.
    name = name:gsub("%.code%-workspace$", "")

    return { path = path, name = name, workspace = isWorkspace or nil }
  end

  local rest = uri:match("^vscode%-remote://ssh%-remote%+(.+)$")
  if rest then
    rest = unescape(rest)
    local host, remotePath = rest:match("^([^/]+)(/.*)$")
    if host then
      return {
        path      = remotePath,
        name      = (remotePath:match("([^/]+)$") or remotePath),
        remote    = M.remoteHost(host),
        authority = "ssh-remote+" .. host,
      }
    end
  end

  return nil
end

----------------------------------------------------------------------

-- The folders and workspaces in VS Code's Open Recent submenu, in its
-- order, from `lastKnownMenubarData` in storage.json. Files are left out:
-- a project is a folder.
function M.openRecentFrom(data)
  local out, seen = {}, {}
  local function walk(node)
    if type(node) ~= "table" then return end
    local uri = node.uri
    if (node.id == "openRecentFolder" or node.id == "openRecentWorkspace")
       and type(uri) == "table" and type(uri.path) == "string" then
      local path = uri.path:gsub("/$", "")
      local name = (path:match("([^/]+)$") or path):gsub("%.code%-workspace$", "")
      local host = type(uri.authority) == "string" and uri.authority:match("^ssh%-remote%+(.+)$")
      local key = (host and uri.authority or "") .. "\0" .. path
      if (uri.scheme == "file" or host) and not seen[key] then
        seen[key] = true
        out[#out + 1] = { path = path, name = name, remote = host and M.remoteHost(host) or nil,
                          authority = host and uri.authority or nil,
                          workspace = node.id == "openRecentWorkspace" or nil }
      end
    end
    -- Lists in order: the submenu's items are the recent list's order.
    if node[1] ~= nil then
      for _, child in ipairs(node) do walk(child) end
    else
      for key, child in pairs(node) do
        if key ~= "uri" then walk(child) end
      end
    end
  end
  walk(data)
  return out
end

local function modifiedAt(path)
  local modified = hs.fs.attributes(path, "modification")
  if type(modified) == "table" then modified = modified.modification end
  return modified
end

-- The workspace storage folders, newest first, reading only as many as are
-- shown: the store can hold hundreds, and each one is a file read.
local function fromWorkspaceStorage(limit)
  local dirs = {}

  local ok, iter, dirObj = pcall(hs.fs.dir, M.storagePath)
  if ok and iter then
    for entry in iter, dirObj do
      if entry ~= "." and entry ~= ".." then
        local file = M.storagePath .. "/" .. entry .. "/workspace.json"
        local attrs = hs.fs.attributes(file)
        if attrs then
          dirs[#dirs + 1] = { file = file, at = attrs.modification or 0 }
        end
      end
    end
  end

  table.sort(dirs, function(a, b) return a.at > b.at end)

  local projects, seen = {}, {}

  for _, entry in ipairs(dirs) do
    if #projects >= limit then break end

    local handle = io.open(entry.file, "r")
    if handle then
      local body = handle:read("a")
      handle:close()

      local decoded, data = pcall(hs.json.decode, body)
      if decoded and type(data) == "table" then
        local project = parseURI(data.folder or data.workspace,
                                 data.folder == nil)
        if project and not seen[project.path] then
          seen[project.path] = true
          project.at = entry.at
          projects[#projects + 1] = project
        end
      end
    end
  end

  return projects
end

-- VS Code's Open Recent list, read when storage.json was written since the
-- last read: at start, and when the folder holding it changes. Never while
-- a picker builds -- the file is VS Code's whole UI state, not only the list.
function M.readRecent()
  local modified = modifiedAt(M.menubarPath)
  if not modified then
    menubar, menubarModified = {}, nil
    return false
  end
  if modified == menubarModified then return false end
  menubarModified = modified
  local handle = io.open(M.menubarPath, "r")
  if not handle then return false end
  local body = handle:read("a")
  handle:close()
  local ok, data = pcall(hs.json.decode, body)
  menubar = ok and type(data) == "table" and M.openRecentFrom(data.lastKnownMenubarData) or {}
  return true
end

-- Folders you have had open, most recent first: VS Code's own Open Recent
-- list, as last read. Where there is none, the workspace storage folders,
-- whose files are written once when a folder is first opened -- so that
-- order is by first open, not last.
function M.recentProjects()
  if #menubar > 0 then return menubar end

  if not layer then return {} end
  return layer.cached("workspaceStorage#" .. generation, {
    seconds = layer.setting("vscode", "cacheSeconds"),
    initial = {},
    refresh = function(done) done(fromWorkspaceStorage(layer.setting("vscode", "limit"))) end,
  })
end

----------------------------------------------------------------------
-- URLS
--
-- vscode://file/<path>[:line[:column]] is answered by VS Code's main
-- process, which asks once before opening a local path from outside unless
-- security.promptForLocalFileProtocolHandling is off -- the dialog has a
-- checkbox that switches it off.
----------------------------------------------------------------------

-- Percent-encoded so `open` takes it as one URL: a space or a # in a path
-- would otherwise end it. VS Code decodes it back into a path.
function M.fileURL(path, position)
  local encoded = path:gsub("[^%w%-%._~/]", function(c)
    return ("%%%02X"):format(c:byte())
  end)
  local url = "vscode://file" .. encoded
  if position then url = url .. ":" .. position end
  return url
end

-- "12" or "12:5", as `code --goto` writes a position.
function M.position(text)
  text = tostring(text or ""):match("^%s*(.-)%s*$")
  if text:match("^%d+$") or text:match("^%d+:%d+$") then return text end
  return nil
end

----------------------------------------------------------------------
-- MENU COMMANDS
----------------------------------------------------------------------

-- Found by bundle id: a lookup by name searches every window when it misses.
M.bundleID = "com.microsoft.VSCode"

-- Paths as VS Code's macOS menu bar spells them, "..." included. A VS Code
-- in another language has other titles, and says so when one is picked.
M.menuCommands = {
  { id = "commandPalette", title = "Command Palette", path = { "View", "Command Palette..." } },
  { id = "goToFile",       title = "Go to File",      path = { "Go", "Go to File..." } },
  { id = "toggleTerminal", title = "Toggle Terminal", path = { "View", "Terminal" } },
  { id = "newTerminal",    title = "New Terminal",    path = { "Terminal", "New Terminal" } },
  { id = "runTask",        title = "Run Task",        path = { "Terminal", "Run Task..." } },
  { id = "toggleSidebar",  title = "Toggle Sidebar",  path = { "View", "Appearance", "Primary Side Bar" } },
  { id = "splitEditor",    title = "Split Editor",    path = { "View", "Editor Layout", "Split Right" } },
  { id = "sourceControl",  title = "Source Control",  path = { "View", "Source Control" } },
  { id = "extensions",     title = "Extensions",      path = { "View", "Extensions" } },
}

-- The menu bar belongs to the app in front, and while the picker closes
-- that is Hammerspoon.
M.menuDelay = 0.1

----------------------------------------------------------------------

-- Writes come in bursts: one read once they settle.
M.readDelay = 0.5

function M.extension(cl)
  layer = cl

  local menuTimer, readTimer

  -- The folder rather than the file, so a file replaced rather than written
  -- into is still seen. The folder also holds state.vscdb, written far more
  -- often, so only a change naming storage.json reads.
  M.start = function()
    M.readRecent()
    if not hs.pathwatcher then return end
    local folder = M.menubarPath:match("(.*)/[^/]+$")
    if not folder then return end
    cl.watch(hs.pathwatcher.new(folder, function(paths)
      local named = type(paths) ~= "table"
      for _, path in ipairs(type(paths) == "table" and paths or {}) do
        if tostring(path):find("storage.json", 1, true) then named = true end
      end
      if not named or readTimer then return end
      readTimer = cl.after(M.readDelay, function()
        readTimer = nil
        M.readRecent()
      end)
    end))
  end

  M.stop = function()
    readTimer = nil
  end

  local function selectMenu(path)
    local app = (hs.application.applicationsForBundleID(M.bundleID) or {})[1]
    if not app then
      hs.alert.show("VS Code is not running")
      return false
    end
    app:activate()
    if menuTimer then menuTimer.dispose() end
    menuTimer = cl.after(M.menuDelay, function()
      menuTimer = nil
      if not app:selectMenuItem(path) then
        hs.alert.show("VS Code has no menu item " .. table.concat(path, " > "))
      end
    end)
    return true
  end

  local function openWith(target, newWindow)
    local path = type(target) == "table" and target.path
    local bin = cl.tools.path("code")
    if type(path) ~= "string" then return end
    if not bin then
      hs.alert.show("code CLI not found")
      return
    end
    cl.tools.run(bin, { newWindow and "--new-window" or "--reuse-window", path })
  end

  -- Offered only where the CLI is, as the verbs need it.
  cl.itemContextKey("codeCLI", function() return cl.tools.path("code") ~= nil end)

  local function openInput()
    return { id = "target", description = "Which file or project",
             picker = { when = "viewItem == 'project' || viewItem == 'file'" } }
  end

  local commands = {
    -- Through VS Code's own Git extension, which answers
    -- vscode://vscode.git/clone and is trusted to without a prompt. VS Code
    -- asks where to put it.
    { id = "vscode.cloneRepository", title = "Clone repository…", category = "VS Code",
      icon = "$(repo-clone)", menus = { "root", "commandPalette" },
      inputs = { { id = "repository", picker = { typed = true },
                   description = "Repository URL to clone in VS Code", encode = "query" } },
      command = "system.open",
      args = { target = "vscode://vscode.git/clone?url=${input:repository}" } },

    -- VS Code's settings editor answers vscode://settings/<id>, searching
    -- for the id; one it does not know opens the editor unsearched.
    { id = "vscode.openSetting", title = "Open setting…", category = "VS Code",
      icon = "$(settings-gear)", menus = { "commandPalette" },
      inputs = { { id = "setting", picker = { typed = true },
                   description = "Setting id, such as editor.fontSize", encode = "query" } },
      command = "system.open",
      args = { target = "vscode://settings/${input:setting}" } },

    { id = "vscode.openAtLine", title = "Open file at line…", category = "VS Code",
      icon = "$(go-to-file)", menus = { "commandPalette" },
      inputs = {
        { id = "target", description = "Which file",
          picker = { when = "viewItem == 'file'", menus = { "files", "recent" } } },
        { id = "line", description = "Line, or line:column", picker = { typed = true } },
      },
      run = function(args, ctx)
        local target = args.target
        if type(target) ~= "table" or type(target.path) ~= "string" then return end
        local position = M.position(args.line)
        if not position then
          hs.alert.show("A line is a number, or line:column")
          return
        end
        cl.executeCommand("system.open", { target = M.fileURL(target.path, position) }, ctx)
      end },

    { id = "vscode.open", title = "Open in VS Code", category = "VS Code",
      menus = { ["view/item/context"] = { when = "codeCLI" } },
      inputs = { openInput() },
      run = function(args) openWith(args.target, false) end },

    { id = "vscode.openInNewWindow", title = "Open in VS Code (new window)", category = "VS Code",
      menus = { ["view/item/context"] = { when = "codeCLI" } },
      inputs = { openInput() },
      run = function(args) openWith(args.target, true) end },
  }

  for _, item in ipairs(M.menuCommands) do
    commands[#commands + 1] = {
      id = "vscode." .. item.id, title = item.title, category = "VS Code",
      menus = { "commandPalette" },
      run = function() selectMenu(item.path) end,
    }
  end

  return {
    name        = "vscode",
    displayName = "VS Code",
    rank        = 0.14,
    menus       = { "commandPalette" },
    commands    = commands,

    settings = {
      -- Only the most recent handful matter; the store holds years of them.
      limit = { type = "integer", default = 40,
                description = "Recent folders read from VS Code's workspace storage" },
      cacheSeconds = { type = "integer", default = 60,
                       description = "How long the workspace storage's folders are kept, in seconds" },
    },

    exports = {
      -- Looked up when called, so a replaced recentProjects is the one used.
      recentProjects = function() return M.recentProjects() end,
    },
  }
end

-- Checks for this extension, run by test.lua.

return M
