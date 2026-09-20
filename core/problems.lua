-- What is wrong in the files a person writes, collected and shown at once.

local M = ...

----------------------------------------------------------------------
-- PROBLEMS
--
-- Collected while the settings and keybindings files are read and shown
-- in one alert at start: a console line is read by nobody, and most silent
-- failures were a typo in one of these files.
----------------------------------------------------------------------

M.problems = {}

local function shortPath(path)
  local home = os.getenv("HOME")
  if home and path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
  return path
end

-- Once per file and message: a file is read more than once during setup.
function M.problem(file, message)
  file = shortPath(tostring(file))
  for _, p in ipairs(M.problems) do
    if p.file == file and p.message == message then return end
  end
  M.problems[#M.problems + 1] = { file = file, message = message }
  M.log.w(file .. ": " .. message)
end

-- What a file said before it was read again: a problem fixed since is gone.
function M.forgetProblems(file)
  file = shortPath(tostring(file))
  for i = #M.problems, 1, -1 do
    if M.problems[i].file == file then table.remove(M.problems, i) end
  end
end

-- A copy, so what is reported cannot be changed by whoever reads it.
function M.getProblems()
  local copy = {}
  for i, p in ipairs(M.problems) do copy[i] = { file = p.file, message = p.message } end
  return copy
end

-- Naming the first few; Show Problems lists them all.
function M.reportProblems()
  local count = #M.problems
  if count == 0 then return false end
  local lines = { ("Command Layer: %d problem%s"):format(count, count == 1 and "" or "s") }
  for i = 1, math.min(count, 3) do
    local p = M.problems[i]
    lines[#lines + 1] = (p.file:match("[^/]+$") or p.file) .. " -- " .. p.message
  end
  if count > 3 then lines[#lines + 1] = "and more: Show Problems lists them all" end
  hs.alert.show(table.concat(lines, "\n"), 8)
  return true
end
