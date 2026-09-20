-- The declared views, as data: registering and finding one, and prefixes.

local M = ...

----------------------------------------------------------------------
-- VIEWS
----------------------------------------------------------------------

M.views = {}

-- A profile's shorter prefixes, by view name. Added to a view's own, never
-- replacing them, so a shipped prefix keeps working wherever an alias is set.
M.prefixes = {}

function M.view(spec)
  if type(spec) ~= "table" or not spec.name then return M end

  for i, existing in ipairs(M.views) do
    if existing.name == spec.name then
      M.views[i] = spec
      return M
    end
  end

  M.views[#M.views + 1] = spec
  return M
end

function M.removeView(name)
  for i, existing in ipairs(M.views) do
    if existing.name == name then
      table.remove(M.views, i)
      return true
    end
  end
  return false
end

function M.viewNamed(name)
  for _, view in ipairs(M.views) do
    if view.name == name then return view end
  end
  return nil
end

----------------------------------------------------------------------
-- PREFIXES
----------------------------------------------------------------------

local function asList(value)
  if type(value) == "string" then return { value } end
  if type(value) == "table" then return value end
  return {}
end

-- The view's own prefixes first, so the one a chord types is the shipped,
-- readable one rather than an alias.
function M.prefixesOf(spec)
  local out = {}
  -- Indexed, not ipairs: a view with no prefix of its own leaves the first
  -- slot nil, and ipairs would stop before ever reading its aliases.
  local sources = { spec.prefix, M.prefixes[spec.name] }
  for i = 1, 2 do
    for _, prefix in ipairs(asList(sources[i])) do
      if type(prefix) == "string" and prefix ~= "" then out[#out + 1] = prefix end
    end
  end
  return out
end

-- The view whose prefix the text starts with, and which of its prefixes,
-- the longest when several do: "ext install " over "ext". A word prefix
-- carries its space, so "git" alone is still a search.
function M.viewForPrefix(query)
  local text = tostring(query or ""):lower()
  local bestName, bestPrefix
  for _, spec in ipairs(M.views) do
    for _, prefix in ipairs(M.prefixesOf(spec)) do
      if text:sub(1, #prefix) == prefix:lower()
         and (not bestPrefix or #prefix > #bestPrefix) then
        bestName, bestPrefix = spec.name, prefix
      end
    end
  end
  return bestName, bestPrefix
end

M.prefixView = M.viewForPrefix

-- Every declared picker as data (M.listShapes.view), a fresh copy per call:
-- an extension building rows from it can change nothing a picker is, and a
-- field of the wrong type, a problem already, is left out.
function M.getViews()
  local out = {}
  for i, spec in ipairs(M.views) do
    out[i] = {
      name        = spec.name,
      kind        = spec.kind or "list",
      title       = type(spec.title) == "string" and spec.title or nil,
      icon        = type(spec.icon) == "string" and spec.icon or nil,
      description = type(spec.description) == "string" and spec.description or nil,
      placeholder = type(spec.placeholder) == "string" and spec.placeholder or nil,
      empty       = type(spec.empty) == "string" and spec.empty or nil,
      prefixes    = M.prefixesOf(spec),
      parent      = type(spec.parent) == "string" and spec.parent or nil,
      menus       = type(spec.menus) == "table" and M.copyData(spec.menus) or nil,
      presenter   = type(spec.presenter) == "string" and spec.presenter or nil,
      extension   = type(spec.extension) == "string" and spec.extension or nil,
    }
  end
  return out
end

-- Which view a quickOpen keybinding opens, so the overlay and `?` can
-- describe it: its view, else the view its query's prefix belongs to,
-- else the entry picker the query is typed into.
function M.quickOpenTarget(entry)
  if type(entry) ~= "table" or entry.command ~= "quickOpen" then return nil end
  local args = type(entry.args) == "table" and entry.args or {}
  if args.view then return args.view end
  return (args.query and (M.viewForPrefix(args.query))) or M.defaultView
end
