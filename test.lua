-- CommandLayer.spoon/test.lua
-- Run with:  lua test.lua        (from this directory)
--
-- `luac -p` proves a file parses, which has never been the failure
-- worth catching: nil-indexing, wrong hs.* arguments and malformed
-- Spotlight predicates all parse cleanly.
--
-- So tests/harness.lua stubs enough of hs.* to load the layer outside
-- Hammerspoon, and the suites in tests/ exercise the parts that are pure
-- logic -- gathering rows, finding an item's verbs, resolving templates,
-- keying subjects. It cannot test anything that actually talks to macOS,
-- and does not pretend to.
--
-- Every file in tests/ is a suite, and every file in tests/extensions/ one
-- extension's checks; each makes a kernel of its own, so no suite sees what
-- another left behind.

local dir = arg and arg[0] and arg[0]:match("(.*/)") or "./"
local T = assert(loadfile(dir .. "tests/harness.lua"))(dir)
local check, group = T.check, T.group

-- What is given to the suites, what runs luacheck and what writes the
-- generated files are not suites.
local NOT_SUITES = { harness = true, luacheck = true, reference = true }

local function luaFiles(folder)
  local out = {}
  for name in T.popen(("ls -1 %q 2>/dev/null"):format(dir .. folder)):gmatch("[^\n]+") do
    local base = name:match("^(.+)%.lua$")
    if base and not NOT_SUITES[base] then out[#out + 1] = base end
  end
  table.sort(out)
  return out
end

-- A suite that throws is one failing check, and the rest still run.
local function run(path, label)
  T.restoreStubs()
  T.suite = label
  print()
  print("== " .. label)
  local chunk, err = loadfile(dir .. path)
  local ok = chunk ~= nil
  if chunk then ok, err = pcall(chunk, T) end
  if not ok then check(label .. " ran to the end", false, tostring(err)) end
end

local suites, extensionSuites = luaFiles("tests"), luaFiles("tests/extensions")
T.guardFiles()
for _, name in ipairs(suites) do run("tests/" .. name .. ".lua", name) end
for _, name in ipairs(extensionSuites) do
  run("tests/extensions/" .. name .. ".lua", "extensions/" .. name)
end

T.restoreStubs()
print()
group("the suites")

check("each suite runs on a kernel of its own", (function()
        local madeBy, shared = {}, {}
        for _, entry in ipairs(T.kernels) do
          local earlier = madeBy[entry.kernel]
          if earlier and earlier ~= entry.suite then shared[#shared + 1] = earlier .. " and " .. entry.suite end
          madeBy[entry.kernel] = madeBy[entry.kernel] or entry.suite
        end
        return #T.kernels >= #suites + #extensionSuites and #shared == 0,
               #T.kernels .. " kernels; " .. table.concat(shared, ", ")
      end)())

check("an extension's checks are in tests/extensions/, named for one that ships", (function()
        local stray = {}
        for _, name in ipairs(extensionSuites) do
          if T.readSource("extensions/" .. name .. ".lua") == "" then stray[#stray + 1] = name end
        end
        return #extensionSuites > 0 and #stray == 0, table.concat(stray, " ")
      end)())

check("no shipped plugin carries checks of its own", (function()
        local found = {}
        for _, path in ipairs(T.sourceFiles(T.SOURCE)) do
          if T.readSource(path):find("\nfunction M%.test%f[^%w_]") then found[#found + 1] = path end
        end
        return #found == 0, table.concat(found, ", ")
      end)())

----------------------------------------------------------------------
-- THE MACHINE
--
-- No check resolves a real tool or changes a real file: a broken build under
-- test once removed a real Homebrew link through a tool's real path.
----------------------------------------------------------------------

group("the machine")
T.suite = "the machine"

check("a tool a plugin registers resolves to a fake path, never one on this machine", (function()
        local layer = T.layer()
        local fzf = layer.tools.path("fzf")
        layer.tools.paths.fzf = "/bin/echo"
        local stubbed = layer.tools.path("fzf")
        layer.tools.paths.fzf = nil
        return fzf == "/fake/fzf" and stubbed == "/bin/echo", tostring(fzf) .. " / " .. tostring(stubbed)
      end)())

-- Every path refused here is in a folder that does not exist, so a guard that
-- fails to refuse still changes nothing.
do
  local outside = "/opt/does-not-exist-g7k"
  local removed, removeErr = pcall(os.remove, outside)
  local removeRefused = T.forgetRefusal(outside)
  local written = outside .. "/file"
  local opened, openErr = pcall(io.open, written, "w")
  local openRefused = T.forgetRefusal(written)
  check("removing or writing a file outside the temporary folders raises, naming it", (function()
          return not removed and not opened and removeRefused and openRefused
                 and tostring(removeErr):find("a check tried to change a real file: " .. outside, 1, true) ~= nil
                 and tostring(openErr):find(written, 1, true) ~= nil,
                 tostring(removeErr) .. " / " .. tostring(openErr)
        end)())
  local inside = os.tmpname() .. "-guard"
  local handle = io.open(inside, "w")
  if handle then handle:close() end
  local climbing = inside .. "-missing/../../../opt/does-not-exist-g7k/file"
  check("inside them it is allowed, and climbing out of one with .. is not", handle ~= nil
        and os.remove(inside) == true and pcall(io.open, climbing, "w") == false and T.forgetRefusal(climbing))
end

check("no check tried to change a real file", #T.refusals() == 0, table.concat(T.refusals(), " | "))

----------------------------------------------------------------------
-- LOG
----------------------------------------------------------------------

-- Lines the checks cause on purpose. Anything else is a hook, backend or
-- presenter that failed quietly.
local expectedLogs = {
  "%-problems/", "%-problems%-broken/", "%-profile/", -- files the settings checks write
  "%-keys/",                                          -- the keybindings checks' file
  "%-keywrites",                                      -- the keybinding writes' folders
  "%-globalkeys/", "keybindings: no global keybinding runs quickOpen",  -- the global keys' checks
  "key hyper%+7 %-> test%.first",                      -- a press explained at debug
  '"open" is not a hotkey',
  "%-reload/", "%-workbench/",                        -- the reload checks' files
  "no%-such%-presenter", "no command named 'no%.such",
  "'test%-picked%-loud' picked", 'extension test%-ns: command "other%.bad" is outside',
  'when clause "a &&" does not parse',
  '"test%-tool" is registered again',
  "command 'test%.boom' %-> ", "'test%-loglevel' items",
  "asking Brave Browser for its tabs failed",         -- the browser's refusal fixture
  "extension apitest: ", "extension 'apitest' timer %-> ",  -- the plugin API's checks
  "'test%.circleA' leads back to itself",
  "before and after lead in a circle: test%-circle",
  "%-schema/", "extension badspec: ", "picker badview: ",  -- the schema's checks
  "%-sites/",                                         -- the browser's site files with mistakes
  "session file is format version 4,",                -- the browser's session file of an unknown version
  "a problem to list", "a problem in no file",        -- Show Problems
  "ranker 'throws' forget %-> ",                      -- a ranker that throws while forgetting
  "extension 'test%-left%-throws' left %-> ",         -- an extension that throws as a level is left
  "%-tasks/tasks%.json",                              -- the tasks checks' broken tasks.json
  "%-task%-inputs/tasks%.json",                       -- and their inputs' mistakes
  "tasks%.contextMenu names deploy",
  "editor forced to 'zed', which is not available",   -- the editor's remote declined by Zed
  "editor forced to 'open', which is not available",  -- and by open
  '"brew%.menus": no picker lists', '"brew%.menus%.root" should be', '"apps%.menus" should be',  -- menus settings
  "Bookmarks file did not read as JSON",                -- the browser's cut-short Bookmarks fixture
  "windows: reading the all list took",                -- the windows' slow app fixture
}

check("every [commandlayer] line was caused on purpose", (function()
        local unexpected = {}
        for _, line in ipairs(T.logged) do
          local expected = false
          for _, pattern in ipairs(expectedLogs) do
            if line:find(pattern) then expected = true; break end
          end
          if not expected then unexpected[#unexpected + 1] = line end
        end
        return #unexpected == 0, table.concat(unexpected, " | ", 1, math.min(#unexpected, 6))
      end)())

----------------------------------------------------------------------

for _, path in ipairs(T.inputFiles) do os.remove(path) end
T.releaseFiles()

local checks, failures = T.counts()
print()
if failures == 0 then
  print(("%d checks, all passing"):format(checks))
  os.exit(0)
else
  print(("%d checks, %d FAILING"):format(checks, failures))
  os.exit(1)
end
