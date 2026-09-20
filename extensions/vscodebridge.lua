-- What only VS Code with the Command Layer extension installed answers
-- (vscode/command-layer-extension in this repository). Switching this
-- extension on says that extension is installed, so its rows are always
-- there; a stock VS Code is vscode.lua's.

local M = {}

-- publisher.name from the extension's package.json, the authority of its URIs.
M.identifier = "saemeon.command-layer"

M.extensionsPath = (os.getenv("HOME") or "") .. "/.vscode/extensions"

M.vscodeBundleID = "com.microsoft.VSCode"

M.NOT_INSTALLED = "VS Code bridge not installed: install vscode/command-layer-extension "
                  .. "(Developer: Install Extension from Location…)"

-- Read when a bridge command runs, never on an open. "Install Extension from
-- Location…" lists the extension in extensions.json without copying it into
-- the folder; an install that copies, or a symlink, is a folder there. A list
-- missing or not JSON names nothing.
function M.installed()
  local handle = io.open(M.extensionsPath .. "/extensions.json", "r")
  if handle then
    local text = handle:read("a")
    handle:close()
    local ok, entries = pcall(hs.json.decode, text or "")
    for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
      local identifier = type(entry) == "table" and entry.identifier
      local id = type(identifier) == "table" and identifier.id
      if type(id) == "string" and id:lower() == M.identifier then return true end
    end
  end
  local ok, names, dir = pcall(hs.fs.dir, M.extensionsPath)
  if not ok or type(names) ~= "function" then return false end
  for name in names, dir do
    if name == M.identifier or name:sub(1, #M.identifier + 1) == M.identifier .. "-" then return true end
  end
  return false
end

-- Why a link would reach nothing, or nil.
function M.missing()
  local find = hs.application.pathForBundleID
  if not (find and find(M.vscodeBundleID)) then return "VS Code is not installed" end
  if not M.installed() then return M.NOT_INSTALLED end
  return nil
end

-- Unreserved characters only, so a value is one query parameter whatever
-- it holds, and no ${...} is left in it for a template to fill.
local function encode(text)
  return (tostring(text):gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

-- The extension's URI handler: ?task=<label>, or ?command=<id> with args a
-- JSON array encoded twice, since VS Code decodes the query once before the
-- handler reads it.
function M.url(spec)
  local base = "vscode://" .. M.identifier .. "/run?"
  if spec.task then return base .. "task=" .. encode(spec.task) end
  local url = base .. "command=" .. encode(spec.command)
  if type(spec.args) == "table" and next(spec.args) ~= nil then
    url = url .. "&args=" .. encode(encode(hs.json.encode(spec.args)))
  end
  return url
end

local function text(value)
  value = type(value) == "string" and value:match("^%s*(.-)%s*$") or nil
  return value ~= "" and value or nil
end

function M.extension(cl)
  -- Every string in args is a template, filled here as the command that
  -- finally runs fills its own.
  local function filled(value, ctx)
    if type(value) == "string" then return cl.resolve(value, ctx) end
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = filled(v, ctx) end
    return copy
  end

  return {
    name        = "vscodebridge",
    displayName = "VS Code bridge",
    description = "Commands answered by the Command Layer extension in VS Code; switch this on once it is installed",
    rank        = 0.14,
    menus       = {},

    commands = {
      -- The allowlists are the extension's: commandLayer.uriHandler.allowedCommands
      -- and allowedTasks in VS Code's settings. A refusal is VS Code's message.
      -- A link nothing would answer is said here instead of sent.
      { id = "vscodebridge.run", title = "Run in VS Code", menus = {},
        run = function(args, ctx)
          local task = text(cl.resolve(args.task, ctx))
          local command = text(cl.resolve(args.command, ctx))
          if not (task or command) then return end
          local why = M.missing()
          if why then
            hs.alert.show(why)
            return
          end
          local url = M.url({ task = task, command = command, args = filled(args.args, ctx) })
          return cl.executeCommand("system.open", { target = url, title = "the VS Code bridge's link" }, ctx)
        end },

      { id = "vscodebridge.findInFiles", title = "Find in files for “${query}”", category = "VS Code",
        icon = "$(search)", menus = { "root", "commandPalette" },
        inputs = { { id = "query", description = "Text to find in VS Code's workspace",
                     picker = { typed = true }, fromQuery = true } },
        command = "vscodebridge.run",
        args = { command = "workbench.action.findInFiles",
                 args = { { query = "${input:query}", triggerSearch = true } } } },

      { id = "vscodebridge.quickOpen", title = "Go to file “${query}”", category = "VS Code",
        icon = "$(go-to-file)", menus = { "root", "commandPalette" },
        inputs = { { id = "query", description = "File name to look for in VS Code",
                     picker = { typed = true }, fromQuery = true } },
        command = "vscodebridge.run",
        args = { command = "workbench.action.quickOpen", args = { "${input:query}" } } },

      { id = "vscodebridge.runTask", title = "Run task…", category = "VS Code",
        icon = "$(run)", menus = { "commandPalette" },
        -- Not named task: the args' own task would stand in for the answer.
        inputs = { { id = "label", description = "Task, as Run Task names it", picker = { typed = true } } },
        command = "vscodebridge.run", args = { task = "${input:label}" } },

      { id = "vscodebridge.runCommand", title = "Run command…", category = "VS Code",
        icon = "$(terminal-cmd)", menus = { "commandPalette" },
        inputs = { { id = "vscodeCommand", picker = { typed = true }, pattern = "^[%w_%.%-]+$",
                     description = "Command id, such as workbench.action.toggleZenMode" } },
        command = "vscodebridge.run", args = { command = "${input:vscodeCommand}" } },
    },
  }
end

return M
