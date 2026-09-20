-- Resolving binaries, and choosing among providers for a job.

local M = ...

----------------------------------------------------------------------
-- TOOLS
--
-- hs.task runs a non-login shell with no useful PATH, so every binary
-- is resolved to an absolute path.
----------------------------------------------------------------------

local tools = {}

-- Empty: the layer runs nothing of its own. Every binary is registered
-- by the backend, extension or matcher that needs it.
tools.candidates = {}

-- Several files may need the same binary and each says so. The same
-- paths twice are one registration; other paths for a name already
-- registered are a problem, and the first stays -- `tools.paths` is how a
-- person overrides one.
local function samePaths(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

function tools.register(name, candidates)
  if type(name) ~= "string" or type(candidates) ~= "table" then return M end
  local known = tools.candidates[name]
  if not known then
    tools.candidates[name] = candidates
  elseif not samePaths(known, candidates) and M.problem then
    M.problem("tools", ("%q is registered again with other paths; the first stays"):format(name))
  end
  return M
end

-- Force one: tools.paths.code = "/somewhere/else/code"
tools.paths = {}

local resolved = {}

function tools.path(name)
  if tools.paths[name] then return tools.paths[name] end

  local hit = resolved[name]
  if hit ~= nil then
    return hit or nil          -- false means "looked, not there"
  end

  for _, candidate in ipairs(tools.candidates[name] or {}) do
    if hs.fs.attributes(candidate) then
      resolved[name] = candidate
      return candidate
    end
  end

  resolved[name] = false
  return nil
end

-- Drop the cache, so a tool installed since load is picked up.
function tools.forget()
  resolved = {}
end

-- Every task the layer started and that has not exited. A task nobody
-- holds can be collected mid-run, and its callback never comes.
tools.running = {}

-- A child's input is never written into its stdin from here. Writing into a
-- pipe whose reader has gone -- fzf or bc terminated for a newer query --
-- raises SIGPIPE, which Hammerspoon does not ignore, so the whole app dies;
-- and a large input blocks the one thread while the pipe is full. The input
-- goes to a file, and a shell redirects the file into the program. The file,
-- the program and its arguments are positional parameters, so no value is
-- ever read as script.
tools.INPUT_SCRIPT = 'input=$1; shift; exec "$@" < "$input"'

local inputToken = ("%x%x"):format(os.time(), math.random(0, 0xffffff))
local inputCount, inputFolder = 0, nil

-- $TMPDIR is the user's own folder on macOS, so a row label written there is
-- readable by nobody else; os.tmpname makes its file readable by the owner.
local function inputPath()
  if not inputFolder then
    local base = os.getenv("TMPDIR")
    local folder = base and base ~= "" and base:gsub("/$", "") .. "/commandlayer"
    if not folder or not M.makeDirectory(folder) then
      local ok, name = pcall(os.tmpname)
      return ok and name or nil
    end
    inputFolder = folder
  end
  inputCount = inputCount + 1
  return ("%s/input-%s-%d"):format(inputFolder, inputToken, inputCount)
end

local function writeInput(text)
  for _ = 1, 2 do
    local path = inputPath()
    local handle = path and io.open(path, "w")
    if handle then
      local ok = handle:write(text)
      handle:close()
      if ok then return path end
      os.remove(path)
      return nil
    end
    -- The folder may have been cleaned out of $TMPDIR since it was made.
    inputFolder = nil
  end
end

-- hs.task reads a child's output as it arrives only when the task has a
-- streaming callback. With a completion callback alone, a child writing
-- more than the pipe buffer (about 64 KB) blocks on the write, never
-- exits, and the completion never fires -- so every task streams, and
-- `done` is still given the whole output at once.
function tools.run(program, args, done, opts)
  opts = opts or {}
  local out, err, finished = {}, {}, false
  local task
  local input
  if opts.input ~= nil then
    input = writeInput(tostring(opts.input))
    if not input then
      M.log.e("could not write the input for " .. tostring(program))
      return nil
    end
  end
  local stopSpan = M.span("task." .. tostring(program):match("([^/]*)$"))

  local function removeInput()
    if input then
      os.remove(input)
      input = nil
    end
  end

  local function keep(stdout, stderr)
    if type(stdout) == "string" and stdout ~= "" then out[#out + 1] = stdout end
    if type(stderr) == "string" and stderr ~= "" then err[#err + 1] = stderr end
  end

  -- hs.task may stream one last chunk after the completion, with no task;
  -- by then `done` has been told, so it is dropped.
  local function stream(_, stdout, stderr)
    if finished then return false end
    keep(stdout, stderr)
    return true
  end

  local function complete(code, stdout, stderr)
    if finished then return end
    finished = true
    if task then tools.running[task] = nil end
    removeInput()
    stopSpan("exit " .. tostring(code))
    keep(stdout, stderr)
    if done then done(code, table.concat(out), table.concat(err)) end
  end

  local launched, argv = program, args or {}
  if input then
    launched = "/bin/sh"
    argv = { "-c", tools.INPUT_SCRIPT, "sh", input, program, table.unpack(args or {}) }
  end

  task = hs.task.new(launched, complete, stream, argv)
  if not task then
    finished = true
    removeInput()
    return nil
  end

  tools.running[task] = true
  if not task:start() then
    finished = true
    tools.running[task] = nil
    removeInput()
    return nil
  end
  if not input then return task end

  -- A terminated task may never report its end, so the file goes as the
  -- caller terminates it. hs.task's methods want the task itself as self.
  local handle
  handle = setmetatable({}, { __index = function(_, key)
    if key == "terminate" then
      return function()
        removeInput()
        task:terminate()
        return handle
      end
    end
    local value = task[key]
    if type(value) ~= "function" then return value end
    return function(_, ...) return value(task, ...) end
  end })
  return handle
end

-- One login shell, once, for anything the candidate lists missed.
function tools.refresh(callback)
  -- Interpolated into a shell script, so only names that are plainly
  -- names. Every registered one is; this is so none can become syntax.
  local missing = {}
  for name in pairs(tools.candidates) do
    if not tools.path(name) and name:match("^[%w._+-]+$") then
      missing[#missing + 1] = name
    end
  end

  if #missing == 0 then
    if callback then callback({}) end
    return
  end

  local script = "for t in " .. table.concat(missing, " ")
    .. [[; do p=$(whence -p $t 2>/dev/null) && printf '%s\t%s\n' "$t" "$p"; done]]

  -- /bin/zsh rather than a registered candidate: this runs before
  -- anything is resolved, and macOS guarantees the path.
  tools.run("/bin/zsh", { "-lc", script }, function(_, stdout)
    local found = {}
    for line in tostring(stdout):gmatch("[^\r\n]+") do
      local name, path = line:match("^(%S+)\t(.+)$")
      if name and path and hs.fs.attributes(path) then
        resolved[name] = path
        found[name] = path
      end
    end
    if callback then callback(found) end
  end)
end

----------------------------------------------------------------------
-- CAPABILITIES
--
-- An ordered list per job. A provider is usable when its binary resolves
-- and its optional `available(opts)` passes; `args(opts)` returning nil
-- means "not usable for this request" and the chain moves on.
----------------------------------------------------------------------

-- Force one: tools.overrides.editor = "zed". An override that is not
-- installed fails rather than quietly falling back -- a typo should be
-- visible, not silently routed somewhere else.
tools.overrides = {}

-- An ordered chain per capability, contributed by whoever knows how to
-- do the job.
tools.providers = {}

function tools.provide(capability, providers)
  tools.providers[capability] = providers
  return M
end

-- opts.force names one provider for this call, taking precedence over
-- tools.overrides.
function tools.pick(capability, opts)
  opts = opts or {}

  local chain = tools.providers[capability]
  if not chain then return nil end

  local forced = opts.force or tools.overrides[capability]

  -- A provider's hooks are an extension's code, and pick runs on the
  -- picker path: one that throws counts as unavailable rather than
  -- breaking whatever asked.
  local function ask(hook)
    if not hook then return true end
    local ok, value = pcall(hook, opts)
    return ok and value or nil
  end

  for _, provider in ipairs(chain) do
    if not forced or provider.name == forced then
      local bin = tools.path(provider.bin)
      if bin and ask(provider.available) then
        local args = provider.args and ask(provider.args)
        if args or not provider.args then
          return provider, bin, args
        end
      end
    end
  end

  if forced then
    M.log.w(capability .. " forced to '" .. forced
          .. "', which is not available")
  end
  return nil
end

-- What each capability would use right now. Handy from the console.
-- A stand-in request, because a provider whose args() finds nothing to
-- work on declines, and would be reported as missing when it is not.
function tools.report()
  local home = os.getenv("HOME")
  local lines = {}
  for capability in pairs(tools.providers) do
    local provider = tools.pick(capability,
      { query = "x", root = home, dir = home, path = home, roots = { home } })
    lines[#lines + 1] = capability .. ": " .. (provider and provider.name or "none")
  end
  table.sort(lines)
  return table.concat(lines, "\n")
end

M.tools = tools

-- BIN.code is whichever `code` is installed, or the bare name if none.
local BIN = setmetatable({}, {
  __index = function(_, name) return tools.path(name) or name end,
})

M.BIN = BIN
