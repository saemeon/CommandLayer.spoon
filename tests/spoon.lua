-- CommandLayer.spoon/tests/spoon.lua
-- What Hammerspoon's Spoon conventions ask of init.lua: its metadata, and a
-- docstring hs.doc.builder can read for everything it offers.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()

group("spoon")

local text = T.readSource("init.lua")
local chunk = loadfile(T.dir .. "init.lua")
local obj = chunk and chunk() or {}

check("init.lua sets the metadata SPOONS.md asks for", (function()
        local missing = {}
        for _, key in ipairs({ "name", "version", "author", "license" }) do
          if type(obj[key]) ~= "string" or obj[key] == "" then missing[#missing + 1] = key end
        end
        return #missing == 0 and obj.name == "CommandLayer"
               and (obj.homepage == nil or type(obj.homepage) == "string"),
               table.concat(missing, " ")
      end)())

-- The fields SPOONS.md names as metadata carry no docstring in the official
-- Spoons.
local METADATA = { __index = true, name = true, version = true, author = true, license = true, homepage = true }

-- hs.doc.builder reads a block of `---` lines: the name, its kind, then a
-- description; a method's also says what it takes and gives back.
local function docstrings()
  local blocks, block = {}, nil
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local body = line:match("^%-%-%- ?(.*)$")
    if body and not line:match("^%-%-%-%-") then
      if block then block[#block + 1] = body else block = { body } end
    else
      if block then blocks[#blocks + 1] = block end
      block = nil
    end
  end
  return blocks
end

check("init.lua opens with the module's docstring, named for the Spoon",
      text:match("^%-%-%- === (%w+) ===\n") == obj.name)

check("every method and variable init.lua offers has a docstring in hs.doc's format, and each docstring "
      .. "names one it offers", (function()
        local documented, wrong = {}, {}
        for _, block in ipairs(docstrings()) do
          local heading = block[1]
          if not heading:match("^=== ") then
            local kind = block[2]
            local method = kind == "Method" and heading:match("^CommandLayer:([%w_]+)%(.*%)$")
            local variable = kind == "Variable" and heading:match("^CommandLayer%.([%w_]+)$")
            local says = {}
            for _, line in ipairs(block) do says[line] = true end
            if not (method or variable) or not block[3] or block[3] == "" then
              wrong[#wrong + 1] = heading
            elseif method and not (says["Parameters:"] and says["Returns:"]) then
              wrong[#wrong + 1] = heading .. " without Parameters and Returns"
            else
              documented[heading] = true
            end
          end
        end
        local offered = {}
        for name, params in text:gmatch("\nfunction obj:([%w_]+)(%b())") do
          offered["CommandLayer:" .. name .. params] = true
        end
        for name in text:gmatch("\nobj%.([%w_]+)%s*=") do
          if not METADATA[name] then offered["CommandLayer." .. name] = true end
        end
        for heading in pairs(offered) do
          if not documented[heading] then wrong[#wrong + 1] = "no docstring: " .. heading end
        end
        for heading in pairs(documented) do
          if not offered[heading] then wrong[#wrong + 1] = "nothing named " .. heading end
        end
        table.sort(wrong)
        return next(offered) ~= nil and #wrong == 0, table.concat(wrong, ", ")
      end)())

check("defaultHotkeys holds the chord the shipped keybindings enter the layer on", (function()
        local enter = type(obj.defaultHotkeys) == "table" and obj.defaultHotkeys.enter
        local shipped = {}
        for _, entry in ipairs(cl.effectiveKeybindings()) do
          if cl.entersLayer(entry) and entry.global then shipped[#shipped + 1] = cl.chordId(entry.key) end
        end
        local ours = type(enter) == "table" and cl.chordId(enter) or tostring(enter)
        return #shipped == 1 and shipped[1] == ours, table.concat(shipped, " ") .. " / " .. tostring(ours)
      end)())

check("init gives the Spoon its homepage and the layer's logger, as Spoons offer one", (function()
        local spoonObj = chunk and chunk() or {}
        local fakeLayer = { log = cl.log }
        spoonObj.spoonPath = T.dir
        T.stub(_G, "dofile", function() return fakeLayer end)
        local ok = pcall(spoonObj.init, spoonObj)
        return ok and spoonObj.logger == cl.log and type(spoonObj.logger.setLogLevel) == "function"
               and spoonObj.homepage == "https://github.com/saemeon/CommandLayer.spoon",
               tostring(spoonObj.homepage)
      end)())

check("scripts/spoon-release.sh writes the zip SpoonInstall unpacks, the Spoon as it runs, and docs.json",
      (function()
        local out = os.tmpname() .. "-release"
        local ran = os.execute(("sh %q %q >/dev/null 2>&1"):format(T.dir .. "scripts/spoon-release.sh", out))
        local list = io.popen(("unzip -Z1 %q 2>/dev/null"):format(out .. "/Spoons/CommandLayer.spoon.zip"))
        local names = list and list:read("a") or ""
        if list then list:close() end
        local docs = io.open(out .. "/docs/docs.json", "r")
        if docs then docs:close() end
        os.execute(("rm -rf %q"):format(out))
        return ran and names:find("CommandLayer.spoon/init.lua", 1, true) ~= nil
               and names:find("CommandLayer.spoon/extensions/apps.lua", 1, true) ~= nil
               and not names:find("/tests/", 1, true) and not names:find("CLAUDE.md", 1, true)
               and docs ~= nil,
               #names .. " bytes of listing"
      end)())
