-- CommandLayer.spoon/tests/commands.lua
-- Commands, verbs, and commands that ask.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local ctx = T.context()
local palette = cl.gather(ctx, { menus = { "commandPalette" } })
local noop = T.noop
local logged = T.logged
local rankerEntry = T.rankerEntry
local substringOnly = T.substringOnly
local removeView = T.removeView
local layerModal = T.layerModal

group("commands")
-- Swaps a registered command for one recording its calls; the second
-- value puts the original back.
local function spyCommand(id)
  local calls, was = {}, cl.getCommand(id)
  cl.registerCommand(id, { title = "spy", menus = {}, run = function(args, c)
    calls[#calls + 1] = { args = args, ctx = c }
  end })
  return calls, function() if was then cl.registerCommand(id, was) end end
end

local function rowWithCommand(rows, id)
  for _, row in ipairs(rows) do
    if row.command == id then return row end
  end
end

check("a command is registered, and registering its id again replaces it",
      (function()
        cl.registerCommand("test.a", { title = "A", menus = {}, run = function() end })
        local first = cl.getCommand("test.a")
        cl.registerCommand("test.a", { title = "B", menus = {}, run = function() end })
        local count = 0
        for _, command in ipairs(cl.getCommands()) do
          if command.id == "test.a" then count = count + 1 end
        end
        return first and first.title == "A" and cl.getCommand("test.a").title == "B"
               and count == 1, tostring(count) .. " registered"
      end)())

check("a command outside its extension's namespace is skipped, and logged",
      (function()
        local mark = #logged
        cl.register({ name = "test-ns", commands = {
          { id = "test-ns.ok",  title = "ok",  menus = {}, run = function() end },
          { id = "other.bad",   title = "bad", menus = {}, run = function() end },
        } })
        local said = false
        for i = mark + 1, #logged do
          if logged[i]:find("other.bad", 1, true) then said = true end
        end
        return cl.getCommand("test-ns.ok") ~= nil
               and cl.getCommand("other.bad") == nil and said
      end)())

check("a command is a row in its menus, carrying its id", (function()
        cl.registerCommand("test.row", { title = "Row", category = "Test",
          menus = { "test-menu" }, run = function() end })
        local row = rowWithCommand(cl.gather(ctx, { menus = { "test-menu" } }), "test.row")
        return row ~= nil and row.label == "Test: Row" and row.description == nil
               and row.subject.kind == "command" and row.subject.id == "test.row"
      end)())

check("and in no other menu, while menus = {} is no row at all", (function()
        cl.registerCommand("test.none", { title = "None", menus = {},
                                          run = function() end })
        return rowWithCommand(cl.gather(ctx, { menus = { "commandPalette" } }), "test.row") == nil
               and rowWithCommand(cl.gather(ctx), "test.none") == nil
      end)())

check("executeCommand with every argument runs it", (function()
        local got, ran
        cl.registerCommand("test.act", { title = "Act", menus = {},
          inputs = { { id = "name", picker = { typed = true } } },
          run = function(_, c) got = c.name end })
        cl.registerCommand("test.run", { title = "Run", menus = {},
          run = function(args, c) ran = args.n == 1 and type(c) == "table" end })
        cl.executeCommand("test.act", { name = "given" })
        cl.executeCommand("test.run", { n = 1 })
        return got == "given" and ran == true, tostring(got)
      end)())

check("an unknown command returns false", cl.executeCommand("no.such.command") == false)

check("a row runs the command it names with its args, or its own run", (function()
        local got, ran
        cl.registerCommand("test.rowTarget", { title = "Row target", menus = {},
          run = function(args) got = args.x end })
        local undo = T.picker("test-rowruns", function()
          return { { label = "named", command = "test.rowTarget", args = { x = 7 } },
                   { label = "own", run = function(ctx) ran = ctx ~= nil end } }
        end)
        for _, label in ipairs({ "named", "own" }) do
          cl.open("test-rowruns")
          local p = cl.viewNamed("test-rowruns").picker
          for i, row in ipairs(p and p.shown or {}) do
            if row.label == label then p.row = i end
          end
          if p then p.accept() end
        end
        undo()
        return got == 7 and ran == true, tostring(got) .. " / " .. tostring(ran)
      end)())

check("a command may run another with args of its own, filled from what it asked", (function()
        local got
        cl.registerCommand("test.destination", { title = "Destination", menus = {},
          run = function(args, ctx) got = cl.resolve(args.target, ctx) end })
        cl.registerCommand("test.search", { title = "Search", menus = {},
          inputs = { { id = "q", picker = { typed = true } } },
          command = "test.destination", args = { target = "https://example.com/?q=${q}" } })
        cl.executeCommand("test.search", { q = "lofi" })
        return got == "https://example.com/?q=lofi", tostring(got)
      end)())

check("commands that run each other in a circle stop, and say so", (function()
        cl.registerCommand("test.circleA", { title = "A", menus = {}, command = "test.circleB" })
        cl.registerCommand("test.circleB", { title = "B", menus = {}, command = "test.circleA" })
        local mark = #logged
        local ok = pcall(cl.executeCommand, "test.circleA", {})
        return ok and tostring(logged[mark + 1]):find("leads back to itself", 1, true) ~= nil,
               tostring(logged[mark + 1])
      end)())

check("a command run by id returns what its run returned", (function()
        cl.registerCommand("test.result", { title = "Result", menus = {}, run = function() return 42 end })
        local ran, value = cl.executeCommand("test.result", {})
        return ran == true and value == 42, tostring(ran) .. " / " .. tostring(value)
      end)())

-- Run by id the layer is often closed, so a log line alone is nothing on
-- screen; a picked row's failure already alerts through dispatch.
check("a command that throws, run by id, is reported with the alert a failing backend shows", (function()
        cl.registerCommand("test.boom", { title = "Boom", menus = {}, run = function() error("boom") end })
        local shown, real = {}, hs.alert.show
        hs.alert.show = function(message) shown[#shown + 1] = message end
        local ok = pcall(cl.executeCommand, "test.boom", {})
        hs.alert.show = real
        return ok and shown[1] == "Could not run Boom", tostring(shown[1])
      end)())

check("${command:id} in a template is what the command returns; a command asking for itself gets nothing", (function()
        cl.registerCommand("test.answer", { title = "Answer", menus = {}, run = function() return "forty-two" end })
        cl.registerCommand("test.selfish", { title = "Selfish", menus = {},
          run = function(_, ctx) return "[" .. cl.resolve("${command:test.selfish}", ctx) .. "]" end })
        local filled = cl.resolve("x ${command:test.answer} y ${command:no.such.answer}", {})
        local ok, _, selfish = pcall(cl.executeCommand, "test.selfish", {})
        -- Run by id it runs once more from its template, and that one asking
        -- again gets nothing: it stops instead of recursing without end.
        return filled == "x forty-two y " and ok and selfish == "[[]]",
               tostring(filled) .. " / " .. tostring(selfish)
      end)())

-- VS Code's tasks.json `command` input: a value that comes from running a
-- command, whether the command taking it is run by id or picked.
check("a command input is answered by running its command, run by id or picked", (function()
        local got = {}
        cl.registerCommand("test.provider", { title = "Provider", menus = {}, run = function() return "provided" end })
        cl.registerCommand("test.consumer", { title = "Consumer", menus = { "test-cmdinput" },
          inputs = { { id = "v", command = "test.provider" } },
          run = function(args) got[#got + 1] = args.v end })
        cl.executeCommand("test.consumer", {})
        cl.view({ name = "test-cmdinput", menus = { "test-cmdinput" }, presenter = "recording" })
        local saved = cl.matchers
        cl.matchers = substringOnly()
        cl.open("test-cmdinput")
        local p = cl.viewNamed("test-cmdinput").picker
        for i, row in ipairs(p and p.shown or {}) do
          if row.command == "test.consumer" then p.row = i end
        end
        if p then p.accept() end
        cl.matchers = saved
        removeView("test-cmdinput")
        return table.concat(got, " ") == "provided provided", table.concat(got, " ")
      end)())

check("commandPalette is the palette's menu, and palette is not another name for it", (function()
        cl.register({ name = "old-menus", menus = { "palette" },
          items = function() return { { label = "old row", subject = { kind = "t", name = "old" } } } end })
        local inPalette = false
        for _, row in ipairs(cl.gather(cl.buildContext(), { menus = { "commandPalette" } })) do
          if row.label == "old row" then inPalette = true end
        end
        cl.unregisterExtension("old-menus")
        cl.registerCommand("test.defaultMenus", { title = "Default menus", run = function() end })
        local menus = cl.getCommand("test.defaultMenus").menus
        return not inPalette and menus[1] == "commandPalette",
               tostring(inPalette) .. " / " .. tostring(menus[1])
      end)())

check("a missing argument enters the layer and asks for it", (function()
        cl.registerCommand("test.ask", { title = "Ask", menus = {}, run = function() end,
          inputs = { { id = "name", description = "Name?", picker = { typed = true } } } })
        local rec, made = cl.presenters.recording
        local create = rec.create
        rec.create = function(opts) made = create(opts); return made end
        local savedEnter, savedPresenter = layerModal.enter, cl.defaultPresenter
        local entered = false
        layerModal.enter = function(m) entered = true; m:entered() end
        cl.defaultPresenter = "recording"
        layerModal:exited()
        local ok, err = pcall(cl.executeCommand, "test.ask", {})
        rec.create, layerModal.enter, cl.defaultPresenter = create, savedEnter, savedPresenter
        layerModal:exited()
        return ok and entered and made ~= nil and made.placeholder == "Name?",
               tostring(err or (made and made.placeholder))
      end)())

check("two commands asking for arguments before the layer opens both ask, the last on top", (function()
        for _, which in ipairs({ "First", "Second" }) do
          cl.registerCommand("test.ask" .. which, { title = which, menus = {}, run = function() end,
            inputs = { { id = "a", description = which .. "?", picker = { typed = true } } } })
        end
        local savedEnter, savedPresenter = layerModal.enter, cl.defaultPresenter
        -- Entering does not open the layer yet, so the second arrives first.
        layerModal.enter = noop
        cl.defaultPresenter = "recording"
        layerModal:exited()
        cl.executeCommand("test.askFirst", {})
        cl.executeCommand("test.askSecond", {})
        layerModal:entered()
        local top = T.lastRecorded() and T.lastRecorded().placeholder
        -- Escape steps back to the one beneath.
        if T.lastRecorded() then T.lastRecorded().dismiss() end
        local beneath = T.lastRecorded() and T.lastRecorded().placeholder
        layerModal.enter, cl.defaultPresenter = savedEnter, savedPresenter
        layerModal:exited()
        return top == "Second?" and beneath == "First?", tostring(top) .. " / " .. tostring(beneath)
      end)())

check("a tool registered again with the same paths is one registration; with other paths, a problem", (function()
        local before = #cl.problems
        cl.tools.register("test-tool", { "/usr/bin/true" })
        cl.tools.register("test-tool", { "/usr/bin/true" })
        local same = #cl.problems == before
        cl.tools.register("test-tool", { "/opt/elsewhere/true" })
        local clash = #cl.problems == before + 1
        local first = cl.tools.candidates["test-tool"][1] == "/usr/bin/true"
        cl.tools.candidates["test-tool"] = nil
        while #cl.problems > before do table.remove(cl.problems) end
        return same and clash and first
      end)())

check("a $(name) icon comes from a row's label or icon field, drawn by a provider", (function()
        cl.themeIconProvider("test-icons", function(name) return name == "rocket" and "ROCKET" or nil end)
        cl.register({ name = "iconic", menus = { "iconic" }, items = function()
          return { { label = "$(rocket) Launch", subject = { kind = "t", name = "launch" } },
                   { label = "Spin", icon = "$(rocket~spin)", subject = { kind = "t", name = "spin" } },
                   { label = "$(nothing-draws-this) Plain", subject = { kind = "t", name = "plain" } } }
        end })
        cl.registerCommand("test.iconic", { title = "Iconic", icon = "$(rocket)", menus = { "iconic" },
                                            run = function() end })
        local byName = {}
        for _, row in ipairs(cl.gather(cl.buildContext(), { menus = { "iconic" } })) do
          byName[row.command or row.subject.name] = row
        end
        cl.unregisterExtension("iconic")
        cl.registerCommand("test.iconic", { title = "Iconic", menus = {}, run = function() end })
        cl.themeIconProvider("test-icons", function() return nil end)
        local launch, spin, plain, command = byName.launch, byName.spin, byName.plain, byName["test.iconic"]
        return launch and launch.label == "Launch" and launch.iconPath == "ROCKET"
               and spin and spin.iconPath == "ROCKET"
               and plain and plain.label == "Plain" and plain.iconPath == nil
               and command and command.iconPath == "ROCKET",
               ("%s/%s, %s, %s/%s, %s"):format(tostring(launch and launch.label), tostring(launch and launch.iconPath),
                 tostring(spin and spin.iconPath), tostring(plain and plain.label), tostring(plain and plain.iconPath),
                 tostring(command and command.iconPath))
      end)())

check("menus as VS Code writes them: a table of menus, each with its own when", (function()
        cl.registerCommand("test.perMenu", { title = "Per menu", run = function() end,
          menus = { commandPalette = true, root = { when = "frontmostApp == 'Safari'" } } })
        local function inMenu(menu, app)
          for _, row in ipairs(cl.gather({ frontmostApp = app }, { menus = { menu } })) do
            if row.command == "test.perMenu" then return true end
          end
          return false
        end
        local palette, rootElsewhere, rootInSafari =
          inMenu("commandPalette", "Finder"), inMenu("root", "Finder"), inMenu("root", "Safari")
        cl.registerCommand("test.perMenu", { title = "Per menu", run = function() end, menus = {} })
        return palette and not rootElsewhere and rootInSafari,
               ("palette %s, root %s, root in Safari %s"):format(tostring(palette),
                 tostring(rootElsewhere), tostring(rootInSafari))
      end)())

check("rows may use VS Code's quick pick names: label, description, detail, iconPath", (function()
        cl.register({ name = "vs-rows", menus = { "vs-rows" }, items = function()
          return { { label = "Named", description = "desc", detail = "more", iconPath = "icon",
                     subject = { kind = "t", name = "named" } } }
        end })
        local row = cl.gather(cl.buildContext(), { menus = { "vs-rows" } })[1]
        cl.unregisterExtension("vs-rows")
        return row ~= nil and row.label == "Named" and cl.secondLine(row) == "desc  --  more"
               and row.iconPath == "icon",
               row and (tostring(row.label) .. " / " .. tostring(cl.secondLine(row)))
      end)())

check("a separator row labels the row after it, and a ranked list drops it", (function()
        local rows = { { kind = "separator", label = "Group" },
                       { label = "alpha", description = "first", subject = { kind = "t", name = "a" } },
                       { label = "bravo", subject = { kind = "t", name = "b" } } }
        -- A search picker shows its own rows as given while nothing is typed.
        local undo = T.picker("test-sep", rows, { kind = "search" })
        cl.open("test-sep")
        local p = cl.viewNamed("test-sep").picker
        local shown = p and p.shown or {}
        local ranked
        cl.rankItems(rows, "", function(out) ranked = out end)
        undo()
        return #shown == 2 and shown[1].description == "Group  --  first" and shown[2].description == nil
               and rows[2].description == "first" and ranked ~= nil and #ranked == 2,
               ("%d shown, first %s, %s ranked"):format(#shown, tostring(shown[1] and shown[1].description),
                 tostring(ranked and #ranked))
      end)())

check("a command whose enablement does not hold is greyed out, and refused when picked", (function()
        local ran = false
        cl.registerCommand("test.enabled", { title = "Only in Safari", menus = { "test-enable" },
          enablement = "frontmostApp == 'Safari'", run = function() ran = true end })
        cl.view({ name = "test-enable", menus = { "test-enable" }, presenter = "recording" })
        local alerts, realAlert = 0, hs.alert.show
        hs.alert.show = function() alerts = alerts + 1 end
        local function rowIn(app)
          for _, row in ipairs(cl.gather({ frontmostApp = app }, { menus = { "test-enable" } })) do
            if row.command == "test.enabled" then return row end
          end
        end
        local off, on = rowIn("Finder"), rowIn("Safari")
        cl.open("test-enable")
        local p = cl.viewNamed("test-enable").picker
        local before, index = layerModal.exits, nil
        for i, row in ipairs(p and p.shown or {}) do
          if row.command == "test.enabled" then index = i end
        end
        if index then
          p.row = index
          p.accept()
        end
        hs.alert.show = realAlert
        removeView("test-enable")
        cl.registerCommand("test.enabled", { title = "Only in Safari", menus = {}, run = function() end })
        return off ~= nil and off.enabled == false and off.description:find("^Unavailable") ~= nil
               and on ~= nil and on.enabled ~= false
               and index ~= nil and not ran and alerts == 1 and layerModal.exits == before,
               ("off %s, on %s, index %s, ran %s, alerts %d"):format(tostring(off and off.enabled),
                 tostring(on and on.enabled), tostring(index), tostring(ran), alerts)
      end)())

check("a picker with a when lists the rows it holds for, and hands the chosen subject to run", (function()
        local got
        cl.register({ name = "things", menus = { "things" }, items = function()
          return { { label = "Red box", subject = { kind = "box", colour = "red", name = "red" } },
                   { label = "Blue box", subject = { kind = "box", colour = "blue", name = "blue" } },
                   { label = "A ball", subject = { kind = "ball", name = "ball" } } }
        end })
        cl.registerCommand("test.paint", { title = "Paint", menus = {},
          inputs = { { id = "box", description = "Which box?",
                       picker = { when = "viewItem == 'box' && colour != 'blue'", menus = { "things" },
                                  options = { { label = "Choose…", value = { kind = "box", name = "chosen" } } } } } },
          run = function(args) got = args.box end })
        local savedEnter, savedPresenter = layerModal.enter, cl.defaultPresenter
        layerModal.enter = function(m) m:entered() end
        cl.defaultPresenter = "recording"
        layerModal:exited()
        cl.executeCommand("test.paint", {})
        local prompt = T.lastRecorded() and T.lastRecorded().placeholder == "Which box?" and T.lastRecorded() or nil
        local texts = {}
        for _, row in ipairs(prompt and prompt.shown or {}) do texts[#texts + 1] = row.label end
        if prompt then
          prompt.row = 1
          prompt.accept()
        end
        layerModal.enter, cl.defaultPresenter = savedEnter, savedPresenter
        layerModal:exited()
        cl.unregisterExtension("things")
        cl.registerCommand("test.paint", { title = "Paint", menus = {}, run = function() end })
        return table.concat(texts, " ") == "Red box Choose…" and got ~= nil and got.colour == "red",
               table.concat(texts, " ") .. " / " .. tostring(got and got.name)
      end)())

check("a row picked in a question answers with its value, else its subject, never runs itself, and typing "
      .. "there switches no picker", (function()
        local got, rowRan = {}, false
        cl.registerCommand("test.rowOwn", { title = "Own", menus = {}, run = function() rowRan = true end })
        cl.register({ name = "loud-things", menus = { "loud-things" }, items = function()
          return { { label = "Loud box", subject = { kind = "box", name = "loud" }, command = "test.rowOwn",
                     keepOpen = true } }
        end })
        cl.registerCommand("test.store", { title = "Store", menus = {},
          inputs = { { id = "box", description = "Which box to store?",
                       picker = { when = "viewItem == 'box'", menus = { "loud-things" },
                                  options = { { label = "Shelf", value = "shelf" } } } } },
          run = function(args) got[#got + 1] = args.box end })
        local savedEnter, savedPresenter = layerModal.enter, cl.defaultPresenter
        layerModal.enter = function(m) m:entered() end
        cl.defaultPresenter = "recording"
        local function ask()
          layerModal:exited()
          cl.executeCommand("test.store", {})
          local prompt = T.lastRecorded()
          return prompt and prompt.placeholder == "Which box to store?" and prompt or nil
        end
        local function pick(label)
          local prompt = ask()
          for i, row in ipairs(prompt and prompt.shown or {}) do
            if row.label == label then
              prompt.row = i
              prompt.accept()
              return true
            end
          end
          return false
        end
        local pickedBox, pickedShelf = pick("Loud box"), pick("Shelf")
        local typedInto = ask()
        if typedInto then typedInto.type(">") end
        local stayed = typedInto ~= nil and T.lastRecorded() == typedInto
        layerModal.enter, cl.defaultPresenter = savedEnter, savedPresenter
        layerModal:exited()
        cl.unregisterExtension("loud-things")
        return pickedBox and pickedShelf and not rowRan and type(got[1]) == "table" and got[1].name == "loud"
               and got[2] == "shelf" and stayed,
               ("box %s, shelf %s, row ran %s, got %s / %s, stayed %s"):format(tostring(pickedBox),
                 tostring(pickedShelf), tostring(rowRan), tostring(type(got[1]) == "table" and got[1].name),
                 tostring(got[2]), tostring(stayed))
      end)())

check("the same command is a verb on every row its picker's when takes, with that row given", (function()
        local got
        cl.registerCommand("test.polish", { title = "Polish", category = "Test", menus = {},
          inputs = { { id = "box", picker = { when = "viewItem == 'box'" } } },
          run = function(args) got = args.box end })
        local function verb(subject)
          for _, v in ipairs(cl.itemActions(subject, {})) do
            if v.command == "test.polish" then return v end
          end
        end
        local onBox, onBall = verb({ kind = "box", name = "b" }), verb({ kind = "ball", name = "x" })
        if onBox then cl.executeCommand("test.polish", onBox.args, {}) end
        cl.registerCommand("test.polish", { title = "Polish", menus = {}, run = function() end })
        return onBox ~= nil and onBox.label == "Polish" and onBall == nil and got ~= nil and got.name == "b",
               tostring(onBox and onBox.label) .. " / " .. tostring(got and got.name)
      end)())

check("a when about a row can ask for a key worked out when asked, once", (function()
        local asked = 0
        cl.itemContextKey("testHeavy", function(subject)
          asked = asked + 1
          return subject.name == "yes"
        end)
        local yes = cl.itemContext({ kind = "t", name = "yes" }, {})
        local no = cl.itemContext({ kind = "t", name = "no" }, {})
        local results = { cl.when("testHeavy", yes), cl.when("testHeavy && viewItem == 't'", yes),
                          cl.when("testHeavy", no), cl.when("!testHeavy", no) }
        return results[1] and results[2] and not results[3] and results[4] and asked == 2,
               ("%s %s %s %s, asked %d"):format(tostring(results[1]), tostring(results[2]),
                 tostring(results[3]), tostring(results[4]), asked)
      end)())

check("run by id, an input with current is answered by what is in front", (function()
        local got
        cl.registerCommand("test.front", { title = "Front", menus = {},
          inputs = { { id = "thing", picker = { when = "viewItem == 'box'" },
                       current = function(ctx) return ctx.frontThing end } },
          run = function(args) got = args.thing end })
        cl.executeCommand("test.front", {}, { frontThing = { kind = "box", name = "front" } })
        cl.registerCommand("test.front", { title = "Front", menus = {}, run = function() end })
        return got ~= nil and got.name == "front", tostring(got and got.name)
      end)())

check("picked, an input that prefers what is in front takes it; cmd+k on the row asks", (function()
        local got
        cl.registerCommand("test.nudge", { title = "Nudge", menus = { "test-nudge" },
          inputs = { { id = "box", description = "Which box to nudge?",
                       picker = { when = "viewItem == 'box'" }, preferCurrent = true,
                       current = function() return { kind = "box", name = "front" } end } },
          run = function(args) got = args.box end })
        cl.view({ name = "test-nudge", menus = { "test-nudge" }, presenter = "recording" })
        local savedPresenter = cl.defaultPresenter
        cl.defaultPresenter = "recording"

        cl.open("test-nudge")
        local p = cl.viewNamed("test-nudge").picker
        local index
        for i, row in ipairs(p and p.shown or {}) do
          if row.command == "test.nudge" then index = i end
        end
        if index then
          p.row = index
          p.accept()
        end
        local picked = got and got.name

        got = nil
        cl.open("test-nudge")
        p = cl.viewNamed("test-nudge").picker
        p.row = index
        cl.showItemActions()
        local asked = T.lastRecorded() and T.lastRecorded().placeholder

        cl.defaultPresenter = savedPresenter
        layerModal:exited()
        removeView("test-nudge")
        cl.registerCommand("test.nudge", { title = "Nudge", menus = {}, run = function() end })
        return picked == "front" and got == nil and asked == "Which box to nudge?",
               ("picked %s, then %s, asked %s"):format(tostring(picked), tostring(got and got.name),
                 tostring(asked))
      end)())

check("a typed picker offers its default; options may be plain strings, the default first", (function()
        cl.registerCommand("test.prompted", { title = "Prompted", menus = {}, run = function() end,
          inputs = { { id = "name", description = "Name?", default = "notes", picker = { typed = true } } } })
        cl.registerCommand("test.picked", { title = "Picked", menus = {}, run = function() end,
          inputs = { { id = "size", description = "Size?",
                       picker = { options = { "small", "medium", "large" } }, default = "large" } } })
        local savedEnter, savedPresenter = layerModal.enter, cl.defaultPresenter
        layerModal.enter = function(m) m:entered() end
        cl.defaultPresenter = "recording"
        layerModal:exited()
        cl.executeCommand("test.prompted", {})
        local promptRows = T.lastRecorded() and T.lastRecorded().placeholder == "Name?" and T.lastRecorded().shown
        layerModal:exited()
        cl.executeCommand("test.picked", {})
        local pick = T.lastRecorded() and T.lastRecorded().placeholder == "Size?" and T.lastRecorded() or nil
        layerModal.enter, cl.defaultPresenter = savedEnter, savedPresenter
        layerModal:exited()
        local picks = {}
        for _, row in ipairs(pick and pick.shown or {}) do picks[#picks + 1] = row.label end
        local first = promptRows and promptRows[1]
        return first ~= nil and first.label == "notes" and table.concat(picks, " ") == "large small medium",
               tostring(first and first.label) .. " / " .. table.concat(picks, " ")
      end)())

check("a keybinding can name any command, with args", (function()
        local calls, restore = spyCommand("appmenus.select")
        local known = cl.knowsCommand("appmenus.select")
        cl.runKeybinding({ key = "cmd+shift+n", command = "appmenus.select",
                           args = { app = "Brave Browser", path = { "File", "New Window" } } })
        restore()
        return known and calls[1] ~= nil and calls[1].args.app == "Brave Browser"
               and calls[1].args.path[2] == "New Window"
      end)())

check("a scraped menu row stays a menu, and runs through appmenus.select",
      (function()
        local registered = cl.getCommand("appmenus.select")
        local menus = cl.modules.appmenus
        menus.refresh({ name = function() return "TestApp" end,
          getMenuItems = function(_, cb)
            cb({ { AXTitle = "File", AXChildren = { { { AXTitle = "New Window" } } } } })
          end })
        local ext
        for _, e in ipairs(cl.extensions) do
          if e.name == "appmenus" then ext = e end
        end
        local row = ext and ext.items({ frontmostApp = "TestApp" })[1]
        local calls, restore = spyCommand("appmenus.select")
        if row and row.command then cl.executeCommand(row.command, row.args, {}) end
        restore()
        menus.forget("TestApp")
        return registered ~= nil and registered.extension == "appmenus"
               and row ~= nil and row.subject.kind == "menu" and row.command == "appmenus.select"
               and calls[1] ~= nil and calls[1].args.app == "TestApp"
               and calls[1].args.path[2] == "New Window"
      end)())

check("a command's history survives a new title", (function()
        T.picker("test-cmd-row", { { label = "Old title", subject = { kind = "command", id = "test.renamed" },
                                     run = function() end } })
        cl.open("test-cmd-row")
        cl.viewNamed("test-cmd-row").picker.accept()
        return rankerEntry("frecency").score({ label = "New title",
                                               subject = { kind = "command", id = "test.renamed" } }) > 0
      end)())

check("git.clone and the window layouts are registered", (function()
        local clone, left = cl.getCommand("git.clone"), cl.getCommand("windows.leftHalf")
        return clone ~= nil and clone.category == "Git" and clone.inputs ~= nil
               and left ~= nil and left.category == "Window"
               and cl.getCommand("windows.leftTwoThirds") ~= nil
      end)())

check("a view/item/context entry narrows where a command is offered on a row, and puts it in no picker", (function()
        cl.registerCommand("test.itemVerb", { title = "Poke", run = function() end,
          inputs = { { id = "thing", picker = { when = "viewItem == 'poke-thing'" } } },
          menus = { ["view/item/context"] = { when = "name == 'yes'" } } })
        local ctx = cl.buildContext()
        local function offered(name)
          for _, row in ipairs(cl.itemActions({ kind = "poke-thing", name = name }, ctx)) do
            if row.command == "test.itemVerb" then return true end
          end
          return false
        end
        local inPicker = false
        for _, row in ipairs(cl.gather(ctx, { menus = { "root", "commandPalette" } })) do
          if row.command == "test.itemVerb" then inPicker = true end
        end
        local yes, no = offered("yes"), offered("no")
        cl.unregisterCommand("test.itemVerb")
        return yes and not no and not inPicker,
               ("yes %s, no %s, in a picker %s"):format(tostring(yes), tostring(no), tostring(inPicker))
      end)())

check("a command whose only menu is view/item/context is a row in no picker, even one naming no menus", (function()
        cl.registerCommand("test.itemOnly", { title = "Item only", run = function() end,
          inputs = { { id = "thing", picker = { when = "viewItem == 'poke-thing'" } } },
          menus = { ["view/item/context"] = true } })
        local found = false
        for _, row in ipairs(cl.gather(cl.buildContext())) do
          if row.command == "test.itemOnly" then found = true end
        end
        local menus = cl.getCommand("test.itemOnly").menus
        cl.unregisterCommand("test.itemOnly")
        return not found and not cl.hasMenus(menus), "a row: " .. tostring(found)
      end)())

group("verbs")
local fileVerbs = cl.itemActions({ kind = "file", path = "/tmp/a.txt" }, ctx)
check("a file has verbs", #fileVerbs > 0, tostring(#fileVerbs))

local appVerbs = cl.itemActions({ kind = "app", name = "Finder",
                                  id = "com.apple.finder" }, ctx)
check("an app has verbs", #appVerbs > 0, tostring(#appVerbs))

check("an unknown kind has none",
      #cl.itemActions({ kind = "nonsense" }, ctx) == 0)

local named = 0
for _, verb in ipairs(fileVerbs) do
  if type(verb.label) == "string" and verb.label ~= "" then named = named + 1 end
end
check("every verb is named", named == #fileVerbs)

-- The verb reads as its title alone, but it is still the command whose
-- category names it: typing "git" on a repository row kept nothing before.
check("a verb on cmd+k is matched by its command's category, though the label leaves it out", (function()
        cl.registerCommand("test.categorised", { title = "Pull", category = "Git", menus = {},
          inputs = { { id = "thing", picker = { when = "viewItem == 'boxish'" } } },
          run = function() end })
        local verb
        for _, row in ipairs(cl.itemActions({ kind = "boxish", name = "one" }, ctx)) do
          if row.command == "test.categorised" then verb = row end
        end
        cl.unregisterCommand("test.categorised")
        if not verb then return false, "no verb" end
        local kept, matchers = {}, cl.matchers
        cl.matchers = substringOnly()
        cl.rankItems({ verb }, "git", function(out) kept = out end)
        cl.matchers = matchers
        return verb.label == "Pull" and #kept == 1, verb.label .. " / " .. #kept .. " kept for 'git'"
      end)())

-- cmd+k learns per kind of row: a verb picked on a box rises among a box's
-- verbs and leaves a ball's order where it was.
check("a verb picked on cmd+k rises on that kind of row, and only there", (function()
        for _, id in ipairs({ "n2.alpha", "n2.beta" }) do
          cl.registerCommand(id, { title = id:sub(4, 4):upper() .. id:sub(5), menus = {},
            inputs = { { id = "thing",
                         picker = { when = "viewItem == 'boxish' || viewItem == 'ballish'" } } },
            run = function() end })
        end
        local function ranked(kind)
          local rows, names = cl.itemActions({ kind = kind, name = kind }, ctx), {}
          cl.rankItems(rows, "", function(out)
            for i, row in ipairs(out) do names[i] = tostring(row.label) end
          end)
          return names, rows
        end

        local before = ranked("boxish")
        local _, boxRows = ranked("boxish")
        local beta
        for _, row in ipairs(boxRows) do if row.label == "Beta" then beta = row end end
        if not beta then return false, "no Beta verb" end
        for _ = 1, 3 do cl.recordUse(beta) end

        local afterBox = ranked("boxish")
        local afterBall = ranked("ballish")
        cl.removeRecentlyUsed(beta)
        cl.unregisterCommand("n2.alpha")
        cl.unregisterCommand("n2.beta")
        return before[1] == "Alpha" and afterBox[1] == "Beta" and afterBall[1] == "Alpha",
               table.concat(before, ",") .. " -> box " .. table.concat(afterBox, ",")
               .. " / ball " .. table.concat(afterBall, ",")
      end)())

group("quicklinks ask for their query")
local asked
for _, row in ipairs(palette) do
  local command = type(row.command) == "string" and cl.getCommand(row.command)
  if command and command.inputs then asked = command end
end
check("something declares inputs", asked ~= nil,
      asked and asked.title or "nothing does")
if asked then
  check("the input has an id and a picker or a command", asked.inputs[1].id ~= nil
        and (asked.inputs[1].picker ~= nil or asked.inputs[1].command ~= nil))
end
