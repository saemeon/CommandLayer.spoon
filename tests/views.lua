-- CommandLayer.spoon/tests/views.lua
-- Views: nested menus, prefixes, declared pickers, menus.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local ctx = T.context()
local rows = cl.gather(ctx, { menus = { "root" } })

local substringOnly = T.substringOnly
local openRecorded = T.openRecorded
local recordedSpec = T.recordedSpec
local rowOpening = T.rowOpening
local removeView = T.removeView
local layerModal = T.layerModal
local feed = T.picker

group("nested menus")
-- A picker of the checks' own under the root, so they hold whichever
-- pickers ship.
feed("test-nested", { { label = "leaf" } }, { title = "Nested", parent = "root" })

check("a view declared under another is a row in it", (function()
        recordedSpec("test-nested")
        local root = openRecorded("root")
        return rowOpening(root, "test-nested") ~= nil
      end)())

check("picking that row opens the view over this one, and stays open",
      (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        root.row = rowOpening(root, "test-nested")
        local before = layerModal.exits
        root.accept()
        local nested = nestedSpec.picker
        return root.row ~= nil and layerModal.exits == before
               and nested ~= nil and #(nested.shown or {}) > 0,
               nested and tostring(nested.placeholder)
      end)())

check("escape from it comes back to the parent, rows intact", (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        local count = #root.shown
        root.row = rowOpening(root, "test-nested")
        root.accept()
        if not nestedSpec.picker then return false, "the nested picker did not open" end
        local before = layerModal.exits
        nestedSpec.picker.dismiss()
        return #root.shown == count and layerModal.exits == before
               and root.placeholder == "Search"
      end)())

check("a picker left for another app closes the layer, even a level down", (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        root.row = rowOpening(root, "test-nested")
        root.accept()
        if not nestedSpec.picker then return false, "the nested picker did not open" end
        local before = layerModal.exits
        nestedSpec.picker.dismiss("away")
        return layerModal.exits == before + 1,
               tostring(layerModal.exits - before) .. " exits"
      end)())

check("a level deep in a tree shows the path to it", (function()
        feed("test-a", {}, { title = "A", parent = "root" })
        feed("test-b", { { label = "leaf" } }, { title = "B", parent = "test-a" })
        openRecorded("root")
        cl.push("test-a")
        cl.push("test-b")
        local b = cl.viewNamed("test-b").picker
        return b ~= nil and b.placeholder == "A \u{25B8} B",
               b and tostring(b.placeholder)
      end)())

check("a pushed level keeps the context the layer was entered with",
      (function()
        local root = openRecorded("root")
        cl.push("test-a")
        local a = cl.viewNamed("test-a").picker
        local row = select(2, rowOpening(a, "test-b"))
        return row ~= nil and row.ctx ~= nil
               and row.ctx == select(2, rowOpening(root, "test-a")).ctx
      end)())

check("picking a row with nothing to run closes quietly", (function()
        feed("test-inert", { { label = "just text" } })
        cl.open("test-inert")
        local before = layerModal.exits
        local ok, err = pcall(cl.viewNamed("test-inert").picker.accept)
        return ok and layerModal.exits == before + 1, tostring(err)
      end)())

