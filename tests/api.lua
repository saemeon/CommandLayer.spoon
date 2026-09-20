-- CommandLayer.spoon/tests/api.lua
-- What a plugin is given.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local stub = T.stub
local dir = T.dir
local logged = T.logged
local loadKernel = T.loadKernel

----------------------------------------------------------------------
-- THE PLUGIN API
--
-- Two extensions in a user folder of their own, loaded as any other is:
-- one registering one of everything, one it depends on.
----------------------------------------------------------------------

group("the plugin API")
do
  local apiDir = os.tmpname() .. "-api"
  os.execute(("mkdir -p %q/extensions"):format(apiDir))
  local function writeFile(path, text)
    local handle = assert(io.open(path, "w"))
    handle:write(text)
    handle:close()
  end
  writeFile(apiDir .. "/extensions/apitest.lua", [[
    local M = { starts = 0, stops = 0 }
    function M.start()
      M.starts = M.starts + 1
      M.cl.after(5, function() end)
      M.cl.every(5, function() end)
      M.cl.watch(M.watcher)
      M.cl.tools.run("/bin/echo", {}, function() end)
    end
    function M.stop() M.stops = M.stops + 1 end
    function M.extension(cl)
      M.cl = cl
      cl.themeIconProvider(function(name) if name == "apitest-icon" then return "IMG" end end)
      cl.itemContextKey("apitestKey", function() return true end)
      cl.setContext("apitestContext", true)
      cl.tools.register("apitest-tool", { "/nonexistent/apitest-tool" })
      cl.tools.provide("apitest", { { name = "x", bin = "apitest-tool" } })
      return {
        menus = {},
        optionalExtensionDependencies = { "apidep" },
        settings = { level = { type = "number", default = 3 } },
        commands = { { id = "apitest.go", title = "Go", menus = {}, run = function(args) M.ran = args.value end },
                     { id = "apitest.say", title = "Say ${query}", prefix = "apitest ", command = "apitest.go",
                       inputs = { { id = "query", picker = { typed = true }, fromQuery = true } } } },
      }
    end
    return M]])
  writeFile(apiDir .. "/extensions/apidep.lua", [[
    local M = {}
    function M.extension(cl)
      cl.tools.register("apitest-tool", { "/nonexistent/apitest-tool" })
      return { menus = {}, exports = { value = 42 } }
    end
    return M]])
  local api = loadKernel()
  api.userDir = apiDir
  -- Before setup, which checks that the picker's presenter is there.
  api.presenter("recording", cl.presenters.recording)
  api.setup()
  local mod = api.modules.apitest or {}
  local ecl = mod.cl

  local readOk, readWhy = pcall(function() return ecl.gather end)
  check("an extension's cl is its API: reading or writing anything else raises",
        ecl ~= nil and ecl.apiVersion == 0 and ecl.name == "apitest" and not readOk
        and tostring(readWhy):find("cl.gather is not part of the extension API", 1, true) ~= nil
        and not pcall(function() ecl.extra = 1 end), tostring(readWhy))

  check("cl.entry and cl.BACKENDS are not part of an extension's API",
        not pcall(function() return ecl.entry end) and not pcall(function() return ecl.BACKENDS end))

  -- A picker is data, so no plugin of code is one.
  check("the kinds of plugin are extensions, presenters, matchers and rankers", (function()
          local kinds = {}
          for kind in pairs(api.apiMembers()) do kinds[#kinds + 1] = kind end
          table.sort(kinds)
          return table.concat(kinds, " ") == "extension matcher presenter ranker", table.concat(kinds, " ")
        end)())

  -- One value, so a setting can be an argument in the middle of a call.
  check("a plugin's cl.setting is the value alone; cl.inspectSetting adds where it came from", (function()
          local count = select("#", ecl.setting("apitest", "level"))
          local value, source = ecl.inspectSetting("apitest", "level")
          local presenter = api.pluginAPI("presenter", "apitest-presenter")
          return count == 1 and value == 3 and source == "default"
                 and select("#", presenter.setting("apitest", "level")) == 1
                 and type(presenter.inspectSetting) == "function",
                 ("%d values, %s from %s"):format(count, tostring(value), tostring(source))
        end)())

  local public = dofile(dir .. "commandlayer.lua")
  public.profile = "raycast"
  check("init.lua is given the public layer, and none of the kernel",
        public.apiVersion == 0 and type(public.start) == "function"
        and type(public.executeCommand) == "function" and public.profile == "raycast"
        and not pcall(function() return public.gather end)
        and not pcall(function() public.gather = 1 end))

  local function problemAbout(text)
    for _, p in ipairs(api.problems) do
      if p.file == "extension apitest" and p.message:find(text, 1, true) then return true end
    end
    return false
  end
  ecl.executeCommand("apitest.go", { value = 7 })
  check("an extension runs a command by id through its API", mod.ran == 7, tostring(mod.ran))

  ecl.problem("something is off")
  check("cl.problem is a problem named for the extension", problemAbout("something is off"))

  writeFile(apiDir .. "/good.jsonc", '// a comment\n{ "list": [ 1, 2, ], }')
  writeFile(apiDir .. "/bad.jsonc", '{ "list": ')
  local good, missing = ecl.readJSONC(apiDir .. "/good.jsonc"), ecl.readJSONC(apiDir .. "/none.jsonc")
  local bad = ecl.readJSONC(apiDir .. "/bad.jsonc")
  check("cl.readJSONC reads comments and trailing commas; a missing file is nil, and one that does not parse "
        .. "is nil and a problem named for the extension, naming the file",
        type(good) == "table" and type(good.list) == "table" and good.list[2] == 2 and missing == nil
        and bad == nil and problemAbout(apiDir .. "/bad.jsonc does not parse") and not problemAbout("none.jsonc")
        and not pcall(function() return api.pluginAPI("presenter", "apitest-presenter").readJSONC end),
        tostring(good) .. " " .. tostring(bad))

  check("a plugin is given no paste, and nothing that writes a setting, a keybinding, profile.json or a generated "
        .. "file: the extensions that do it write through the JSONC functions", (function()
          local offered = {}
          for _, name in ipairs({ "paste", "setSetting", "removeKeybinding", "changeKeybinding", "switchProfile",
                                  "writeGenerated", "defaultSettingsText", "defaultKeybindingsText" }) do
            if pcall(function() return ecl[name] end) or api.apiDescriptions[name] ~= nil then
              offered[#offered + 1] = name
            end
          end
          return #offered == 0 and type(ecl.editJSONC) == "function", table.concat(offered, ", ")
        end)())

  check("an extension reloads through cl.reload, and has no profileFilesChanged of its own",
        type(ecl.reload) == "function" and not pcall(function() return ecl.profileFilesChanged end))

  local exported = ecl.extension("apidep")
  local undeclaredOk, undeclaredWhy = pcall(ecl.extension, "browser")
  check("an extension's exports reach one that declared it a dependency, and no other",
        type(exported) == "table" and exported.value == 42 and not undeclaredOk
        and tostring(undeclaredWhy):find("without declaring it a dependency", 1, true) ~= nil,
        tostring(undeclaredWhy))

  local now, asked, answer = 1000, 0, nil
  stub(os, "time", function() return now end)
  local function slow()
    return { seconds = 60, initial = "initial",
             refresh = function(done) asked = asked + 1; answer = done end }
  end
  local first, second = ecl.cached("slow", slow()), ecl.cached("slow", slow())
  answer({})
  local empty = ecl.cached("slow", slow())
  now = 1030
  ecl.cached("slow", slow())
  local askedWithin = asked
  now = 1061
  ecl.cached("slow", slow())
  local atOnce = ecl.cached("quick", { seconds = 60, refresh = function(done) done("now") end })
  check("cl.cached answers at once, asks once while a refresh is out, and keeps even an empty answer",
        first == "initial" and second == "initial" and type(empty) == "table" and next(empty) == nil
        and askedWithin == 1 and asked == 2 and atOnce == "now",
        ("%s %s asked %d then %d"):format(tostring(first), tostring(atOnce), askedWithin, asked))

  -- done(nil) is a call that did not work: the last good answer stays, and
  -- the next ask tries again rather than waiting out `seconds`.
  local tries, reply = 0, nil
  local function flaky()
    return { seconds = 300, initial = "none",
             refresh = function(done) tries = tries + 1; reply = done end }
  end
  now = 2000
  ecl.cached("flaky", flaky())
  reply({ "mine" })
  now = 2400
  ecl.cached("flaky", flaky())
  reply(nil)
  local kept = ecl.cached("flaky", flaky())
  check("a refresh answering nil keeps the last answer and is asked again at once",
        type(kept) == "table" and kept[1] == "mine" and tries == 3,
        ("%s after %d tries"):format(tostring(type(kept) == "table" and kept[1] or kept), tries))

  local timers, tasks = {}, {}
  local function timer()
    local t = { stopped = false }
    function t:stop() self.stopped = true end
    timers[#timers + 1] = t
    return t
  end
  stub(hs.timer, "doAfter", timer)
  stub(hs.timer, "doEvery", timer)
  stub(hs.task, "new", function()
    local t = { terminated = false }
    function t:start() return self end
    function t:terminate() self.terminated = true end
    tasks[#tasks + 1] = t
    return t
  end)
  local watcher = { starts = 0, stops = 0 }
  function watcher:start() self.starts = self.starts + 1 end
  function watcher:stop() self.stops = self.stops + 1 end
  mod.watcher = watcher

  local others = {}
  for _, ext in ipairs(api.extensions) do
    if ext.name ~= "apitest" and ext.name ~= "apidep" then others[#others + 1] = ext.name end
  end
  for _, name in ipairs(others) do api.unregisterExtension(name) end
  api.startExtensions()
  local startedOnce = mod.starts == 1 and watcher.starts == 1 and #timers == 2 and #tasks == 1
  api.stopExtensions()
  local stoppedAll = mod.stops == 1 and watcher.stops == 1 and timers[1] and timers[1].stopped
                     and timers[2] and timers[2].stopped and tasks[1] and tasks[1].terminated
  api.startExtensions()
  check("what an extension starts is held, stopped with it, and started again with it",
        startedOnce and stoppedAll and mod.starts == 2 and watcher.starts == 2 and #timers == 4,
        ("starts %d stops %d watcher %d/%d timers %d tasks %d"):format(mod.starts, mod.stops,
          watcher.starts, watcher.stops, #timers, #tasks))

  stub(hs.timer, "doAfter", function(_, fn) fn(); return { stop = function() end } end)
  ecl.after(1, function() error("apitest timer fails") end)
  check("a timer that throws is logged as an error, naming its extension",
        tostring(logged[#logged]):find("extension 'apitest' timer -> ", 1, true) ~= nil
        and api.log.lastLevel == "error", tostring(logged[#logged]))

  local function present()
    return {
      icon     = api.themeIcon("apitest-icon") == "IMG",
      key      = api.itemContext({ kind = "x" }).apitestKey == true,
      context  = api.buildContext().apitestContext == true,
      tool     = api.tools.candidates["apitest-tool"] ~= nil,
      provider = api.tools.providers.apitest ~= nil,
      command  = api.getCommand("apitest.say") ~= nil,
      view     = api.viewNamed("apitest.say") ~= nil,
    }
  end
  local function describe(state)
    local out = {}
    for name, value in pairs(state) do out[#out + 1] = name .. "=" .. tostring(value) end
    table.sort(out)
    return table.concat(out, " ")
  end
  local before = present()
  api.unregisterExtension("apidep")
  local toolKept, exportsGone = api.tools.candidates["apitest-tool"] ~= nil, ecl.extension("apidep") == nil
  api.unregisterExtension("apitest")
  local after = present()
  local allBefore, noneAfter = true, true
  for _, value in pairs(before) do allBefore = allBefore and value end
  for _, value in pairs(after) do noneAfter = noneAfter and not value end
  check("switching an extension off undoes everything it registered, and stops it",
        allBefore and noneAfter and mod.stops == 2 and watcher.stops == 2,
        describe(before) .. " / " .. describe(after))
  check("a tool stays while another extension claims it, and exports go with their extension",
        toolKept and exportsGone)

  os.execute(("rm -rf %q"):format(apiDir))
end

----------------------------------------------------------------------
-- THE LAYER'S LISTS
--
-- What an extension reads of the pickers, keybindings and setting
-- declarations: copies of a documented shape.
----------------------------------------------------------------------

group("the layer's lists")
do
  local ecl = cl.pluginAPI("extension", "help")
  local lists = { view = ecl.getViews(), keybinding = ecl.getKeybindings(), settingOwner = ecl.getSettingOwners() }

  check("every entry of every list holds only the fields its shape documents, each of its type", (function()
          local wrong = {}
          for name, list in pairs(lists) do
            local fields = cl.listShapes[name].fields
            if #list == 0 then wrong[#wrong + 1] = name .. " is empty" end
            for i, entry in ipairs(list) do
              for field, value in pairs(entry) do
                local doc = fields[field]
                if not doc then
                  wrong[#wrong + 1] = ("%s %d: %s"):format(name, i, tostring(field))
                elseif type(value) ~= doc.type then
                  wrong[#wrong + 1] = ("%s %d: %s is %s"):format(name, i, field, type(value))
                end
              end
            end
          end
          return #wrong == 0, table.concat(wrong, ", ")
        end)())

  check("changing a copy changes nothing the layer holds, and the next call is a fresh copy", (function()
          local views, keys, owners = lists.view, lists.keybinding, lists.settingOwner
          local palette, opensPalette, browser
          for _, v in ipairs(views) do if v.name == "palette" then palette = v end end
          for _, k in ipairs(keys) do if k.opens == "palette" then opensPalette = k end end
          for _, o in ipairs(owners) do if o.name == "browser" then browser = o end end
          if not (palette and opensPalette and browser and browser.settings.tabOrder) then
            return false, "missing an entry"
          end
          palette.prefixes[1] = "zz "
          palette.menus[1] = "nowhere"
          opensPalette.args.view = "nowhere"
          browser.settings.tabOrder.default = "changed"
          local spec = cl.viewNamed("palette")
          local declared = cl.declaredExtensions.browser.settings.tabOrder
          local live
          for _, entry in ipairs(cl.effectiveKeybindings()) do
            if cl.quickOpenTarget(entry) == "palette" and entry.key == opensPalette.key then live = entry end
          end
          local again = ecl.getViews()
          return cl.prefixesOf(spec)[1] == ">" and spec.menus[1] == "commandPalette"
                 and live ~= nil and live.args.view == "palette" and declared.default ~= "changed"
                 and again ~= views and cl.viewForPrefix("zz ") == nil,
                 ("%s %s %s %s"):format(tostring(cl.prefixesOf(spec)[1]), tostring(spec.menus[1]),
                                        tostring(live and live.args.view), tostring(declared.default))
        end)())
end
