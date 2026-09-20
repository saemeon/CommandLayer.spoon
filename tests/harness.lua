-- CommandLayer.spoon/tests/harness.lua
-- What every suite is given: hs.* stubbed, the log trap, the assertions,
-- and the helpers that drive a layer. test.lua loads it once and hands it
-- to each suite, which makes a kernel of its own with T.layer().

local dir = ...

----------------------------------------------------------------------
-- STUBS
----------------------------------------------------------------------

local function noop() end
local function nilfn() return nil end
local inputFiles = {}

local function popen(cmd)
  local handle = io.popen(cmd)
  if not handle then return "" end
  local out = handle:read("a")
  handle:close()
  return out or ""
end

hs = {
  fs = {
    attributes = function(path)
      local handle = io.open(path, "r")
      if handle then handle:close() return { mode = "file", modification = 0 } end
      -- Directories do not open, so fall back to asking the shell.
      local out = popen(("test -e %q && echo yes"):format(path))
      if out:match("yes") then return { mode = "directory", modification = 0 } end
      return nil
    end,
    mkdir = function(path) return os.execute(("mkdir %q 2>/dev/null"):format(path)) end,
    dir = function(path)
      local out = popen(("ls -1 %q 2>/dev/null"):format(path))
      local names, i = {}, 0
      for line in out:gmatch("[^\n]+") do names[#names + 1] = line end
      return function() i = i + 1 return names[i] end, nil
    end,
    displayName = function(path) return path:match("([^/]+)$") end,
  },

  json = { decode = function() return {} end },

  settings = { get = nilfn, set = noop },
  plist = { read = nilfn },
  pasteboard = { getContents = function() return "" end, setContents = noop },
  alert = { show = noop, closeSpecific = noop },
  timer = { doAfter = function() return { stop = noop } end,
            secondsSinceEpoch = function() return 0 end,
            doEvery = function() return { stop = noop } end },
  -- start answers the task, as hs.task's does when it started. This task
  -- never exits, so the input file tools.run wrote for it is noted, for
  -- test.lua to remove.
  task = { new = function(program, _, _, args)
    if program == "/bin/sh" and type(args) == "table" and args[3] == "sh" then
      inputFiles[#inputFiles + 1] = args[4]
    end
    return { start = function(t) return t end, terminate = noop }
  end },
  execute = function() return "" end,
  osascript = { applescript = function() return false, nil, nil end },
  urlevent = { openURL = noop, bind = noop },
  http = { encodeForQuery = function(s) return (s:gsub(" ", "%%20")) end },
  inspect = tostring,

  -- Pieces kept, so a check can see which part of a title was styled how.
  styledtext = (function()
    local meta = {}
    meta.__index = meta
    meta.__concat = function(a, b)
      local pieces = {}
      for _, p in ipairs(a.pieces) do pieces[#pieces + 1] = p end
      for _, p in ipairs(b.pieces) do pieces[#pieces + 1] = p end
      return setmetatable({ pieces = pieces }, meta)
    end
    return {
      new = function(text, attrs)
        return setmetatable({ pieces = { { text = text, attrs = attrs } } }, meta)
      end,
      defaultFonts = { system = { name = "System", size = 13 },
                       boldSystem = { name = "SystemBold", size = 13 } },
      isStub = meta,
    }
  end)(),

  image = {
    iconForFile = nilfn, iconForFileType = nilfn, imageFromAppBundle = nilfn, imageFromName = nilfn,
    systemImageNames = { ActionTemplate = "action" },
  },

  application = {
    frontmostApplication = function()
      return { name = function() return "Finder" end,
               bundleID = function() return "com.apple.finder" end,
               getMenuItems = function() end }
    end,
    runningApplications = function() return {} end,
    get = nilfn,
    watcher = { new = function() return { start = noop, stop = noop } end,
                activated = 1, terminated = 2 },
    enableSpotlightForNameSearches = noop,
    launchOrFocus = function() return true end,
    launchOrFocusByBundleID = function() return true end,
  },

  spotlight = {
    new = function()
      local q = {}
      function q:queryString() return self end
      function q:callbackMessages() return self end
      function q:setCallback() return self end
      function q:searchScopes() return self end
      function q:sortDescriptors() return self end
      function q:start() return self end
      function q:stop() return self end
      return q
    end,
  },

  -- Never calls back: a check that wants a change notification keeps the
  -- callback of a stub of its own.
  pathwatcher = { new = function() return { start = function(w) return w end, stop = noop } end },

  chooser = {
    new = function(complete)
      local c = { complete = complete }
      local api = { "choices", "placeholderText", "queryChangedCallback",
                    "show", "hide", "query", "bgDark", "fgColor",
                    "subTextColor", "width", "rows", "select",
                    "selectedRow", "selectedRowContents" }
      for _, name in ipairs(api) do c[name] = function() return c end end
      -- Kept, so a check can play the chooser's side: report a pick, or
      -- report its own hide as a dismissal the way the real one does.
      hs.chooser.last = c
      return c
    end,
  },

  hotkey = {
    bind = function() return { delete = noop, enable = noop, disable = noop } end,
    new = function()
      local hk = { delete = noop, disable = noop }
      function hk.enable() return hk end
      return hk
    end,
    modal = { new = function()
      local m = { bind = noop, exits = 0 }
      -- As Hammerspoon's does, entering calls entered() before returning.
      function m.enter(self) if self.entered then self:entered() end end
      -- Counted, so a check can tell whether something closed the layer.
      function m.exit() m.exits = m.exits + 1 end
      hs.hotkey.modal.last = m
      return m
    end },
  },

  keycodes = { map = { a = 0, c = 8, space = 49, ["return"] = 36 } },
  -- A tap that never calls back; a check that presses keys keeps the callback of a stub of its own.
  eventtap = { keyStroke = noop, checkMouseButtons = function() return {} end,
               isSecureInputEnabled = function() return false end,
               new = function() return { start = function(t) return t end, stop = noop } end,
               event = { newSystemKeyEvent = function() return { post = noop } end,
                         types = { keyDown = 10 } } },
  -- No devices, and a watcher that never calls back; a check hands out its own.
  audiodevice = {
    allOutputDevices = function() return {} end, allInputDevices = function() return {} end,
    defaultOutputDevice = nilfn, defaultInputDevice = nilfn, findDeviceByUID = nilfn,
    watcher = { setCallback = noop, start = noop, stop = noop },
  },
  -- Reachable, with SCNetworkReachability's own flag values.
  network = { reachability = {
    flags = { reachable = 2, connectionRequired = 4 },
    internet = function()
      local r = {}
      function r.setCallback(self) return self end
      function r.start(self) return self end
      function r.stop(self) return self end
      function r.status() return 2 end
      return r
    end,
  } },
  host = { localizedName = function() return "Test Mac" end },
  screen = { allScreens = function() return { {} } end },
  -- A table rather than nil, so the window extension's capture can be
  -- seen to have run.
  window = { focusedWindow = function() return {} end, allWindows = function() return {} end,
             orderedWindows = function() return {} end, visibleWindows = function() return {} end },
  -- No element, so nothing asks a real app; a check hands out elements of its own.
  axuielement = { applicationElement = nilfn },
  processInfo = { processID = 1 },
  dialog = { chooseFileOrFolder = nilfn },
}

----------------------------------------------------------------------
-- THE FILE GUARD
--
-- A check, or a broken build of the code under test, can hand a removal or a
-- write the wrong path: a mutation of tools.run once removed a real Homebrew
-- link instead of its input file. While test.lua runs the suites, changing a
-- file outside the temporary folders raises, and each refusal is kept for
-- test.lua to fail the run on, since a pcalled hook would swallow the error.
----------------------------------------------------------------------

local realFiles = { remove = os.remove, rename = os.rename, open = io.open, tmpname = os.tmpname,
                    mkdir = hs.fs.mkdir }
local tempNames, refusals, guarding = {}, {}, false

-- Suites make their folders as os.tmpname() .. "-suffix", so a name handed
-- out is a place, and anything spelled from it is inside.
os.tmpname = function()
  local name = realFiles.tmpname()
  tempNames[#tempNames + 1] = name
  return name
end

local function tempPlaces()
  local places = {}
  local tmpdir = os.getenv("TMPDIR")
  if tmpdir and tmpdir:find("^/.") then places[#places + 1] = tmpdir:gsub("/*$", "/") end
  for _, name in ipairs(tempNames) do places[#places + 1] = name end
  -- /tmp and /var are links to /private's, and a path may be spelled either way.
  for i = 1, #places do
    if places[i]:find("^/tmp/") or places[i]:find("^/var/") then places[#places + 1] = "/private" .. places[i] end
  end
  return places
end

local function mayChange(path)
  if type(path) ~= "string" then return true end
  -- Relative, or climbing out of a place with "..", is outside every place.
  if not path:find("^/") or path:find("/%.%.?/") or path:find("/%.%.?$") then return false end
  for _, place in ipairs(tempPlaces()) do
    if path:sub(1, #place) == place then return true end
  end
  return false
end

local function refuseOutside(path)
  if guarding and not mayChange(path) then
    refusals[#refusals + 1] = tostring(path)
    error("a check tried to change a real file: " .. tostring(path), 3)
  end
end

os.remove = function(path, ...)
  refuseOutside(path)
  return realFiles.remove(path, ...)
end
os.rename = function(from, to, ...)
  refuseOutside(from)
  refuseOutside(to)
  return realFiles.rename(from, to, ...)
end
io.open = function(path, mode, ...)
  if type(mode) == "string" and mode:find("[wa+]") then refuseOutside(path) end
  return realFiles.open(path, mode, ...)
end
hs.fs.mkdir = function(path, ...)
  refuseOutside(path)
  return realFiles.mkdir(path, ...)
end

-- hs.logger's levels as numbers, its refusal of an unknown one, and every
-- line printed whatever the level, so the log trap below sees it. `lastLevel`
-- is which method wrote last.
local LOGGER_LEVELS = { nothing = 0, error = 1, warning = 2, info = 3, debug = 4, verbose = 5 }
hs.logger = { new = function(id, level)
  local logger = { level = LOGGER_LEVELS[level or "warning"] }
  function logger.setLogLevel(name)
    if LOGGER_LEVELS[name] == nil then error("invalid log level", 2) end
    logger.level = LOGGER_LEVELS[name]
  end
  function logger.getLogLevel() return logger.level end
  for method, name in pairs({ e = "error", w = "warning", i = "info", d = "debug", v = "verbose" }) do
    logger[method] = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      logger.lastLevel = name
      print("[" .. id .. "] " .. table.concat(parts, " "))
    end
  end
  return logger
end }

----------------------------------------------------------------------
-- LOG TRAP
--
-- Hooks, backends and presenters are pcalled, so a failing extension is a
-- [commandlayer] log line rather than an error. Right in production and
-- wrong here: every such line from the start is kept, and the last check
-- fails on any that no check caused on purpose.
----------------------------------------------------------------------

local logged = {}
local realPrint = print
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local line = table.concat(parts, " ")
  if line:match("^%[commandlayer%]") then logged[#logged + 1] = line end
  realPrint(...)
end

----------------------------------------------------------------------
-- ASSERTIONS
----------------------------------------------------------------------

local failures, checks = 0, 0

local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print(("  ok   %s"):format(label))
  else
    failures = failures + 1
    print(("  FAIL %s%s"):format(label, detail and ("  -- " .. detail) or ""))
  end
end

-- A value replaced for a check, put back when the next group starts, so a
-- check that forgets to restore one cannot change what later groups see.
local stubbed = {}

local function stub(target, key, value)
  stubbed[#stubbed + 1] = { target = target, key = key, value = target[key] }
  target[key] = value
  return value
end

local function restoreStubs()
  for i = #stubbed, 1, -1 do
    local s = stubbed[i]
    s.target[s.key] = s.value
  end
  stubbed = {}
end

local function group(name)
  restoreStubs()
  print(name)
end
-- The kernel's own source, for the checks that are claims about code
-- rather than behaviour. Every file in core/, whether or not it loads.
local function coreSource(name)
  local handle = io.open(dir .. "core/" .. name .. ".lua")
  if not handle then return nil end
  local src = handle:read("a"); handle:close()
  return src
end

local function coreFiles()
  local names = {}
  local handle = io.popen(("ls %qcore 2>/dev/null"):format(dir))
  for entry in handle:read("a"):gmatch("[^\n]+") do
    local name = entry:match("^(.+)%.lua$")
    if name then names[#names + 1] = name end
  end
  handle:close()
  return names
end

-- Counted rather than asserted: "loading touches nothing" is a claim
-- about I/O, and hs.settings is a file on disk like any other.
local settingsReads = 0
do
  local real = hs.settings.get
  hs.settings.get = function(...)
    settingsReads = settingsReads + 1
    return real(...)
  end
end


-- Never the real ~/.config/commandlayer: a folder there on this machine
-- would change what every check sees.
local NO_USER_DIR = os.tmpname() .. "-no-user-config"

-- Never a real tool: a tool a plugin registers resolves to /fake/<name>, so no
-- check, and no broken build of the code under test, acts on a binary of this
-- machine. A check that needs a real program names it in tools.paths;
-- candidates a check writes itself resolve to nothing, as a tool not installed.
local function fakeTools(kernel)
  local tools = kernel.tools
  local registered = setmetatable({}, { __mode = "k" })
  local register = tools.register
  tools.register = function(name, candidates, ...)
    local answer = register(name, candidates, ...)
    if type(name) == "string" and type(tools.candidates[name]) == "table" then
      registered[tools.candidates[name]] = true
    end
    return answer
  end
  tools.path = function(name)
    if tools.paths[name] then return tools.paths[name] end
    local candidates = tools.candidates[name]
    return candidates ~= nil and registered[candidates] and "/fake/" .. name or nil
  end
end

local function loadKernel()
  local kernel = {}
  assert(loadfile(dir .. "commandlayer.lua"))(kernel)
  fakeTools(kernel)
  -- Still: a span's length would be this machine's speed, and a slow one a
  -- warning the log trap cannot tell from a failure. A check that measures
  -- stubs a clock of its own.
  kernel.clock = function() return 0 end
  return kernel
end

-- The kernel of the suite running, which the helpers below act on.
local cl

-- A shipped ranker's entry, for checks that stub or read what it keeps.
local function rankerEntry(name)
  for _, ranker in ipairs(cl.rankers) do
    if ranker.name == name then return ranker end
  end
end

-- fzf resolves to a fake path here and hs.task never calls back, so a
-- check that needs narrowing to happen keeps only the matcher that needs
-- nothing installed.
local function substringOnly()
  for _, m in ipairs(cl.matchers) do
    if m.name == "substring" then return { m } end
  end
  return {}
end

----------------------------------------------------------------------
-- THE RECORDING PRESENTER
----------------------------------------------------------------------

-- A presenter with no hs.chooser behind it, recording what it is shown.
-- Several checks drive the layer through it, which is also the proof
-- that the kernel needs nothing from hs.chooser to work.
-- The last picker any recording presenter showed or redrew, for a check
-- that cannot hold the picker it opened: the argument picker is made once
-- and reused.
local lastRecorded

local function addRecordingPresenter()
cl.presenter("recording", { create = function(opts)
  local p = { search = true, opts = opts }
  function p.show(state)
    p.placeholder, p.shown, p.row = state.placeholder, state.items, 1
    p.query = state.query
    -- Shown again after a hide, as the chooser is when a view redraws itself.
    p.hidden = false
    lastRecorded = p
  end
  -- New rows put the highlight back at the top, as a presenter that keeps no
  -- selection of its own does; select() is how the kernel keeps one.
  function p.setItems(items, query)
    p.shown, p.shownQuery, p.row = items, query, 1
    lastRecorded = p
  end
  function p.select(i) p.row = i end
  function p.hide(closing) p.hidden, p.closing = true, closing == true end
  function p.selected() return p.shown and p.shown[p.row or 1] end
  function p.move(delta) p.row = (p.row or 1) + delta end
  -- As hs.chooser does: a pick closes the picker it was made in, and only
  -- then reports. A level that stays open has to be shown again.
  function p.accept() p.hidden = true; opts.onPick(p, p.selected()) end
  function p.type(query) opts.onQuery(p, query) end
  function p.dismiss(reason) opts.onPick(p, nil, reason) end
  return p
end })
end

-- Opens a declared view through the recording presenter.
local function openRecorded(name)
  local spec = cl.viewNamed(name)
  spec.presenter, spec.picker = "recording", nil
  cl.open(name)
  return spec.picker
end

local function recordedSpec(name)
  local spec = cl.viewNamed(name)
  spec.presenter, spec.picker = "recording", nil
  return spec
end

local function rowOpening(picker, name)
  for i, item in ipairs(picker.shown or {}) do
    if item.submenu == name then return i, item end
  end
end

local function removeView(name)
  for i, v in ipairs(cl.views) do
    if v.name == name then table.remove(cl.views, i); return end
  end
end

-- A declared picker drawn by the recording presenter, fed by an extension of
-- its own on a menu no other feeds: `rows` a list, or a function of the
-- context giving one; `fields` added to the picker. Returns a function taking
-- both away again.
local function picker(name, rows, fields)
  local extension = "test-feeds-" .. name
  cl.register({ name = extension, menus = { extension }, items = function(ctx)
    if type(rows) == "function" then return rows(ctx) end
    return rows
  end })
  local spec = { name = name, menus = { extension }, presenter = "recording" }
  for k, v in pairs(fields or {}) do spec[k] = v end
  cl.view(spec)
  return function()
    removeView(name)
    cl.unregisterExtension(extension)
  end
end

local function capturingPrint()
  local lines, real = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    lines[#lines + 1] = table.concat(parts, " ")
  end
  return lines, function() print = real end
end

local function rowFor(rows, id)
  for i, row in ipairs(rows or {}) do
    if row.command == id then return row, i end
  end
end

----------------------------------------------------------------------
-- READING THE SOURCE
----------------------------------------------------------------------

local function sourceFiles(folders)
  local out = {}
  for _, folder in ipairs(folders) do
    for name in popen(("ls -1 %q 2>/dev/null"):format(dir .. folder)):gmatch("[^\n]+") do
      if name:match("%.lua$") then out[#out + 1] = folder .. "/" .. name end
    end
  end
  return out
end

local function readSource(path)
  local handle = io.open(dir .. path, "r")
  local text = handle and handle:read("a") or ""
  if handle then handle:close() end
  return text
end

local SOURCE = { "core", "extensions", "presenters", "matchers", "rankers" }

-- A plugin's own code, before its checks, which stub timers and build rows
-- on purpose.
local function pluginCode(folders)
  local out = {}
  for _, path in ipairs(sourceFiles(folders)) do
    local text = readSource(path)
    local at = text:find("\nfunction M%.test")
    out[#out + 1] = { path = path, text = at and text:sub(1, at) or text }
  end
  return out
end

-- Each line without its comment, and whether it declares a local.
local function eachCodeLine(file, fn)
  local n = 0
  for line in (file.text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local code = line:gsub("%-%-.*$", "")
    fn(code, n, code:find("^%s*local%s") ~= nil)
  end
end

-- A field written in a table, or assigned on its own line.
local function writesField(code, name)
  return code:find("^%s*" .. name .. "%s*=%f[^=]") ~= nil
         or code:find("[{,]%s*" .. name .. "%s*=%f[^=]") ~= nil
end

----------------------------------------------------------------------
-- A LAYER PER SUITE
----------------------------------------------------------------------

-- Never the real browser session files, as never the real user folder:
-- the tabs open on this machine would change what checks see, and could
-- land in their output. Nor VS Code's real recent-projects list: its paths
-- would be looked up on this machine -- one in Dropbox makes macOS ask for
-- network-volume access. Nor the extensions installed in the real VS Code,
-- nor the hosts in the real ssh config.
local function guard(kernel)
  if kernel.modules.ssh then
    kernel.modules.ssh.configPath = NO_USER_DIR .. "/ssh_config"
    kernel.modules.ssh.forget()
  end
  if kernel.modules.browser then
    kernel.modules.browser.sessionDir = function() return nil end
  end
  if kernel.modules.vscode then
    kernel.modules.vscode.storagePath = NO_USER_DIR
    kernel.modules.vscode.menubarPath = NO_USER_DIR .. "/storage.json"
    if kernel.modules.vscode.forget then kernel.modules.vscode.forget() end
  end
  if kernel.modules.vscodebridge then
    kernel.modules.vscodebridge.extensionsPath = NO_USER_DIR
  end
end

local T = {
  check = check, stub = stub, group = group, restoreStubs = restoreStubs,
  noop = noop, nilfn = nilfn, popen = popen, dir = dir, NO_USER_DIR = NO_USER_DIR, inputFiles = inputFiles,
  logged = logged, coreSource = coreSource, coreFiles = coreFiles, loadKernel = loadKernel,
  rankerEntry = rankerEntry, substringOnly = substringOnly, openRecorded = openRecorded,
  recordedSpec = recordedSpec, rowOpening = rowOpening, removeView = removeView, picker = picker,
  capturingPrint = capturingPrint, rowFor = rowFor,
  sourceFiles = sourceFiles, readSource = readSource, SOURCE = SOURCE,
  pluginCode = pluginCode, eachCodeLine = eachCodeLine, writesField = writesField,
  -- Each kernel a suite made, and which suite made it.
  kernels = {},
}

-- The context most checks resolve and gather against: Finder in front, a
-- file selected, something copied.
function T.context()
  return { finderSelection = "/tmp/a.txt", clipboard = "x", frontmostApp = "Finder" }
end

-- The file guard, switched on by test.lua for the suites and given back at the
-- end; `lua tests/reference.lua` loads the harness to write the generated files,
-- and never switches it on. A check that makes the guard refuse on purpose
-- takes its refusal back with forgetRefusal.
function T.guardFiles() guarding = true end
function T.refusals() return refusals end
function T.forgetRefusal(path)
  for i = #refusals, 1, -1 do
    if refusals[i] == path then table.remove(refusals, i); return true end
  end
  return false
end
function T.releaseFiles()
  guarding = false
  os.remove, os.rename, io.open, os.tmpname = realFiles.remove, realFiles.rename, realFiles.open, realFiles.tmpname
  hs.fs.mkdir = realFiles.mkdir
end

-- hs.hotkey.new's own reading of its arguments after mods and key: a nil or
-- a function where the message goes means there is no message, and the
-- rest shift down one. A stub recording hotkeys reads them the same way.
function T.hotkeyFunctions(message, pressedfn, releasedfn, repeatfn)
  if message == nil or type(message) == "function" then
    pressedfn, releasedfn, repeatfn = message, pressedfn, releasedfn
  end
  return pressedfn, releasedfn, repeatfn
end

function T.settingsReads() return settingsReads end
function T.counts() return checks, failures end
function T.lastRecorded() return lastRecorded end

-- A kernel set up and made the one the helpers act on. A suite that must
-- look at a kernel before setup loads one itself and adopts it after.
function T.adopt(kernel)
  guard(kernel)
  cl = kernel
  addRecordingPresenter()
  T.cl = kernel
  T.kernels[#T.kernels + 1] = { kernel = kernel, suite = T.suite }
  return kernel
end

-- A kernel set up on no user folder, or, given `settings` -- a table or a
-- function of the kernel giving one -- on a settings.json saying that, in a
-- folder gone again once setup has read it.
function T.setup(kernel, settings)
  kernel.userDir = NO_USER_DIR
  local folder
  if type(settings) == "function" then settings = settings(kernel) end
  if type(settings) == "table" then
    folder = os.tmpname() .. "-layer"
    os.execute(("mkdir -p %q"):format(folder))
    local handle = assert(io.open(folder .. "/settings.json", "w"))
    handle:write(kernel.encodeJSON(settings))
    handle:close()
    kernel.userDir = folder
  end
  kernel.setup()
  if folder then os.execute(("rm -rf %q"):format(folder)) end
  return kernel
end

function T.layer(settings)
  local kernel = loadKernel()
  -- Taken now, before another kernel makes a modal of its own.
  T.layerModal = hs.hotkey.modal.last
  return T.adopt(T.setup(kernel, settings))
end

-- For T.layer: every extension the defaults switch off, switched on, so a
-- check over every shipped extension sees them all.
function T.everyExtensionOn(kernel)
  local defaults = kernel.decodeJSONC(kernel.readText(kernel.SPOON_DIR .. "config/defaults.jsonc") or "")
  local on = {}
  for key, value in pairs(type(defaults) == "table" and defaults or {}) do
    if type(key) == "string" and key:match("%.enabled$") and value == false then on[key] = true end
  end
  return on
end

return T
