-- CommandLayer.spoon/tests/presenters.lua
-- Presenters: the chooser, the popup, and what the kernel promises them.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local noop = T.noop
local substringOnly = T.substringOnly
local openRecorded = T.openRecorded
local rowOpening = T.rowOpening
local layerModal = T.layerModal

group("presenters")
check("the chooser presenter is loaded from presenters/",
      cl.presenters.chooser ~= nil)

check("what a person might change is a setting: frecency's maxAge, the popup's limits, the webview's size, the kernel's options", (function()
        return cl.setting("frecency", "maxAge") == 10000 and cl.setting("popup", "limit") == 40
               and cl.setting("popup", "depth") == 3 and cl.setting("webview", "width") == 60
               and cl.settings.appearance.maxRows == 200 and type(cl.settings.tools) == "table"
               and type(cl.settings.prefixes) == "table"
      end)())

check("the chooser declares its own settings, read under its name and listed in Default Settings", (function()
        local styledRows, source = cl.setting("chooser", "styledRows")
        local text = cl.modules.workbench.defaultSettingsText()
        return styledRows == 40 and source == "default" and cl.appearance.screen == nil
               and text:find('"chooser.screen": "primary"', 1, true) ~= nil,
               tostring(styledRows) .. " " .. tostring(source)
      end)())

-- The reason the chooser presenter keeps rows on its own side: a
-- function in a row does not survive a choice table's trip through
-- Objective-C.
check("with more than one display the chooser opens on the main one, unless set to focused", (function()
        local saved = { all = hs.screen.allScreens, primary = hs.screen.primaryScreen,
                        main = hs.screen.mainScreen, settings = cl.userSettings }
        local function display(x, w)
          return { frame = function() return { x = x, y = 0, w = w, h = 1000 } end }
        end
        hs.screen.allScreens = function() return { display(0, 2000), display(2000, 1000) } end
        hs.screen.primaryScreen = function() return display(0, 2000) end
        hs.screen.mainScreen = function() return display(2000, 1000) end
        local p = cl.presenters.chooser.create({ onPick = function() end, onQuery = function() end })
        local shownAt
        hs.chooser.last.show = function(_, point) shownAt = point end

        cl.userSettings = {}
        p.show({ items = {} })
        local byDefault = shownAt
        cl.userSettings = { ["chooser.screen"] = "focused" }
        shownAt = "not shown"
        p.show({ items = {} })
        local onFocused = shownAt
        cl.userSettings = saved.settings
        hs.screen.allScreens = function() return { display(0, 2000) } end
        shownAt = "not shown"
        p.show({ items = {} })
        local oneDisplay = shownAt

        hs.screen.allScreens, hs.screen.primaryScreen, hs.screen.mainScreen =
          saved.all, saved.primary, saved.main
        return type(byDefault) == "table" and byDefault.x == 820 and byDefault.y == 200
               and onFocused == nil and oneDisplay == nil,
               ("%s / %s / %s"):format(type(byDefault) == "table" and (byDefault.x .. "," .. byDefault.y)
                 or tostring(byDefault), tostring(onFocused), tostring(oneDisplay))
      end)())

check("a chooser pick comes back as the row, functions intact", (function()
        local picked
        local p = cl.presenters.chooser.create({
          onPick = function(_, item) picked = item end,
          onQuery = function() end })
        local fn = function() end
        p.setItems({ { label = "a" }, { label = "b", fn = fn } })
        hs.chooser.last.complete({ id = 2 })
        return picked ~= nil and picked.fn == fn
      end)())