-- An extension may hand back a list it keeps between opens; the menu rows
-- are added to a list of the picker's own, or every open would add them to
-- that list again.
check("opening a picker twice does not repeat its menu rows in a list its extension keeps", (function()
        local kept = { { label = "one" } }
        feed("test-kept", kept)
        feed("test-kept-child", {}, { title = "Child", parent = "test-kept" })
        cl.open("test-kept")
        cl.open("test-kept")
        return #kept == 1 and #cl.viewNamed("test-kept").picker.shown == 2,
               ("%d kept, %d shown"):format(#kept,
                 #cl.viewNamed("test-kept").picker.shown)
      end)())

group("prefixes")
-- The nested picker has no prefix, so a word prefix is given to it here,
-- as a profile's alias would, for the checks of how one behaves.
local savedPrefixes = cl.prefixes
cl.prefixes = { ["test-nested"] = "nest " }

check("typing a prefix opens its view, the prefix left in the field", (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        local before = layerModal.exits
        root.type("nest clone")
        local nested = nestedSpec.picker
        if not nested then return false, "did not open" end
        return nested.query == "nest clone" and nested.placeholder == "Nested"
               and layerModal.exits == before,
               ("%s / %s"):format(tostring(nested.query), tostring(nested.placeholder))
      end)())

check("and what follows it is what is searched", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        root.type("nest zzqqxx-nothing")
        if not nestedSpec.picker then cl.matchers = saved; return false, "did not open" end
        local shown = #(nestedSpec.picker.shown or { 1 })
        cl.matchers = saved
        return shown == 0, tostring(shown)
      end)())

check("a word prefix needs its space", (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        root.type("nest")
        return nestedSpec.picker == nil
      end)())

check("a symbol prefix needs none", (function()
        local paletteSpec = recordedSpec("palette")
        local root = openRecorded("root")
        root.type(">")
        local p = paletteSpec.picker
        return p ~= nil and p.query == ">", p and tostring(p.query)
      end)())

check("deleting the prefix goes back, keeping what is left", (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        root.type("nest x")
        local nested = nestedSpec.picker
        if not nested then return false, "did not open" end
        local before = layerModal.exits
        nested.type("nestx")
        return nested.hidden == true and root.query == "nestx"
               and layerModal.exits == before, tostring(root.query)
      end)())

