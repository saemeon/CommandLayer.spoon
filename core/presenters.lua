-- The presenter registry: what draws a picker, and what every picker shares.

local M = ...

----------------------------------------------------------------------
-- PRESENTERS
----------------------------------------------------------------------

M.presenters = {}

-- What draws a view that does not name a presenter. A profile may name
-- another.
M.defaultPresenter = "chooser"

function M.presenter(name, spec)
  if type(name) == "string" and type(spec) == "table"
     and type(spec.create) == "function" then
    M.presenters[name] = spec
  end
  return M
end

-- A view naming a presenter that is not there still opens with the
-- default: a typo in a profile should cost a log line, not the picker.
-- A presenter is a file anyone can write, so creating one is guarded the
-- way gather guards an extension.
local function createPicker(name, opts)
  local wanted = name or M.defaultPresenter
  local presenter = M.presenters[wanted]

  if not presenter then
    M.log.w("no presenter '" .. tostring(wanted) .. "', using '"
          .. tostring(M.defaultPresenter) .. "'")
    presenter = M.presenters[M.defaultPresenter]
  end
  if not presenter then return nil end

  local ok, picker = pcall(presenter.create, opts)
  if not ok or type(picker) ~= "table" then
    M.log.e("presenter '" .. tostring(wanted)
          .. "' could not create a picker: " .. tostring(picker))
    return nil
  end
  return picker
end

M.createPicker = createPicker

----------------------------------------------------------------------
-- APPEARANCE
----------------------------------------------------------------------

-- What every picker shares, overridden by the profile. A presenter's own
-- options are its settings, as chooser.screen.
M.appearance = {
  dark    = true,

  -- Percentage of screen width, and visible rows.
  width   = 36,
  rows    = 12,

  -- The most rows a picker is handed. Everything is still matched and
  -- ranked; only drawing is capped, because a presenter may convert
  -- every row it gets, icon included, on each keystroke -- and a browser's
  -- tabs, bookmarks and history alone run to thousands.
  maxRows = 200,

  -- The cmd+k panel is a detail view of one row, so it reads better
  -- small.
  actionWidth = 24,
  actionRows  = 7,
}
