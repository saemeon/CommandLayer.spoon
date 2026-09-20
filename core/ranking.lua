-- Which rows a query keeps, and in what order.

local M = ...

local subjectKey = M.subjectKey

----------------------------------------------------------------------
-- MATCHING
--
-- Which rows a query keeps, and in what order. A presenter shows the
-- rows it is given and filters none of them, and the kernel matches no
-- text itself: every matcher is a file in matchers/, and the first that
-- takes a query decides.
----------------------------------------------------------------------

M.matchers = {}

function M.matcher(name, match)
  for _, existing in ipairs(M.matchers) do
    if existing.name == name then
      existing.match = match
      return M
    end
  end
  M.matchers[#M.matchers + 1] = { name = name, match = match }
  return M
end

-- In the order the profile's `matchers` list gives, which is also the whole
-- set: setup leaves out any it does not name.
local function matchWith(items, query, callback)
  for _, matcher in ipairs(M.matchers) do
    -- To the callback, so a match through a process counts its wait, and
    -- the ranking the callback goes on to do is not counted as matching.
    -- Only a matcher that takes the query records anything.
    local stop = M.span("match." .. tostring(matcher.name))
    local ok, handled = pcall(matcher.match, items, query, function(ranked, quality)
      stop(#items .. " rows")
      callback(ranked, type(quality) == "table" and quality or nil)
    end)

    if not ok then
      M.log.e("matcher '" .. tostring(matcher.name)
            .. "' -> " .. tostring(handled))
    elseif handled ~= false then
      return
    end
  end

  -- Nothing took the query, so nothing narrows it: every row stays
  -- rather than none, which would read as "no results".
  callback(items)
end

----------------------------------------------------------------------
-- RANKING
----------------------------------------------------------------------

-- A row's identity from one build to the next, for whatever remembers rows:
-- by subject -- a command row's is its id, so a command keeps its history
-- through a change of title -- then by label. A verb offered on cmd+k says
-- which kind of row it was offered on (`viewItem`), so "Reveal in Finder"
-- learned on files does not reorder the verbs on tabs.
function M.rowKey(item)
  local key = subjectKey(item)
  if not key then return "text\0" .. tostring(item.label) end
  local on = item.subject.viewItem
  return on ~= nil and (key .. "\0" .. tostring(on)) or key
end

local function tellRankers(hook, ...)
  for _, ranker in ipairs(M.rankers) do
    if ranker.weight ~= 0 and type(ranker[hook]) == "function" then
      local ok, err = pcall(ranker[hook], ...)
      if not ok then
        M.log.e("ranker '" .. tostring(ranker.name) .. "' " .. hook .. " -> " .. tostring(err))
      end
    end
  end
end

-- Called when something is actually run, which is the only honest signal
-- about what you use: every ranker in use that keeps track hears of it,
-- then every extension that learns from picks.
local function remember(item)
  if not item then return end
  tellRankers("picked", item)
  if M.notifyPicked then M.notifyPicked(item) end
end

M.recordUse = remember

-- When a row was last picked, as the rankers in use that keep track say --
-- the latest of them -- and 0 for never.
function M.lastUsed(item)
  local latest = 0
  for _, ranker in ipairs(M.rankers) do
    if ranker.weight ~= 0 and type(ranker.lastUsed) == "function" then
      local ok, value = pcall(ranker.lastUsed, item)
      if ok and type(value) == "number" and value > latest then latest = value end
    end
  end
  return latest
end

-- Every ranker in use forgets the row, as it was told of its picks.
function M.removeRecentlyUsed(item)
  if item then tellRankers("forget", M.rowKey(item)) end
end

function M.clearRecentlyUsed()
  tellRankers("reset")
end

-- Each ranker scores a row, and the weighted scores are added. Summed
-- rather than tiered on purpose: tiers would mean a context verb always
-- beats an app, so typing an app's exact name would bury it.
M.rankers = {}

function M.ranker(name, weight, score)
  for _, existing in ipairs(M.rankers) do
    if existing.name == name then
      existing.weight, existing.score = weight, score
      return M
    end
  end
  M.rankers[#M.rankers + 1] = { name = name, weight = weight, score = score }
  return M
end

-- Every row by name. Each name is lowered once, not once per comparison.
local function alphabeticalOrder(items)
  local name, byName = {}, {}
  for i, item in ipairs(items) do
    name[item] = tostring(item.label or item.text):lower()
    byName[i] = item
  end
  table.sort(byName, function(a, b) return name[a] < name[b] end)
  local order = {}
  for i, item in ipairs(byName) do order[item] = i end
  return order
end

-- Everything a ranker might need about the list as a whole, worked out
-- once rather than per ranker per row. `alphabetical` sorts every row, so it
-- is worked out the first time a ranker in use reads it: at weight 0 no
-- ranker asks, and no keystroke pays for it.
local function rankingContext(items, ranked, quality, query)
  local position = {}
  for i, item in ipairs(ranked) do position[item] = i end

  return setmetatable({
    count    = #items,
    matched  = #ranked,
    -- What was typed, so a ranker can tell a list nobody narrowed from one
    -- a matcher chose.
    query    = query,
    position = position,
    -- quality[i] is how well the i-th matched row matched, 0..1, when the
    -- matcher graded its rows.
    quality  = quality,
  }, {
    __index = function(context, key)
      if key ~= "alphabetical" then return nil end
      local order = alphabeticalOrder(items)
      rawset(context, key, order)
      return order
    end,
  })
end

local function sortByScore(items, ranked, quality, query)
  local stopContext = M.span("rank.context")
  local context = rankingContext(items, ranked, quality, query)
  stopContext()
  local stopScore = M.span("rank.score")
  local score, index = {}, {}

  for i, item in ipairs(items) do index[item] = i end

  -- Only the rows that matched are sorted, so only they are scored.
  for _, item in ipairs(ranked) do
    local total = 0
    for _, ranker in ipairs(M.rankers) do
      if ranker.weight ~= 0 then
        local ok, value = pcall(ranker.score, item, items, context)
        if ok and type(value) == "number" then
          total = total + value * ranker.weight
        end
      end
    end
    score[item] = total
  end
  stopScore(#ranked .. " rows")

  local stopSort = M.span("rank.sort")
  local out = {}
  for i, item in ipairs(ranked) do out[i] = item end

  -- table.sort is not stable, so the original position breaks ties and
  -- keeps the order an extension asked for.
  table.sort(out, function(a, b)
    local sa, sb = score[a] or 0, score[b] or 0
    if sa ~= sb then return sa > sb end
    return (index[a] or 0) < (index[b] or 0)
  end)
  stopSort()

  return out
end

----------------------------------------------------------------------
-- ALIASES
--
-- The one exception to adding scores up: an alias is a person naming a
-- command, so typed as the whole query its row goes first, matched or not.
----------------------------------------------------------------------

local function aliasKey(text)
  return text:lower():match("^%s*(.-)%s*$")
end

-- Typed text to the command ids it names, turned around once per settings
-- table rather than on every keystroke.
local aliasesRead, idsByAlias

local function aliasedIds(query)
  local aliases = type(M.settings) == "table" and M.settings.aliases or nil
  if type(aliases) ~= "table" or next(aliases) == nil then return nil end
  if aliases ~= aliasesRead then
    aliasesRead, idsByAlias = aliases, {}
    for id, written in pairs(aliases) do
      for _, alias in ipairs(type(written) == "table" and written or { written }) do
        local key = type(alias) == "string" and aliasKey(alias)
        if key and key ~= "" then
          idsByAlias[key] = idsByAlias[key] or {}
          idsByAlias[key][id] = true
        end
      end
    end
  end
  return idsByAlias[aliasKey(query)]
end

-- The command rows an alias names, in the order given, then the rest as
-- ranked; and how many went first.
local function aliasedFirst(items, ranked, ids)
  local out, first = {}, {}
  for _, item in ipairs(items) do
    local subject = item.subject
    if type(subject) == "table" and subject.kind == "command" and ids[subject.id] then
      out[#out + 1] = item
      first[item] = true
    end
  end
  local aliased = #out
  if aliased == 0 then return ranked, 0 end
  for _, item in ipairs(ranked) do
    if not first[item] then out[#out + 1] = item end
  end
  return out, aliased
end

-- What the pickers call: narrow to what matched, then order it. The
-- callback's second value is how many rows at the top an alias put there.
--
-- An `alwaysShow` row is VS Code's: no matcher drops it. It is not ranked
-- either, since whoever marked it placed it -- a status line, another source's
-- own matches -- so with text typed it follows the ranked rows in the order
-- given. With nothing typed nothing is narrowed, and it ranks with the rest.
local function rankItems(items, query, callback)
  -- Ranking moves every row, so a separator has no place left to mark:
  -- a ranked picker groups with `sections`, which label after ranking.
  local rows, always = {}, {}
  for _, item in ipairs(items or {}) do
    if item.kind ~= "separator" then
      local list = (item.alwaysShow == true and query ~= "") and always or rows
      list[#list + 1] = item
    end
  end
  items = rows
  matchWith(items, query, function(ranked, quality)
    local out = sortByScore(items, ranked, quality, query)
    for _, item in ipairs(always) do out[#out + 1] = item end
    local ids = query ~= "" and aliasedIds(query)
    if ids then
      callback(aliasedFirst(items, out, ids))
    else
      callback(out, 0)
    end
  end)
end

M.rankItems = rankItems

M.remember = remember
