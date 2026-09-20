-- CommandLayer.spoon/extensions/projects.lua
-- Directories you work in.
--
-- zoxide already tracks every directory you visit and ranks them by
-- frecency, and VS Code already records the folders it opened. Scanning
-- for .git throws both orderings away, so it is the last resort rather
-- than the first idea.

local M = {}

local HOME = os.getenv("HOME")

-- Kept from extension(cl): the list is read from outside it, by git and the
-- harness.
local layer

-- Part of the scan cache's key, so forgetting starts a new entry rather than
-- waiting out one still being asked.
local generation = 0

local function expand(path)
  return (path:gsub("^~", HOME))
end

local function isGitRepo(path)
  return hs.fs.attributes(path .. "/.git") ~= nil
end

-- Turns a list of paths, one per line, into project entries.
-- Order is preserved: zoxide emits most-frecent first.
function M.parsePaths(output, requireGit)
  local seen, items = {}, {}
  for line in tostring(output):gmatch("[^\r\n]+") do
    -- zoxide --score prefixes a numeric weight; strip it if present.
    local path = line:match("^%s*[%d%.]+%s+(/.*)$") or line
    path = path:gsub("/$", "")
    if path:sub(1, 1) == "/" and not seen[path] then
      seen[path] = true
      if not requireGit or isGitRepo(path) then
        items[#items + 1] = {
          path = path,
          name = path:match("([^/]+)$") or path,
        }
      end
    end
  end
  return items
end

-- The find-based scan's output is .git paths rather than project directories.
function M.parseScan(output)
  local seen, items = {}, {}
  for line in tostring(output):gmatch("[^\r\n]+") do
    local dir = line:match("^(.*)/%.git/?$")
    if dir and not seen[dir] then
      seen[dir] = true
      items[#items + 1] = {
        path = dir,
        name = dir:match("([^/]+)$") or dir,
      }
    end
  end
  return items
end

----------------------------------------------------------------------

local function setting(key)
  return layer.setting("projects", key)
end

