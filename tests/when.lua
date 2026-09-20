-- CommandLayer.spoon/tests/when.lua
-- When clauses.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local capturingPrint = T.capturingPrint

group("when clauses")
check("when clauses evaluate the way VS Code's do", (function()
        local cases = {
          { "frontmostApp == 'Safari'", { frontmostApp = "Safari" }, true },
          { "frontmostApp == 'Safari'", { frontmostApp = "Finder" }, false },
          { 'frontmostApp != "Safari"', { frontmostApp = "Finder" }, true },
          { "url =~ /youtube%.com%/watch/", { url = "https://www.youtube.com/watch?v=1" }, true },
          { "url =~ /youtube%.com%/watch/", { url = "https://www.youtube.com/" }, false },
          { "finderSelection && !clipboard", { finderSelection = "/a" }, true },
          { "finderSelection && !clipboard", { finderSelection = "/a", clipboard = "x" }, false },
          { "finderSelection && !clipboard", { finderSelection = "/a", clipboard = "" }, true },
          { "a || b && c", { a = "1" }, true },
          { "(a || b) && c", { a = "1" }, false },
          { "!(a && b)", { a = "1" }, true },
          { "flag == true", { flag = true }, true },
          { "flag == false", { flag = true }, false },
          { "missing == 'x'", {}, false },
          { "", {}, true },
        }
        local wrong = {}
        for _, c in ipairs(cases) do
          if cl.when(c[1], c[2]) ~= c[3] then wrong[#wrong + 1] = c[1] end
        end
        return #wrong == 0, table.concat(wrong, " | ")
      end)())

check("setContext sets a key every context built afterwards has, until set to nil", (function()
        cl.setContext("launcherMode", "focus")
        local set = cl.buildContext().launcherMode
        local asClause = cl.when("launcherMode == 'focus'", cl.buildContext())
        cl.setContext("launcherMode", nil)
        local cleared = cl.buildContext().launcherMode
        return set == "focus" and asClause and cleared == nil, tostring(set) .. " / " .. tostring(cleared)
      end)())

check("in, not in and the comparisons evaluate the way VS Code's do", (function()
        local cases = {
          { "name in folders", { name = "src", folders = { "src", "lib" } }, true },
          { "name in folders", { name = "docs", folders = { "src", "lib" } }, false },
          { "lang in known", { lang = "lua", known = { lua = true } }, true },
          { "lang not in known", { lang = "py", known = { lua = true } }, true },
          { "lang not in known", { lang = "lua", known = { lua = true } }, false },
          { "name in missing", { name = "src" }, false },
          { "name not in missing", { name = "src" }, true },
          { "index == '1'", { index = "1" }, true },
          { "count >= 1", { count = 2 }, true },
          { "count < 1", { count = 2 }, false },
          { "count > 1", { count = "3" }, true },
          { "count <= 2", { count = 2 }, true },
          { "count > -1 && count < 0.5", { count = 0 }, true },
          { "name > 1", { name = "abc" }, false },
        }
        local wrong = {}
        for _, c in ipairs(cases) do
          if cl.when(c[1], c[2]) ~= c[3] then wrong[#wrong + 1] = c[1] end
        end
        return #wrong == 0, table.concat(wrong, " | ")
      end)())

check("a comparison without a number, or in without a key, does not parse", (function()
        local lines, restore = capturingPrint()
        local noNumber = cl.when("count > many", { count = 5, many = 1 })
        local literal = cl.when("name in 'src'", { name = "src" })
        restore()
        return noNumber == false and literal == false and #lines == 2, tostring(#lines) .. " lines"
      end)())

check("a clause that does not parse is false, and reported once", (function()
        local lines, restore = capturingPrint()
        local first = cl.when("a &&", { a = "1" })
        local again = cl.when("a &&", { a = "1" })
        local noSlashes = cl.when("url =~ youtube", { url = "youtube" })
        local badPattern = cl.when("url =~ /[unclosed/", { url = "[" })
        restore()
        return first == false and again == false and noSlashes == false
               and badPattern == false and #lines == 3, tostring(#lines) .. " lines"
      end)())

check("a row, a command and a verb show only while their clause holds", (function()
        cl.register({ name = "whenish", menus = { "whenish" },
          items = function()
            return { { label = "always row" },
                     { label = "safari row", when = "frontmostApp == 'Safari'" } }
          end,
          commands = { { id = "whenish.safari", title = "safari command",
                         menus = { "whenish" }, when = "frontmostApp == 'Safari'",
                         run = function() end },
                       { id = "whenish.safariVerb", title = "safari verb", menus = {},
                         when = "frontmostApp == 'Safari'", run = function() end,
                         inputs = { { id = "thing", picker = { when = "viewItem == 'thing'" } } } },
                       { id = "whenish.anyVerb", title = "any verb", menus = {}, run = function() end,
                         inputs = { { id = "thing", picker = { when = "viewItem == 'thing'" } } } } } })
        local function texts(rows)
          local t = {}
          for _, row in ipairs(rows) do t[row.label] = true end
          return t
        end
        local inSafari, inFinder = { frontmostApp = "Safari" }, { frontmostApp = "Finder" }
        local a = texts(cl.gather(inSafari, { menus = { "whenish" } }))
        local b = texts(cl.gather(inFinder, { menus = { "whenish" } }))
        local va = texts(cl.itemActions({ kind = "thing" }, inSafari))
        local vb = texts(cl.itemActions({ kind = "thing" }, inFinder))
        cl.unregisterExtension("whenish")
        return a["always row"] and a["safari row"] and a["safari command"]
               and b["always row"] and not b["safari row"] and not b["safari command"]
               and va["safari verb"] and vb["any verb"] and not vb["safari verb"]
      end)())

check("a keybinding whose clause is false does not run", (function()
        local ran = 0
        cl.registerCommand("test.whenKey", { title = "when key", menus = {},
                                             run = function() ran = ran + 1 end })
        local ctx = cl.buildContext()
        local app = ctx.frontmostApp or ""
        cl.runKeybinding({ key = "cmd+1", command = "test.whenKey",
                           when = "frontmostApp == 'NoSuchApp'" })
        local blocked = ran
        cl.runKeybinding({ key = "cmd+1", command = "test.whenKey",
                           when = "frontmostApp == '" .. app .. "' || !frontmostApp" })
        return blocked == 0 and ran == 1, ("%d blocked, %d ran"):format(blocked, ran)
      end)())

check("config.<ext>.<key> in a when clause reads the setting", (function()
        T.stub(cl, "userSettings", { ["browser.tabOrder"] = "browser" })
        local mine = cl.when("config.browser.tabOrder == 'browser'", {})
        T.stub(cl, "userSettings", {})
        local declared = cl.when("config.browser.tabOrder == 'recent'", {})
        local missing = cl.when("config.browser.noSuchSetting || config.nosuch.thing || config.browser", {})
        local own = cl.when("config.browser.tabOrder == 'mine'", { ["config.browser.tabOrder"] = "mine" })
        return mine and declared and not missing and own,
               ("%s %s %s %s"):format(tostring(mine), tostring(declared), tostring(missing), tostring(own))
      end)())
check("a config key is read once per context, however many rows ask", (function()
        local reads, real = 0, cl.setting
        T.stub(cl, "setting", function(...)
          reads = reads + 1
          return real(...)
        end)
        local ctx = {}
        local scoped = cl.argContext(ctx, { activeView = "root" })
        for _ = 1, 20 do
          cl.when("config.browser.tabOrder == 'recent'", ctx)
          cl.when("config.browser.tabOrder", scoped)
        end
        local once = reads
        cl.when("config.browser.tabOrder", {})
        return once == 1 and reads == 2, ("%d then %d"):format(once, reads)
      end)())
