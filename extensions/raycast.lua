-- Raycast, as a destination.
--
-- Get a URL from Raycast with cmd+K -> Copy Deeplink.

local M = {}

M.appPath = "/Applications/Raycast.app"

function M.installed()
  return hs.fs.attributes(M.appPath) ~= nil
end

-- Hand-listed, because Raycast has no way to enumerate its deeplinks.
M.defaultCommands = {
  { title = "Raycast: Clipboard history",
    url   = "raycast://extensions/raycast/clipboard-history/clipboard-history" },
  { title = "Raycast: Search files",
    url   = "raycast://extensions/raycast/file-search/search-files" },
}

-- A script command's header, as Raycast reads it: "# @raycast.title Hello",
-- "// @raycast.title Hello" or "-- @raycast.title Hello" among its first lines.
function M.scriptHeader(text)
  local header = {}
  local n = 0
  for line in tostring(text or ""):gmatch("[^\n]*") do
    n = n + 1
    if n > 40 then break end
    local key, value = line:match("@raycast%.(%w+)%s+(.-)%s*$")
    if key and value ~= "" and header[key] == nil then header[key] = value end
  end
  return header.title and header or nil
end

-- Per folder: when it was last read, and the script commands in it.
local scriptFolders = {}

-- Every script command in the folders named, read again only once a folder
-- changes: { title, name, package, description }.
function M.scripts(folders)
  local out = {}
  for _, folder in ipairs(type(folders) == "table" and folders or {}) do
    local path = tostring(folder):gsub("^~", os.getenv("HOME") or "~")
    local attributes = hs.fs.attributes(path)
    -- Listing it is the check: a path that is not a folder lists nothing.
    if attributes then
      local kept = scriptFolders[path]
      if not kept or kept.stamp ~= attributes.modification then
        kept = { stamp = attributes.modification, scripts = {} }
        local ok, iter, dir = pcall(hs.fs.dir, path)
        for entry in (ok and iter or function() end), dir do
          if entry:sub(1, 1) ~= "." then
            local handle = io.open(path .. "/" .. entry, "r")
            local head = handle and handle:read(4096)
            if handle then handle:close() end
            local header = M.scriptHeader(head)
            if header then
              kept.scripts[#kept.scripts + 1] = { title = header.title, name = entry:gsub("%.[^.]+$", ""),
                package = header.packageName, description = header.description }
            end
          end
        end
        table.sort(kept.scripts, function(a, b) return a.title < b.title end)
        scriptFolders[path] = kept
      end
      for _, script in ipairs(kept.scripts) do out[#out + 1] = script end
    end
  end
  return out
end

function M.extension(cl)
  local function open(args, ctx)
    local url = cl.resolve(args.target, ctx)
    if type(url) ~= "string" or url == "" then return end

    if args.fallbackText then
      local sep = url:find("%?") and "&" or "?"
      url = url .. sep .. "fallbackText="
            .. hs.http.encodeForQuery(cl.resolve(args.fallbackText, ctx))
    end

    hs.urlevent.openURL(url)
  end

  return {
    name  = "raycast",
    rank  = 0.06,
    menus = { "commandPalette", "scripts" },

    settings = {
      commands = { type = "array", default = M.defaultCommands,
                   description = "Raycast deeplinks: { title, url }" },
      scriptDirectories = { type = "array", default = {},
                            description = "The folders of script commands added in Raycast's settings: each "
                                          .. "script is a row in scripts, run through Raycast" },
    },

    commands = {
      { id = "raycast.open", title = "Open in Raycast", menus = {}, run = open },
    },

    exports = { installed = function() return M.installed() end },

    items = function(ctx)
      if not M.installed() then return {} end

      -- In scripts, the script commands alone: Raycast runs them, by name.
      if ctx.activeView == "scripts" then
        local rows = {}
        for _, script in ipairs(M.scripts(cl.setting("raycast", "scriptDirectories"))) do
          rows[#rows + 1] = {
            label       = script.title,
            description = "Raycast script" .. (script.package and (" -- " .. script.package) or ""),
            command     = "raycast.open",
            args        = { target = "raycast://script-commands/" .. script.name },
            ctx         = ctx,
            icon        = "$(file-code)",
          }
        end
        return rows
      end

      local listed = cl.setting("raycast", "commands")
      local rows = {}
      for _, command in ipairs(type(listed) == "table" and listed or M.defaultCommands) do
        if type(command) == "table" and type(command.title) == "string"
           and type(command.url) == "string" then
          rows[#rows + 1] = {
            label       = command.title,
            description = "Raycast",
            command     = "raycast.open",
            args        = { target = command.url },
            ctx         = ctx,
            subject     = { kind = "command", name = command.title },
          }
        end
      end
      return rows
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
