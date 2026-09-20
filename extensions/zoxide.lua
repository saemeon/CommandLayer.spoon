-- CommandLayer.spoon/extensions/zoxide.lua
-- The folders you work in, as zoxide ranks them, and zoxide told about the
-- folders you open here.
--
-- zoxide records a folder when a shell changes into it. Opening one from
-- the launcher changes no shell, so a pick is passed on with `zoxide add`,
-- and the terminal's `z` and this list learn from each other.

local M = {}

local HOME = os.getenv("HOME") or ""

local layer
-- The last list zoxide gave, for whoever hears of a query that failed.
local last = {}
local loading, waiting = false, {}
-- Set when zoxide has counted something since it was last asked.
local dirty = false

function M.available()
  return layer ~= nil and layer.tools.path("zoxide") ~= nil
end

local function settle()
  loading = false
  local callbacks = waiting
  waiting = {}
  for _, callback in ipairs(callbacks) do callback(last) end
end

-- Everyone who asked while zoxide was being asked hears the same answer, so
-- a second caller is never left waiting for a callback.
local function ask(callback)
  if callback then waiting[#waiting + 1] = callback end
  if loading then return end
  local bin = layer and layer.tools.path("zoxide")
  if not bin then return settle() end

  loading = true
  local task = layer.tools.run(bin, { "query", "--list" }, function(code, stdout)
    if code == 0 then
      local list = {}
      for line in tostring(stdout):gmatch("[^\r\n]+") do
        local path = line:gsub("/$", "")
        if path:sub(1, 1) == "/" then list[#list + 1] = path end
      end
      last = list
    end
    settle()
  end)
  if not task then settle() end
end

-- Most frecent first, from the last answer; a stale one is asked again.
local function dirs()
  if not layer then return last end
  return layer.cached("dirs", {
    seconds = dirty and 0 or layer.setting("zoxide", "cacheSeconds"),
    initial = {},
    refresh = function(done)
      dirty = false
      ask(done)
    end,
  })
end

-- Asks zoxide again whatever the cache holds, and `callback` hears the answer.
function M.refresh(callback)
  if callback then waiting[#waiting + 1] = callback end
  dirty = true
  dirs()
  if not layer and callback then settle() end
end

function M.forget()
  last, loading, waiting, dirty = {}, false, {}, false
end

function M.add(path)
  local bin = layer and layer.tools.path("zoxide")
  if not bin or type(path) ~= "string" then return false end
  return layer.tools.run(bin, { "add", path }, function() dirty = true end) ~= nil
end

local function isDirectory(path)
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" then return false end
  local attributes = hs.fs.attributes(path)
  return attributes ~= nil and attributes.mode == "directory"
end

-- The folder a pick went to, if it went to one: the row's own path, or
-- what its command was given -- a folder opened, Open in terminal on a
-- folder row.
function M.folderOf(item)
  if type(item) ~= "table" then return nil end
  local subject = item.subject or {}
  local args = type(item.args) == "table" and item.args or {}
  local candidates = { subject.path, args.target }
  for _, arg in pairs(args) do
    if type(arg) == "table" then candidates[#candidates + 1] = arg.path end
  end
  for i = 1, #candidates do
    if isDirectory(candidates[i]) then return candidates[i] end
  end
  return nil
end

function M.start() M.refresh() end
function M.stop() M.forget() end

function M.extension(cl)
  layer = cl
  cl.tools.register("zoxide", { "/opt/homebrew/bin/zoxide", "/usr/local/bin/zoxide" })

  local function tilde(path)
    if HOME ~= "" and path:sub(1, #HOME) == HOME then return "~" .. path:sub(#HOME + 1) end
    return path
  end

  local function folderRow(ctx, path)
    local icons = cl.extension("icons")
    return {
      label       = path:match("([^/]+)$") or path,
      description = "Folder -- " .. tilde(path),
      command     = "system.open",
      args        = { target = path },
      subject     = { kind = "folder", path = path },
      iconPath    = icons and icons.folder(),
      ctx         = ctx,
    }
  end

  return {
    name        = "zoxide",
    displayName = "zoxide",
    description = "Folders you visit, ranked by zoxide; folders opened here are added to it",
    -- After recent files, which is what `files ` is mostly for.
    after       = { "files" },
    rank        = 0,
    menus       = { "files" },
    optionalExtensionDependencies = { "icons" },

    settings = {
      learn = { type = "boolean", description = "Tell zoxide about folders opened here",
                default = true },
      limit = { type = "integer", default = 15,
                description = "Folders listed in files before anything is typed" },
      searchLimit = { type = "integer", default = 50,
                      description = "The most folders found by typing" },
      cacheSeconds = { type = "integer", default = 60,
                       description = "How long zoxide's list is kept before asking again, in seconds" },
    },

    exports = {
      available = function() return M.available() end,
      refresh   = function(callback) return M.refresh(callback) end,
    },

    items = function(ctx)
      local rows, limit = {}, cl.setting("zoxide", "limit")
      for i, path in ipairs(dirs()) do
        if i > limit then break end
        rows[#rows + 1] = folderRow(ctx, path)
      end
      return rows
    end,

    -- zoxide matches its own keywords, as `z` in a shell does.
    search = function(query, ctx, done)
      local bin = cl.tools.path("zoxide")
      local args = { "query", "--list" }
      for word in query:gmatch("%S+") do args[#args + 1] = word end
      if not bin or #args == 2 then
        done({})
        return
      end

      local limit = cl.setting("zoxide", "searchLimit")
      local task = cl.tools.run(bin, args, function(code, stdout)
        local rows = {}
        for line in tostring(code == 0 and stdout or ""):gmatch("[^\r\n]+") do
          if #rows >= limit then break end
          local path = line:gsub("/$", "")
          if path:sub(1, 1) == "/" then rows[#rows + 1] = folderRow(ctx, path) end
        end
        done(rows)
      end)

      if not task then
        done({})
        return
      end
      return function() task:terminate() end
    end,

    picked = function(item)
      if cl.setting("zoxide", "learn") == false then return end
      local folder = M.folderOf(item)
      if folder then M.add(folder) end
    end,

    -- Opening a folder in the terminal or the editor, revealing it and
    -- copying its path are files' commands, offered on every row with a path.
  }
end

-- Checks for this extension, run by test.lua.

return M
