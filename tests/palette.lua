-- CommandLayer.spoon/tests/palette.lua
-- The palette: text commands, presentation, searching pickers, the actions panel.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local rankerEntry = T.rankerEntry
local substringOnly = T.substringOnly
local openRecorded = T.openRecorded
local recordedSpec = T.recordedSpec
local removeView = T.removeView
local rowFor = T.rowFor
local layerModal = T.layerModal

group("commands that take text")
check("a text command is a row with what you typed filled in, encoded", (function()
        local row = rowFor(cl.textRowsFor(cl.buildContext(), "lofi beats"), "browser.searchWeb")
        return row ~= nil and row.label == "Search the web for “lofi beats”"
               and row.args and row.args.query == "lofi%20beats",
               row and (row.label .. " / " .. tostring(row.args and row.args.query))
      end)())

check("without text it keeps the question for when it is picked", (function()
        local row = rowFor(cl.textRowsFor(cl.buildContext(), ""), "browser.searchWeb")
        return row ~= nil and row.args == nil and row.label:find("…", 1, true) ~= nil
      end)())

check("a text command whose clause is false is not offered", (function()
        cl.registerCommand("test.nowhereText", { title = "Nowhere ${query}", menus = {},
          when = "frontmostApp == 'NoSuchApp'",
          inputs = { { id = "q", picker = { typed = true }, fromQuery = true } }, run = function() end })
        return rowFor(cl.textRowsFor(cl.buildContext(), "x"), "test.nowhereText") == nil
      end)())

check("'?' with text lists them filled in, and picking one runs it at once",
      (function()
        local got
        cl.registerCommand("test.echo", { title = "Echo ${query}", menus = {},
          inputs = { { id = "q", picker = { typed = true }, fromQuery = true } },
          run = function(_, c) got = c.q end })
        local textSpec = recordedSpec("help")
        local savedMatchers = cl.matchers
        cl.matchers = substringOnly()
        openRecorded("root").type("?hello")
        cl.matchers = savedMatchers
        local p = textSpec.picker
        if not p then return false, "did not open" end
        local row, index = rowFor(p.shown, "test.echo")
        if not row then return false, "no echo row" end
        local before = layerModal.exits
        p.row = index
        p.accept()
        return got == "hello" and layerModal.exits == before + 1 and row.label == "Echo hello",
               tostring(got)
      end)())

check("a command's own prefix shows that one command, filled in", (function()
        if not cl.viewNamed("browser.searchYouTube") then
          return false, "no view for the command"
        end
        local spec = recordedSpec("browser.searchYouTube")
        openRecorded("root").type("youtube lofi")
        local p = spec.picker
        local shown = p and p.shown or {}
        return #shown == 1 and shown[1].label == "Search YouTube for “lofi”"
               and shown[1].args and shown[1].args.query == "lofi",
               shown[1] and shown[1].label
      end)())

check("with nothing matching, the text commands are offered instead", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local root = openRecorded("root")
        root.type("zzqqxx nothing here")
        local offered = rowFor(root.shown, "browser.searchWeb")
        root.type("lock")
        local notWhenMatched = rowFor(root.shown, "browser.searchWeb")
        cl.matchers = saved
        return offered ~= nil and notWhenMatched == nil,
               ("%s / %s"):format(tostring(offered ~= nil), tostring(notWhenMatched ~= nil))
      end)())

group("palette presentation")
check("a command with a category reads 'Category: Title', and matches on it", (function()
        cl.registerCommand("test.categorised", { title = "Do the thing", category = "Things",
          menus = { "test-cat" }, run = function() end })
        local row = rowFor(cl.gather(cl.buildContext(), { menus = { "test-cat" } }), "test.categorised")
        local found
        cl.rankItems({ row }, "things", function(out) found = out end)
        local saved = cl.matchers
        cl.matchers = substringOnly()
        cl.rankItems({ row }, "things", function(out) found = out end)
        cl.matchers = saved
        return row ~= nil and row.label == "Things: Do the thing" and #(found or {}) == 1,
               row and row.label
      end)())

