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
    menus = { "commandPalette" },

    settings = {
      commands = { type = "array", default = M.defaultCommands,
                   description = "Raycast deeplinks: { title, url }" },
    },

    commands = {
      { id = "raycast.open", title = "Open in Raycast", menus = {}, run = open },
    },

    exports = { installed = function() return M.installed() end },

    items = function(ctx)
      if not M.installed() then return {} end

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