-- A text field that takes focus selects its contents, so a prefix carried
-- into a new picker would be overwritten by the next keystroke.
check("a picker opened with text moves the caret past it, one opened empty does not",
      (function()
        local strokes, real = {}, hs.eventtap.keyStroke
        hs.eventtap.keyStroke = function(_, key) strokes[#strokes + 1] = key end
        local p = cl.presenters.chooser.create({ onPick = function() end, onQuery = function() end })
        p.show({ placeholder = "x", items = {}, query = "recent " })
        local withText = #strokes
        p.show({ placeholder = "x", items = {}, query = "" })
        hs.eventtap.keyStroke = real
        return withText == 1 and strokes[1] == "right" and #strokes == 1,
               table.concat(strokes, " ")
      end)())

-- Styled rows: what matched in bold, the rest plain, a dimmer subtitle.
local function styledChoices(list, query, settings)
  local saved, mine = cl.userSettings, {}
  for k, v in pairs(saved or {}) do mine[k] = v end
  for k, v in pairs(settings or {}) do mine["chooser." .. k] = v end
  cl.userSettings = mine
  local p = cl.presenters.chooser.create({ onPick = function() end, onQuery = function() end })
  local captured
  hs.chooser.last.choices = function(_, choices) captured = choices end
  p.setItems(list, query)
  cl.userSettings = saved
  return captured
end

local function pieces(value)
  if type(value) ~= "table" or not value.pieces then return nil end
  local out = {}
  for _, piece in ipairs(value.pieces) do
    out[#out + 1] = piece.text .. (piece.attrs.font.name == "SystemBold" and "*" or "")
  end
  return table.concat(out, "|")
end

check("a row's title is styled, what the query matched in bold", (function()
        local c = styledChoices({ { label = "Lock screen", description = "Global" } }, "lock")
        local subtitle = c and c[1].subText
        return c and pieces(c[1].text) == "Lock*| screen"
               and subtitle and subtitle.pieces and subtitle.pieces[1].attrs.font.size == 12,
               c and pieces(c[1].text)
      end)())

check("a fuzzy match highlights the characters in order", (function()
        local c = styledChoices({ { label = "Open in VS Code" } }, "ovc")
        return c and pieces(c[1].text) == "O*|pen in |V*|S |C*|ode", c and pieces(c[1].text)
      end)())

check("the query as one run is preferred to scattered characters", (function()
        local c = styledChoices({ { label = "Load clock" } }, "lock")
        return c and pieces(c[1].text) == "Load c|lock*", c and pieces(c[1].text)
      end)())

check("a query only partly found highlights nothing", (function()
        local c = styledChoices({ { label = "Safari" } }, "sfz")
        return c and pieces(c[1].text) == "Safari", c and pieces(c[1].text)
      end)())

check("a row that is not enabled is drawn faded, title and subtitle", (function()
        local c = styledChoices({ { label = "Nope", description = "Unavailable", enabled = false },
                                  { label = "Yes", description = "Fine" } }, "")
        local function alpha(value)
          return value and value.pieces and value.pieces[1].attrs.color.alpha
        end
        local faded, normal = alpha(c and c[1].text), alpha(c and c[2].text)
        local fadedSub, normalSub = alpha(c and c[1].subText), alpha(c and c[2].subText)
        return faded and normal and fadedSub and normalSub
               and faded < normal and fadedSub < normalSub,
               ("%s/%s  %s/%s"):format(tostring(faded), tostring(normal), tostring(fadedSub), tostring(normalSub))
      end)())

check("with nothing typed, or no match, the title is styled but nothing is bold", (function()
        local empty = styledChoices({ { label = "Safari" } }, "")
        local none = styledChoices({ { label = "Safari" } }, "zzz")
        return pieces(empty[1].text) == "Safari" and pieces(none[1].text) == "Safari",
               pieces(empty[1].text) .. " / " .. pieces(none[1].text)
      end)())

check("only the first styledRows rows are styled, and styled = false styles none",
      (function()
        local rows = { { label = "one" }, { label = "two" } }
        local limited = styledChoices(rows, "", { styledRows = 1 })
        local off = styledChoices(rows, "", { styled = false })
        return type(limited[1].text) == "table" and limited[2].text == "two"
               and off[1].text == "one" and off[2].text == "two"
      end)())

check("the chooser highlights the row it is asked to, within its rows", (function()
        local p = cl.presenters.chooser.create({ onPick = noop, onQuery = noop })
        local c = hs.chooser.last
        local selected
        c.selectedRow = function(_, row) selected = row; return c end
        p.setItems({ { label = "a" }, { label = "b" } })
        p.select(2)
        local two = selected
        selected = nil
        p.select(5)
        return two == 2 and selected == nil, tostring(two) .. " / " .. tostring(selected)
      end)())

check("a hide the kernel asks for is not a dismissal", (function()
        local reports = 0
        local p = cl.presenters.chooser.create({
          onPick = function() reports = reports + 1 end,
          onQuery = function() end })
        local c = hs.chooser.last
        c.hide = function() c.complete(nil); return c end
        p.hide()
        return reports == 0
      end)())

-- Hammerspoon's side of focus: its global callback told a chooser opens or
-- closes, and the app in front and its window as the machine reports them.
local function focusMachine()
  local m = { focused = {}, front = "com.apple.Notes", buttons = {} }
  local saved = { front = hs.application.frontmostApplication, window = hs.window.focusedWindow,
                  buttons = hs.eventtap.checkMouseButtons }
  hs.application.frontmostApplication = function()
    local id = m.front
    return { bundleID = function() return id end,
             activate = function() m.focused[#m.focused + 1] = "app " .. id end }
  end
  hs.window.focusedWindow = function()
    local id = m.front
    return { focus = function() m.focused[#m.focused + 1] = id end }
  end
  hs.eventtap.checkMouseButtons = function() return m.buttons end
  function m.restore()
    hs.application.frontmostApplication, hs.window.focusedWindow = saved.front, saved.window
    hs.eventtap.checkMouseButtons = saved.buttons
  end
  function m.chooser()
    local p = cl.presenters.chooser.create({ onPick = noop, onQuery = noop })
    return p, hs.chooser.last
  end
  function m.event(c, name) hs.chooser.globalCallback(c, name) end
  return m
end

check("focus goes back to the window you were in once, as the layer closes, and not as its pickers switch",
      (function()
        local m = focusMachine()
        local first, firstChooser = m.chooser()
        local second, secondChooser = m.chooser()
        m.event(firstChooser, "willOpen")
        m.front = "org.hammerspoon.Hammerspoon"
        first.hide()
        m.event(firstChooser, "didClose")
        m.event(secondChooser, "willOpen")
        local switched = #m.focused
        second.hide(true)
        m.event(secondChooser, "didClose")
        second.hide(true)
        m.restore()
        local focused = table.concat(m.focused, " ")
        return switched == 0 and focused == "com.apple.Notes", switched .. " while switching / " .. focused
      end)())

check("escape hands focus back as the layer closes; a click on another app leaves it where it went", (function()
        local m = focusMachine()
        local p, c = m.chooser()
        m.event(c, "willOpen")
        c.complete(nil)
        p.hide(true)
        m.front = "com.apple.mail"
        m.event(c, "willOpen")
        m.buttons = { true }
        c.complete(nil)
        p.hide(true)
        m.restore()
        local focused = table.concat(m.focused, " ")
        return focused == "com.apple.Notes", focused
      end)())

check("the layer's choosers answer to its own global callback, and any other chooser to the one there before, "
        .. "however often the presenter is loaded", (function()
        local heard = {}
        local shared = hs.chooser._commandLayer
        local ours = shared and shared.callback
        hs.chooser.globalCallback = function(which, event)
          heard[#heard + 1] = tostring(which.name) .. " " .. event
        end
        cl.presenters.chooser.create({ onPick = noop, onQuery = noop })
        local first = hs.chooser.last
        local factory = assert(loadfile(T.dir .. "presenters/chooser.lua"))
        factory()(cl.pluginAPI("presenter", "chooser")).create({ onPick = noop, onQuery = noop })
        local again = hs.chooser.last
        local installed = hs.chooser.globalCallback == ours
        hs.chooser.globalCallback({ name = "another spoon's" }, "willOpen")
        hs.chooser.globalCallback(first, "didClose")
        hs.chooser.globalCallback(again, "didClose")
        hs.chooser._commandLayer.previous = nil
        local result = table.concat(heard, ", ")
        return ours ~= nil and installed and result == "another spoon's willOpen", result
      end)())

-- Escape and a click on another app arrive as the same empty choice; which
-- it was is read from the machine at that instant. hs.chooser takes the
-- keyboard without activating Hammerspoon, so the app in front through all
-- of this is the app the picker opened over: what was measured on the real
-- one, and why "not Hammerspoon" could not mean the layer was left.
local function chooserDismissal(buttons, frontID, openedOver)
  openedOver = openedOver or "com.apple.Notes"
  local got, reason = false, nil
  local realButtons = hs.eventtap.checkMouseButtons
  local realFront = hs.application.frontmostApplication
  local front = openedOver
  hs.application.frontmostApplication = function()
    local id = front
    return { bundleID = function() return id end }
  end
  cl.presenters.chooser.create({
    onPick = function(_, _, why) got, reason = true, why end,
    onQuery = function() end })
  local c = hs.chooser.last
  -- Opening is where the app to come back to is remembered.
  hs.chooser.globalCallback(c, "willOpen")
  front = frontID
  hs.eventtap.checkMouseButtons = function() return buttons end
  c.complete(nil)
  hs.eventtap.checkMouseButtons = realButtons
  hs.application.frontmostApplication = realFront
  if not got then return "not reported" end
  return reason
end

check("a chooser dismissed by escape, with the app it opened over still in front, is not reported as left",
      chooserDismissal({}, "com.apple.Notes") == nil,
      tostring(chooserDismissal({}, "com.apple.Notes")))
check("a chooser dismissed by a click elsewhere is reported as left",
      chooserDismissal({ true, left = true }, "com.apple.Notes") == "away")
check("a chooser dismissed as another app came to the front is reported as left",
      chooserDismissal({}, "com.apple.finder") == "away")

check("a row picked through another presenter still runs", (function()
        local ran = false
        T.picker("test-presented", { { label = "run", run = function() ran = true end } })
        cl.open("test-presented")
        cl.viewNamed("test-presented").picker.accept()
        return ran
      end)())

-- Only the picker on screen may report. One the layer has moved past,
-- reporting a dismissal, would otherwise close whatever replaced it.
check("a picker that has been left cannot close the layer", (function()
        local left = openRecorded("palette")
        openRecorded("recent")
        local before = layerModal.exits
        left.dismiss()
        return layerModal.exits == before
      end)())

-- The kernel's side of that promise, which no presenter can keep for
-- it: one that does report its own hide, as hs.chooser does, still
-- cannot close the layer while the kernel switches away from it.
check("switching away from a presenter that reports its hide stays open",
      (function()
        cl.presenter("noisy", { create = function(opts)
          local p = {}
          function p.show() end
          function p.setItems() end
          function p.hide() opts.onPick(p, nil) end
          return p
        end })
        T.picker("test-noisy", { { label = "x" } }, { presenter = "noisy" })
        cl.open("test-noisy")
        local before = layerModal.exits
        openRecorded("palette")
        return layerModal.exits == before
      end)())

-- The picker on screen changes on every switch. Anything that steers it
-- has to ask which one it is at the time, not remember the first.
check("a control steers the picker on screen, not the one it replaced",
      (function()
        local earlier = openRecorded("palette")
        local current = openRecorded("recent")
        local moveNext
        for _, control in ipairs(cl.controls) do
          if control.name == "quickOpen.selectNext" then moveNext = control.fn end
        end
        moveNext()
        return current.row == 2 and earlier.row == 1,
               ("current %s, earlier %s"):format(tostring(current.row),
                                                 tostring(earlier.row))
      end)())

check("closing the layer hides the picker on screen", (function()
        local picker = openRecorded("palette")
        picker.hidden = nil
        layerModal:exited()
        return picker.hidden == true
      end)())

check("a picker hidden as the layer closes is told so, and one hidden for another picker is not", (function()
        local earlier = openRecorded("palette")
        local current = openRecorded("recent")
        local switched = earlier.hidden == true and earlier.closing == false
        layerModal:exited()
        return switched and current.closing == true,
               tostring(earlier.closing) .. " / " .. tostring(current.closing)
      end)())

check("an unknown presenter falls back to the default", (function()
        T.picker("test-typo", {}, { presenter = "no-such-presenter" })
        cl.open("test-typo")
        return cl.viewNamed("test-typo").picker ~= nil
      end)())

group("row cap")
check("a picker is handed at most maxRows rows, open or typed", (function()
        local many = {}
        for i = 1, 500 do many[i] = { label = "row " .. i } end
        T.picker("test-many", many)
        cl.open("test-many")
        local p = cl.viewNamed("test-many").picker
        local opened = #(p.shown or {})
        local saved = cl.matchers
        cl.matchers = substringOnly()
        p.type("row")
        cl.matchers = saved
        local typed = #(p.shown or {})
        local limit = cl.appearance.maxRows
        return opened == limit and typed == limit,
               ("%d opened, %d typed, limit %d"):format(opened, typed, limit)
      end)())

group("popup presenter")
check("it is loaded from presenters/", cl.presenters.popup ~= nil)

-- A presenter drawing a tree at once needs the rows behind an open row
-- before anyone picks it.
check("a presenter can expand an open row without opening it", (function()
        local undo = T.picker("test-expand", { { label = "leaf" } }, { title = "Expand", parent = "root" })
        local root = openRecorded("root")
        local _, row = rowOpening(root, "test-expand")
        local rows = row and root.opts.expand(row)
        undo()
        if not row then return false, "no row opening the view" end
        return rows ~= nil and #rows > 0 and root.opts.expand({ label = "x" }) == nil
      end)())

-- Stubs just for these checks, restored afterwards.
local saved = { menubar = hs.menubar, doAfter = hs.timer.doAfter,
                mainScreen = hs.screen.mainScreen }
local queue = {}
hs.timer.doAfter = function(_, fn) queue[#queue + 1] = fn; return { stop = noop } end
local function drain()
  while #queue > 0 do table.remove(queue, 1)() end
end
hs.screen.mainScreen = function()
  return { frame = function() return { x = 0, y = 0, w = 1000, h = 800 } end }
end

local popped
hs.menubar = { new = function()
  local m = {}
  function m:setMenu(t) m.menu = t; return m end
  function m:popupMenu() popped = m; if m.onPopup then m.onPopup(m) end; return m end
  return m
end }

local function popupWith(onPick)
  popped = nil
  return cl.presenters.popup.create({
    onPick = onPick, onQuery = noop,
    expand = function(item) return item.submenu and { { label = "leaf" } } or nil end,
  })
end

check("popup: rows become entries, open rows become submenus", (function()
        local p = popupWith(noop)
        p.show({ items = { { label = "a" }, { label = "Sub", submenu = "test-sub" } } })
        drain()
        local m = popped and popped.menu
        return m and #m == 2 and m[2].menu and m[2].menu[1].title == "leaf"
      end)())

check("popup: a row that is not enabled is a disabled menu item", (function()
        local p = popupWith(noop)
        p.show({ items = { { label = "off", enabled = false }, { label = "on" } } })
        drain()
        local m = popped and popped.menu
        return m and m[1].disabled == true and not m[2].disabled
      end)())

check("popup: a pick reports the row itself and no dismissal", (function()
        local reports = {}
        local fn = function() end
        local p = popupWith(function(_, item) reports[#reports + 1] = item or "dismissed" end)
        p.show({ items = { { label = "a", fn = fn } } })
        -- The menu is chosen from while it is open.
        local real = hs.menubar.new
        hs.menubar.new = function()
          local m = real()
          m.onPopup = function(self) self.menu[1].fn() end
          return m
        end
        drain()
        hs.menubar.new = real
        return #reports == 1 and type(reports[1]) == "table" and reports[1].fn == fn,
               tostring(#reports)
      end)())

check("popup: closing it without a pick is a dismissal", (function()
        local reports = {}
        local p = popupWith(function(_, item) reports[#reports + 1] = item or "dismissed" end)
        p.show({ items = { { label = "a" } } })
        drain()
        return #reports == 1 and reports[1] == "dismissed"
      end)())

check("popup: a hide before it opens stops it opening", (function()
        local p = popupWith(noop)
        p.show({ items = { { label = "a" } } })
        p.hide()
        drain()
        return popped == nil
      end)())

check("popup: a long list is cut, and says so", (function()
        local rows = {}
        for i = 1, 50 do rows[i] = { label = "row " .. i } end
        local p = popupWith(noop)
        p.show({ items = rows })
        drain()
        local m = popped and popped.menu
        return m and #m == 41 and m[41].disabled == true, m and tostring(#m)
      end)())

hs.menubar, hs.timer.doAfter = saved.menubar, saved.doAfter
hs.screen.mainScreen = saved.mainScreen
