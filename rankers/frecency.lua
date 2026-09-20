-- How often and how lately you pick a row, zoxide's frecency copied: each
-- run adds 1 to a row's rank, scored at x4 within the hour, x2 the day,
-- x0.5 the week and x0.25 after, each step a setting. Once the ranks together pass maxAge they
-- are all scaled to 90% of it, and one below 1 is forgotten, so an old
-- habit fades rather than outranking a new one for ever.
--
-- The smallest default weight: history should break a tie, never win one.
-- At weight 0 nothing is recorded.

return function(cl)
  local KEY = "commandlayer.actionUsage"
  local HOUR, DAY, WEEK = 3600, 86400, 7 * 86400

  -- Read on first use rather than at load: hs.settings is a file.
  local usage

  local function store()
    if not usage then usage = hs.settings.get(KEY) or {} end
    return usage
  end

  -- A plain number is a count kept before runs had times; it is read as a
  -- rank last used long ago.
  local function entryOf(value)
    if type(value) == "number" then return { rank = value, last = 0 } end
    return value
  end

  local function age(ranks)
    local maxAge = cl.setting("frecency", "maxAge") or 10000
    local total = 0
    for _, value in pairs(ranks) do total = total + entryOf(value).rank end
    if total <= maxAge then return end
    local factor = 0.9 * maxAge / total
    for key, value in pairs(ranks) do
      local entry = entryOf(value)
      entry.rank = entry.rank * factor
      ranks[key] = entry.rank >= 1 and entry or nil
    end
  end

  local spec = {
    weight      = 0.2,
    description = "How often and how lately you pick a row, as zoxide ranks folders",
    settings    = {
      maxAge = { type = "number", default = 10000,
                 description = "Past this total, every rank is scaled down and the smallest forgotten" },
      -- zoxide's steps, as Albert makes them settings.
      hourWeight = { type = "number", default = 4, order = 1,
                     description = "How much a pick within the last hour counts" },
      dayWeight = { type = "number", default = 2, order = 2,
                    description = "How much a pick within the last day counts" },
      weekWeight = { type = "number", default = 0.5, order = 3,
                     description = "How much a pick within the last week counts" },
      olderWeight = { type = "number", default = 0.25, order = 4,
                      description = "How much an older pick counts" },
    },
  }

  local function step(key, fallback)
    local value = cl.setting("frecency", key)
    return type(value) == "number" and value or fallback
  end

  -- zoxide's score, unbounded: rank times the weight for how long ago.
  function spec.scoreOf(item, now)
    local entry = entryOf(store()[cl.rowKey(item)])
    if not entry then return 0 end
    local since = (now or os.time()) - (entry.last or 0)
    local weight = (since < HOUR and step("hourWeight", 4)) or (since < DAY and step("dayWeight", 2))
                   or (since < WEEK and step("weekWeight", 0.5)) or step("olderWeight", 0.25)
    return entry.rank * weight
  end

  -- Squashed into 0..1 like every ranker, saturating so nothing wins on
  -- history alone.
  function spec.score(item)
    local score = spec.scoreOf(item)
    if score <= 0 then return 0 end
    return 1 - 1 / (1 + math.log(1 + score))
  end

  -- What "Recently used" orders by. A count kept before runs had times was
  -- still picked, so it is used, only before anything with a time.
  function spec.lastUsed(item)
    local entry = entryOf(store()[cl.rowKey(item)])
    if not entry then return 0 end
    return math.max(entry.last or 0, 1)
  end

  -- Called when something is actually run, which is the only honest signal
  -- about what you use.
  function spec.picked(item)
    local ranks = store()
    local key = cl.rowKey(item)
    local entry = entryOf(ranks[key]) or { rank = 0 }
    entry.rank, entry.last = entry.rank + 1, os.time()
    ranks[key] = entry
    age(ranks)
    hs.settings.set(KEY, ranks)
  end

  function spec.forget(key)
    local ranks = store()
    if ranks[key] == nil then return end
    ranks[key] = nil
    hs.settings.set(KEY, ranks)
  end

  function spec.reset()
    hs.settings.set(KEY, {})
    usage = nil
  end

  return spec
end
