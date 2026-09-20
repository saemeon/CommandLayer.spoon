-- hs.menubar:popupMenu: a native menu near the top of the screen.
--
-- No search field -- the menu's own type-select jumps to a title instead
-- -- but every level of a menu tree is a real submenu, so a tree reads
-- the way a Mac menu does. Best for short, declared menus rather than a
-- root holding every app.

return function(cl)
  local function setting(key, default)
    local value = cl.setting("popup", key)
    if value == nil then return default end
    return value
  end

  local function create(opts)
    local picker = {}
    local items = {}

    -- Held for the life of the picker: a menubar item that is only a local
    -- can be collected while its menu is on screen.
    local menu

    -- One per show. A hide, or a newer show, makes an older popup that has
    -- not opened yet -- and its dismissal -- stale.
    local token = 0

    local function entries(rows, depth, onChosen)
      local out = {}
      for i, item in ipairs(rows) do
        local limit = setting("limit", 40)
        if i > limit then
          out[#out + 1] = { title = ("%d more -- search for them"):format(#rows - limit),
                            disabled = true }
          break
        end

        local entry = {
          title    = tostring(item.label or ""),
          tooltip  = item.detail or item.description,
          fn       = function() onChosen(item) end,
          -- A menu can disable an item outright, which is what greyed out means.
          disabled = item.enabled == false or nil,
        }
        -- App icons arrive at full size, and a menu does not scale them.
        if item.iconPath then entry.image = item.iconPath:copy():size({ w = 16, h = 16 }) end

        if item.submenu and depth < setting("depth", 3) and opts.expand then
          local below = opts.expand(item)
          if below and #below > 0 then entry.menu = entries(below, depth + 1, onChosen) end
        end

        out[#out + 1] = entry
      end
      return out
    end

    local function popup(mine)
      if mine ~= token then return end

      local chosen = false
      local function onChosen(item)
        chosen = true
        opts.onPick(picker, item)
      end

      menu = menu or hs.menubar.new(false)
      menu:setMenu(entries(items, 1, onChosen))

      local frame = hs.screen.mainScreen():frame()
      menu:popupMenu({ x = frame.x + frame.w / 2 - 150, y = frame.y + frame.h / 5 },
                     cl.appearance.dark)

      -- Whether a pick's callback runs before popupMenu returns is up to
      -- AppKit, so a dismissal waits a turn and counts only if nothing was
      -- chosen in the meantime.
      picker.dismissTimer = hs.timer.doAfter(0, function()
        picker.dismissTimer = nil
        if not chosen and mine == token then opts.onPick(picker, nil) end
      end)
    end

    function picker.show(state)
      items = state.items or {}
      token = token + 1
      local mine = token
      -- Deferred: popupMenu blocks until the menu closes, and show runs in
      -- the middle of the kernel switching pickers. A pick made while it
      -- blocked would re-enter the kernel before that switch finished.
      picker.openTimer = hs.timer.doAfter(0, function()
        picker.openTimer = nil
        popup(mine)
      end)
    end

    -- Rows that arrive after the menu has opened wait for the next one:
    -- an open menu cannot be changed.
    function picker.setItems(list)
      items = list or {}
    end

    -- An open menu cannot be closed from here either, and while it is open
    -- Lua is blocked anyway. What this can stop is one not yet opened.
    function picker.hide()
      token = token + 1
    end

    return picker
  end

  return {
    create = create,

    settings = {
      -- A menu is for choosing, not browsing; past the limit, the rest are
      -- what a search is for. Submenus are built before the menu opens, so
      -- depth bounds that work; a row deeper still opens its level.
      limit = { type = "integer", default = 40, description = "The most rows a menu shows" },
      depth = { type = "integer", default = 3,
                description = "How many levels of submenus are built before the menu opens" },
    },
  }
end
