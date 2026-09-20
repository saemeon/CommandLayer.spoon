-- CommandLayer.spoon/tests/extensions.lua
-- The extension manifest, and the order extensions run in.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()

local substringOnly = T.substringOnly
local removeView = T.removeView
local capturingPrint = T.capturingPrint

group("extension manifest")
check("an extension's display name is its own, or its name capitalised", (function()
        cl.register({ name = "test-named", displayName = "Test Named" })
        cl.register({ name = "plain" })
        local named, plain = cl.displayNameOf("test-named"), cl.displayNameOf("plain")
        cl.unregisterExtension("test-named")
        cl.unregisterExtension("plain")
        return named == "Test Named" and plain == "Plain",
               tostring(named) .. " / " .. tostring(plain)
      end)())

check("a command with no category is grouped under its extension's display name",
      (function()
        cl.register({ name = "grouped", displayName = "Grouped Things",
          commands = { { id = "grouped.run", title = "Run grouped", menus = { "commandPalette" },
                         run = function() end } } })
        local found
        for _, row in ipairs(cl.gather(cl.buildContext(), { menus = { "commandPalette" } })) do
          if row.command == "grouped.run" then found = row end
        end
        cl.unregisterExtension("grouped")
        return found ~= nil and found.description == "Grouped Things", found and found.description
      end)())

check("an extension whose requirement is missing is dropped, commands too, and logged",
      (function()
        local lines, restore = capturingPrint()
        cl.register({ name = "needy", extensionDependencies = { "no-such-extension" },
          commands = { { id = "needy.go", title = "Go", run = function() end } } })
        cl.resolveRequires()
        restore()
        local present = false
        for _, ext in ipairs(cl.extensions) do
          if ext.name == "needy" then present = true end
        end
        local logged = false
        for _, line in ipairs(lines) do
          if line:find("needy", 1, true) and line:find("no-such-extension", 1, true) then
            logged = true
          end
        end
        return not present and cl.getCommand("needy.go") == nil and logged
      end)())

check("an extension starts after the extensions it requires", (function()
        cl.register({ name = "zz-base" })
        cl.register({ name = "aa-dependent", extensionDependencies = { "zz-base" } })
        cl.resolveRequires()
        local base, dependent
        for i, name in ipairs(cl.startOrder()) do
          if name == "zz-base" then base = i elseif name == "aa-dependent" then dependent = i end
        end
        cl.unregisterExtension("aa-dependent")
        cl.unregisterExtension("zz-base")
        return base ~= nil and dependent ~= nil and base < dependent,
               tostring(base) .. " < " .. tostring(dependent)
      end)())

group("extension order")
check("before and after order extensions, whatever their names", (function()
        cl.register({ name = "test-order-b", before = { "test-order-a" }, menus = {} })
        cl.register({ name = "test-order-a", menus = {} })
        cl.register({ name = "test-order-c", after = "test-order-a", menus = {} })
        local at = {}
        for i, ext in ipairs(cl.sortedExtensions()) do at[ext.name] = i end
        for _, name in ipairs({ "test-order-a", "test-order-b", "test-order-c" }) do
          cl.unregisterExtension(name)
        end
        return at["test-order-b"] and at["test-order-a"] and at["test-order-c"]
               and at["test-order-b"] < at["test-order-a"] and at["test-order-a"] < at["test-order-c"],
               ("b %s, a %s, c %s"):format(tostring(at["test-order-b"]), tostring(at["test-order-a"]),
                                          tostring(at["test-order-c"]))
      end)())

check("before and after in a circle is a problem, and each extension in it still runs", (function()
        cl.register({ name = "test-circle-x", after = { "test-circle-y" }, menus = {} })
        cl.register({ name = "test-circle-y", after = { "test-circle-x" }, menus = {} })
        local found = {}
        for _, ext in ipairs(cl.sortedExtensions()) do found[ext.name] = true end
        local reported = false
        for _, p in ipairs(cl.problems) do
          if p.message:find("lead in a circle: test-circle-x, test-circle-y", 1, true) then reported = true end
        end
        cl.unregisterExtension("test-circle-x")
        cl.unregisterExtension("test-circle-y")
        return found["test-circle-x"] and found["test-circle-y"] and reported,
               tostring(reported)
      end)())

check("picker rows and text commands are view fields, not the entry picker's alone", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local function shown(fields, query)
          local spec = { name = "test-fields", menus = { "test-fields-none" }, presenter = "recording" }
          for k, v in pairs(fields) do spec[k] = v end
          cl.view(spec)
          cl.open("test-fields")
          local p = cl.viewNamed("test-fields").picker
          if p and query then p.type(query) end
          local out = p and p.shown or {}
          removeView("test-fields")
          return out
        end
        local function has(rows, test)
          for _, row in ipairs(rows) do
            if test(row) then return true end
          end
          return false
        end
        local function isPicker(row) return (row.description or ""):find("^Picker %-%- type") ~= nil end
        local function isSearch(row) return row.command == "browser.searchWeb" end
        local pickers = has(shown({ pickerRows = true }), isPicker)
        local noPickers = not has(shown({}), isPicker)
        local fallbacks = has(shown({ textCommands = "fallback" }, "zzqq nothing like it"), isSearch)
        local noFallbacks = not has(shown({}, "zzqq nothing like it"), isSearch)
        cl.matchers = saved
        return pickers and noPickers and fallbacks and noFallbacks,
               ("pickers %s/%s, fallbacks %s/%s"):format(tostring(pickers), tostring(noPickers),
                                                          tostring(fallbacks), tostring(noFallbacks))
      end)())

check("textCommands first puts the text commands, filled in, before the picker's own rows that match, "
      .. "only while text is typed", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local function shown(query)
          local undo = T.picker("test-first", { { label = "lofi picker" } }, { answers = false, textCommands = "first" })
          cl.open("test-first")
          local p = cl.viewNamed("test-first").picker
          if p and query then p.type(query) end
          local out = p and p.shown or {}
          undo()
          return out
        end
        local function isText(row) return row.command == "browser.searchWeb" end
        local bare, typed = shown(nil), shown("  lofi")
        local bareText = false
        for _, row in ipairs(bare) do bareText = bareText or isText(row) end
        local own, lastText, search
        for i, row in ipairs(typed) do
          if row.label == "lofi picker" then own = i end
          if row.command and row.args then lastText = i end
          if isText(row) then search = row end
        end
        cl.matchers = saved
        return #bare == 1 and bare[1].label == "lofi picker" and not bareText
               and search ~= nil and search.args.query == "lofi" and own ~= nil and lastText ~= nil
               and lastText < own and own == #typed,
               ("bare %d rows, text %s; typed own at %s, last text at %s of %d"):format(#bare, tostring(bareText),
                 tostring(own), tostring(lastText), #typed)
      end)())
