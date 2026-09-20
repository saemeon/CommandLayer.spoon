-- The log, the clock, and making a folder.

local M = ...

----------------------------------------------------------------------
-- LOG
--
-- One logger for the layer, extensions included (`cl.log`): `e` for
-- something that failed, `w` for a mistake found, `i` and `d` below that.
-- Through hs.logger so every line carries its level and the console
-- filters by it, which a print cannot.
----------------------------------------------------------------------

-- VS Code's names for the levels, and what hs.logger calls each.
M.logLevels = { "off", "trace", "debug", "info", "warning", "error" }
local HS_LEVEL = { off = "nothing", trace = "verbose", debug = "debug",
                   info = "info", warning = "warning", error = "error" }

M.log = hs.logger.new("commandlayer", "warning")
M.logLevel = "warning"

function M.setLogLevel(level)
  if not HS_LEVEL[level] then return false end
  M.log.setLogLevel(HS_LEVEL[level])
  M.logLevel = level
  return true
end

local VERBOSITY = { off = 0, error = 1, warning = 2, info = 3, debug = 4, trace = 5 }

-- Whether a line at this level would be written, so a caller can skip
-- formatting one that would not.
function M.logs(level)
  return (VERBOSITY[level] or 6) <= (VERBOSITY[M.logLevel] or 0)
end

----------------------------------------------------------------------
-- CLOCK
----------------------------------------------------------------------

-- Milliseconds from an arbitrary start. hs.timer.absoluteTime is wall time
-- in nanoseconds; os.clock, where it is missing, is CPU time, which a wait
-- for a process does not count.
function M.clock()
  if hs.timer and hs.timer.absoluteTime then return hs.timer.absoluteTime() / 1e6 end
  return os.clock() * 1000
end

-- A folder and every folder above it, through hs.fs rather than a shell:
-- os.execute blocks, and a path is never interpolated into a command.
function M.makeDirectory(path)
  if type(path) ~= "string" or path == "" then return false end
  local built = path:sub(1, 1) == "/" and "" or "."
  for part in path:gmatch("[^/]+") do
    built = built .. "/" .. part
    if not hs.fs.attributes(built) then
      hs.fs.mkdir(built)
      if not hs.fs.attributes(built) then return false end
    end
  end
  return true
end
