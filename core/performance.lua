-- Where the time goes: spans, what each name adds up to, and one line per
-- open or keystroke.

local M = ...

----------------------------------------------------------------------
-- SPANS
--
-- A span is one measured stretch, named `group.part` -- `gather.browser`,
-- `match.fzf` -- so a summary can add the parts of a group. Every span is
-- kept per name and in a ring of the latest; one over the setting's
-- threshold is a warning, every one a trace line.
----------------------------------------------------------------------

-- On until the performance setting says otherwise, so setup, which runs
-- before settings are read, is measured too.
local recording = true
-- From the `performance` setting: nil until it is read.
local slow, keep

local aggregates = {}
local recent, head = {}, 0

-- The durations a median is taken over, per name: the latest, not every one
-- since the reload.
local SAMPLES = 64

-- A trace that is never drawn -- a view with nothing to show -- is replaced
-- by the next, but a timer's spans can still reach it until then.
local TRACE_LIMIT = 2000

-- The trace spans join: an open, a keystroke, setup.
local active

-- The first open after setup is the one a reload makes slow.
local firstOpen = true

local function idle() return 0 end

local function round(ms) return math.floor(ms + 0.5) end

local function withDetail(detail)
  return detail ~= nil and (" (" .. tostring(detail) .. ")") or ""
end

local function aggregate(name, ms)
  local a = aggregates[name]
  if not a then
    a = { count = 0, total = 0, max = 0, last = 0, samples = {}, nextSample = 1 }
    aggregates[name] = a
  end
  a.count, a.total, a.last = a.count + 1, a.total + ms, ms
  if ms > a.max then a.max = ms end
  a.samples[a.nextSample] = ms
  a.nextSample = a.nextSample % SAMPLES + 1
end