check("escape from a prefix view comes back with the parent's rows",
      (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        local count = #root.shown
        root.type("nest x")
        if not nestedSpec.picker then return false, "did not open" end
        nestedSpec.picker.dismiss()
        return #root.shown == count and root.query == "",
               ("%d vs %d"):format(#root.shown, count)
      end)())

check("its own prefix typed inside it is just a search", (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        root.type("nest x")
        local nested = nestedSpec.picker
        if not nested then return false, "did not open" end
        nested.type("nest y")
        return nested.hidden ~= true and nested.placeholder == "Nested"
      end)())

check("a longer prefix takes over from a shorter one", (function()
        local undoQ = feed("test-q", {}, { title = "Q", prefix = "q" })
        local undoQQ = feed("test-qq", {}, { title = "QQ", prefix = "qq " })
        local root = openRecorded("root")
        root.type("q")
        local q = cl.viewNamed("test-q").picker
        local reached = q and (q.type("qq x") or true)
        local qq = cl.viewNamed("test-qq").picker
        undoQ(); undoQQ()
        return reached and qq ~= nil and qq.query == "qq x", qq and tostring(qq.query)
      end)())

check("a chord on a view with a prefix opens the root with it typed", (function()
        recordedSpec("root")
        local paletteSpec = recordedSpec("palette")
        cl.quickOpen("palette")
        local root, p = cl.viewNamed("root").picker, paletteSpec.picker
        return root ~= nil and root.query == ">" and p ~= nil and p.query == ">",
               ("%s / %s"):format(tostring(root and root.query), tostring(p and p.query))
      end)())

check("a quickOpen keybinding with a query opens the view it names", (function()
        recordedSpec("root")
        local nestedSpec = recordedSpec("test-nested")
        cl.runKeybinding({ key = "cmd+g", command = "quickOpen",
                           args = { query = "nest " } })
        local root, nested = cl.viewNamed("root").picker, nestedSpec.picker
        return root ~= nil and root.query == "nest " and nested ~= nil
               and nested.query == "nest ",
               ("%s / %s"):format(tostring(root and root.query),
                                  tostring(nested and nested.query))
      end)())

cl.prefixes = savedPrefixes

check("without the alias, a view with no prefix is not opened by typing its word", (function()
        local nestedSpec = recordedSpec("test-nested")
        local root = openRecorded("root")
        root.type("nest init")
        return nestedSpec.picker == nil
      end)())

-- hs.chooser runs its query callback from inside show(), and a picker
-- that finishes showing after another took over becomes key again, which
-- dismisses the other. A chord that types a prefix switches pickers at
-- exactly that moment, so this presenter behaves the same way.
check("a chord that types a prefix lands in its picker, with a chooser-like presenter",
      (function()
        local lastShown
        cl.presenter("reentrant", { create = function(opts)
          local p = {}
          function p.show(state)
            p.hidden, p.shown = false, state.items
            lastShown = p
            opts.onQuery(p, state.query or "")
            if lastShown ~= p then
              opts.onPick(lastShown, nil)
              lastShown = p
            end
          end
          function p.setItems(items) p.shown = items end
          function p.hide() p.hidden = true end
          return p
        end })

        local saved = {}
        for _, name in ipairs({ "root", "recent" }) do
          local s = cl.viewNamed(name)
          saved[name] = s.presenter
          s.presenter, s.picker = "reentrant", nil
        end

        local before = layerModal.exits
        cl.runKeybinding({ key = "cmd+r", command = "quickOpen", args = { view = "recent" } })
        local root, recent = cl.viewNamed("root").picker, cl.viewNamed("recent").picker
        local ok = recent ~= nil and recent.hidden == false
                   and root ~= nil and root.hidden == true
                   and layerModal.exits == before
        local detail = ("recent hidden=%s, root hidden=%s"):format(
          tostring(recent and recent.hidden), tostring(root and root.hidden))

        for name, presenter in pairs(saved) do
          local s = cl.viewNamed(name)
          s.presenter, s.picker = presenter, nil
        end
        return ok, detail
      end)())

check("what follows a prefix is what is searched", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local paletteSpec = recordedSpec("palette")
        openRecorded("root").type(">lock")
        cl.matchers = saved
        local p = paletteSpec.picker
        if not p then return false, "did not open" end
        for _, row in ipairs(p.shown or {}) do
          if tostring(row.label):lower():find("lock", 1, true) then return true end
        end
        return false, tostring(#(p.shown or {})) .. " rows"
      end)())

check("a view's prefix may be a list, and any of them opens it", (function()
        local undo = feed("test-list", { { label = "x" } }, { title = "List", prefix = { "listing ", "li " } })
        openRecorded("root").type("li x")
        local p = cl.viewNamed("test-list").picker
        undo()
        return p ~= nil and p.placeholder == "List", p and tostring(p.placeholder)
      end)())

check("a profile's alias adds a prefix, and the view's own still works", (function()
        local saved = cl.prefixes
        cl.prefixes = { recent = "r " }
        local recentSpec = recordedSpec("recent")
        openRecorded("root").type("r x")
        local byAlias = recentSpec.picker ~= nil
        recentSpec.picker = nil
        openRecorded("root").type("recent x")
        local byOwn = recentSpec.picker ~= nil
        cl.prefixes = saved
        return byAlias and byOwn, ("%s / %s"):format(tostring(byAlias), tostring(byOwn))
      end)())

check("editing a prefix into its alias searches what follows the alias", (function()
        local undo = feed("test-alias", { { label = "x" } }, { prefix = "aliasing " })
        local saved = cl.prefixes
        cl.prefixes = { ["test-alias"] = "al " }
        openRecorded("root").type("aliasing one")
        local p = cl.viewNamed("test-alias").picker
        local first = cl.topView() and cl.topView().query
        if p then p.type("al two") end
        local got = cl.topView() and cl.topView().query
        cl.prefixes = saved
        undo()
        return p ~= nil and p.hidden ~= true and first == "one" and got == "two",
               ("%s then %s"):format(tostring(first), tostring(got))
      end)())

check("a prefix whose view has nothing leaves you searching, told once", (function()
        local undo = feed("test-empty", {}, { prefix = "hollow ", empty = "Nothing here" })
        local alerts, real = 0, hs.alert.show
        hs.alert.show = function() alerts = alerts + 1 end
        local root = openRecorded("root")
        root.type("hollow a")
        root.type("hollow ab")
        hs.alert.show = real
        undo()
        return alerts == 1 and root.hidden ~= true, tostring(alerts) .. " alerts"
      end)())

check("a prefix alone whose view has nothing clears the field, so the root opens as usual", (function()
        local undo = feed("test-empty-alone", {}, { prefix = "hollow ", empty = "Nothing here" })
        local alerts, real = 0, hs.alert.show
        hs.alert.show = function() alerts = alerts + 1 end
        local root = openRecorded("root")
        root.query = "unchanged"
        root.type("hollow ")
        hs.alert.show = real
        undo()
        return alerts == 1 and root.query == "" and root.hidden ~= true,
               tostring(alerts) .. " alerts, field " .. tostring(root.query)
      end)())

check("'?' names each prefix of a picker, aliases too, and its chord", (function()
        local saved = cl.prefixes
        cl.prefixes = { recent = "r " }
        local helpSpec = recordedSpec("help")
        openRecorded("root").type("?")
        cl.prefixes = saved
        local help = helpSpec.picker
        if not help then return false, "did not open" end
        for _, row in ipairs(help.shown or {}) do
          if row.submenu == "recent" then
            local text = row.description
            return text:find("'recent '", 1, true) ~= nil
                   and text:find("'r '", 1, true) ~= nil
                   and text:find("cmd+r", 1, true) ~= nil, text
          end
        end
        return false, "no recent row"
      end)())

check("'?' lists the pickers you can reach, and how", (function()
        local helpSpec = recordedSpec("help")
        local root = openRecorded("root")
        root.type("?")
        local help = helpSpec.picker
        if not help then return false, "did not open" end
        local palette
        for _, row in ipairs(help.shown or {}) do
          if row.submenu == "palette" then palette = row end
        end
        return palette ~= nil and palette.description:find(">", 1, true) ~= nil
               and palette.description:find("cmd+o", 1, true) ~= nil,
               palette and palette.description
      end)())

check("'?' with text after it offers every text command, filled in, then the pickers it matches", (function()
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local helpSpec = recordedSpec("help")

        openRecorded("root").type("?")
        local bareSearches = 0
        for _, row in ipairs(helpSpec.picker and helpSpec.picker.shown or {}) do
          -- The search prefix is a picker of its own, listed like any other.
          if not row.submenu and (row.label or ""):find("Search the web", 1, true) then
            bareSearches = bareSearches + 1
          end
        end

        openRecorded("root").type("? lofi")
        local shown = helpSpec.picker.shown or {}
        local first, pickers = shown[1], 0
        for _, row in ipairs(shown) do if row.submenu then pickers = pickers + 1 end end

        openRecorded("root").type("?files")
        local filesPicker, filesSearch = false, false
        for _, row in ipairs(helpSpec.picker.shown or {}) do
          if row.submenu == "files" then filesPicker = true end
          if (row.label or ""):find("“files”", 1, true) then filesSearch = true end
        end

        cl.matchers = saved
        return bareSearches == 0
               and first ~= nil and (first.label or ""):find("“lofi”", 1, true) ~= nil
               and pickers == 0 and filesPicker and filesSearch,
               ("bare %d, first %s, pickers %d, files %s/%s"):format(bareSearches,
                 tostring(first and first.label), pickers, tostring(filesPicker), tostring(filesSearch))
      end)())

check("a picker reached by a prefix is a row in the root, and picking it types the prefix", (function()
        local undo = feed("test-reached", { { label = "x" } }, { title = "Reached", prefix = "reached " })
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local reachedSpec = recordedSpec("test-reached")
        local root = openRecorded("root")

        root.type("reac")
        local _, row = rowOpening(root, "test-reached")
        root.type("context")
        local _, contextRow = rowOpening(root, "context")
        root.type("search")
        local _, searchRow = rowOpening(root, "browser.searchWeb")

        root.type("reac")
        local index = rowOpening(root, "test-reached")
        local opened
        if index then
          root.row = index
          root.accept()
          opened = reachedSpec.picker
        end
        cl.matchers = saved
        undo()
        return row ~= nil and row.label == "Reached"
               and row.description:find("'reached '", 1, true) ~= nil
               and contextRow ~= nil and searchRow == nil
               and opened ~= nil and opened.query == "reached ",
               ("%s / context %s / search %s / query %s"):format(tostring(row and row.label),
                 tostring(contextRow and contextRow.label), tostring(searchRow ~= nil),
                 tostring(opened and opened.query))
      end)())

check("a picker's row in the root carries the picker's icon", (function()
        cl.themeIconProvider("test-view-icons", function(name)
          return name == "settings-gear" and "GEAR" or nil
        end)
        local saved = cl.matchers
        cl.matchers = substringOnly()
        local root = openRecorded("root")
        root.type("settings")
        local _, row = rowOpening(root, "settings")
        cl.matchers = saved
        cl.themeIconProvider("test-view-icons", function() return nil end)
        return row ~= nil and row.iconPath == "GEAR", tostring(row and row.iconPath)
      end)())

-- A cache that answers at once calls its callback straight away, and the
-- projects extension's callback asks for a refresh -- from inside building
-- rows. Rebuilding from there recursed until Hammerspoon crashed.
check("a refresh asked for while rows are built does not recurse", (function()
        local calls = 0
        cl.register({ name = "test-refresher", menus = { "root", "test-refresher" },
          items = function()
            calls = calls + 1
            if calls < 50 then cl.refresh() end
            return { { label = "refresher row" } }
          end })
        cl.view({ name = "test-refresher", prefix = "refresher ",
                  menus = { "test-refresher" }, presenter = "recording" })

        local root = openRecorded("root")
        local afterOpen = calls
        root.type("refresher x")
        local afterPush = calls

        removeView("test-refresher")
        for i, ext in ipairs(cl.extensions) do
          if ext.name == "test-refresher" then table.remove(cl.extensions, i); break end
        end
        cl.register({ name = "test-refresher-flush" })
        for i, ext in ipairs(cl.extensions) do
          if ext.name == "test-refresher-flush" then table.remove(cl.extensions, i); break end
        end

        return afterOpen <= 2 and afterPush - afterOpen <= 2,
               ("%d gathers opening, %d pushing"):format(afterOpen, afterPush - afterOpen)
      end)())

-- Chromium and Electron apps animate every frame change while
-- AXEnhancedUserInterface is on, which is what made a layout land late.
check("a layout turns enhanced UI off for the move, and back on after", (function()
        local enhanced, movedWith, sets = true, nil, {}
        local element = {
          attributeValue = function(_, name)
            if name == "AXEnhancedUserInterface" then return enhanced end
          end,
          setAttributeValue = function(_, _, value)
            sets[#sets + 1] = tostring(value)
            enhanced = value
          end,
        }
        local win = {
          application = function() return {} end,
          moveToUnit = function() movedWith = enhanced end,
        }
        local saved = hs.axuielement
        hs.axuielement = { applicationElement = function() return element end }
        local ctx = cl.buildContext()
        ctx.focusedWindow = win
        cl.executeCommand("windows.leftHalf", {}, ctx)
        hs.axuielement = saved
        return movedWith == false and table.concat(sets, " ") == "false true",
               ("moved with %s, set %s"):format(tostring(movedWith), table.concat(sets, " "))
      end)())

group("views")
check("the shipped pickers are declared", #cl.views >= 5,
      (function()
        local n = {}
        for _, v in ipairs(cl.views) do n[#n+1] = v.name end
        table.sort(n)
        return table.concat(n, " ")
      end)())
check("each names a menu, holds a text command, or offers the verbs on the subject it is given", (function()
        for _, v in ipairs(cl.views) do
          if not v.menus and not v.command and v.kind ~= "item" then return false, v.name end
        end
        return true
      end)())
-- A page or a selection is a context inside the app's, so the context
-- picker leads with its verbs, as the root leads with context's.
check("the context picker leads with what is in front, then the recent tabs", (function()
        local spec
        for _, v in ipairs(cl.views) do if v.name == "context" then spec = v end end
        local sections = spec and spec.sections or {}
        return #sections >= 2 and sections[1].from == "context" and sections[1].limit == 4
               and sections[2].from == "browser",
               tostring(sections[1] and sections[1].from) .. " then "
               .. tostring(sections[2] and sections[2].from)
      end)())

-- A chord comes from one place. A key left on a view would be a second,
-- and setup only logs it.
check("no view declares a key of its own", (function()
        for _, v in ipairs(cl.views) do
          if v.key then return false, v.name end
        end
        return true
      end)())
check("each picker is opened by a keybinding", (function()
        for _, name in ipairs({ "palette", "context", "recent", "files" }) do
          local found = false
          for _, entry in ipairs(cl.effectiveKeybindings()) do
            if cl.quickOpenTarget(entry) == name then found = true end
          end
          if not found then return false, name end
        end
        return true
      end)())
check("no two keybindings claim the same chord", (function()
        local seen = {}
        for _, entry in ipairs(cl.effectiveKeybindings()) do
          if type(entry.key) == "string" then
            local chord = entry.key:lower()
            if seen[chord] then return false, chord end
            seen[chord] = true
          end
        end
        return true
      end)())
check("every keybinding chord is readable", (function()
        for _, entry in ipairs(cl.effectiveKeybindings()) do
          if entry.key ~= nil then
            local _, key = cl.chord(entry.key)
            if not key then return false, tostring(entry.key) end
          end
        end
        return true
      end)())
-- A short shipped prefix would catch ordinary searches -- "w lan".
check("shipped prefixes are words, or VS Code's symbols", (function()
        for _, name in ipairs({ "palette", "recent", "context", "files", "grep", "settings", "keybindings", "help" }) do
          local v = cl.viewNamed(name)
          for _, p in ipairs(v and cl.prefixesOf(v) or {}) do
            if not (p == ">" or p == "?" or #p >= 4) then return false, p end
          end
        end
        return true
      end)())

group("menus")
local palette = cl.gather(ctx, { menus = { "commandPalette" } })
local recent  = cl.gather(cl.argContext(ctx, { activeView = "recent" }), { menus = { "recent" } })
check("palette is populated", #palette > 0, tostring(#palette) .. " rows")
check("recent is narrower than root", #recent <= #rows,
      tostring(#recent) .. " vs " .. tostring(#rows))

check("the root's projects follow the editor's recent list as it changes, not a scan's copy", (function()
        local vscode, projects = cl.modules.vscode, cl.modules.projects
        if not (vscode and projects and projects.forget) then return false, "missing module" end
        local savedRecent, savedNew = vscode.recentProjects, hs.task.new
        hs.task.new = function() return { start = function(t) return t end } end
        local listed = "/work/first"
        vscode.recentProjects = function() return { { path = listed, name = "p" } } end
        projects.forget()
        local before = projects.projects()
        listed = "/work/second"
        local after = projects.projects()
        vscode.recentProjects, hs.task.new = savedRecent, savedNew
        projects.forget()
        return before[1] ~= nil and before[1].path == "/work/first"
               and after[1] ~= nil and after[1].path == "/work/second",
               tostring(before[1] and before[1].path) .. " / " .. tostring(after[1] and after[1].path)
      end)())

-- What recent is for: the editor's recent projects, then the windows you
-- were using, apps you used at the bottom -- no app catalogue, and no zoxide
-- list burying the windows.
check("recent is the editor's projects, then windows, recent apps last, no catalogue", (function()
        local vscode, projects, windows, apps =
          cl.modules.vscode, cl.modules.projects, cl.modules.windows, cl.modules.apps
        if not (vscode and projects and windows and apps) then return false, "missing module" end
        local saved = { recentProjects = vscode.recentProjects,
                        projects = projects.projects, windows = windows.windows,
                        all = apps.all, apps = apps.apps }
        -- An installed app, so leaving the catalogue out is something the check sees.
        apps.all = function()
          return { { name = "Safari", bundleID = "com.apple.Safari",
                     path = "/Applications/Safari.app" } }
        end
        apps.apps = function() return { { name = "Mail", id = "com.apple.mail" } } end
        vscode.recentProjects = function()
          return { { path = "/work/editor-project", name = "editor-project" } }
        end
        projects.projects = function()
          return { { path = "/zoxide/somewhere", name = "somewhere" } }
        end
        windows.windows = function()
          return { { id = 42, title = "A window", app = "Notes" } }
        end

        -- What the recent picker shows, sections and all.
        local recentSpec = recordedSpec("recent")
        cl.open("recent")
        local got = recentSpec.picker and recentSpec.picker.shown
        vscode.recentProjects, projects.projects, windows.windows, apps.all, apps.apps =
          saved.recentProjects, saved.projects, saved.windows, saved.all, saved.apps

        local project, window, recentApp, catalogue, zoxide
        for i, row in ipairs(got or {}) do
          local kind = row.subject and row.subject.kind
          if kind == "project" and row.subject.path == "/work/editor-project" then project = i end
          if kind == "project" and row.subject.path == "/zoxide/somewhere" then zoxide = true end
          if kind == "window" then window = window or i end
          if kind == "app" and row.subject.name == "Mail" then
            recentApp = (row.description or ""):find("^Recent apps") and i or nil
          end
          if kind == "app" and row.subject.name == "Safari" then catalogue = true end
        end
        return project ~= nil and window ~= nil and project < window
               and recentApp ~= nil and recentApp > window and not catalogue and not zoxide,
               ("project %s, window %s, recent app %s, catalogue %s, zoxide %s"):format(
                 tostring(project), tostring(window), tostring(recentApp), tostring(catalogue),
                 tostring(zoxide))
      end)())

group("windows")
local layouts = 0
for _, row in ipairs(palette) do
  if row.command and row.command:match("^windows%.") then layouts = layouts + 1 end
end
check("layouts reach the palette", layouts > 0, tostring(layouts) .. " rows")
check("and the root, as commands that ask which window", (function()
        for _, row in ipairs(rows) do
          if row.command == "windows.leftHalf" then
            local inputs = cl.getCommand(row.command).inputs
            return inputs ~= nil and type(inputs[1].picker) == "table" and inputs[1].picker.when ~= nil, "no input taking a window"
          end
        end
        return false, "Left half is not in the root"
      end)())

group("a picker holding a text command")
-- On a kernel of its own, from a settings.json, as a person declares one: the
-- helpers above act on it from here on.
local holding = T.layer({ views = { { name = "test-holds", title = "Holds", prefix = "holds ",
                                      command = "browser.searchWeb" } } })

check("a picker declared in settings with a command holds that text command, what is typed filled in", (function()
        local saved = holding.matchers
        holding.matchers = T.substringOnly()
        local spec = T.recordedSpec("test-holds")
        holding.open("test-holds")
        local p = spec.picker
        local bare = p and p.shown or {}
        local root = T.openRecorded("root")
        root.type("holds lofi")
        p = spec.picker
        local typed = p and p.shown or {}
        holding.matchers = saved
        return #bare == 1 and bare[1].command == "browser.searchWeb" and (bare[1].args or {}).query == nil
               and #typed == 1 and typed[1].command == "browser.searchWeb" and typed[1].args.query == "lofi"
               and #holding.problems == 0,
               ("bare %d rows (%s), typed %d rows (%s), %d problems"):format(#bare, tostring(bare[1] and bare[1].label),
                 #typed, tostring(typed[1] and typed[1].label), #holding.problems)
      end)())