check("a command's keybinding is shown on its row, and follows a rebind", (function()
        cl.registerCommand("test.bound", { title = "Bound", menus = { "test-bound" },
          run = function() end })
        cl.keybindings[#cl.keybindings + 1] = { key = "cmd+shift+9", command = "test.bound" }
        local row = rowFor(cl.gather(cl.buildContext(), { menus = { "test-bound" } }), "test.bound")
        cl.keybindings[#cl.keybindings] = nil
        local after = rowFor(cl.gather(cl.buildContext(), { menus = { "test-bound" } }), "test.bound")
        return row ~= nil and (row.description or ""):find("cmd+shift+9", 1, true) ~= nil
               and not (after.description or ""):find("cmd+shift+9", 1, true),
               row and tostring(row.description)
      end)())

check("command rows read the keybindings once per list, not once per command per open", (function()
        local reads, real = 0, cl.effectiveKeybindings
        cl.effectiveKeybindings = function() reads = reads + 1; return real() end
        cl.keybindingsChanged()
        local rows = cl.gather(cl.buildContext(), { menus = { "commandPalette" } })
        local first = reads
        cl.gather(cl.buildContext(), { menus = { "commandPalette" } })
        cl.effectiveKeybindings = real
        local commands = 0
        for _, row in ipairs(rows) do
          if row.subject and row.subject.kind == "command" then commands = commands + 1 end
        end
        return commands > 5 and first == 1 and reads == 1,
               ("%d reads, then %d, for %d command rows"):format(first, reads, commands)
      end)())

check("a picker with recentlyUsed opens on what you picked latest, marked, and keeps it first as you type",
      (function()
        cl.register({ name = "test-used", menus = { "test-used" },
          items = function()
            return { { label = "alpha", subject = { kind = "t", name = "a" } },
                     { label = "bravo", subject = { kind = "t", name = "b" } },
                     { label = "charlie", subject = { kind = "t", name = "c" } },
                     { label = "delta", subject = { kind = "t", name = "d" } } }
          end })
        cl.view({ name = "test-used", menus = { "test-used" }, recentlyUsed = 2,
                  presenter = "recording" })
        -- Picked often long ago is not recent: alpha has the most picks and the oldest.
        local last = { alpha = 100, charlie = 300, bravo = 200 }
        local frecency = rankerEntry("frecency")
        local realLastUsed, realScore = frecency.lastUsed, frecency.score
        frecency.lastUsed = function(item) return last[item.label] or 0 end
        frecency.score = function(item) return item.label == "alpha" and 1 or 0 end
        local saved = cl.matchers
        cl.matchers = substringOnly()

        local function read(p)
          local out = {}
          for _, row in ipairs(p.shown or {}) do
            out[#out + 1] = row.label .. ((row.description or ""):find("Recently used", 1, true) and "*" or "")
          end
          return table.concat(out, " ")
        end
        cl.open("test-used")
        local p = cl.viewNamed("test-used").picker
        local opened = read(p)
        p.type("a")
        local typed = read(p)

        cl.matchers, frecency.lastUsed, frecency.score = saved, realLastUsed, realScore
        removeView("test-used")
        cl.unregisterExtension("test-used")
        return opened == "charlie* bravo* alpha delta" and typed == "charlie* bravo* alpha delta",
               opened .. " / " .. typed
      end)())

check("sections open on the first rows of each extension, in its order, the first labelled", (function()
        local function rows(prefix, n)
          local out = {}
          for i = 1, n do
            out[i] = { label = prefix .. i, description = "row", subject = { kind = "t", name = prefix .. i },
                       rank = (prefix .. i == "a2") and 1 or 0 }
          end
          return out
        end
        cl.register({ name = "test-sec-a", rank = 0, menus = { "test-sec" },
                      items = function() return rows("a", 4) end })
        cl.register({ name = "test-sec-b", rank = 0, menus = { "test-sec" },
                      items = function() return rows("b", 2) end })
        cl.view({ name = "test-sec", menus = { "test-sec" }, presenter = "recording",
                  sections = { { from = "test-sec-a", limit = 2, title = "Alphas" },
                               { from = "test-sec-b", limit = 1, title = "Bees" } } })
        -- a2 is more specific and picked more often, so ranking alone would
        -- put it first.
        local frecency = rankerEntry("frecency")
        local realScore = frecency.score
        frecency.score = function(item) return item.label == "a2" and 0.9 or 0 end
        local saved = cl.matchers
        cl.matchers = substringOnly()

        cl.open("test-sec")
        local p = cl.viewNamed("test-sec").picker
        local texts, subs = {}, {}
        for i, row in ipairs(p and p.shown or {}) do texts[i], subs[i] = row.label, row.description end
        p.type("a")
        local labelled = false
        for _, row in ipairs(p.shown or {}) do
          if (row.description or ""):find("Alphas", 1, true) then labelled = true end
        end

        cl.matchers, frecency.score = saved, realScore
        removeView("test-sec")
        cl.unregisterExtension("test-sec-a")
        cl.unregisterExtension("test-sec-b")
        return table.concat(texts, " ") == "a1 a2 b1 a3 a4 b2"
               and subs[1] == "Alphas  --  row" and subs[2] == "row"
               and subs[3] == "Bees  --  row" and subs[4] == "row"
               and not labelled,
               table.concat(texts, " ") .. " / " .. tostring(subs[1]) .. " / " .. tostring(subs[3])
      end)())

check("a section can be the top of another picker, its rows not repeated below", (function()
        local function rows(prefix, n)
          local out = {}
          for i = 1, n do
            out[i] = { label = prefix .. i, description = "row", subject = { kind = "t", name = prefix .. i } }
          end
          return out
        end
        cl.register({ name = "test-src", rank = 0, menus = { "test-src", "test-host" },
                      items = function() return rows("s", 3) end })
        cl.register({ name = "test-own", rank = 0, menus = { "test-host" },
                      items = function() return rows("h", 2) end })
        cl.view({ name = "test-src-view", menus = { "test-src" }, presenter = "recording" })
        cl.view({ name = "test-host", menus = { "test-host" }, presenter = "recording",
                  sections = { { view = "test-src-view", limit = 2, title = "From source" } } })
        local saved = cl.matchers
        cl.matchers = substringOnly()
        cl.open("test-host")
        local p = cl.viewNamed("test-host").picker
        local texts, counts = {}, {}
        for i, row in ipairs(p and p.shown or {}) do
          texts[i] = row.label
          counts[row.label] = (counts[row.label] or 0) + 1
        end
        local first = p and p.shown and p.shown[1]
        cl.matchers = saved
        removeView("test-host")
        removeView("test-src-view")
        cl.unregisterExtension("test-src")
        cl.unregisterExtension("test-own")
        local repeated = false
        for _, n in pairs(counts) do if n > 1 then repeated = true end end
        return #texts == 5 and texts[1] == "s1" and texts[2] == "s2" and not repeated
               and first.description == "From source  --  row",
               table.concat(texts, " ") .. " / " .. tostring(first and first.description)
      end)())

-- The root leads with the context picker's top rows without the window
-- commands, which are in every context and would otherwise take them all.
check("a section can leave out an extension's rows, before its limit is taken", (function()
        local function rows(prefix, n, rank)
          local out = {}
          for i = 1, n do
            out[i] = { label = prefix .. i, description = "row", rank = rank,
                       subject = { kind = "t", name = prefix .. i } }
          end
          return out
        end
        cl.register({ name = "test-ex-src", rank = 0, menus = { "test-ex-src" },
                      items = function() return rows("s", 3, 0) end })
        cl.register({ name = "test-ex-noise", rank = 1, before = { "test-ex-src" }, menus = { "test-ex-src", "test-ex-host" },
                      items = function() return rows("n", 2, 1) end })
        cl.view({ name = "test-ex-src-view", menus = { "test-ex-src" }, presenter = "recording" })
        cl.view({ name = "test-ex-host", menus = { "test-ex-host" }, presenter = "recording",
                  sections = { { view = "test-ex-src-view", limit = 2, exclude = { "test-ex-noise" } } } })
        local saved = cl.matchers
        cl.matchers = substringOnly()
        cl.open("test-ex-host")
        local p = cl.viewNamed("test-ex-host").picker
        local texts = {}
        for i, row in ipairs(p and p.shown or {}) do texts[i] = row.label end
        cl.matchers = saved
        removeView("test-ex-host")
        removeView("test-ex-src-view")
        cl.unregisterExtension("test-ex-src")
        cl.unregisterExtension("test-ex-noise")
        return texts[1] == "s1" and texts[2] == "s2" and table.concat(texts, " "):find("n1", 1, true) ~= nil,
               table.concat(texts, " ")
      end)())

-- An extension or a `when` that differs by picker reads which one asks,
-- rather than guessing it from the menus it was handed.
check("rows are built and searched knowing which picker asks", (function()
        local built, searched
        cl.register({ name = "test-asker", menus = { "test-asker" },
          items = function(ctx) built = ctx.activeView; return { { label = "a1" } } end,
          search = function(_, ctx, done) searched = ctx.activeView; done({}) end })
        cl.view({ name = "test-asker-view", menus = { "test-asker" }, presenter = "recording" })
        cl.view({ name = "test-asker-search", menus = { "test-asker" }, presenter = "recording",
                  kind = "search", debounce = 0 })
        local saved, realAfter = cl.matchers, hs.timer.doAfter
        cl.matchers = substringOnly()
        hs.timer.doAfter = function(_, fn) fn(); return { stop = function() end } end
        cl.open("test-asker-view")
        local afterOpen = built
        cl.open("test-asker-search")
        local p = cl.viewNamed("test-asker-search").picker
        if p then p.type("abc") end
        cl.matchers, hs.timer.doAfter = saved, realAfter
        removeView("test-asker-view")
        removeView("test-asker-search")
        cl.unregisterExtension("test-asker")
        return afterOpen == "test-asker-view" and searched == "test-asker-search",
               tostring(afterOpen) .. " / " .. tostring(searched)
      end)())

check("typing keeps what the sections showed searchable, another picker's rows too, and first among what matches",
      (function()
        local function rows(prefix, n)
          local out = {}
          for i = 1, n do
            out[i] = { label = prefix .. i, description = "row", subject = { kind = "t", name = prefix .. i } }
          end
          return out
        end
        cl.register({ name = "test-tsrc", rank = 0, menus = { "test-tsrc" },
                      items = function() return rows("match-s", 2) end })
        cl.register({ name = "test-town", rank = 1, menus = { "test-thost" },
                      items = function() return rows("match-h", 3) end })
        cl.view({ name = "test-tsrc-view", menus = { "test-tsrc" }, presenter = "recording" })
        cl.view({ name = "test-thost", menus = { "test-thost" }, presenter = "recording",
                  sections = { { view = "test-tsrc-view", limit = 1 } } })
        local saved = cl.matchers
        cl.matchers = substringOnly()
        cl.open("test-thost")
        local p = cl.viewNamed("test-thost").picker
        p.type("match")
        local texts = {}
        for i, row in ipairs(p.shown or {}) do texts[i] = row.label end
        p.type("zzz")
        local none = #(p.shown or {})
        cl.matchers = saved
        removeView("test-thost")
        removeView("test-tsrc-view")
        cl.unregisterExtension("test-tsrc")
        cl.unregisterExtension("test-town")
        return texts[1] == "match-s1" and #texts == 4 and none == 0, table.concat(texts, " ") .. " / " .. none
      end)())

check("two pickers whose sections name each other open instead of hanging", (function()
        cl.register({ name = "test-loop", menus = { "test-loop" }, items = function()
          return { { label = "x1", subject = { kind = "t", name = "x1" } } }
        end })
        cl.view({ name = "test-loop-a", menus = { "test-loop" }, presenter = "recording",
                  sections = { { view = "test-loop-b", limit = 2 } } })
        cl.view({ name = "test-loop-b", menus = { "test-loop" }, presenter = "recording",
                  sections = { { view = "test-loop-a", limit = 2 } } })
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local ok, err = pcall(cl.open, "test-loop-a")
        local p = cl.viewNamed("test-loop-a").picker
        local shown = p and p.shown and #p.shown or 0
        cl.matchers = saved
        removeView("test-loop-a")
        removeView("test-loop-b")
        cl.unregisterExtension("test-loop")
        return ok and shown > 0, tostring(err) .. " / " .. tostring(shown)
      end)())

-- Ranking an empty query is at once because matchers decline it; a
-- section must still build if one answers later anyway.
check("a matcher answering an empty query later leaves sections built from the rows as gathered", (function()
        cl.register({ name = "test-late", menus = { "test-late" }, items = function()
          return { { label = "l1", subject = { kind = "t", name = "l1" } } }
        end })
        cl.view({ name = "test-late-view", menus = { "test-late" }, presenter = "recording" })
        cl.view({ name = "test-late-host", menus = { "test-late-none" }, presenter = "recording",
                  sections = { { view = "test-late-view", limit = 1 } } })
        local saved, calls = cl.matchers, 0
        -- Answers the first ranking at once, and never the ones after it.
        cl.matchers = { { name = "late", match = function(items, _, callback)
          calls = calls + 1
          if calls == 1 then callback(items) end
          return true
        end } }
        local ok, err = pcall(cl.open, "test-late-host")
        local p = cl.viewNamed("test-late-host").picker
        local first = p and p.shown and p.shown[1]
        cl.matchers = saved
        removeView("test-late-host")
        removeView("test-late-view")
        cl.unregisterExtension("test-late")
        return ok and first ~= nil and first.label == "l1", tostring(err) .. " / " .. tostring(first and first.label)
      end)())

check("an extension's picked hook hears of a pick, even after one that throws", (function()
        local heard
        cl.register({ name = "test-picked-loud", before = { "test-picked" }, menus = {},
                      picked = function() error("boom") end })
        cl.register({ name = "test-picked", menus = { "test-picked" },
          items = function()
            return { { label = "folder", subject = { kind = "t", name = "folder" },
                       run = function() end } }
          end,
          picked = function(item) heard = item.label end })
        cl.view({ name = "test-picked", menus = { "test-picked" }, presenter = "recording" })
        cl.open("test-picked")
        local p = cl.viewNamed("test-picked").picker
        p.row = 1
        p.accept()
        removeView("test-picked")
        cl.unregisterExtension("test-picked")
        cl.unregisterExtension("test-picked-loud")
        return heard == "folder", tostring(heard)
      end)())

check("a picker is handed what was typed after its prefix, to highlight", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local paletteSpec = recordedSpec("palette")
        openRecorded("root").type(">lock")
        cl.matchers = saved
        local p = paletteSpec.picker
        return p ~= nil and p.shownQuery == "lock", p and tostring(p.shownQuery)
      end)())

group("searching pickers")
-- A stand-in search source, with the debounce timer fired by hand, so what
-- happens between keystrokes can be watched.
local function searchFixture()
  local calls, stops, pending = {}, 0, {}
  cl.register({ name = "test-search", menus = { "test-search" },
    items = function() return { { label = "recent one", subject = { kind = "file", path = "/recent/one" } } } end,
    search = function(query, _, done)
      calls[#calls + 1] = query
      pending[query] = done
      return function() stops = stops + 1 end
    end })
  cl.view({ name = "test-search", prefix = "seek ", menus = { "test-search" },
            kind = "search", presenter = "recording" })

  local fire
  local realDoAfter = hs.timer.doAfter
  hs.timer.doAfter = function(_, fn)
    fire = fn
    return { stop = function() fire = nil end }
  end

  return {
    calls = calls, pending = pending,
    stops = function() return stops end,
    fire = function()
      if fire then local fn = fire; fire = nil; fn() end
    end,
    done = function()
      hs.timer.doAfter = realDoAfter
      removeView("test-search")
      for i, ext in ipairs(cl.extensions) do
        if ext.name == "test-search" then table.remove(cl.extensions, i); break end
      end
      -- Registering drops the sorted cache, which still held the fixture.
      cl.register({ name = "test-search-flush" })
      for i, ext in ipairs(cl.extensions) do
        if ext.name == "test-search-flush" then table.remove(cl.extensions, i); break end
      end
    end,
  }
end

check("a searching picker shows its own rows before anything is typed", (function()
        local f = searchFixture()
        openRecorded("root").type("seek ")
        local p = cl.viewNamed("test-search").picker
        local rows = p and p.shown or {}
        f.fire()
        local searched = #f.calls
        f.done()
        return #rows == 1 and rows[1].label == "recent one" and searched == 0,
               ("%d rows, %d searches"):format(#rows, searched)
      end)())

check("too little typed searches nothing, and keeps the view's own rows that match", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local f = searchFixture()
        local p = openRecorded("root")
        p.type("seek o")
        f.fire()
        local view = cl.viewNamed("test-search").picker
        local searched = #f.calls
        local kept = view ~= nil and #(view.shown or {}) == 1 and view.shown[1].label == "recent one"
        view.type("seek z")
        f.fire()
        local none = #(view and view.shown or {})
        cl.matchers = saved
        f.done()
        return searched == 0 and kept and none == 0,
               ("%d searches, kept %s, %d for z"):format(searched, tostring(kept), none)
      end)())

check("the view's own rows that match stay first beside what the search finds, the busy row after them", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local f = searchFixture()
        openRecorded("root").type("seek one")
        f.fire()
        local p = cl.viewNamed("test-search").picker
        local function labels()
          local out = {}
          for i, row in ipairs(p and p.shown or {}) do out[i] = row.label end
          return table.concat(out, "|")
        end
        local waiting = labels()
        if f.pending["one"] then
          f.pending["one"]({ { label = "one found", rank = 1 },
                             { label = "recent one", subject = { kind = "file", path = "/recent/one" } } })
        end
        local after = labels()
        cl.matchers = saved
        f.done()
        return waiting == "recent one|Searching…" and after == "recent one|one found", waiting .. " / " .. after
      end)())

check("a search waits for typing to pause, and gets what follows the prefix", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local f = searchFixture()
        openRecorded("root").type("seek notes")
        local before = #f.calls
        f.fire()
        local p = cl.viewNamed("test-search").picker
        if f.pending["notes"] then
          f.pending["notes"]({ { label = "notes.md" }, { label = "other" } })
        end
        cl.matchers = saved
        local shown = p and p.shown or {}
        local first = f.calls[1]
        f.done()
        return before == 0 and first == "notes" and #shown == 1
               and shown[1].label == "notes.md",
               ("%d before, %s, %d shown"):format(before, tostring(first), #shown)
      end)())

check("a newer query stops the older search, and its late answer is dropped", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local f = searchFixture()
        openRecorded("root").type("seek note")
        f.fire()
        local p = cl.viewNamed("test-search").picker
        if not (p and f.pending["note"]) then
          cl.matchers = saved; f.done(); return false, "first search did not run"
        end
        p.type("seek notes")
        local stopped = f.stops()
        f.fire()
        if f.pending["notes"] then f.pending["notes"]({ { label = "notes.md" } }) end
        f.pending["note"]({ { label = "note-old.md" } })   -- arrives last
        cl.matchers = saved
        local shown = p.shown or {}
        f.done()
        return stopped == 1 and #shown == 1 and shown[1].label == "notes.md",
               ("%d stopped, %s"):format(stopped, shown[1] and shown[1].label or "none")
      end)())

check("file search is the files extension's search hook, in a picker whose kind is search", (function()
        local files
        for _, ext in ipairs(cl.extensions) do
          if ext.name == "files" then files = ext end
        end
        local view = cl.viewNamed("files")
        return files ~= nil and type(files.search) == "function"
               and view ~= nil and view.kind == "search"
      end)())

group("the actions panel")
local function controlNamed(name)
  for _, c in ipairs(cl.controls) do
    if c.name == name then return c.fn end
  end
end

T.picker("test-subject", {
  { label = "a.txt", subject = { kind = "file", path = "/tmp/a.txt" } },
  { label = "no subject" },
})

check("cmd+k opens a declared view", cl.viewNamed(cl.actionsView) ~= nil,
      tostring(cl.actionsView))

check("over the list, for the highlighted row", (function()
        local acts = recordedSpec(cl.actionsView)
        cl.open("test-subject")
        local before = layerModal.exits
        controlNamed("quickOpen.showActions")()
        local p = acts.picker
        if not p then return false, "did not open" end
        return p.placeholder == "a.txt" and #(p.shown or {}) > 0
               and layerModal.exits == before, tostring(p.placeholder)
      end)())

check("escape from it comes back to the list", (function()
        local acts = recordedSpec(cl.actionsView)
        cl.open("test-subject")
        local list = cl.viewNamed("test-subject").picker
        controlNamed("quickOpen.showActions")()
        if not acts.picker then return false, "did not open" end
        local before = layerModal.exits
        acts.picker.dismiss()
        controlNamed("quickOpen.selectNext")()
        return layerModal.exits == before and #list.shown == 2 and list.row == 2
      end)())

check("a row with nothing to act on opens nothing", (function()
        local acts = recordedSpec(cl.actionsView)
        cl.open("test-subject")
        cl.viewNamed("test-subject").picker.row = 2
        controlNamed("quickOpen.showActions")()
        return acts.picker == nil
      end)())

check("typing in it adds no keyword switch", (function()
        local undo = T.picker("test-switch", { { label = "x" } }, { prefix = "switching " })
        local acts = recordedSpec(cl.actionsView)
        local switchSpec = recordedSpec("test-switch")
        -- The same text does switch in the root, so the panel is what differs.
        openRecorded("root").type("switching x")
        local fromRoot = switchSpec.picker ~= nil
        switchSpec.picker = nil
        cl.open("test-subject")
        controlNamed("quickOpen.showActions")()
        if not acts.picker then undo(); return false, "did not open" end
        acts.picker.type("switching x")
        local fromPanel = switchSpec.picker ~= nil
        undo()
        return fromRoot and not fromPanel,
               ("root %s, panel %s"):format(tostring(fromRoot), tostring(fromPanel))
      end)())

-- The point of it being a view: a profile can replace the panel.
check("a profile can point cmd+k at another view", (function()
        T.picker("test-acts", { { label = "only" } }, { placeholder = "custom ${subject:label}" })
        local was = cl.actionsView
        cl.actionsView = "test-acts"
        cl.open("test-subject")
        controlNamed("quickOpen.showActions")()
        cl.actionsView = was
        local p = cl.viewNamed("test-acts").picker
        return p ~= nil and p.placeholder == "custom a.txt" and #p.shown == 1,
               p and tostring(p.placeholder)
      end)())

check("a picker given a subject builds with it in its context, its placeholder and empty reading ${subject:label}",
      (function()
        local seen
        local undo = T.picker("test-given", function(ctx)
          seen = ctx.subject
          return ctx.subject and ctx.subject.path == "/x" and { { label = "one" } } or {}
        end, { placeholder = "About ${subject:label}", empty = "Nothing about ${subject:label}" })
        local said, realAlert = {}, hs.alert.show
        hs.alert.show = function(message) said[#said + 1] = message end
        cl.open("test-subject")
        local opened = cl.push("test-given", { subject = { kind = "file", path = "/x" }, label = "x.txt" })
        local p = cl.viewNamed("test-given").picker
        local placeholder = p and p.placeholder
        local refused = cl.push("test-given", { subject = { kind = "file", path = "/y" }, label = "y.txt" })
        hs.alert.show = realAlert
        undo()
        return opened == true and placeholder == "About x.txt" and refused == false
               and seen ~= nil and seen.path == "/y" and said[1] == "Nothing about y.txt",
               ("%s / %s / %s / %s"):format(tostring(opened), tostring(placeholder), tostring(refused), tostring(said[1]))
      end)())

check("quickOpen with a subject opens that picker given it, from a closed layer too", (function()
        local seen
        local undo = T.picker("test-given-open", function(ctx) seen = ctx.subject; return { { label = "row" } } end)
        local savedEnter = layerModal.enter
        layerModal.enter = function(m) m:entered() end
        layerModal:exited()
        cl.executeCommand("quickOpen", { view = "test-given-open", subject = { kind = "folder", path = "/z" } }, {})
        layerModal.enter = savedEnter
        layerModal:exited()
        undo()
        return seen ~= nil and seen.path == "/z", tostring(seen and seen.path)
      end)())

check("cmd+k's picker, given nothing to act on, opens nothing", (function()
        local realAlert = hs.alert.show
        hs.alert.show = function() end
        cl.open("test-subject")
        local opened = cl.push(cl.actionsView, {})
        hs.alert.show = realAlert
        return opened == false, tostring(opened)
      end)())