local function keepRecent(entry)
  if keep == 0 then return end
  if keep then
    head = head % keep + 1
    recent[head] = entry
  else
    recent[#recent + 1] = entry
  end
end

local function record(name, ms, detail)
  aggregate(name, ms)
  keepRecent({ name = name, ms = ms, detail = detail })
  if M.logs("trace") then
    M.log.v(("span %s %d ms%s"):format(name, round(ms), withDetail(detail)))
  end
end

-- A task or a cache waits on another process, off the main thread, so its
-- time slows nothing on screen: a debug line, not a warning.
local OFF_THREAD = { task = true, cache = true }

local function warn(name, ms, detail)
  local line = ("slow: %s took %d ms%s"):format(name, round(ms), withDetail(detail))
  if OFF_THREAD[name:match("^([^%.]+)")] then
    if M.logs("debug") then M.log.d(line) end
  else
    M.log.w(line)
  end
end

-- Returns stop(detail), which records the span and gives its milliseconds.
-- A detail known only at the end -- how many rows -- is given to stop.
function M.span(name, detail)
  if not recording then return idle end
  local trace, started = active, M.clock()
  return function(more)
    -- Turned off while it ran: the settings are read inside setup's spans.
    if not recording then return 0 end
    local ms = M.clock() - started
    if more ~= nil then detail = more end
    record(name, ms, detail)
    local entry = { name = name, ms = ms, detail = detail }
    if slow then
      if ms >= slow then warn(name, ms, detail) end
    else
      entry.unchecked = true
    end
    if trace and not trace.ended and #trace.spans < TRACE_LIMIT then
      trace.spans[#trace.spans + 1] = entry
    end
    return ms
  end
end

----------------------------------------------------------------------
-- TRACES
--
-- What one open, keystroke or setup was made of. Setup and start end when
-- they return; the others when their rows are drawn, which matching through
-- a process can make later.
----------------------------------------------------------------------

local ENDS_ON_RETURN = { setup = true, start = true }
-- A whole open or keystroke over the threshold is a warning; setup and start
-- are allowed to take longer, and their slow parts warn on their own.
local WARNS = { open = true, keystroke = true, search = true, refresh = true }

local function sortedParts(group, limit)
  local list = {}
  for _, part in ipairs(group.order) do list[#list + 1] = { name = part, ms = group.parts[part] } end
  table.sort(list, function(a, b)
    if a.ms ~= b.ms then return a.ms > b.ms end
    return a.name < b.name
  end)
  local out = {}
  for i = 1, math.min(limit, #list) do out[i] = ("%s %d"):format(list[i].name, round(list[i].ms)) end
  if #list > limit then out[#out + 1] = "…" end
  return out
end

-- `open root 412ms first: capture 38 (windows 20) · gather 290 (browser 180,
-- apps 70) · match 25 · rank 40 · draw 44 · 1480 rows`
local function summary(trace, total, first)
  local groups, order = {}, {}
  for _, span in ipairs(trace.spans) do
    local name, part = span.name:match("^([^.]+)%.(.+)$")
    name = name or span.name
    local group = groups[name]
    if not group then
      group = { name = name, ms = 0, parts = {}, order = {} }
      groups[name], order[#order + 1] = group, group
    end
    group.ms = group.ms + span.ms
    if part then
      if not group.parts[part] then
        group.parts[part] = 0
        group.order[#group.order + 1] = part
      end
      group.parts[part] = group.parts[part] + span.ms
    end
  end

  local pieces = {}
  for _, group in ipairs(order) do
    if group.name == trace.kind then
      for _, piece in ipairs(sortedParts(group, 6)) do pieces[#pieces + 1] = piece end
    elseif #group.order > 0 then
      pieces[#pieces + 1] = ("%s %d (%s)"):format(group.name, round(group.ms),
                                                  table.concat(sortedParts(group, 3), ", "))
    else
      pieces[#pieces + 1] = ("%s %d"):format(group.name, round(group.ms))
    end
  end
  if trace.rows then pieces[#pieces + 1] = trace.rows .. " rows" end

  return ("%s%s %dms%s: %s"):format(trace.kind, trace.label and (" " .. trace.label) or "",
                                    round(total), first and " first" or "", table.concat(pieces, " · "))
end

local function endTrace(trace)
  if trace.ended then return end
  trace.ended = true
  if active == trace then active = nil end
  if not recording then return end

  local total = M.clock() - trace.started
  local first = trace.kind == "open" and firstOpen
  if first then firstOpen = false end

  -- Spans that ended before the settings were read, checked now.
  if slow then
    for _, span in ipairs(trace.spans) do
      if span.unchecked and span.ms >= slow then warn(span.name, span.ms, span.detail) end
      span.unchecked = nil
    end
  end

  local name = trace.kind .. (trace.label and ("." .. trace.label) or "") .. (first and ".first" or "")
  record(name, total, trace.rows and (trace.rows .. " rows") or nil)

  local loud = slow and total >= slow and WARNS[trace.kind]
  if loud then
    M.log.w(summary(trace, total, first))
  elseif M.logs("debug") then
    M.log.d(summary(trace, total, first))
  end
end

-- Runs fn inside a trace. Inside another trace's own call -- a prefix typed
-- opens a view -- it joins that one; a trace only waiting for its rows is
-- replaced.
function M.traced(kind, label, fn, ...)
  if not recording or (active and active.busy) then return fn(...) end
  local trace = { kind = kind, label = label, spans = {}, started = M.clock(), busy = true }
  active = trace
  local results = table.pack(pcall(fn, ...))
  trace.busy = false
  if ENDS_ON_RETURN[kind] or not results[1] then endTrace(trace) end
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

-- Rows reached the screen: the trace waiting for them is done.
function M.traceDrawn(rows)
  local trace = active
  if not trace or ENDS_ON_RETURN[trace.kind] then return end
  trace.rows = rows
  endTrace(trace)
end

-- The layer closed: a trace still waiting for rows will not get them.
function M.dropTrace()
  if active and not active.busy then
    active.ended = true
    active = nil
  end
end

----------------------------------------------------------------------
-- READING AND SETTING IT
----------------------------------------------------------------------

local function sortedSamples(a)
  local list = {}
  for i, ms in ipairs(a.samples) do list[i] = ms end
  table.sort(list)
  return list
end

-- A copy per name: count, total, max, last, and the median and 90th
-- percentile of the latest. { reset = true } clears everything after copying.
function M.performance(opts)
  local out = {}
  for name, a in pairs(aggregates) do
    local list, n = sortedSamples(a), #a.samples
    local median = n % 2 == 1 and list[(n + 1) // 2] or (list[n // 2] + list[n // 2 + 1]) / 2
    out[name] = { count = a.count, total = a.total, max = a.max, last = a.last,
                  median = median, p90 = list[math.max(1, math.ceil(n * 0.9))] }
  end
  if type(opts) == "table" and opts.reset then
    aggregates, recent, head = {}, {}, 0
  end
  return out
end

-- The latest spans, oldest first.
function M.recentSpans()
  local out = {}
  local n = #recent
  if not keep or n < keep then
    for i = 1, n do out[i] = recent[i] end
  else
    for i = head + 1, n do out[#out + 1] = recent[i] end
    for i = 1, head do out[#out + 1] = recent[i] end
  end
  return out
end

-- slowMilliseconds 0 turns recording off, and forgets what setup recorded.
function M.configurePerformance(section)
  if type(section) ~= "table" then return end
  local ms = tonumber(section.slowMilliseconds)
  if ms then
    recording = ms > 0
    slow = recording and ms or nil
    if not recording then
      aggregates, recent, head, active = {}, {}, 0, nil
    end
  end
  local count = tonumber(section.keep)
  if count and count >= 0 then
    local kept = M.recentSpans()
    keep = math.floor(count)
    recent = {}
    for i = math.max(1, #kept - keep + 1), #kept do recent[#recent + 1] = kept[i] end
    head = #recent
  end
end
