-- hs.chooser: Hammerspoon's native search panel, and the default.
--
-- A presenter draws a picker. It is handed rows and told when to show
-- and hide; it reports what was picked and what was typed. Everything
-- about which rows, in what order and what happens next is the kernel's.

return function(cl)

  local HAMMERSPOON = "org.hammerspoon.Hammerspoon"
  local titleText, subtitleText

  -- hs.chooser has one line under the title, where VS Code draws
  -- `description` beside the label and `detail` below it.
  local function secondLine(item)
    local parts = {}
    if item.description ~= nil and item.description ~= "" then parts[#parts + 1] = tostring(item.description) end
    if item.detail ~= nil and item.detail ~= "" then parts[#parts + 1] = tostring(item.detail) end
    return #parts > 0 and table.concat(parts, "  --  ") or nil
  end

  -- Read when drawing, so a changed setting shows on the next keystroke.
  local function setting(key)
    return (cl.setting("chooser", key))
  end

  -- The window in front as a picker opened over another app. A picker opening
  -- while Hammerspoon is in front is a switch, and keeps what the first found.
  -- It also says which app a dismissal has to still be in to be escape.
  local returnTo

  -- Escape and a click on another app both reach the completion callback as
  -- no choice. hs.chooser takes the keyboard without activating Hammerspoon,
  -- so the app in front is the one you were in either way -- reading "not
  -- Hammerspoon" as leaving made escape close the whole layer. What tells
  -- them apart is whether the app in front is still the one this picker
  -- opened over, asked at that instant: a mouse button still down is the
  -- click that took focus, and any other app in front means focus has gone.
  local function dismissalReason()
    for _, down in pairs(hs.eventtap.checkMouseButtons() or {}) do
      if down == true then return "away" end
    end
    local front = hs.application.frontmostApplication()
    local id = front and front:bundleID()
    local opened = returnTo and returnTo.app and returnTo.app:bundleID()
    if id and opened and id ~= HAMMERSPOON and id ~= opened then return "away" end
    return nil
  end

  ----------------------------------------------------------------------
  -- FOCUS
  --
  -- Hammerspoon's default chooser callback focuses, on every hide, the
  -- window in front when that chooser opened. Switching pickers hides one
  -- and shows another, which would hand focus to the app you were in
  -- between the two, and the picker shown could lose its key window to it.
  -- The layer's choosers hand focus back once, as the layer closes; every
  -- other chooser still reaches the callback that was there before.
  ----------------------------------------------------------------------

  local function remember()
    local front = hs.application.frontmostApplication()
    if returnTo and not (front and front:bundleID() ~= HAMMERSPOON) then return end
    returnTo = { app = front, window = hs.window.focusedWindow() }
  end

  -- The window while it can still be focused, else its app.
  local function giveFocusBack()
    local target = returnTo
    returnTo = nil
    if not target then return end
    local win, app = target.window, target.app
    if win and pcall(function() win:focus() end) then return end
    if app then pcall(function() app:activate() end) end
  end

  -- Kept on hs.chooser and made once, so a layer set up again keeps its own
  -- callback rather than wrapping it, and passes other choosers to the
  -- callback that was there before the layer's.
  -- hs.chooser's globalCallback is Hammerspoon's to be set.
  -- luacheck: push ignore 122
  local function ownEvents()
    local chooserModule = hs.chooser
    local shared = chooserModule._commandLayer
    if not shared then
      shared = { choosers = setmetatable({}, { __mode = "k" }), previous = chooserModule.globalCallback }
      -- Compared with ==, as the default callback compares: the object handed
      -- to it need not be the one hs.chooser.new returned.
      shared.callback = function(which, event)
        for c, handle in pairs(shared.choosers) do
          if c == which then return handle(event) end
        end
        if shared.previous then return shared.previous(which, event) end
      end
      chooserModule._commandLayer = shared
    elseif chooserModule.globalCallback ~= shared.callback then
      shared.previous = chooserModule.globalCallback
    end
    chooserModule.globalCallback = shared.callback
    return shared
  end
  -- luacheck: pop

  ----------------------------------------------------------------------
  -- STYLED ROWS
  --
  -- hs.chooser's own fonts are fixed, but a row's text may be an
  -- hs.styledtext: a regular title with what matched the query in bold and
  -- tinted, and a smaller, dimmer subtitle. Row height is fixed by the
  -- chooser, so the sizes stay close to its own.
  ----------------------------------------------------------------------

  local function colour(explicit, dark, light)
    if explicit then return explicit end
    return cl.appearance.dark and dark or light
  end

  local function fonts()
    local system = hs.styledtext.defaultFonts.system
    local bold = hs.styledtext.defaultFonts.boldSystem
    return { name = system.name, size = setting("titleSize") or 17 },
           { name = bold.name,   size = setting("titleSize") or 17 },
           { name = system.name, size = setting("subtitleSize") or 12 }
  end

  -- UTF-8 characters rather than bytes, so a highlight never splits one.
  local function characters(text)
    local out = {}
    for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      out[#out + 1] = ch
    end
    return out
  end

  -- Which characters of `text` the query matched: the query as one run where
  -- it appears, otherwise its characters in order, as a fuzzy matcher finds
  -- them. Spaces in the query separate terms and match nothing themselves.
  local function matchedPositions(chars, query)
    local matched = {}
    local wanted = {}
    for _, ch in ipairs(characters(query or "")) do
      if ch ~= " " then wanted[#wanted + 1] = ch:lower() end
    end
    if #wanted == 0 then return matched end

    local lower = {}
    for i, ch in ipairs(chars) do lower[i] = ch:lower() end

    for start = 1, #lower - #wanted + 1 do
      local run = true
      for k = 1, #wanted do
        if lower[start + k - 1] ~= wanted[k] then run = false; break end
      end
      if run then
        for k = start, start + #wanted - 1 do matched[k] = true end
        return matched
      end
    end

    local k = 1
    for i, ch in ipairs(lower) do
      if k <= #wanted and ch == wanted[k] then
        matched[i] = true
        k = k + 1
      end
    end
    if k <= #wanted then return {} end
    return matched
  end

  -- A row that is not enabled keeps its colours, at a fraction of them.
  local function faded(color, dimmed)
    if not dimmed then return color end
    local out = {}
    for k, v in pairs(color) do out[k] = v end
    out.alpha = (out.alpha or 1) * 0.4
    return out
  end

  titleText = function(text, query, dimmed)
    if type(text) ~= "string" then return text end
    local regular, bold = fonts()
    local plain = { font = regular,
                    color = faded(colour(setting("fg"), { white = 1, alpha = 0.95 },
                                               { white = 0, alpha = 0.9 }), dimmed) }
    local hit = { font = bold,
                  color = faded(colour(setting("match"), { red = 0.45, green = 0.72, blue = 1, alpha = 1 },
                                                { red = 0.0, green = 0.36, blue = 0.85, alpha = 1 }),
                                dimmed) }

    local chars = characters(text)
    local matched = matchedPositions(chars, query)

    -- Consecutive characters sharing a style become one piece, so a title
    -- is a handful of objects joined rather than one per character.
    local result, piece, pieceMatched
    local function flush()
      if piece and piece ~= "" then
        local part = hs.styledtext.new(piece, pieceMatched and hit or plain)
        result = result and (result .. part) or part
      end
    end
    for i, ch in ipairs(chars) do
      local m = matched[i] == true
      if piece and m == pieceMatched then
        piece = piece .. ch
      else
        flush()
        piece, pieceMatched = ch, m
      end
    end
    flush()
    return result or text
  end

  -- Subtitles repeat -- "App", "Window -- Safari" -- and depend on nothing
  -- typed, so they are made once.
  local subtitleCache, subtitleCount = {}, 0

  subtitleText = function(text, dimmed)
    if type(text) ~= "string" or text == "" then return text end
    local key = (dimmed and "\0faded\0" or "") .. text
    local hit = subtitleCache[key]
    if hit then return hit end
    if subtitleCount > 500 then subtitleCache, subtitleCount = {}, 0 end
    local _, _, small = fonts()
    hit = hs.styledtext.new(text, { font = small,
      color = faded(colour(setting("subText"), { white = 1, alpha = 0.55 },
                                      { white = 0, alpha = 0.5 }), dimmed) })
    subtitleCache[key], subtitleCount = hit, subtitleCount + 1
    return hit
  end

  local function create(opts)
    local picker = { search = true }

    -- Only basic Lua types survive hs.chooser's trip through Objective-C:
    -- a function stored in a choice is dropped, which would silently break
    -- every row that runs Lua. So each choice carries an integer id and the
    -- real item stays here. The icon is the exception -- the chooser handles
    -- an image specially, so it goes straight into the choice.
    local items = {}

    -- hs.chooser reports its own hide as a dismissal. A hide the kernel
    -- asked for -- switching pickers, closing the layer -- is not one.
    local hiding = false

    local chooser = hs.chooser.new(function(choice)
      if hiding then return end
      local item = choice and choice.id and items[choice.id] or nil
      local reason = not item and dismissalReason() or nil
      -- Focus went where you clicked; handing it back would take it away again.
      if reason == "away" then returnTo = nil end
      opts.onPick(picker, item, reason)
    end)
    ownEvents().choosers[chooser] = function(event)
      if event == "willOpen" then remember() end
    end

    -- All hs.chooser exposes: there is no border, shadow or corner radius
    -- to set, the panel being AppKit's.
    local a = cl.appearance
    chooser:bgDark(a.dark)
    if setting("fg")      then chooser:fgColor(setting("fg"))           end
    if setting("subText") then chooser:subTextColor(setting("subText")) end
    chooser:width(opts.width or a.width)
    chooser:rows(opts.rows or a.rows)

    -- Setting this is also what stops hs.chooser filtering on its own:
    -- its source hands the whole job to Lua once a callback is set, and
    -- the kernel expects a presenter to show exactly the rows it is given.
    chooser:queryChangedCallback(function(query)
      opts.onQuery(picker, query)
    end)

    -- New ids with every push: the chooser only remembers its latest
    -- choices, so the previous ids are dead the moment this runs.
    function picker.setItems(list, query)
      items = list or {}
      local styled = setting("styled") ~= false and hs.styledtext ~= nil
      local limit = setting("styledRows") or 40
      local choices = {}
      for i, item in ipairs(items) do
        -- Only the rows near the top are styled: every styled string is an
        -- Objective-C object made again on each keystroke, and rows far
        -- down the list are rarely scrolled to.
        local fancy = styled and i <= limit
        local dimmed = item.enabled == false
        local second = secondLine(item)
        choices[i] = {
          text    = fancy and titleText(item.label, query, dimmed) or item.label,
          subText = fancy and subtitleText(second, dimmed) or second,
          image   = item.iconPath,
          id      = i,
        }
      end
      chooser:choices(choices)
    end

    -- hs.chooser centres itself on the display with the focused window. On
    -- "primary" it is placed on the main display instead, once there is more
    -- than one; its width is a share of the focused display's, which is what
    -- hs.chooser measures it against.
    local function topLeft()
      if setting("screen") == "focused" then return nil end
      local screens = hs.screen.allScreens and hs.screen.allScreens() or {}
      if #screens < 2 or not hs.screen.primaryScreen then return nil end
      local primary = hs.screen.primaryScreen()
      if not primary then return nil end
      local frame = primary:frame()
      local focused = hs.screen.mainScreen and hs.screen.mainScreen()
      local basis = focused and focused:frame().w or frame.w
      local w = basis * (opts.width or a.width or 36) / 100
      return { x = frame.x + (frame.w - w) / 2, y = frame.y + frame.h * 0.2 }
    end

    function picker.show(state)
      chooser:placeholderText(state.placeholder or "")
      picker.setItems(state.items)
      chooser:query(state.query or "")
      local point = topLeft()
      if point then chooser:show(point) else chooser:show() end
      -- A text field that takes focus selects what is in it, so a prefix
      -- carried into this picker would be replaced by the next keystroke.
      -- Moving the caret to the end keeps it, and there is no API for the
      -- selection itself.
      if state.query and state.query ~= "" then
        hs.eventtap.keyStroke({}, "right", 0)
      end
    end

    function picker.hide(closing)
      hiding = true
      chooser:hide()
      hiding = false
      if closing then giveFocusBack() end
    end

    function picker.selected()
      local row = chooser:selectedRowContents()
      return row and row.id and items[row.id] or nil
    end

    -- selectedRow is a setter as well as a getter, which is the only way
    -- in: hs.chooser owns its key handling and exposes no hook into it.
    -- The count is #items because the chooser will not report one.
    function picker.move(delta)
      local count = #items
      if count == 0 then return end

      local row = (chooser:selectedRow() or 1) + delta
      if row < 1     then row = count end   -- wraps, the way quick open does
      if row > count then row = 1     end

      chooser:selectedRow(row)
    end

    function picker.select(row)
      if row >= 1 and row <= #items then chooser:selectedRow(row) end
    end

    -- select() fires the completion callback for the highlighted row,
    -- which is the same path return takes.
    function picker.accept()
      chooser:select()
    end

    return picker
  end

  return {
    create = create,

    settings = {
      screen = { type = "string", default = "primary", description = "Open on display",
                 enum = { "primary", "focused" },
                 enumDescriptions = { "The main display, with the menu bar",
                                      "The display with the focused window" } },
      styled = { type = "boolean", default = true,
                 description = "Highlight what you typed, with a smaller subtitle" },
      styledRows   = { type = "integer", default = 40,
                       description = "How many rows from the top are styled; each is made again per keystroke" },
      titleSize    = { type = "number", default = 17, description = "Title size, in points" },
      subtitleSize = { type = "number", default = 12, description = "Subtitle size, in points" },
      fg      = { type = "object", description = "Title colour, as hs.drawing.color takes one" },
      subText = { type = "object", description = "Subtitle colour" },
      match   = { type = "object", description = "Colour of what you typed" },
    },
  }
end
