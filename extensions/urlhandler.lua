-- hammerspoon://commandlayer?command=<id>&args=<JSON object> runs a command,
-- so Stream Deck, Karabiner or Shortcuts can reach one. Any web page can
-- open such a URL, so only the ids urlhandler.allowedCommands lists run.

local M = {}

M.event = "commandlayer"

local layer

local function refuse(message)
  hs.alert.show("Command Layer: " .. message)
  layer.log.w("hammerspoon://" .. M.event .. " refused: " .. message)
end

-- `params` as hs.urlevent gives them: the query's fields, already decoded.
function M.handle(params)
  if not layer then return end
  params = type(params) == "table" and params or {}
  local id = params.command
  if type(id) ~= "string" or id == "" then return refuse("the URL names no command") end

  local allowed = false
  local listed = layer.setting("urlhandler", "allowedCommands")
  for _, entry in ipairs(type(listed) == "table" and listed or {}) do
    if entry == id then allowed = true end
  end
  if not allowed then return refuse(id .. " is not in urlhandler.allowedCommands") end

  local args = {}
  if params.args ~= nil and params.args ~= "" then
    local ok, decoded = pcall(hs.json.decode, params.args)
    -- A list decodes to a table too; one with elements is not an object.
    if not ok or type(decoded) ~= "table" or #decoded > 0 then
      return refuse("the args for " .. id .. " are not a JSON object")
    end
    args = decoded
  end
  return layer.executeCommand(id, args)
end

function M.start()
  if not layer or M.binding then return M end
  M.binding = layer.watch({
    start = function() hs.urlevent.bind(M.event, function(_, params) M.handle(params) end) end,
    stop  = function() hs.urlevent.bind(M.event, nil) end,
  })
  return M
end

function M.stop()
  if M.binding then M.binding.dispose() end
  M.binding = nil
  return M
end

function M.extension(cl)
  layer = cl
  return {
    name        = "urlhandler",
    displayName = "URL Handler",
    description = "Run a command from a hammerspoon://commandlayer URL",
    menus       = {},

    settings = {
      allowedCommands = { type = "array", default = {},
        description = "The command ids a hammerspoon://commandlayer?command=<id>&args=<JSON> URL may run; "
                   .. "any web page can open such a URL" },
    },
  }
end

return M
