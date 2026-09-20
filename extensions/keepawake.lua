-- Keeping the Mac awake is macOS's own caffeinate, run in a task this
-- extension holds, and what else is keeping it awake is pmset's to say.

local M = {}

-- -d keeps the display awake, -i the machine; -t ends it after that many
-- seconds, as caffeinate itself counts.
function M.args(minutes, display)
  local args = { display ~= false and "-di" or "-i" }
  if type(minutes) == "number" and minutes > 0 then
    args[#args + 1] = "-t"
    args[#args + 1] = tostring(math.floor(minutes * 60))
  end
  return args
end

-- The processes holding an assertion that keeps the machine or its display
-- awake, once each, in the order pmset lists them: one per line, the
-- process named in parentheses after its pid.
function M.holders(text)
  local names, seen = {}, {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local name, kind = line:match("pid %d+%(([^)]+)%):.-(Prevent%w+)")
    if name and not seen[name] then
      seen[name] = true
      names[#names + 1] = name .. " (" .. kind .. ")"
    end
  end
  return names
end

function M.extension(cl)
  cl.tools.register("caffeinate", { "/usr/bin/caffeinate" })
  cl.tools.register("pmset", { "/usr/bin/pmset" })

  -- One caffeinate at a time: a new request replaces the one running, so
  -- "for an hour" after "until I say" means an hour.
  local running

  local function stop()
    local task = running
    running = nil
    cl.setContext("keepAwake", nil)
    if task then pcall(function() task:terminate() end) end
  end
  -- The task is held through tools.run and ended with the extension anyway;
  -- this forgets it too, so a start after a stop does not think it runs.
  M.stop = stop

  local function start(minutes)
    local caffeinate = cl.tools.path("caffeinate")
    if not caffeinate then
      hs.alert.show("caffeinate not found")
      return
    end
    stop()
    local task
    task = cl.tools.run(caffeinate, M.args(minutes, cl.setting("keepawake", "display")), function()
      -- Its time ran out, or it was stopped: only the one still running says so.
      if running == task then
        running = nil
        cl.setContext("keepAwake", nil)
      end
    end)
    if not task then
      hs.alert.show("Could not start caffeinate")
      return
    end
    running = task
    cl.setContext("keepAwake", true)
    hs.alert.show(minutes and ("Keeping awake for " .. minutes .. " minutes") or "Keeping awake")
  end

  local function durations()
    local options = {}
    for _, minutes in ipairs(cl.setting("keepawake", "durations") or {}) do
      if type(minutes) == "number" and minutes > 0 then
        options[#options + 1] = { label = minutes >= 60 and minutes % 60 == 0
                                    and ((minutes // 60) .. (minutes == 60 and " hour" or " hours"))
                                    or (minutes .. " minutes"),
                                  value = minutes }
      end
    end
    return options
  end

  return {
    displayName = "Keep Awake",
    description = "Keep the Mac awake through caffeinate, and say what else is keeping it awake",
    menus       = {},

    settings = {
      durations = { type = "array", default = { 15, 60, 120 },
                    description = "The minutes Keep awake for… offers" },
      display = { type = "boolean", default = true,
                  description = "Keep the display awake too, not only the machine" },
    },

    commands = {
      { id = "keepawake.on", title = "Keep awake", category = "Keep Awake", icon = "$(eye)",
        menus = { "root", "commandPalette" }, when = "!keepAwake",
        run = function() start(nil) end },
      { id = "keepawake.for", title = "Keep awake for…", category = "Keep Awake", icon = "$(watch)",
        menus = { "root", "commandPalette" },
        inputs = { { id = "minutes", description = "Keep awake for", picker = { options = durations } } },
        run = function(args) start(tonumber(args.minutes)) end },
      { id = "keepawake.off", title = "Allow sleep", category = "Keep Awake", icon = "$(eye-closed)",
        menus = { "root", "commandPalette" }, when = "keepAwake",
        run = function()
          stop()
          hs.alert.show("Sleep allowed again")
        end },
      -- pmset lists the assertions every process holds; the ones that keep
      -- the machine or its display awake are named, so a Mac that will not
      -- sleep says why.
      { id = "keepawake.holders", title = "What is keeping it awake", category = "Keep Awake",
        icon = "$(question)", menus = { "commandPalette" },
        run = function()
          local pmset = cl.tools.path("pmset")
          if not pmset then return hs.alert.show("pmset not found") end
          cl.tools.run(pmset, { "-g", "assertions" }, function(code, stdout)
            local names = code == 0 and M.holders(stdout) or {}
            hs.alert.show(#names == 0 and "Nothing is keeping it awake"
                          or ("Kept awake by " .. table.concat(names, ", ")), 6)
          end)
        end },
    },
  }
end

return M
