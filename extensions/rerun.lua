-- A command run again with the arguments it had: Git: Checkout… on the same
-- branch, a window layout on the same window, without answering again.

local M = {}

-- What was picked, latest first: the command and the arguments it ran with.
-- In memory only: arguments may hold a window or an app object, which
-- nothing outside the layer could keep, so a reload starts it empty.
M.recent = {}
M.limit = 20

-- What picking these does to the picker itself, not to the world, and the
-- extension's own commands: running either again is never what was meant.
local function replayable(command)
  return type(command) == "string" and not command:find("^quickOpen") and not command:find("^rerun%.")
end

-- An argument as a line can show it: a subject by its name, text as it is.
local function shown(value)
  if type(value) == "table" then
    return value.label or value.name or value.title or (value.path and value.path:match("[^/]+/?$")) or value.value
  end
  if type(value) == "string" or type(value) == "number" then return tostring(value) end
  return nil
end

local function summary(args)
  local parts = {}
  local keys = {}
  for key in pairs(type(args) == "table" and args or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local text = shown(args[key])
    if text and text ~= "" then parts[#parts + 1] = tostring(text) end
  end
  return table.concat(parts, " · ")
end

local function copyArgs(args)
  local copy = {}
  for k, v in pairs(type(args) == "table" and args or {}) do copy[k] = v end
  return copy
end

-- The same command with the same arguments is moved to the front, not kept twice.
function M.record(item)
  if type(item) ~= "table" or not replayable(item.command) then return end
  local entry = { command = item.command, args = copyArgs(item.args), label = tostring(item.label or item.command) }
  entry.key = entry.command .. "\0" .. summary(entry.args)
  for i, kept in ipairs(M.recent) do
    if kept.key == entry.key then
      table.remove(M.recent, i)
      break
    end
  end
  table.insert(M.recent, 1, entry)
  while #M.recent > M.limit do table.remove(M.recent) end
end

function M.extension(cl)
  local function rerun(entry, ctx)
    if not entry then
      hs.alert.show("Nothing has been run yet")
      return
    end
    cl.executeCommand(entry.command, copyArgs(entry.args), ctx)
  end

  return {
    name        = "rerun",
    displayName = "Rerun",
    description = "Run a command picked before again, with the arguments it had",
    menus       = {},

    picked = function(item) M.record(item) end,

    commands = {
      { id = "rerun.last", title = "Rerun last command", category = "Command", icon = "$(debug-rerun)",
        menus = { "commandPalette" },
        run = function(_, ctx) rerun(M.recent[1], ctx) end },

      { id = "rerun.recent", title = "Rerun a recent command…", category = "Command", icon = "$(history)",
        menus = { "commandPalette" },
        inputs = { {
          id = "entry", description = "Run again",
          picker = { options = function()
            local rows = {}
            for _, entry in ipairs(M.recent) do
              local args = summary(entry.args)
              rows[#rows + 1] = { label = entry.label, description = args ~= "" and args or nil, value = entry }
            end
            if #rows == 0 then
              rows[1] = { label = "Nothing has been run yet", enabled = false, value = false }
            end
            return rows
          end },
        } },
        run = function(args, ctx)
          if type(args.entry) == "table" then rerun(args.entry, ctx) end
        end },
    },
  }
end

return M
