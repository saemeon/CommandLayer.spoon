-- The processes running, busiest first, as ps lists them: a live picker,
-- read again every few seconds while it is open and never otherwise, with
-- Quit and Force quit on cmd+k, through kill.

local M = {}

M.limit = 50
M.seconds = 2

local list = {}
local reading, ticking

-- "  98043  45.1 392848 /Applications/…/Code Helper (Renderer)" -> one entry
-- per line, its name the program's last path part, busiest first.
function M.parse(stdout)
  local out = {}
  for line in tostring(stdout or ""):gmatch("[^\n]+") do
    local pid, cpu, rss, command = line:match("^%s*(%d+)%s+([%d%.]+)%s+(%d+)%s+(.+)$")
    if pid then
      out[#out + 1] = { pid = tonumber(pid), cpu = tonumber(cpu) or 0, mb = math.floor((tonumber(rss) or 0) / 1024),
                        name = command:match("([^/]+)$") or command }
    end
  end
  table.sort(out, function(a, b) return a.cpu > b.cpu end)
  return out
end

function M.forget()
  list, reading = {}, nil
  if ticking then ticking.dispose() end
  ticking = nil
end

function M.extension(cl)
  cl.tools.register("ps", { "/bin/ps" })
  cl.tools.register("kill", { "/bin/kill" })

  local function read()
    local ps = cl.tools.path("ps")
    if not ps or reading then return end
    reading = cl.tools.run(ps, { "-Ao", "pid=,pcpu=,rss=,comm=" }, function(code, stdout)
      reading = nil
      if code ~= 0 then return end
      list = M.parse(stdout)
      cl.refresh()
    end)
  end

  local function signal(process, which)
    local kill = cl.tools.path("kill")
    if type(process) ~= "table" or not process.pid or not kill then return end
    cl.tools.run(kill, { which, tostring(process.pid) }, function(code, _, stderr)
      if code ~= 0 then
        hs.alert.show(("Could not quit %s: %s"):format(process.name, tostring(stderr):match("[^\n]*")))
      end
    end)
  end

  local takesProcess = { id = "process", description = "Which process", picker = { when = "viewItem == 'process'" } }

  return {
    name        = "processes",
    displayName = "Processes",
    description = "The processes running, busiest first, updated while the picker is open; Quit and Force quit",
    menus       = { "processes" },
    viewItems   = { "process" },

    items = function(ctx)
      -- Open: read now, then every few seconds until the picker is left.
      if not ticking then
        read()
        ticking = cl.every(M.seconds, read)
      end
      local rows = {}
      for i = 1, math.min(#list, M.limit) do
        local p = list[i]
        rows[#rows + 1] = {
          label = p.name, ctx = ctx, icon = "$(pulse)",
          description = ("%.1f%% CPU · %d MB · pid %d"):format(p.cpu, p.mb, p.pid),
          subject = { kind = "process", id = p.pid, pid = p.pid, name = p.name },
        }
      end
      return rows
    end,

    left = function()
      if ticking then ticking.dispose() end
      ticking = nil
    end,

    commands = {
      { id = "processes.quit", title = "Quit", category = "Process", icon = "$(close)",
        menus = { ["view/item/context"] = true }, inputs = { takesProcess },
        run = function(args) signal(args.process, "-TERM") end },
      { id = "processes.forceQuit", title = "Force quit", category = "Process", icon = "$(error)",
        menus = { ["view/item/context"] = true }, inputs = { takesProcess },
        targetName = "${input:process.name}",
        confirm = function(args)
          local name = type(args.process) == "table" and args.process.name or "this process"
          return "Force quit " .. name .. "? Anything unsaved in it is lost."
        end,
        run = function(args) signal(args.process, "-KILL") end },
    },
  }
end

return M
