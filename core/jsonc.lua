-- JSON with comments and trailing commas, as VS Code's settings files are.

local M = ...

----------------------------------------------------------------------
-- JSONC
--
-- Settings are written by a person before a picker ever rewrites them, so
-- they carry comments. hs.json reads neither comments nor trailing commas,
-- and is not there at all in the harness. `null` reads as absent.
----------------------------------------------------------------------

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
                  b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

-- The value, and where each part of it stands in the text, for editing in
-- place: every node has `start` and `stop`; an object or array also has
-- `close` and `entries`, each entry its `start`, `key`, `node`, and the
-- position of the `comma` after it when there is one.
local function parse(text)
  local pos, n = 1, #text

  local function fail(message)
    error({ jsonc = message .. " at character " .. pos }, 0)
  end

  local function skip()
    while pos <= n do
      local c = text:sub(pos, pos)
      if c:match("%s") then
        pos = pos + 1
      elseif text:sub(pos, pos + 1) == "//" then
        local stop = text:find("\n", pos, true)
        pos = stop and stop + 1 or n + 1
      elseif text:sub(pos, pos + 1) == "/*" then
        local stop = text:find("*/", pos + 2, true)
        if not stop then fail("unclosed comment") end
        pos = stop + 2
      else
        return
      end
    end
  end

  local function str()
    pos = pos + 1
    local out = {}
    while true do
      local c = text:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == '"' then
        pos = pos + 1
        return table.concat(out)
      end
      if c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        if ESCAPES[e] then
          out[#out + 1] = ESCAPES[e]
          pos = pos + 2
        elseif e == "u" then
          local hex = text:sub(pos + 2, pos + 5)
          if not hex:match("^%x%x%x%x$") then fail("bad \\u escape") end
          local code = tonumber(hex, 16)
          pos = pos + 6
          if code >= 0xD800 and code <= 0xDBFF and text:sub(pos, pos + 1) == "\\u" then
            local low = tonumber(text:sub(pos + 2, pos + 5), 16)
            if low and low >= 0xDC00 and low <= 0xDFFF then
              code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
              pos = pos + 6
            end
          end
          out[#out + 1] = utf8.char(code)
        else
          fail("bad escape")
        end
      else
        local _, stop = text:find('^[^"\\]+', pos)
        out[#out + 1] = text:sub(pos, stop)
        pos = stop + 1
      end
    end
  end

  local value

  -- Objects and arrays share this: a comma between entries, and one more
  -- allowed before the close.
  local function entries(close, each, node)
    pos = pos + 1
    while true do
      skip()
      if text:sub(pos, pos) == close then break end
      local entry = { start = pos }
      each(entry)
      node.entries[#node.entries + 1] = entry
      skip()
      local c = text:sub(pos, pos)
      if c == "," then
        entry.comma = pos
        pos = pos + 1
      elseif c ~= close then
        fail("expected , or " .. close)
      end
    end
    node.close = pos
    pos = pos + 1
  end

  value = function()
    skip()
    local node = { start = pos }
    local c = text:sub(pos, pos)
    local result
    if c == "{" then
      result, node.entries = {}, {}
      entries("}", function(entry)
        if text:sub(pos, pos) ~= '"' then fail("expected a key") end
        entry.key = str()
        skip()
        if text:sub(pos, pos) ~= ":" then fail("expected :") end
        pos = pos + 1
        local v
        v, entry.node = value()
        result[entry.key] = v
      end, node)
    elseif c == "[" then
      result, node.entries = {}, {}
      entries("]", function(entry)
        local v
        v, entry.node = value()
        result[#result + 1] = v
      end, node)
    elseif c == '"' then
      result = str()
    elseif text:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      result = true
    elseif text:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      result = false
    elseif text:sub(pos, pos + 3) == "null" then
      pos = pos + 4
    else
      local start, stop = text:find("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
      local number = start and tonumber(text:sub(start, stop))
      if not number then fail("unexpected character") end
      pos = stop + 1
      result = math.tointeger(number) or number
    end
    node.stop = pos - 1
    return result, node
  end

  local result, root = value()
  skip()
  if pos <= n then fail("text after the value") end
  return result, root
end

-- Written back the way a person would lay it out: two-space indentation,
-- object keys sorted so the same settings always write the same file.
-- `inline` puts it on one line, for a keybinding entry; `order` names keys
-- written first, in that order, as VS Code writes "key" before "command".
local function encode(value, depth, inline, order)
  local t = type(value)
  if t == "string" then
    return '"' .. value:gsub('[%c"\\]', function(c)
      local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
      return named[c] or ("\\u%04x"):format(c:byte())
    end) .. '"'
  elseif t == "number" or t == "boolean" then
    return tostring(value)
  elseif t ~= "table" then
    return "null"
  end

  local parts, isList = {}, value[1] ~= nil
  if isList then
    for _, item in ipairs(value) do parts[#parts + 1] = encode(item, depth + 1, inline, order) end
  else
    local keys, first = {}, {}
    for _, key in ipairs(order or {}) do
      if value[key] ~= nil then
        keys[#keys + 1] = key
        first[key] = true
      end
    end
    local rest = {}
    for key in pairs(value) do
      if not first[tostring(key)] then rest[#rest + 1] = tostring(key) end
    end
    table.sort(rest)
    for _, key in ipairs(rest) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
      parts[#parts + 1] = encode(key, depth + 1, inline) .. ": " .. encode(value[key], depth + 1, inline, order)
    end
  end
  local open, close = isList and "[" or "{", isList and "]" or "}"
  if #parts == 0 then return open .. close end
  if inline then return open .. " " .. table.concat(parts, ", ") .. " " .. close end
  local pad = ("  "):rep(depth + 1)
  return open .. "\n" .. pad .. table.concat(parts, ",\n" .. pad) .. "\n" .. ("  "):rep(depth) .. close
end

function M.encodeJSON(value, inline, order)
  return encode(value, 0, inline, order)
end

-- The value, or nil and why not.
function M.decodeJSONC(text)
  if type(text) ~= "string" then return nil, "not text" end
  local ok, result = pcall(parse, text)
  if ok then return result end
  return nil, type(result) == "table" and result.jsonc or tostring(result)
end

----------------------------------------------------------------------
-- EDITING IN PLACE
--
-- A write from the settings picker changes one value, as VS Code's
-- settings editor does: by editing the text where that value stands, so
-- a person's comments, order and layout survive it.
----------------------------------------------------------------------

local function indentOf(text, at)
  local lineStart = at
  while lineStart > 1 and text:sub(lineStart - 1, lineStart - 1) ~= "\n" do
    lineStart = lineStart - 1
  end
  return text:match("^[ \t]*", lineStart)
end

-- Past a comment ending the line after `at`: it belongs to the entry
-- before, and an entry added after it must not take it along.
local function pastLineComment(text, at)
  local _, stop = text:find("^[ \t]*//[^\n]*", at + 1)
  return stop or at
end

-- The text without the object entry `index` of `node`. An entry on lines of
-- its own goes with those lines, and a comment ending its last line with it;
-- one sharing a line goes with the space after it. The last entry takes the
-- comma before it along, unless it had a trailing comma of its own.
local function removeEntry(text, node, index)
  local entry, previous = node.entries[index], node.entries[index - 1]
  local last = index == #node.entries
  local stop = entry.comma or entry.node.stop

  local lineStart = entry.start
  while lineStart > 1 and text:sub(lineStart - 1, lineStart - 1):match("[ \t]") do
    lineStart = lineStart - 1
  end
  local lineEnd = pastLineComment(text, stop)
  lineEnd = select(2, text:find("^[ \t]*", lineEnd + 1))
  local ownLines = (lineStart == 1 or text:sub(lineStart - 1, lineStart - 1) == "\n")
                   and (lineEnd >= #text or text:sub(lineEnd + 1, lineEnd + 1) == "\n")

  local from, to
  if ownLines then
    from, to = lineStart, lineEnd + 1
  elseif not last then
    from, to = entry.start, select(2, text:find("^[ \t]*", stop + 1))
  elseif previous then
    from, to = previous.comma or previous.node.stop + 1, stop
  else
    from, to = node.start + 1, node.close - 1
  end

  local out = text:sub(1, from - 1) .. text:sub(to + 1)
  if ownLines and last and previous and previous.comma and not entry.comma then
    out = out:sub(1, previous.comma - 1) .. out:sub(previous.comma + 1)
  end
  return out
end

-- The text with `value` at `path` -- { "extensions", "browser", "tabs" } --
-- or nil and why not. A value already there is replaced where it stands; a
-- missing key goes after the object's last entry, indented like it, with
-- objects made along the path as needed. Absent a value, the key is removed
-- -- every entry for it, since an earlier one is read once the last is gone
-- -- and a key that is not there leaves the text as it is.
function M.editJSONC(text, path, value)
  if type(text) ~= "string" then return nil, "not text" end
  local ok, result, root = pcall(parse, text)
  if not ok then
    return nil, type(result) == "table" and result.jsonc or tostring(result)
  end
  if text:sub(root.start, root.start) ~= "{" then return nil, "not an object" end

  local function nested(from)
    if from > #path then return value end
    return { [path[from]] = nested(from + 1) }
  end
  local function encodeAt(v, indent)
    return (encode(v, 0):gsub("\n", "\n" .. indent))
  end

  local node = root
  for depth, key in ipairs(path) do
    -- The last of a repeated key, since that is the one decoding keeps.
    local found, index
    for i, entry in ipairs(node.entries) do
      if entry.key == key then found, index = entry, i end
    end
    local isObject = found and text:sub(found.node.start, found.node.start) == "{"

    if value == nil then
      if found and depth == #path then return M.editJSONC(removeEntry(text, node, index), path) end
      if not isObject then return text end
      node = found.node
    elseif found and (depth == #path or not isObject) then
      return text:sub(1, found.node.start - 1)
             .. encodeAt(nested(depth + 1), indentOf(text, found.start))
             .. text:sub(found.node.stop + 1)
    elseif found then
      node = found.node
    else
      local last = node.entries[#node.entries]
      if last then
        local after = last.comma or last.node.stop
        local comma = last.comma and "" or ","
        -- An object written on one line stays on one line.
        if not text:sub(node.start, after):find("\n") then
          return text:sub(1, after) .. comma .. " " .. encode(key, 0) .. ": "
                 .. encode(nested(depth + 1), 0, true) .. text:sub(after + 1)
        end
        local indent = indentOf(text, last.start)
        local stop = pastLineComment(text, after)
        return text:sub(1, after) .. comma .. text:sub(after + 1, stop)
               .. "\n" .. indent .. encode(key, 0) .. ": " .. encodeAt(nested(depth + 1), indent)
               .. text:sub(stop + 1)
      end
      local outer = indentOf(text, node.start)
      local indent = outer .. "  "
      local entry = encode(key, 0) .. ": " .. encodeAt(nested(depth + 1), indent)
      if text:sub(node.start + 1, node.close - 1):match("^%s*$") then
        return text:sub(1, node.start) .. "\n" .. indent .. entry .. "\n" .. outer
               .. text:sub(node.close)
      end
      return text:sub(1, node.start) .. "\n" .. indent .. entry .. text:sub(node.start + 1)
    end
  end
  return nil, "no path"
end

-- The parsed text and the list node at `path` -- object keys down from the
-- root, {} for a root that is the list -- or nil and why not.
local function listAt(text, path)
  if type(text) ~= "string" then return nil, "not text" end
  local ok, result, root = pcall(parse, text)
  if not ok then
    return nil, type(result) == "table" and result.jsonc or tostring(result)
  end
  local node = root
  for _, key in ipairs(path or {}) do
    if text:sub(node.start, node.start) ~= "{" then return nil, "no path" end
    local found
    for _, entry in ipairs(node.entries) do
      if entry.key == key then found = entry end
    end
    if not found then return nil, "no path" end
    node = found.node
  end
  if text:sub(node.start, node.start) ~= "[" then return nil, "not a list" end
  return node
end

-- The text without element `index` of the list at `path`, laid out as a
-- removed key is: its lines go with it, and a comment ending its line.
function M.removeJSONCElement(text, path, index)
  local node, err = listAt(text, path)
  if not node then return nil, err end
  if type(index) ~= "number" or not node.entries[index] then return nil, "no such element" end
  return removeEntry(text, node, index)
end

-- The text with `value` after the last element of the list at `path`,
-- indented like it. An element on one line is followed by one on one line,
-- and a list written on one line stays on one; `order` is encodeJSON's.
function M.appendJSONCElement(text, path, value, order)
  local node, err = listAt(text, path)
  if not node then return nil, err end
  local last = node.entries[#node.entries]
  if not last then
    local outer = indentOf(text, node.start)
    local indent = outer .. "  "
    return text:sub(1, node.start) .. "\n" .. indent .. encode(value, 0, true, order) .. "\n" .. outer
           .. text:sub(node.close)
  end
  local after = last.comma or last.node.stop
  local comma = last.comma and "" or ","
  if not text:sub(node.start, after):find("\n") then
    return text:sub(1, after) .. comma .. " " .. encode(value, 0, true, order) .. text:sub(after + 1)
  end
  local indent = indentOf(text, last.start)
  local inline = not text:sub(last.node.start, last.node.stop):find("\n")
  local encoded = inline and encode(value, 0, true, order)
                  or (encode(value, 0, false, order):gsub("\n", "\n" .. indent))
  local stop = pastLineComment(text, after)
  return text:sub(1, after) .. comma .. text:sub(after + 1, stop) .. "\n" .. indent .. encoded
         .. text:sub(stop + 1)
end

----------------------------------------------------------------------
-- FILES
----------------------------------------------------------------------

function M.readText(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local text = handle:read("a")
  handle:close()
  return text
end

-- What each file said when the layer last read or wrote it, so a change on
-- disk can be told from a write of the layer's own. A missing file says what
-- an empty one does.
local lastKnown = {}
local BROKEN = {}

local function sameJSON(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not sameJSON(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

M.sameJSON = sameJSON

-- A copy all the way down, so what is handed out cannot change what the layer
-- holds. Functions are left out: a copy is data.
local function copyData(value)
  if type(value) == "function" then return nil end
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copyData(v) end
  return out
end

M.copyData = copyData

-- A missing file is nothing. One that does not parse is a problem and is
-- treated as nothing, never half-applied.
function M.readJSONC(path)
  local text = M.readText(path)
  if not text then
    lastKnown[path] = {}
    return nil, "missing"
  end
  local data, err = M.decodeJSONC(text)
  if data == nil then
    lastKnown[path] = BROKEN
    M.problem(path, "does not parse, so it was ignored: " .. tostring(err))
    return nil, "broken"
  end
  lastKnown[path] = data
  return data, "ok"
end

function M.rememberJSONC(path, data)
  lastKnown[path] = data
end

-- Whether the file says something other than when the layer last read or
-- wrote it -- a comment or a space is no change -- or nil and why not, for a
-- file that does not parse. A file that did not parse, and now does, has
-- changed whatever it says.
function M.changedJSONC(path)
  local text = M.readText(path)
  local data, err = {}, nil
  if text then data, err = M.decodeJSONC(text) end
  if data == nil then
    lastKnown[path] = BROKEN
    return nil, err or "no value"
  end
  local known = lastKnown[path] or {}
  return known == BROKEN or not sameJSON(known, data)
end

function M.isList(value)
  return type(value) == "table" and value[1] ~= nil
end

function M.jsonType(value)
  if type(value) == "table" then return M.isList(value) and "array" or "object" end
  return type(value)
end
