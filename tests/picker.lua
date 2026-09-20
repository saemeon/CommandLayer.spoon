-- CommandLayer.spoon/tests/picker.lua
-- The picker: what a command does to it once run, argument steps and
-- validation, naming a target and confirming, searching, the highlight
-- across a redraw, and a level hearing it is left.

local T = ...
local check, group, stub = T.check, T.group, T.stub
local cl = T.layer()
local layerModal = T.layerModal
local removeView = T.removeView
local substringOnly = T.substringOnly

-- Before anything makes the one picker every argument prompt shares, which
-- takes the default presenter once.
cl.defaultPresenter = "recording"

local function indexOf(picker, id)
  for i, row in ipairs(picker and picker.shown or {}) do
    if row.command == id then return i end
  end
end

-- Argument prompts are drawn by the default presenter, so the layer is
-- entered through the recording one and closed again after.
local function asking(fn)
  local savedEnter = layerModal.enter
  layerModal.enter = function(m) m:entered() end
  layerModal:exited()
  local ok, err = pcall(fn)
  layerModal.enter = savedEnter
  layerModal:exited()
  if not ok then error(err, 0) end
end

----------------------------------------------------------------------
group("after a command")

local builds = 0
cl.register({ name = "test-after", menus = { "test-after" },
  items = function()
    builds = builds + 1
    return { { label = "a thing", subject = { kind = "t", name = "thing" } } }
  end })
cl.view({ name = "test-after", menus = { "test-after" }, presenter = "recording" })
T.picker("test-after-parent", { { label = "parent row" } })

local runs = {}
local function afterCommand(after, inputs)
  local id = "test.after" .. (after or "Close") .. (inputs and "Asks" or "")
  runs[id] = 0
  cl.registerCommand(id, { title = id, menus = { "test-after" }, after = after, inputs = inputs,
    run = function(args) runs[id] = runs[id] + 1; runs[id .. ".args"] = args end })
  return id
end
local keepOpen, back, close = afterCommand("keepOpen"), afterCommand("back"), afterCommand(nil)
local keepAsking = afterCommand("keepOpen", { { id = "name", description = "Name?", picker = { typed = true } } })

check("keepOpen runs the command and redraws the picker where it was, in the context it had", (function()
        cl.open("test-after")
        local p = cl.viewNamed("test-after").picker
        local ctx, before, exits = cl.topView().ctx, builds, layerModal.exits
        p.row = indexOf(p, keepOpen)
        p.accept()
        local top = cl.topView()
        return runs[keepOpen] == 1 and layerModal.exits == exits and top and top.name == "test-after"
               and top.ctx == ctx and builds == before + 1 and p.hidden ~= true,
               ("%d runs, %d exits, %d builds, top %s"):format(runs[keepOpen], layerModal.exits - exits,
                 builds - before, tostring(top and top.name))
      end)())

-- A row carrying keepOpen of its own, as a settings switch does: the same
-- promise, for a row that runs Lua rather than a command.
local flips = 0
cl.register({ name = "test-switch", menus = { "test-switch" },
  items = function(ctx)
    return { { label = "Browser: Bookmarks", ctx = ctx, keepOpen = true,
               subject = { kind = "setting", id = "browser.bookmarks" },
               run = function() flips = flips + 1 end } }
  end })
cl.view({ name = "test-switch", menus = { "test-switch" }, presenter = "recording" })

check("a row that says keepOpen runs and leaves the picker open, redrawn where it was", (function()
        cl.open("test-switch")
        local p = cl.viewNamed("test-switch").picker
        local exits = layerModal.exits
        p.row = 1
        p.accept()
        local top = cl.topView()
        return flips == 1 and layerModal.exits == exits and top and top.name == "test-switch"
               and p.hidden ~= true,
               ("%d flips, %d exits, top %s"):format(flips, layerModal.exits - exits,
                                                    tostring(top and top.name))
      end)())

