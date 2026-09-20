-- CommandLayer.spoon/tests/ranking.lua
-- Matching and ranking.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local rows = cl.gather(T.context(), { menus = { "root" } })

local rankerEntry = T.rankerEntry
local substringOnly = T.substringOnly
local openRecorded = T.openRecorded

group("matching")
check("a matcher is registered", #cl.matchers >= 1,
      (function()
        local n = {}
        for _, m in ipairs(cl.matchers) do n[#n+1] = m.name end
        return table.concat(n, " ")
      end)())
-- fzf is found at the path stubbed here, never a real one, and hs.task is a
-- stub that never calls back. What is testable is that it declines rather
-- than swallowing a query it cannot serve.
T.stub(cl.tools.paths, "fzf", "/fake/fzf")
check("fzf declines an empty query", (function()
        local handled
        for _, m in ipairs(cl.matchers) do
          if m.name == "fzf" then
            handled = m.match({ { label = "a" } }, "", function() end)
          end
        end
        return handled == false
      end)())
check("fzf declines an empty list", (function()
        local handled
        for _, m in ipairs(cl.matchers) do
          if m.name == "fzf" then handled = m.match({}, "x", function() end) end
        end
        return handled == false
      end)())
check("without fzf, the substring matcher narrows", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local got
        cl.rankItems({ { label = "Safari" }, { label = "Terminal" } }, "saf",
                     function(out) got = out end)
        cl.matchers = saved
        return got and #got == 1 and got[1].label == "Safari"
      end)())

local function substringMatch(items, query)
  local got
  for _, m in ipairs(cl.matchers) do
    if m.name == "substring" then m.match(items, query, function(out) got = out end) end
  end
  return got
end

check("it puts a row starting with the query before a word, before inside",
      (function()
        local got = substringMatch(
          { { label = "Encode" }, { label = "VS Code" }, { label = "Codec" } }, "cod")
        return got and #got == 3 and got[1].label == "Codec"
               and got[2].label == "VS Code" and got[3].label == "Encode",
               got and table.concat((function()
                 local t = {}; for i, r in ipairs(got) do t[i] = r.label end; return t
               end)(), ", ")
      end)())

check("a query with pattern characters is taken literally", (function()
        local got = substringMatch({ { label = "C++ notes" }, { label = "Cxx" } }, "c++")
        return got and #got == 1 and got[1].label == "C++ notes"
      end)())

-- The kernel matches no text itself; with no matcher taking the query,
-- every row stays rather than none.
check("with no matcher at all, nothing is narrowed", (function()
        local saved = cl.matchers
        cl.matchers = {}
        local got
        cl.rankItems({ { label = "Safari" }, { label = "Terminal" } }, "saf",
                     function(out) got = out end)
        cl.matchers = saved
        return got and #got == 2
      end)())

check("the default profile tries fzf first", (function()
        local order = cl.settings.matchers or {}
        return order[1] == "fzf" and order[2] == "substring"
      end)())

-- Typing narrows the rows and deleting has to bring them back, which
-- only holds if every query searches all of them rather than what the
-- previous query left.
check("deleting what you typed brings every row back", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local picker = openRecorded("palette")
        local all = #(picker.shown or {})

        picker.type("zzqqxx-matches-nothing")
        local narrowed = #(picker.shown or {})
        picker.type("")
        local restored = #(picker.shown or {})

        cl.matchers = saved
        return all > 1 and narrowed == 0 and restored == all,
               ("%d -> %d -> %d"):format(all, narrowed, restored)
      end)())

-- Matchers answer through hs.task, so the answer for an older query can
-- land after the one for a newer query. Whatever is on screen has to be
-- the answer to what is in the field.
check("a late answer to an older query is dropped", (function()
        local saved = cl.matchers
        local pending = {}
        cl.matchers = { { name = "slow", match = function(items, q, cb)
          pending[q] = function() cb(items) end
          return true
        end } }

        local picker = openRecorded("palette")

        picker.type("a")
        picker.type("ab")
        pending["ab"]()
        local answered = picker.shown
        pending["a"]()                      -- arrives last

        cl.matchers = saved
        return picker.shown == answered
      end)())

