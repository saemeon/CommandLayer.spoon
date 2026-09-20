-- What a view opens on with nothing typed: recently used rows, sections,
-- and the separators that label them.

local M = ...

local session = M.session
local rankItems = M.rankItems

-- The `limit` rows picked most lately go first, the latest first, marked, as
-- VS Code's palette keeps its "recently used": by when, not how often, so
-- the command you just ran is the first row. Copies, so the row in the view
-- is unchanged.
local function recentlyUsedFirst(rows, limit)
  local used, when, position = {}, {}, {}
  for i, row in ipairs(rows) do
    local last = M.lastUsed(row)
    if last > 0 then
      used[#used + 1] = row
      when[row], position[row] = last, i
    end
  end
  if #used == 0 then return rows end
  table.sort(used, function(a, b)
    if when[a] ~= when[b] then return when[a] > when[b] end
    return position[a] < position[b]
  end)

  local out, placed = {}, {}
  for i = 1, math.min(limit, #used) do
    local row = used[i]
    placed[row] = true
    local marked = {}
    for k, v in pairs(row) do marked[k] = v end
    marked.description = "Recently used" .. (row.description and ("  --  " .. row.description) or "")
    M.normaliseRow(marked)
    out[#out + 1] = marked
  end
  for _, row in ipairs(rows) do
    if not placed[row] then out[#out + 1] = row end
  end
  return out
end

M.recentlyUsedFirst = recentlyUsedFirst

-- A separator row -- VS Code's QuickPickItemKind.Separator, written
-- `{ kind = "separator", label = "Tabs" }` -- labels the rows after it.
-- The chooser has no header rows, and one drawn as a row could be picked,
-- so the label goes into the subtitle of the first row after it and the
-- separator itself is not shown. Copies, so the row in the view is unchanged.
local function withSeparators(items)
  local out, label = {}, nil
  for _, item in ipairs(items or {}) do
    if item.kind == "separator" then
      label = item.label
    else
      if label then
        local copy = {}
        for k, v in pairs(item) do copy[k] = v end
        copy.description = label .. (item.description and ("  --  " .. item.description) or "")
        M.normaliseRow(copy)
        item, label = copy, nil
      end
      out[#out + 1] = item
    end
  end
  return out
end

M.withSeparators = withSeparators

local sectionsFirst

-- Views whose sections are being worked out right now. Two views whose
-- sections name each other would otherwise build each other forever, and
-- the picker would hang; the second visit gets no rows instead.
local building = {}

local function whileBuilding(name, fn)
  if name == nil or building[name] then return fn() end
  building[name] = true
  local ok, result = pcall(fn)
  building[name] = nil
  if not ok then error(result, 0) end
  return result
end

-- The rows another view opens on, with nothing typed: its rows, ranked,
-- with its own sections -- what it would show first.
local function topRowsOf(name, ctx, limit, excluded)
  if building[name] or not (M.viewNamed(name) and session.rowsOfView) then return {} end
  return whileBuilding(name, function()
    local spec = M.viewNamed(name)
    local rows = session.rowsOfView(name, ctx)
    -- An empty query is ranked at once: matchers decline it, so only the
    -- rankers run. One that answered later anyway would find the section
    -- already built from the rows as gathered.
    local ordered
    rankItems(rows, "", function(out) ordered = out end)
    ordered = ordered or rows
    if type(spec.sections) == "table" then
      ordered = sectionsFirst(rows, ordered, spec.sections, ctx, name)
    end
    local out = {}
    for _, row in ipairs(ordered) do
      if row.kind ~= "separator" and not excluded[row.source] then
        out[#out + 1] = row
        if #out >= limit then break end
      end
    end
    return out
  end)
end

-- The same thing twice -- a tab in the context section and in the root's
-- own rows -- is one row, where the section put it.
local function sameThing(row)
  return M.subjectKey and M.subjectKey(row) or nil
end

-- With nothing typed, a view's sections go first, each under a separator:
-- up to `limit` rows from an extension (`from`), in the order it gave them
-- -- for `recent` that is recency, which ranking would reorder by pick
-- count -- or the first rows another view opens on (`view`), so the root
-- can lead with what the context picker would. `exclude` names extensions
-- whose rows a section leaves out, before its limit is taken. Every other
-- row follows as ranked.
-- `shown`, when given, is filled with the rows the sections placed.
sectionsFirst = function(gathered, ranked, sections, ctx, viewName, shown)
  return whileBuilding(viewName, function()
  local placed, seen, out = {}, {}, {}
  for _, section in ipairs(sections) do
    local limit = section.limit or 3
    local excluded = {}
    for _, name in ipairs(type(section.exclude) == "table" and section.exclude or {}) do
      excluded[name] = true
    end
    local candidates, label
    if section.view then
      local other = M.viewNamed(section.view)
      label = section.title or (other and other.title) or M.displayNameOf(section.view)
      candidates = section.view ~= viewName and topRowsOf(section.view, ctx, limit, excluded) or {}
    else
      label = section.title or M.displayNameOf(section.from)
      candidates = gathered
    end
    local taken = 0
    for _, row in ipairs(candidates) do
      if taken >= limit then break end
      local key = sameThing(row)
      if (section.view or row.source == section.from) and not excluded[row.source]
         and not placed[row]
         and not (key and seen[key]) then
        placed[row] = true
        if key then seen[key] = true end
        if taken == 0 then out[#out + 1] = { kind = "separator", label = label } end
        out[#out + 1] = row
        if shown then shown[#shown + 1] = row end
        taken = taken + 1
      end
    end
  end
  for _, row in ipairs(ranked) do
    local key = sameThing(row)
    if not placed[row] and not (key and seen[key]) then out[#out + 1] = row end
  end
  return out
  end)
end

M.sectionsFirst = sectionsFirst