check("a row that is not available says so, runs nothing, and the picker is back on screen", (function()
        local ran = false
        local remove = T.picker("test-unavailable",
          { { label = "Not now", enabled = false, run = function() ran = true end },
            { label = "Fine" } })
        local alerts = {}
        stub(hs.alert, "show", function(message) alerts[#alerts + 1] = message end)
        local p = T.openRecorded("test-unavailable")
        local exits = layerModal.exits
        p.row = 1
        p.accept()
        -- Read before the layer is closed again, which hides it in any case.
        local top, onScreen = cl.topView(), p.hidden ~= true
        layerModal:exited()
        remove()
        return ran == false and layerModal.exits == exits and onScreen
               and top and top.name == "test-unavailable"
               and alerts[1] == "Not now is not available now",
               tostring(alerts[1]) .. " / on screen " .. tostring(onScreen)
      end)())

check("back runs the command and steps back a level from where it was picked", (function()
        cl.open("test-after-parent")
        cl.push("test-after")
        local p = cl.viewNamed("test-after").picker
        local exits = layerModal.exits
        p.row = indexOf(p, back)
        p.accept()
        local top = cl.topView()
        return runs[back] == 1 and layerModal.exits == exits and top and top.name == "test-after-parent"
               and p.hidden == true, tostring(top and top.name)
      end)())

check("back from the only level closes the layer, and a command saying nothing closes it", (function()
        cl.open("test-after")
        local p = cl.viewNamed("test-after").picker
        local exits = layerModal.exits
        p.row = indexOf(p, back)
        p.accept()
        local afterBack = layerModal.exits - exits
        cl.open("test-after")
        p = cl.viewNamed("test-after").picker
        p.row = indexOf(p, close)
        p.accept()
        return afterBack == 1 and layerModal.exits - exits == 2 and runs[back] == 2 and runs[close] == 1,
               ("%d then %d exits"):format(afterBack, layerModal.exits - exits)
      end)())

check("keepOpen after an argument comes back to the picker, and the row asks again next time", (function()
        cl.open("test-after")
        local p = cl.viewNamed("test-after").picker
        local exits = layerModal.exits
        p.row = indexOf(p, keepAsking)
        p.accept()
        local prompt = T.lastRecorded()
        local asked = prompt ~= p and prompt.placeholder
        prompt.type("bob")
        prompt.accept()
        local top = cl.topView()
        local answered = runs[keepAsking .. ".args"]
        p.row = indexOf(p, keepAsking)
        p.accept()
        local again = T.lastRecorded() ~= p and T.lastRecorded().placeholder
        local stayedOpen = layerModal.exits == exits
        layerModal:exited()
        return asked == "Name?" and runs[keepAsking] == 1 and answered and answered.name == "bob"
               and top and top.name == "test-after" and stayedOpen and again == "Name?"
               and runs[keepAsking] == 1,
               ("asked %s, %d runs, top %s, again %s"):format(tostring(asked), runs[keepAsking],
                 tostring(top and top.name), tostring(again))
      end)())

check("run by id while the layer is open, a command's after is kept too", (function()
        cl.open("test-after")
        local exits = layerModal.exits
        local ran = cl.executeCommand(keepOpen, {})
        local top = cl.topView()
        local stayedOpen = layerModal.exits == exits
        layerModal:exited()
        return ran == true and runs[keepOpen] == 2 and stayedOpen
               and top and top.name == "test-after",
               ("ran %s, %d runs, %d exits, top %s"):format(tostring(ran), runs[keepOpen],
                 layerModal.exits - exits, tostring(top and top.name))
      end)())

----------------------------------------------------------------------
group("argument steps and validation")

local got
cl.registerCommand("test.twoSteps", { title = "Two steps", menus = {}, run = function(args) got = args end,
  inputs = { { id = "name", description = "Name", picker = { typed = true } },
             { id = "size", description = "Size", picker = { options = { "small", "large" } } } } })

check("a prompt of several says which step it is; one already given is no step", (function()
        local first, second, only
        asking(function()
          cl.executeCommand("test.twoSteps", {})
          first = T.lastRecorded().placeholder
          T.lastRecorded().type("bob")
          T.lastRecorded().accept()
          second = T.lastRecorded().placeholder
        end)
        asking(function()
          cl.executeCommand("test.twoSteps", { name = "given" })
          only = T.lastRecorded().placeholder
        end)
        return first == "Name (1/2)" and second == "Size (2/2)" and only == "Size",
               ("%s / %s / %s"):format(tostring(first), tostring(second), tostring(only))
      end)())

cl.registerCommand("test.validated", { title = "Validated", menus = {}, run = function(args) got = args end,
  inputs = { { id = "name", description = "Name", picker = { typed = true }, pattern = "^%w+$",
               validate = function(value) if value == "taken" then return "That name is taken" end end } } })

check("an answer that will not do keeps the prompt open, saying why; one that will runs", (function()
        local alerts = {}
        stub(hs.alert, "show", function(message) alerts[#alerts + 1] = message end)
        got = nil
        local shownReason, stayed, rejected
        asking(function()
          cl.executeCommand("test.validated", {})
          local prompt = T.lastRecorded()
          prompt.type("a b")
          shownReason = prompt.shown[1] and prompt.shown[1].description
          prompt.accept()
          prompt.type("taken")
          prompt.accept()
          stayed = cl.topView() ~= nil and cl.topView().picker == prompt and prompt.hidden ~= true
          rejected = got
          prompt.type("fine")
          prompt.accept()
        end)
        return shownReason == "Name should match ^%w+$" and alerts[1] == "Name should match ^%w+$"
               and alerts[2] == "That name is taken" and stayed and rejected == nil
               and got ~= nil and got.name == "fine",
               ("%s / %s / %s / %s"):format(tostring(shownReason), tostring(alerts[1]), tostring(alerts[2]),
                 tostring(got and got.name))
      end)())

check("typed text that will not do is not taken as a text command's answer, so picking asks", (function()
        cl.registerCommand("test.textValid", { title = "Look up ${query}", menus = {},
          inputs = { { id = "q", picker = { typed = true }, fromQuery = true, pattern = "^%d+$" } },
          run = function() end })
        local command = cl.getCommand("test.textValid")
        local bad, good = cl.textRow(command, {}, "abc"), cl.textRow(command, {}, "42")
        cl.unregisterCommand("test.textValid")
        return bad.args == nil and good.args and good.args.q == "42"
      end)())

----------------------------------------------------------------------
group("naming the target, and confirming")

local zapped = {}
cl.registerCommand("test.zap", { title = "Zap", category = "Test", menus = { "test-zap" },
  targetName = "${input:thing.name}", confirm = "Zap ${input:thing.name}?",
  inputs = { { id = "thing", description = "Which thing", picker = { when = "viewItem == 'thing'" },
               preferCurrent = true, current = function(ctx) return ctx.frontThing end } },
  run = function(args) zapped[#zapped + 1] = args.thing.name end })
cl.view({ name = "test-zap", menus = { "test-zap" }, presenter = "recording" })

local function zapRow(ctx)
  for _, row in ipairs(cl.gather(ctx, { menus = { "test-zap" } })) do
    if row.command == "test.zap" then return row end
  end
end

check("a row names what its command acts on, from what is in front, and nothing when nothing is", (function()
        local front = zapRow({ frontThing = { kind = "thing", name = "Lamp" } })
        local none = zapRow({})
        local verb
        for _, row in ipairs(cl.itemActions({ kind = "thing", name = "Chair" }, {})) do
          if row.command == "test.zap" then verb = row end
        end
        return front and front.label == "Test: Zap -- Lamp" and none and none.label == "Test: Zap"
               and verb and verb.label == "Zap -- Chair",
               ("%s / %s / %s"):format(tostring(front and front.label), tostring(none and none.label),
                 tostring(verb and verb.label))
      end)())

check("a command that confirms asks yes or no before it runs; yes runs it, no steps back", (function()
        cl.setContext("frontThing", { kind = "thing", name = "Lamp" })
        cl.open("test-zap")
        local p = cl.viewNamed("test-zap").picker
        local exits = layerModal.exits
        p.row = indexOf(p, "test.zap")
        p.accept()
        local question = T.lastRecorded()
        local asked, answers = question.placeholder, {}
        for _, row in ipairs(question.shown or {}) do answers[#answers + 1] = row.label end
        local beforeYes = #zapped
        question.row = 1
        question.accept()
        local yes = #zapped == beforeYes + 1 and zapped[#zapped] == "Lamp" and layerModal.exits == exits + 1

        cl.open("test-zap")
        p = cl.viewNamed("test-zap").picker
        exits = layerModal.exits
        p.row = indexOf(p, "test.zap")
        p.accept()
        question = T.lastRecorded()
        question.row = 2
        question.accept()
        local top = cl.topView()
        local no = #zapped == beforeYes + 1 and layerModal.exits == exits and top and top.name == "test-zap"
        layerModal:exited()
        cl.setContext("frontThing", nil)
        return asked == "Zap Lamp?" and table.concat(answers, " ") == "Yes No" and yes and no,
               ("asked %s, answers %s, yes %s, no %s"):format(tostring(asked), table.concat(answers, " "),
                 tostring(yes), tostring(no))
      end)())

check("run by id with everything given, a command that confirms still asks", (function()
        local asked, before = nil, #zapped
        asking(function()
          cl.executeCommand("test.zap", { thing = { kind = "thing", name = "Desk" } })
          asked = T.lastRecorded() and T.lastRecorded().placeholder
          local unasked = #zapped == before
          T.lastRecorded().row = 1
          T.lastRecorded().accept()
          asked = unasked and asked
        end)
        cl.registerCommand("test.quietZap", { title = "Quiet zap", menus = {}, confirm = function() return nil end,
          run = function() zapped[#zapped + 1] = "quiet" end })
        cl.executeCommand("test.quietZap", {})
        return asked == "Zap Desk?" and zapped[before + 1] == "Desk" and zapped[before + 2] == "quiet",
               tostring(asked) .. " / " .. tostring(zapped[before + 1])
      end)())

----------------------------------------------------------------------
group("searching")

check("while a searching picker searches it shows one disabled row saying so, until rows land or none will",
      (function()
        local pending = {}
        cl.register({ name = "test-seek", menus = { "test-seek" },
          search = function(query, _, done) pending[query] = done; return function() end end })
        cl.register({ name = "test-seek-slow", menus = { "test-seek" },
          search = function(query, _, done) pending["slow " .. query] = done; return function() end end })
        cl.view({ name = "test-seek", prefix = "seek ", menus = { "test-seek" }, kind = "search",
                  presenter = "recording" })
        local fire
        stub(hs.timer, "doAfter", function(_, fn)
          fire = fn
          return { stop = function() fire = nil end }
        end)
        local alerts = 0
        stub(hs.alert, "show", function() alerts = alerts + 1 end)
        local saved = cl.matchers
        cl.matchers = substringOnly()
        T.openRecorded("root").type("seek notes")
        local p = cl.viewNamed("test-seek").picker
        local function shown()
          local out = {}
          for i, row in ipairs(p and p.shown or {}) do
            out[i] = tostring(row.label) .. (row.enabled == false and " (disabled)" or "")
          end
          return table.concat(out, ", ")
        end
        local seen = { shown() }
        if fire then fire() end
        seen[2] = shown()
        local exits = layerModal.exits
        p.accept()
        -- Nothing runs, no alert, and the picker is back on screen: a pick
        -- closes it, so "does nothing" has to put it back.
        local pickedNothing = layerModal.exits == exits and alerts == 0 and p.hidden ~= true
        if pending.notes then pending.notes({}) end
        seen[3] = shown()
        if pending["slow notes"] then pending["slow notes"]({ { label = "notes.md" } }) end
        seen[4] = shown()
        cl.refresh()
        if fire then fire() end
        seen[5] = shown()
        p.type("seek note")
        if fire then fire() end
        seen[6] = shown()
        if pending.note then pending.note({}) end
        if pending["slow note"] then pending["slow note"]({}) end
        seen[7] = shown()
        p.type("seek n")
        seen[8] = shown()
        cl.matchers = saved
        layerModal:exited()
        removeView("test-seek")
        cl.unregisterExtension("test-seek")
        cl.unregisterExtension("test-seek-slow")
        local expected = { "", "Searching… (disabled)", "Searching… (disabled)", "notes.md", "notes.md",
                           "Searching… (disabled)", "", "" }
        local same = pickedNothing
        for i, text in ipairs(expected) do same = same and seen[i] == text end
        return same, table.concat(seen, " / ") .. " / picked nothing " .. tostring(pickedNothing)
      end)())

check("a search input shows the busy row until its query is answered, drops an older answer unmatched, "
      .. "narrows an answer to what was typed but for alwaysShow rows, and is asked again on a refresh", (function()
        local pending, asked = {}, {}
        cl.registerCommand("test.seekInput", { title = "Seek input", menus = {},
          inputs = { { id = "thing", description = "Which",
                       picker = { kind = "search", search = function(query, _, _, done) asked[#asked + 1] = query; pending[query] = done end } } },
          run = function() end })
        local substring, matched = substringOnly()[1], 0
        local saved = cl.matchers
        cl.matchers = { { name = "counting", match = function(items, query, callback)
          matched = matched + 1
          return substring.match(items, query, callback)
        end } }
        local alerts = 0
        stub(hs.alert, "show", function() alerts = alerts + 1 end)
        local p
        local function shown()
          local out = {}
          for i, row in ipairs(p and p.shown or {}) do
            out[i] = tostring(row.label) .. (row.enabled == false and " (disabled)" or "")
          end
          return table.concat(out, ", ")
        end
        local rows = { { label = "apple", value = "a" }, { label = "banana", value = "b" },
                       { label = "Use what was typed", value = "typed", alwaysShow = true } }
        local seen, pickedNothing, refreshed = {}, false, false
        asking(function()
          cl.executeCommand("test.seekInput", {})
          p = T.lastRecorded()
          seen[1] = shown()
          if pending[""] then pending[""](rows) end
          seen[2] = shown()
          p.type("an")
          seen[3] = shown()
          p.type("ban")
          local before = matched
          if pending.an then pending.an(rows) end
          seen[4] = shown() .. (matched == before and "" or " (matched)")
          if pending.ban then pending.ban(rows, true) end
          seen[5] = shown()
          p.row = 3
          local exits = layerModal.exits
          p.accept()
          pickedNothing = layerModal.exits == exits and alerts == 0 and T.lastRecorded() == p
          local count = #asked
          cl.refresh()
          refreshed = #asked == count + 1 and asked[#asked] == "ban"
          seen[6] = shown()
          if pending.ban then pending.ban(rows) end
          seen[7] = shown()
        end)
        cl.matchers = saved
        local expected = { "Searching… (disabled)", "apple, banana, Use what was typed", "Searching… (disabled)",
                           "Searching… (disabled)", "banana, Use what was typed, Searching… (disabled)",
                           "banana, Use what was typed, Searching… (disabled)", "banana, Use what was typed" }
        local same = pickedNothing and refreshed
        for i, text in ipairs(expected) do same = same and seen[i] == text end
        return same, table.concat(seen, " / ") .. " / picked nothing " .. tostring(pickedNothing)
               .. " / refreshed " .. tostring(refreshed)
      end)())

----------------------------------------------------------------------
group("the highlight across a redraw")

local listed = { { label = "one" }, { label = "two" }, { label = "three" } }
T.picker("test-highlight", function()
  local out = {}
  for i, row in ipairs(listed) do out[i] = { label = row.label } end
  return out
end)

check("a redraw keeps the row you moved to, found where it now is", (function()
        cl.open("test-highlight")
        local p = cl.viewNamed("test-highlight").picker
        local rows = {}
        for i, row in ipairs(p.shown) do rows[row.label] = i end
        p.row = rows.two
        table.insert(listed, 1, { label = "zero" })
        cl.refresh()
        local kept = p.selected() and p.selected().label
        layerModal:exited()
        table.remove(listed, 1)
        return kept == "two", tostring(kept)
      end)())

check("on the first row a redraw leaves the top to better rows, and typing starts from the top", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        cl.open("test-highlight")
        local p = cl.viewNamed("test-highlight").picker
        p.row = 1
        local first = p.selected().label
        table.insert(listed, 1, { label = "a-new-top" })
        cl.refresh()
        local top = p.selected() and p.selected().label
        p.row = 2
        p.type("t")
        local typed = p.row
        cl.matchers = saved
        layerModal:exited()
        table.remove(listed, 1)
        return first ~= top and typed == 1, tostring(first) .. " / " .. tostring(top) .. " / " .. tostring(typed)
      end)())

----------------------------------------------------------------------
group("leaving a level")

local left, elsewhere = {}, 0
cl.register({ name = "test-leaving", menus = { "test-leave" },
  items = function() return { { label = "a" } } end,
  left = function(ctx) left[#left + 1] = ctx end })
cl.register({ name = "test-leaving-elsewhere", menus = { "test-leave-elsewhere" },
  left = function() elsewhere = elsewhere + 1 end })
cl.view({ name = "test-leave", title = "Leave", menus = { "test-leave" }, presenter = "recording" })
T.picker("test-leave-over", { { label = "b" } })

check("an extension feeding a level hears it is left when escape steps back from it, in the context it had, "
      .. "and one feeding another picker does not", (function()
        cl.open("test-after-parent")
        local marked = {}
        cl.push("test-leave", { ctx = { marker = marked } })
        local before, elsewhereBefore = #left, elsewhere
        cl.viewNamed("test-leave").picker.dismiss()
        local ctx = left[#left]
        return #left == before + 1 and ctx.marker == marked and ctx.activeView == "test-leave"
               and elsewhere == elsewhereBefore,
               ("%d heard, activeView %s, elsewhere %d"):format(#left - before, tostring(ctx and ctx.activeView),
                 elsewhere - elsewhereBefore)
      end)())

check("and when the layer closes, and when a chord replaces it; not when a level opens over it", (function()
        local before = #left
        cl.open("test-leave")
        cl.push("test-leave-over")
        local covered = #left - before
        layerModal:exited()
        local closed = #left - before
        cl.open("test-leave")
        cl.open("test-after-parent")
        local replaced = #left - before
        layerModal:exited()
        return covered == 0 and closed == 1 and replaced == 2,
               ("%d / %d / %d"):format(covered, closed, replaced)
      end)())

check("one that throws is logged, the rest still hear, and the layer still steps back", (function()
        local heard = 0
        cl.register({ name = "test-left-throws", menus = { "test-leave-throws" },
          items = function() return { { label = "c" } } end,
          left = function() error("leaving went wrong") end })
        cl.register({ name = "test-left-hears", menus = { "test-leave-throws" }, after = { "test-left-throws" },
          left = function() heard = heard + 1 end })
        cl.view({ name = "test-leave-throws", menus = { "test-leave-throws" }, presenter = "recording" })
        cl.open("test-after-parent")
        cl.push("test-leave-throws")
        local exits = layerModal.exits
        local ok = pcall(cl.viewNamed("test-leave-throws").picker.dismiss)
        local top = cl.topView()
        local logged = false
        for _, line in ipairs(T.logged) do
          if line:find("extension 'test-left-throws' left -> ", 1, true) then logged = true end
        end
        layerModal:exited()
        removeView("test-leave-throws")
        cl.unregisterExtension("test-left-throws")
        cl.unregisterExtension("test-left-hears")
        return ok and logged and heard == 1 and top and top.name == "test-after-parent" and layerModal.exits == exits,
               ("logged %s, heard %d, top %s"):format(tostring(logged), heard, tostring(top and top.name))
      end)())
