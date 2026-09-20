-- The layer's log: Hammerspoon's console, and how much reaches it; where
-- the time goes; and the context the layer was entered with.

local M = {}

local function ms(value)
  return type(value) == "number" and tostring(math.floor(value + 0.5)) or "?"
end

-- Long enough to recognise a value, short enough for one line.
local SHORT = 60

-- A value as one line holds it. The clipboard is only ever its length: it
-- can be anything copied, and this list is on screen.
function M.shortValue(key, value)
  if key == "clipboard" then
    return type(value) == "string" and (#value .. " characters") or type(value)
  end
  local kind = type(value)
  -- A list of paths -- finderSelectedFiles -- says what is in it, by name,
  -- rather than only how long it is.
  if kind == "table" and #value > 0 and type(value[1]) == "string" then
    local names = {}
    for i, item in ipairs(value) do names[i] = tostring(item):gsub("/+$", ""):match("[^/]*$") end
    return M.shortValue(nil, ("%d: %s"):format(#value, table.concat(names, ", ")))
  end
  if kind == "table" then
    local n = 0
    for _ in pairs(value) do n = n + 1 end
    return ("table, %d %s"):format(n, n == 1 and "entry" or "entries")
  elseif kind == "string" then
    local line = value:gsub("%s+", " ")
    local length = utf8.len(line)
    if length and length > SHORT then
      line = line:sub(1, utf8.offset(line, SHORT + 1) - 1) .. "…"
    elseif not length and #line > SHORT then
      line = line:sub(1, SHORT) .. "…"
    end
    return line
  elseif kind == "function" or kind == "userdata" then
    return kind
  end
  return tostring(value)
end

-- Through cl.contextKeys, since the context a row carries is a scoped copy
-- and its own keys are only what that scope added.
function M.contextOptions(ctx, keys)
  keys = keys or {}
  local options = {}
  for _, key in ipairs(keys) do
    options[#options + 1] = { label = key, value = key, description = M.shortValue(key, ctx[key]) }
  end
  if #options == 0 then
    options[1] = { label = "No context keys", value = "", description = "No extension captured anything" }
  end
  return options
end

-- Slowest first, by the longest single time: that is the one felt.
function M.performanceOptions(figures)
  local names = {}
  for name in pairs(figures) do names[#names + 1] = name end
  table.sort(names, function(a, b)
    if figures[a].max ~= figures[b].max then return figures[a].max > figures[b].max end
    return a < b
  end)
  local options = {}
  for _, name in ipairs(names) do
    local f = figures[name]
    options[#options + 1] = {
      label = name, value = name,
      description = ("%d× · median %s ms · max %s ms · last %s ms")
                    :format(f.count, ms(f.median), ms(f.max), ms(f.last)),
    }
  end
  if #options == 0 then
    options[1] = { label = "Nothing recorded", value = "",
                   description = "performance.slowMilliseconds 0 records nothing" }
  end
  return options
end

function M.extension(cl)
  return {
    name        = "developer",
    displayName = "Developer",
    description = "Show the log and set how much reaches it, see where the time goes, and inspect the context",
    menus       = {},

    commands = {
      -- The console is where the log already is; nothing is copied out of it.
      { id = "developer.showLogs", title = "Show Logs", category = "Developer", icon = "$(output)",
        menus = { "commandPalette" },
        run = function() hs.openConsole() end },

      -- For this session, as VS Code's command is; the `logLevel` setting is
      -- what outlasts a reload.
      { id = "developer.setLogLevel", title = "Set Log Level…", category = "Developer",
        icon = "$(list-filter)", menus = { "commandPalette" },
        inputs = { {
          id = "level", description = "Log level",
          picker = { options = function()
            local options = {}
            for _, level in ipairs(cl.logLevels) do
              options[#options + 1] = { label = level, value = level,
                                        description = level == cl.logLevel and "Current level" or nil }
            end
            return options
          end },
        } },
        run = function(args) cl.setLogLevel(args.level) end },

      { id = "developer.showPerformance", title = "Show Performance", category = "Developer",
        icon = "$(dashboard)", menus = { "commandPalette" },
        inputs = { {
          id = "name", description = "Slowest first",
          picker = { options = function() return M.performanceOptions(cl.performance()) end },
        } },
        run = function(args)
          local f = cl.performance()[args.name]
          if not f then return end
          hs.alert.show(("%s: %d× · total %s · median %s · p90 %s · max %s · last %s ms"):format(
            args.name, f.count, ms(f.total), ms(f.median), ms(f.p90), ms(f.max), ms(f.last)))
        end },

      { id = "developer.resetPerformance", title = "Reset Performance", category = "Developer",
        icon = "$(clear-all)", menus = { "commandPalette" },
        run = function()
          cl.performance({ reset = true })
          hs.alert.show("Performance figures cleared")
        end },

      -- VS Code's workbench.action.inspectContextKeys: what a when clause or a
      -- template can read right now.
      { id = "developer.inspectContextKeys", title = "Inspect Context Keys", category = "Developer",
        icon = "$(symbol-key)", menus = { "commandPalette" },
        inputs = { {
          id = "key", description = "Context keys",
          picker = { options = function(ctx) return M.contextOptions(ctx, cl.contextKeys(ctx)) end },
        } },
        run = function(args, ctx)
          if args.key == "" or type(ctx) ~= "table" then return end
          hs.alert.show(args.key .. ": " .. M.shortValue(args.key, ctx[args.key]))
        end },
    },
  }
end

return M