-- The roots worth scanning, for the find fallback. zoxide and ~/.z
-- ignore these -- they already know where you have been.
local function existingRoots()
  local roots = {}
  for _, root in ipairs(setting("projectRoots") or {}) do
    local path = expand(tostring(root))
    if hs.fs.attributes(path) then roots[#roots + 1] = path end
  end
  return roots
end

-- A folder on an SSH host has no path here: only its own rows take it, so
-- whoever reads the projects list gets local folders alone.
local function editorRecents(withRemote)
  local vscode = layer.extension("vscode")
  local list = {}
  for _, p in ipairs(vscode and vscode.recentProjects() or {}) do
    if not p.remote then
      list[#list + 1] = { path = p.path, name = p.name }
    elseif withRemote and p.authority then
      list[#list + 1] = { path = p.path, name = p.name, host = p.remote, authority = p.authority }
    end
  end
  return list
end

-- The same path on two hosts, or here and on a host, is two projects.
local function keyOf(p)
  return (p.authority or "") .. "\0" .. p.path
end

-- The editor's own recent folders go first. zoxide ranks every directory
-- you have ever visited by frecency, which answers "where have I been";
-- VS Code's list answers "what am I working on", and that is the one you
-- want at the top of a launcher. Merged each time the list is read, not
-- when a scan lands: the editor's list changes every time a folder opens,
-- and a scan is kept for minutes.
local function withEditorRecents(scanned, withRemote)
  local merged, seen = {}, {}

  if setting("useEditorRecents") then
    for _, p in ipairs(editorRecents(withRemote)) do
      if not seen[keyOf(p)] then
        seen[keyOf(p)] = true
        merged[#merged + 1] = p
      end
    end
  end

  for _, p in ipairs(scanned or {}) do
    if not seen[keyOf(p)] then
      seen[keyOf(p)] = true
      merged[#merged + 1] = p
    end
  end

  return merged
end

-- zoxide first, because it already ranks by frecency and that order is the
-- useful one; ~/.z next; a scan of projectRoots last.
local function scan(done)
  local source = setting("projectSource")
  local requireGit = setting("onlyGitRepos")

  local zoxide = layer.extension("zoxide")
  if zoxide and zoxide.available() and (source == "auto" or source == "zoxide") then
    zoxide.refresh(function(paths)
      done(M.parsePaths(table.concat(paths, "\n"), requireGit))
    end)
    return
  end

  local provider, bin, args = layer.tools.pick("projects", {
    roots = existingRoots(),
    depth = setting("scanDepth"),
    force = source ~= "auto" and source or nil,
  })
  if not provider then return done({}) end

  local task = layer.tools.run(bin, args, function(_, stdout)
    -- "scan" yields .git directories, everything else yields plain paths.
    if provider.parse == "scan" then
      done(M.parseScan(stdout))
    else
      done(M.parsePaths(stdout, requireGit))
    end
  end)
  if not task then done({}) end
end

-- The scan as last answered -- possibly empty on the very first call -- with
-- the editor's recents, which never are.
function M.projects(withRemote)
  if not layer then return {} end
  local scanned = layer.cached("scan#" .. generation, {
    seconds = setting("cacheSeconds"),
    initial = {},
    refresh = scan,
  })
  return withEditorRecents(scanned, withRemote)
end

function M.forget()
  generation = generation + 1
end

----------------------------------------------------------------------

function M.extension(cl)
  layer = cl
  cl.tools.register("find", { "/usr/bin/find" })
  cl.tools.register("zsh", { "/bin/zsh" })

  cl.tools.provide("projects", {
    { name = "z", bin = "zsh", parse = "paths",
      available = function() return hs.fs.attributes(HOME .. "/.z") ~= nil end,
      args = function()
        return { "-c", [[sort -t'|' -k2 -rn "$HOME/.z" 2>/dev/null | cut -d'|' -f1]] }
      end },

    { name = "find", bin = "find", parse = "scan",
      args = function(o)
        local args = {}
        for _, root in ipairs(o.roots or {}) do args[#args + 1] = root end
        if #args == 0 then return nil end   -- nowhere to scan
        for _, extra in ipairs({ "-maxdepth", tostring(o.depth or 3),
                                 "-name", ".git", "-type", "d" }) do
          args[#args + 1] = extra
        end
        return args
      end },
  })

  return {
    name  = "projects",
    rank  = 0.57,
    menus = { "root", "recent" },
    optionalExtensionDependencies = { "vscode", "zoxide", "icons" },

    settings = {
      projectSource = { type = "string", default = "auto", description = "Where projects come from",
                        enum = { "auto", "zoxide", "z", "find" },
                        enumDescriptions = {
                          "Whichever of the others is available, in that order",
                          "Directories you actually visit, ranked by zoxide's frecency",
                          "The older ~/.z database",
                          "A scan of the project roots for .git directories",
                        } },
      -- zoxide tracks every directory you visit, which is broader than
      -- "projects".
      onlyGitRepos = { type = "boolean", default = true,
                       description = "Only directories that are git repositories" },
      projectRoots = { type = "array", default = { "~/projects", "~/work", "~/dev" },
                       description = "Where a scan looks for projects; ~ is your home folder" },
      scanDepth = { type = "integer", default = 3,
                    description = "How deep a scan descends looking for a .git directory" },
      cacheSeconds = { type = "integer", default = 300,
                       description = "How long a project scan is kept, in seconds" },
      useEditorRecents = { type = "boolean", default = true,
                           description = "VS Code's own recent folders ahead of the rest" },
      remoteProjects = { type = "boolean", default = true,
                         description = "VS Code's recent folders on SSH hosts, opened in a remote window" },
      opensWith = { type = "string", default = "editor.open",
                    description = "The command that opens a project, given its path as target" },
    },

    exports = {
      -- Looked up when called, so a replaced projects is the one used.
      projects = function() return M.projects() end,
    },

    items = function(ctx)
      -- The recent picker gets only what you had open in the editor.
      -- zoxide's frecency list runs to hundreds of directories, which would
      -- bury the windows listed after them.
      local list
      local withRemote = cl.setting("projects", "remoteProjects")
      if ctx.activeView == "recent" then
        list = editorRecents(withRemote)
      else
        list = M.projects(withRemote)
      end

      local icons = cl.extension("icons")
      local opensWith = cl.setting("projects", "opensWith")
      local rows = {}
      for _, p in ipairs(list) do
        -- opensWith is given a local path; a remote one opens only as a
        -- remote window.
        rows[#rows + 1] = p.authority and {
          label       = p.name,
          description = "Project on " .. p.host .. " -- " .. p.path,
          command     = "editor.open",
          args        = { target = p.path, remote = p.authority },
          subject     = { kind = "remoteProject", name = p.name, path = p.path, host = p.host,
                          id = p.authority .. p.path },
          iconPath    = "$(remote)",
          ctx         = ctx,
        } or {
          label       = p.name,
          description = "Project -- " .. p.path,
          command     = opensWith,
          args        = { target = p.path },
          subject     = { kind = "project", name = p.name, path = p.path },
          iconPath    = icons and icons.folder(),
          ctx         = ctx,
        }
      end
      return rows
    end,

    -- Open in terminal, in the editor, reveal and copy path are files'
    -- commands, offered on every row with a path.
  }
end

return M
