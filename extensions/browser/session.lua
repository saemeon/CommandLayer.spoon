-- Chromium's session file: the open tabs, and when each was last active.
--
-- Chromium-family browsers -- Brave, Chrome, Edge, Vivaldi, Arc -- append
-- every change to their windows and tabs to <profile>/Sessions/Session_*,
-- a few seconds after it happens. Reading it lists tabs without asking the
-- browser anything, so no Automation permission, and its "last active"
-- times are real recency rather than the moments the launcher happened to
-- look. Its layout is Chromium's own (components/sessions): a record this
-- does not understand is skipped, and a file it cannot read gives nil, so
-- the browser extension falls back to asking.

local M = {}

-- Seconds from Chromium's epoch, 1601-01-01, to the Unix one.
M.EPOCH_OFFSET = 11644473600

-- The header's versions whose records are read here, from Chromium's
-- command_storage_backend.cc: 1, and 3, the same records with a marker once
-- the initial state is written (a record id this skips). 2 and 4 are those
-- encrypted, which cannot be read, and anything newer may lay records out
-- differently.
M.KNOWN_VERSIONS = { [1] = true, [3] = true }

-- The format version in a file's header, "SNSS" then a little-endian int32;
-- nil for what is not a session file.
function M.version(data)
  if type(data) ~= "string" or #data < 8 or data:sub(1, 4) ~= "SNSS" then return nil end
  return (string.unpack("<i4", data, 5))
end

-- Record ids, from Chromium's session_service_commands.cc.
local SET_TAB_WINDOW         = 0
local SET_TAB_INDEX          = 2
local UPDATE_NAVIGATION      = 6
local SELECTED_NAVIGATION    = 7
local SELECTED_TAB_IN_WINDOW = 8
local TAB_CLOSED             = 16
local WINDOW_CLOSED          = 17
local ACTIVE_WINDOW          = 20
local LAST_ACTIVE            = 21

local function utf16(bytes)
  local out, i, n = {}, 1, #bytes
  while i + 1 <= n do
    local unit = string.unpack("<I2", bytes, i)
    i = i + 2
    if unit >= 0xD800 and unit <= 0xDBFF and i + 1 <= n then
      local low = string.unpack("<I2", bytes, i)
      if low >= 0xDC00 and low <= 0xDFFF then
        unit = 0x10000 + (unit - 0xD800) * 0x400 + (low - 0xDC00)
        i = i + 2
      end
    end
    out[#out + 1] = utf8.char(unit)
  end
  return table.concat(out)
end

-- The tabs open when the file was last written, in window and position
-- order, each { id, window, index, url, title, lastActive } with
-- lastActive in Unix seconds, and `front`, the selected tab of the active
-- window. Nil for what is not a session file, and for a version not known,
-- with that version second.
function M.parse(data)
  local version = M.version(data)
  if not version then return nil end
  if not M.KNOWN_VERSIONS[version] then return nil, version end

  local tabs, selectedInWindow, closedWindows, activeWindow = {}, {}, {}, nil
  local function tab(id)
    tabs[id] = tabs[id] or { id = id, navigations = {} }
    return tabs[id]
  end

  local pos, n = 9, #data
  while pos + 1 <= n do
    local size = string.unpack("<I2", data, pos)
    pos = pos + 2
    if size == 0 or pos + size - 1 > n then break end
    local id = data:byte(pos)
    local body = data:sub(pos + 1, pos + size - 1)
    pos = pos + size

    pcall(function()
      if id == SET_TAB_WINDOW then
        local window, t = string.unpack("<i4i4", body)
        tab(t).window = window
      elseif id == SET_TAB_INDEX then
        local t, index = string.unpack("<i4i4", body)
        tab(t).index = index
      elseif id == SELECTED_NAVIGATION then
        local t, index = string.unpack("<i4i4", body)
        tab(t).selected = index
      elseif id == SELECTED_TAB_IN_WINDOW then
        local window, index = string.unpack("<i4i4", body)
        selectedInWindow[window] = index
      elseif id == TAB_CLOSED then
        tabs[string.unpack("<i4", body)] = nil
      elseif id == WINDOW_CLOSED then
        closedWindows[string.unpack("<i4", body)] = true
      elseif id == ACTIVE_WINDOW then
        activeWindow = string.unpack("<i4", body)
      elseif id == LAST_ACTIVE then
        local t, _, time = string.unpack("<i4i4i8", body)
        tab(t).lastActive = time / 1e6 - M.EPOCH_OFFSET
      elseif id == UPDATE_NAVIGATION then
        -- A pickle: its payload size, then fields aligned to four bytes --
        -- tab id, navigation index, the URL, the title in UTF-16.
        local t, index, urlLength, p = string.unpack("<i4i4i4", body, 5)
        local url = body:sub(p, p + urlLength - 1)
        p = p + ((urlLength + 3) & ~3)
        local titleLength
        titleLength, p = string.unpack("<i4", body, p)
        local title = utf16(body:sub(p, p + 2 * titleLength - 1))
        tab(t).navigations[index] = { url = url, title = title }
      end
    end)
  end

  local out = {}
  for _, t in pairs(tabs) do
    local nav = t.selected and t.navigations[t.selected]
    if not nav then
      local last
      for index in pairs(t.navigations) do
        if not last or index > last then last = index end
      end
      nav = last and t.navigations[last]
    end
    if nav and nav.url ~= "" and not closedWindows[t.window] then
      out[#out + 1] = { id = t.id, window = t.window or 0, index = t.index or 0,
                        url = nav.url, title = nav.title ~= "" and nav.title or nav.url,
                        lastActive = t.lastActive }
    end
  end
  table.sort(out, function(a, b)
    if a.window ~= b.window then return a.window < b.window end
    return a.index < b.index
  end)

  local front
  for _, t in ipairs(out) do
    if t.window == activeWindow and t.index == selectedInWindow[activeWindow] then front = t end
  end
  return { tabs = out, front = front }
end

-- The newest Session_ file in a profile's Sessions folder, and when it
-- was written.
function M.latest(dir)
  local ok, iter, dirObj = pcall(hs.fs.dir, dir)
  if not ok or not iter then return nil end
  local best, bestTime
  for entry in iter, dirObj do
    if entry:match("^Session_") then
      local path = dir .. "/" .. entry
      local modified = hs.fs.attributes(path, "modification")
      if type(modified) == "table" then modified = modified.modification end
      if modified and (not bestTime or modified > bestTime) then best, bestTime = path, modified end
    end
  end
  return best, bestTime
end

-- Read again only when the newest file is another one, or has been written
-- since: the file is a few hundred KB, and Chromium writes it every few
-- seconds while you browse.
local cache = {}

-- What the last read found, touching no file: for a picker.
function M.kept(dir)
  local hit = cache[dir]
  return hit and hit.result or nil
end

-- The tabs, or nil; a version not known comes second, when the file is parsed.
function M.read(dir)
  local path, modified = M.latest(dir)
  if not path then return nil end
  local hit = cache[dir]
  if hit and hit.path == path and hit.modified == modified then return hit.result end
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local data = handle:read("a")
  handle:close()
  local result, unknown = M.parse(data)
  cache[dir] = { path = path, modified = modified, result = result }
  return result, unknown
end

function M.forget()
  cache = {}
end

return M
