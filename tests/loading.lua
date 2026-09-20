-- CommandLayer.spoon/tests/loading.lua
-- Loading defines things and touches nothing; what the loaded layer holds.

local T = ...
local check, group = T.check, T.group
local stub = T.stub
local dir = T.dir
local coreSource = T.coreSource
local coreFiles = T.coreFiles

group("stubs")
do
  local probe = { value = "real" }
  stub(probe, "value", "stubbed")
  local during = probe.value
  group("stubs put back")
  check("a stub holds within its group and is put back when the next starts",
        during == "stubbed" and probe.value == "real", tostring(during) .. " / " .. tostring(probe.value))
end

group("loading is inert")
local readsBefore = T.settingsReads()
local cl = T.loadKernel()
local settingsReads = T.settingsReads() - readsBefore
cl.userDir = T.NO_USER_DIR

-- A file dropped into core/ and not listed in the loader would sit there
-- looking like part of the kernel while nothing runs it.
check("every file in core/ is loaded", (function()
        local handle = io.open(dir .. "commandlayer.lua")
        local loader = handle:read("a"); handle:close()
        local unlisted = {}
        for _, name in ipairs(coreFiles()) do
          if not loader:find('"' .. name .. '"', 1, true) then
            unlisted[#unlisted + 1] = name
          end
        end
        return #coreFiles() > 0 and #unlisted == 0, table.concat(unlisted, " ")
      end)())
-- The loader's order is the order of dependence: a core file reads only
-- what the files before it define. What a later file fills in is reached
-- through the session's hooks, and M.session is defined early.
check("no core file reads what only a later core file defines", (function()
        local handle = io.open(dir .. "commandlayer.lua")
        local loader = handle:read("a"); handle:close()
        local order = {}
        for name in (loader:match("local CORE = (%b{})") or ""):gmatch('"([%w_]+)"') do
          order[#order + 1] = name
        end
        local definedIn, sources = {}, {}
        for i, name in ipairs(order) do
          local text = coreSource(name) or ""
          sources[i] = text
          for def in text:gmatch("function M%.([%w_]+)") do definedIn[def] = definedIn[def] or i end
          for def in ("\n" .. text):gmatch("\nM%.([%w_]+)%s*=[^=]") do definedIn[def] = definedIn[def] or i end
        end
        local forward = {}
        for i, name in ipairs(order) do
          local seen = {}
          for line in (sources[i] .. "\n"):gmatch("(.-)\n") do
            if not line:match("^%s*%-%-") then
              for ref in line:gmatch("M%.([%w_]+)") do
                local at = definedIn[ref]
                if at and at > i and not seen[ref] then
                  seen[ref] = true
                  forward[#forward + 1] = ("%s reads M.%s, defined in %s"):format(name, ref, order[at])
                end
              end
            end
          end
        end
        return #order > 0 and #forward == 0, table.concat(forward, "; ")
      end)())
-- Loading the kernel must define and touch nothing: no folder read, no
-- chord claimed. Everything below needs setup(), which start() calls.
check("nothing is registered before setup", #cl.extensions == 0
      and #cl.views == 0 and #cl.rankers == 0 and #cl.matchers == 0
      and #cl.getCommands() == 0,
      ("%d ext %d views %d rankers %d matchers %d commands"):format(
        #cl.extensions, #cl.views, #cl.rankers, #cl.matchers, #cl.getCommands()))
check("no profile read", cl.settings == nil)
check("and nothing read from hs.settings", settingsReads == 0,
      tostring(settingsReads) .. " reads")

cl.setup()
T.adopt(cl)

check("setup is idempotent", (function()
        local before = #cl.extensions
        cl.setup()
        return #cl.extensions == before
      end)())

group("layer loads")
check("module returned", type(cl) == "table")
check("the extensions folder loaded", next(cl.modules) ~= nil,
      (function()
        local names = {}
        for n in pairs(cl.modules) do names[#names + 1] = n end
        table.sort(names)
        return table.concat(names, " ")
      end)())
check("extensions registered", #cl.extensions > 0,
      tostring(#cl.extensions) .. " extensions")
check("every way of running a thing is a command of an extension, in no menu", (function()
        local missing = {}
        for _, id in ipairs({ "system.open", "system.reveal", "apps.open", "editor.open", "terminal.open",
                              "webview.open", "spoon.call", "applescript.run", "shell.run", "shortcuts.run" }) do
          local command = cl.getCommand(id)
          if not (command and type(command.run) == "function" and command.extension
                  and next(command.menus) == nil) then
            missing[#missing + 1] = id
          end
        end
        return #missing == 0, table.concat(missing, " ")
      end)())

group("tools")
-- Asserted against the source, since by the time this runs every
-- backend and extension has registered into the table.
check("the kernel declares no binaries of its own", (function()
        if not (coreSource("tools") or ""):match("tools%.candidates = {%s*}") then
          return false, "core/tools.lua"
        end
        for _, name in ipairs(coreFiles()) do
          if coreSource(name):match("tools%.register%(%s*[\"']") then
            return false, "core/" .. name .. ".lua"
          end
        end
        return true
      end)())
check("every capability provider names a registered binary", (function()
        for capability, chain in pairs(cl.tools.providers) do
          for _, provider in ipairs(chain) do
            if not cl.tools.candidates[provider.bin] then
              return false, capability .. "/" .. tostring(provider.bin)
            end
          end
        end
        return true
      end)(), "a provider names a binary nobody registered")