check("a declined query falls through with its rows", (function()
        local got
        local rows = { { label = "a", rank = 0 }, { label = "b", rank = 0 } }
        cl.rankItems(rows, "", function(out) got = out end)
        return got ~= nil and #got == 2
      end)(), "matchWith did not fall through to the callback")

group("ranking")
check("rankers are registered", #cl.rankers >= 3,
      (function()
        local n = {}
        for _, r in ipairs(cl.rankers) do n[#n+1] = r.name end
        return table.concat(n, " ")
      end)())
check("alphabetical is off by default", (function()
        for _, r in ipairs(cl.rankers) do
          if r.name == "alphabetical" then return r.weight == 0 end
        end
        return false
      end)())
-- The premise of a weighted sum: if a ranker scores on its own scale,
-- the weight beside it in config/defaults.jsonc means something different from the
-- one next to it, and tuning either is guesswork.
check("a declared rank is its specificity score, held within 0..1", (function()
        local score
        for _, ranker in ipairs(cl.rankers) do
          if ranker.name == "specificity" then score = ranker.score end
        end
        return score ~= nil and score({ rank = 0.5 }) == 0.5 and score({ rank = 1 }) == 1
               and score({ rank = 10 }) == 1 and score({ rank = -1 }) == 0 and score({}) == 0
      end)())

check("every ranker scores within 0..1", (function()
        local probes = {
          { label = "a", rank = 0.5 },
          { label = "b", rank = 10 },   -- above 1, as a mistaken declaration would be
          { label = "c" },              -- no rank at all
        }
        local context = { count = #probes, matched = #probes,
                          position = {}, alphabetical = {} }
        for i, item in ipairs(probes) do
          context.position[item], context.alphabetical[item] = i, i
        end

        for _, ranker in ipairs(cl.rankers) do
          for _, item in ipairs(probes) do
            local ok, score = pcall(ranker.score, item, "", context)
            if not ok or type(score) ~= "number"
               or score < 0 or score > 1 then
              return false, ranker.name .. " -> " .. tostring(score)
            end
          end
        end
        return true
      end)())

local shippedFrecency
for _, ranker in ipairs(cl.rankers) do
  if ranker.name == "frecency" then shippedFrecency = { weight = ranker.weight, score = ranker.score } end
end
check("a ranker can be replaced by name", (function()
        local before = #cl.rankers
        cl.ranker("frecency", 1, function() return 0 end)
        local replaced = #cl.rankers == before
        cl.ranker("frecency", shippedFrecency.weight, shippedFrecency.score)
        return replaced
      end)())
-- The sorted list is cached, so an extension registered after setup has
-- to invalidate it or it never appears.
check("registering later re-sorts the extensions", (function()
        local before = #cl.sortedExtensions()
        cl.register({ name = "zz-test-only-last" })
        local after = cl.sortedExtensions()
        local last = after[#after].name
        cl.unregisterExtension("zz-test-only-last")
        return #after == before + 1 and last == "zz-test-only-last",
               tostring(before) .. " -> " .. tostring(#after)
      end)())

check("a new ranker can be added", (function()
        local before = #cl.rankers
        cl.ranker("test-only", 0, function() return 0 end)
        local added = #cl.rankers == before + 1
        if cl.rankers[#cl.rankers].name == "test-only" then table.remove(cl.rankers) end
        return added
      end)())

-- Every extension's own checks run after these, against the shipped rankers.
check("and those checks leave no ranker or extension of theirs behind", (function()
        for _, ext in ipairs(cl.extensions) do
          if ext.name == "zz-test-only-last" then return false, ext.name end
        end
        for _, ranker in ipairs(cl.rankers) do
          if ranker.name == "test-only" then return false, "test-only ranker" end
          if ranker.name == "frecency" and ranker.score ~= shippedFrecency.score then
            return false, "frecency replaced"
          end
        end
        return true
      end)())
check("context rows outrank catalogue rows", (function()
        local ctxRank, appRank
        for _, ext in ipairs(cl.extensions) do
          if ext.name == "context" then ctxRank = ext.rank end
          if ext.name == "systemsettings" then appRank = ext.rank end
        end
        return ctxRank and appRank and ctxRank > appRank
      end)())
check("rows carry a rank", (function()
        for _, row in ipairs(rows) do
          if row.rank == nil then return false end
        end
        return true
      end)())
check("frecency is zero for something never run",
      rankerEntry("frecency").score({ label = "never run this" }) == 0)

check("frecency weights a run by how long ago, as zoxide does", (function()
        local frecency = rankerEntry("frecency").spec
        local row = { label = "zoxide-weighted" }
        cl.recordUse(row)
        local now = os.time()
        local scores = {
          frecency.scoreOf(row, now + 60), frecency.scoreOf(row, now + 2 * 3600),
          frecency.scoreOf(row, now + 2 * 86400), frecency.scoreOf(row, now + 8 * 86400),
        }
        cl.recordUse(row)
        local twice = frecency.scoreOf(row, now + 60)
        return scores[1] == 4 and scores[2] == 2 and scores[3] == 0.5 and scores[4] == 0.25
               and twice == 8,
               table.concat(scores, " ") .. " / " .. tostring(twice)
      end)())

check("each of those steps is a setting, as Albert has them", (function()
        local frecency = rankerEntry("frecency").spec
        local row = { label = "stepped" }
        cl.recordUse(row)
        local now, settings = os.time(), cl.userSettings
        cl.userSettings = { ["frecency.hourWeight"] = 10, ["frecency.olderWeight"] = 0 }
        local hour, older = frecency.scoreOf(row, now + 60), frecency.scoreOf(row, now + 8 * 86400)
        local day = frecency.scoreOf(row, now + 2 * 3600)
        cl.userSettings = settings
        return hour == 10 and older == 0 and day == 2, ("%s %s %s"):format(hour, day, older)
      end)())

check("past maxAge every rank is scaled down, and one below 1 forgotten", (function()
        local frecency, savedSettings = rankerEntry("frecency").spec, cl.userSettings
        frecency.reset()
        cl.userSettings = { ["frecency.maxAge"] = 10 }
        local a, b, c = { label = "age-a" }, { label = "age-b" }, { label = "age-c" }
        for _ = 1, 12 do cl.recordUse(a) end
        cl.recordUse(b)
        cl.recordUse(b)
        cl.recordUse(c)
        local now = os.time()
        -- a was run 12 times but scaled on the way; c, run once past the
        -- limit, is scaled below 1 and forgotten.
        local ra, rc = frecency.scoreOf(a, now) / 4, frecency.scoreOf(c, now)
        cl.userSettings = savedSettings
        frecency.reset()
        return ra > 1 and ra < 12 and rc == 0, ("a %.2f, c %.2f"):format(ra, rc)
      end)())

check("a count kept before runs had times still counts, as an old run, used before anything timed", (function()
        local frecency = rankerEntry("frecency").spec
        local realGet = hs.settings.get
        frecency.reset()
        hs.settings.get = function(key)
          if key == "commandlayer.actionUsage" then return { ["text\0legacy row"] = 3 } end
          return realGet(key)
        end
        local score = frecency.scoreOf({ label = "legacy row" })
        local ranked = frecency.score({ label = "legacy row" })
        local last = cl.lastUsed({ label = "legacy row" })
        cl.recordUse({ label = "legacy row" })
        local after = frecency.scoreOf({ label = "legacy row" })
        hs.settings.get = realGet
        frecency.reset()
        return score == 0.75 and ranked > 0 and last == 1 and after == 16,
               ("%s / %s / %s / %s"):format(tostring(score), tostring(ranked), tostring(last), tostring(after))
      end)())

check("frecency weighted 0 records nothing, and nothing is recently used", (function()
        local entry = rankerEntry("frecency")
        local weight = entry.weight
        entry.spec.reset()
        entry.weight = 0
        local row = { label = "unweighted", subject = { kind = "t", name = "unweighted" } }
        cl.recordUse(row)
        local used = cl.lastUsed(row)
        entry.weight = weight
        local score = entry.spec.scoreOf(row)
        entry.spec.reset()
        return score == 0 and used == 0, tostring(score) .. " / " .. tostring(used)
      end)())

group("forgetting what was picked")

check("lastUsed is when a row was last picked, by the latest ranker in use", (function()
        local frecency = rankerEntry("frecency").spec
        frecency.reset()
        local clock = 1000
        T.stub(os, "time", function() return clock end)
        local a, b = { label = "last-a" }, { label = "last-b" }
        cl.recordUse(a)
        clock = 2000
        cl.recordUse(b)
        clock = 3000
        cl.recordUse(a)
        local saved = cl.rankers
        cl.rankers = { rankerEntry("frecency"),
          { name = "later", weight = 1, score = function() return 0 end,
            lastUsed = function(item) return item.label == "last-b" and 2500 or 0 end },
          { name = "unused", weight = 0, score = function() return 0 end,
            lastUsed = function() return 9999 end } }
        local la, lb, never = cl.lastUsed(a), cl.lastUsed(b), cl.lastUsed({ label = "last-never" })
        cl.rankers = saved
        frecency.reset()
        return la == 3000 and lb == 2500 and never == 0, ("%s %s %s"):format(la, lb, never)
      end)())

check("removing a row tells every ranker in use its key, clearing tells them to reset; at weight 0, neither",
      (function()
        local heard = {}
        local function fake(name, weight)
          return { name = name, weight = weight, score = function() return 0 end,
                   forget = function(key) heard[#heard + 1] = name .. " forget " .. key end,
                   reset = function() heard[#heard + 1] = name .. " reset" end }
        end
        local saved = cl.rankers
        cl.rankers = { fake("on", 1), fake("off", 0),
                       { name = "throws", weight = 1, score = function() return 0 end,
                         forget = function() error("no") end } }
        cl.removeRecentlyUsed({ label = "x", subject = { kind = "t", name = "gone" } })
        cl.clearRecentlyUsed()
        cl.rankers = saved
        local text = table.concat(heard, " | ")
        return text == "on forget t\0gone | on reset", text
      end)())

check("frecency forgets one row, and resets every row", (function()
        local frecency = rankerEntry("frecency").spec
        frecency.reset()
        local a, b = { label = "forget-a" }, { label = "forget-b" }
        cl.recordUse(a)
        cl.recordUse(b)
        cl.removeRecentlyUsed(a)
        local afterForget = { cl.lastUsed(a), frecency.scoreOf(a), cl.lastUsed(b) }
        cl.recordUse(a)
        cl.clearRecentlyUsed()
        local afterReset = { cl.lastUsed(a), cl.lastUsed(b) }
        return afterForget[1] == 0 and afterForget[2] == 0 and afterForget[3] > 0
               and afterReset[1] == 0 and afterReset[2] == 0,
               table.concat(afterForget, " ") .. " / " .. table.concat(afterReset, " ")
      end)())

check("a verb picked on cmd+k is learned for that kind of row, apart from the command's own row", (function()
        local frecency = rankerEntry("frecency").spec
        frecency.reset()
        cl.registerCommand("test.shine", { title = "Shine", menus = {},
          inputs = { { id = "thing", picker = { when = "viewItem == 'box' || viewItem == 'ball'" } } },
          run = function() end })
        local function verb(kind)
          for _, row in ipairs(cl.itemActions({ kind = kind, name = "one" }, {})) do
            if row.command == "test.shine" then return row end
          end
        end
        local onBox, onBall = verb("box"), verb("ball")
        if not (onBox and onBall) then return false, "no verb" end
        cl.recordUse(onBox)
        local scores = { frecency.scoreOf(onBox), frecency.scoreOf(verb("ball")),
                         frecency.scoreOf(cl.commandRow(cl.getCommand("test.shine"), {})) }
        cl.registerCommand("test.shine", { title = "Shine", menus = {}, run = function() end })
        frecency.reset()
        return scores[1] > 0 and scores[2] == 0 and scores[3] == 0, table.concat(scores, " ")
      end)())

-- Sorting every row by name took most of a keystroke's ranking, for a ranker
-- that ships at weight 0.
group("the alphabetical order, only for a ranker that reads it")
do
  local stub = T.stub
  local sorts, realSort = 0, table.sort
  stub(table, "sort", function(list, compare)
    sorts = sorts + 1
    return realSort(list, compare)
  end)
  stub(cl, "matchers", {})
  local unsorted = { { label = "banana" }, { label = "Cherry" }, { label = "apple" } }
  cl.rankItems(unsorted, "", function() end)
  local whileOff = sorts
  for _, ranker in ipairs(cl.rankers) do
    stub(ranker, "weight", ranker.name == "alphabetical" and 1 or 0)
  end
  sorts = 0
  local ordered
  cl.rankItems(unsorted, "", function(out) ordered = out end)
  local labels = {}
  for i, row in ipairs(ordered or {}) do labels[i] = row.label end
  check("at weight 0 no row is sorted by name; in use, rows are, whatever their case",
        whileOff == 1 and sorts == 2 and table.concat(labels, ",") == "apple,banana,Cherry",
        ("%d sorts off, %d in use: %s"):format(whileOff, sorts, table.concat(labels, ",")))
end

local function labelsOf(rows, grades)
  local out = {}
  for i, row in ipairs(rows or {}) do
    out[i] = tostring(row.label) .. (grades and (" " .. tostring(grades[i])) or "")
  end
  return table.concat(out, ", ")
end

local function shippedMatcher(name)
  for _, m in ipairs(cl.loadedMatchers or cl.matchers) do
    if m.name == name then return m.match end
  end
end

group("alwaysShow")

check("an alwaysShow row is never dropped, and with text typed follows the ranked rows in the order given",
      (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local items = { { label = "status two", alwaysShow = true }, { label = "Alphabet" },
                        { label = "alpha status", alwaysShow = true }, { label = "Beta" }, { label = "Alpha" } }
        local typed, empty
        cl.rankItems(items, "alpha", function(out) typed = out end)
        cl.rankItems(items, "", function(out) empty = out end)
        cl.matchers = saved
        local function names(list)
          local out = {}
          for i, row in ipairs(list or {}) do out[i] = row.label end
          return table.concat(out, ", ")
        end
        return names(typed) == "Alpha, Alphabet, status two, alpha status" and #(empty or {}) == 5,
               names(typed) .. " / " .. names(empty)
      end)())

check("a row's alwaysShow is a boolean",
      #cl.checkRow({ label = "x", alwaysShow = true }) == 0 and #cl.checkRow({ label = "x", alwaysShow = "yes" }) == 1)

----------------------------------------------------------------------
group("keywords and graded matches")
do
  local stub = T.stub
  local rowsForGrades = {
    { label = "Foo", keywords = { "https://github.com/foo" } }, { label = "Legithubby" },
    { label = "Open GitHub" }, { label = "GitHub Desktop" }, { label = "GitHub" }, { label = "Unrelated" },
  }
  local kept, grades
  shippedMatcher("substring")(rowsForGrades, "github", function(r, g) kept, grades = r, g end)
  local falling = grades ~= nil and #grades == #(kept or {})
  for i = 2, #(grades or {}) do falling = falling and grades[i] < grades[i - 1] end
  check("substring grades exact, prefix, word start, inside, then a row found only by its keywords",
        kept and #kept == 5 and kept[1].label == "GitHub" and kept[2].label == "GitHub Desktop"
        and kept[3].label == "Open GitHub" and kept[4].label == "Legithubby" and kept[5].label == "Foo"
        and grades[1] == 1 and falling,
        labelsOf(kept, grades))

  local long
  shippedMatcher("substring")({ { label = "Long", keywords = { string.rep("x", 170) .. "needle", 7 } },
                               { label = "Short", keywords = { "a needle" } } },
                             "needle", function(r) long = r end)
  check("keywords are matched only up to their limit, and a keyword that is not a string is passed over",
        long and #long == 1 and long[1].label == "Short", labelsOf(long))

  -- hs.task never answers in the harness, so fzf's answer is given by hand.
  local sent
  stub(cl.tools, "path", function(name) return name == "fzf" and "/fzf" or nil end)
  stub(cl.tools, "run", function(program, args, done, opts)
    sent = { program = program, args = args, input = opts and opts.input, done = done }
    return { terminate = function() end }
  end)
  local tabs = { { label = "Tab", keywords = { "https://a.example" } },
                 { label = "Tab", keywords = { "https://b.example" } }, { label = "Bexample" } }
  local got, gotGrades
  local handled = shippedMatcher("fzf")(tabs, "bexample", function(r, g) got, gotGrades = r, g end)
  local args = sent and table.concat(sent.args, " ") or ""
  check("fzf is sent each row as index, label and keywords, and searches from the label on",
        handled == true and sent.input == "1\tTab\thttps://a.example\n2\tTab\thttps://b.example\n3\tBexample\t"
        and args:find("--delimiter=\t", 1, true) ~= nil and args:find("--nth=2..", 1, true) ~= nil,
        sent and (sent.input .. " / " .. args))
  sent.done(0, "3\tBexample\t\n2\tTab\thttps://b.example\n", "")
  check("its answer comes back by index, so rows sharing a label are told apart, graded in Lua",
        got and #got == 2 and got[1] == tabs[3] and got[2] == tabs[2]
        and gotGrades[1] == 1 and gotGrades[2] < 0.3,
        labelsOf(got, gotGrades))

  shippedMatcher("fzf")({ { label = "Git: Pull" }, { label = "Legit pulse" } }, "git pul", function(r, g)
    got, gotGrades = r, g
  end)
  sent.done(0, "2\tLegit pulse\t\n1\tGit: Pull\t\n", "")
  check("a query of several terms is graded term by term: each a prefix or word start beats inside",
        got and got[1].label == "Legit pulse" and gotGrades[2] > gotGrades[1], labelsOf(got, gotGrades))

  check("a row's keywords are a list of strings", (function()
          local fine, wrong = cl.checkRow({ label = "x", keywords = { "a" } }),
                              cl.checkRow({ label = "x", keywords = { "a", 1 } })
          return #fine == 0 and #wrong == 1 and wrong[1]:find('"keywords" item 2', 1, true) ~= nil,
                 table.concat(fine, " | ") .. " / " .. table.concat(wrong, " | ")
        end)())
end

group("relevance from graded matches")
do
  local stub = T.stub
  local relevance = rankerEntry("relevance")
  stub(cl, "rankers", { relevance })
  stub(cl, "matchers", { { name = "graded", match = function(items, _, callback)
    callback({ items[1], items[2] }, { 0.15, 1 })
    return true
  end } })
  local ordered
  cl.rankItems({ { label = "by keyword" }, { label = "exact" } }, "q", function(out) ordered = out end)
  check("a matcher's scores reach the rankers: a better match ranks above one the matcher put first",
        ordered and ordered[1].label == "exact", labelsOf(ordered))

  local many, position = {}, {}
  for i = 1, 2000 do
    many[i] = { label = "row " .. i }
    position[many[i]] = i
  end
  local quality = {}
  for i = 1, 2000 do quality[i] = 0.3 end
  quality[50] = 0.85
  -- Both stand for a query someone typed: with nothing typed relevance has
  -- no opinion, which the check below says.
  local graded = { count = 2000, matched = 2000, position = position,
                   quality = quality, query = "row" }
  local orderOnly = { count = 2000, matched = 2000, position = position, query = "row" }
  local score = relevance.score
  check("graded, the 50th of 2000 scores by its grade: a prefix there beats a fuzzy match first, "
        .. "and a fuzzy match there scores low",
        score(many[50], nil, graded) > score(many[1], nil, graded) and score(many[51], nil, graded) < 0.3
        and score(many[1], nil, graded) > score(many[2], nil, graded),
        ("%.3f %.3f %.3f"):format(score(many[50], nil, graded), score(many[1], nil, graded),
                                  score(many[51], nil, graded)))
  check("an exact-match boost lifts a row whose label is what was typed, and is nothing as shipped",
        (function()
          local exactFirst = { count = 2, matched = 2, query = "row",
                               position = { [many[1]] = 2, [many[2]] = 1 }, quality = { 0.85, 1 } }
          local shipped = score(many[1], nil, exactFirst) - score(many[2], nil, exactFirst)
          local settings = cl.userSettings
          cl.userSettings = { ["relevance.exactMatchBoost"] = 0.5 }
          local boosted = score(many[1], nil, exactFirst) - score(many[2], nil, exactFirst)
          cl.userSettings = settings
          return boosted > shipped + 0.2, ("%.3f shipped, %.3f boosted"):format(shipped, boosted)
        end)())

  check("a matcher giving only an order is scored by position in it",
        score(many[1], nil, orderOnly) == 1 and score(many[50], nil, orderOnly) > 0.97)

  -- Scoring the given order with nothing typed froze it: the first row of a
  -- cmd+k list scored 1 and the second 0, so no history could lift one.
  check("with nothing typed every row scores the same, whatever order it was given in", (function()
          local nothing = { count = 2000, matched = 2000, position = position, query = "" }
          return score(many[1], nil, nothing) == score(many[2], nil, nothing)
                 and score(many[1], nil, nothing) == score(many[2000], nil, nothing),
                 ("%.3f %.3f"):format(score(many[1], nil, nothing), score(many[2000], nil, nothing))
        end)())
end

group("aliases")
do
  local stub = T.stub
  stub(cl, "matchers", substringOnly())
  cl.registerCommand("test.leftHalf", { title = "Left half", menus = { "test-aliases" }, run = function() end })
  cl.registerCommand("test.lhasa", { title = "Lhasa", menus = { "test-aliases" }, run = function() end })
  cl.view({ name = "test-aliases", menus = { "test-aliases" }, recentlyUsed = 3 })
  stub(cl.settings, "aliases", { ["test.leftHalf"] = "lh", ["test.lhasa"] = { "place" } })
  local frecency = rankerEntry("frecency").spec
  frecency.reset()

  local function commands(picker)
    local out = {}
    for i, row in ipairs(picker.shown or {}) do out[i] = tostring(row.command) end
    return out
  end

  cl.recordUse(cl.commandRow(cl.getCommand("test.lhasa"), {}))
  local picker = openRecorded("test-aliases")
  picker.type("lh")
  local typed = commands(picker)
  check("an alias typed puts its command first, unmatched, ahead of a match used lately",
        typed[1] == "test.leftHalf" and typed[2] == "test.lhasa", table.concat(typed, ", "))

  picker.type(" LH ")
  local cased = commands(picker)
  picker.type("PLACE")
  local listed = commands(picker)
  picker.type("lha")
  local partial = commands(picker)
  check("whatever its case and the spaces around it, from a list too; a part of an alias is only text",
        cased[1] == "test.leftHalf" and listed[1] == "test.lhasa"
        and partial[1] == "test.lhasa" and #partial == 1,
        table.concat(cased, ", ") .. " / " .. table.concat(listed, ", ") .. " / " .. table.concat(partial, ", "))

  cl.checkSettings({ aliases = { ["no.such"] = "x", ["test.leftHalf"] = { "lh", 3 } } },
                   "test-aliases-problems/settings.json", cl.readJSONC(cl.SPOON_DIR .. "config/defaults.jsonc"))
  local named = {}
  for _, p in ipairs(cl.getProblems()) do
    if p.file:find("test-aliases-problems", 1, true) then named[#named + 1] = p.message end
  end
  local text = table.concat(named, " | ")
  check("an alias for no command, or one that is not text, is a problem; aliases is a setting",
        #named == 2 and text:find('"aliases": there is no command "no.such"', 1, true) ~= nil
        and text:find('"aliases.test.leftHalf" should be a string or a list of strings', 1, true) ~= nil,
        text)

  frecency.reset()
  cl.registerCommand("test.leftHalf", { title = "Left half", menus = {}, run = function() end })
  cl.registerCommand("test.lhasa", { title = "Lhasa", menus = {}, run = function() end })
  T.removeView("test-aliases")
end
