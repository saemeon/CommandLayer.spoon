-- `when` clauses: VS Code's syntax for "only in this situation", evaluated
-- over the context's fields.

local M = ...

----------------------------------------------------------------------
-- WHEN
--
-- `==`, `!=`, `=~ /lua pattern/`, `!`, `&&`, `||`, parentheses, and a bare
-- key meaning "is set". A key is a context field. One that no extension
-- captured is unset, so a clause about something not installed is simply
-- false rather than an error.
----------------------------------------------------------------------

-- By text, since the same clause is checked for every row on every
-- keystroke. false marks one that did not parse, so it is reported once.
local cache = {}

local function isSet(v)
  return v ~= nil and v ~= false and v ~= ""
end

-- Keys a later part of the kernel answers rather than a capture:
-- `config.browser.tabOrder` is a setting. `fn(rest)` returns the value.
local namespaces = {}

function M.registerWhenNamespace(name, fn)
  namespaces[name] = fn
end

-- Answered once per context however many rows ask, and kept on the context
-- a scoped copy reads through, so a gather's copy for its view shares them.
local answered = setmetatable({}, { __mode = "k" })
local NOTHING = {}

local function baseOf(ctx)
  for _ = 1, 32 do
    local mt = getmetatable(ctx)
    local up = type(mt) == "table" and rawget(mt, "__index")
    if type(up) ~= "table" then break end
    ctx = up
  end
  return ctx
end

local function read(ctx, key)
  local value = ctx[key]
  if value ~= nil then return value end
  local name, rest = key:match("^([%a_][%w_]*)%.(.+)$")
  local fn = name and namespaces[name]
  if not fn then return nil end
  local base = baseOf(ctx)
  local known = answered[base]
  if not known then
    known = {}
    answered[base] = known
  end
  if known[key] == nil then
    local ok, found = pcall(fn, rest)
    if ok and found ~= nil then known[key] = found else known[key] = NOTHING end
  end
  if known[key] == NOTHING then return nil end
  return known[key]
end

-- Recursive descent over the text itself; a token list would only be a
-- second copy of something this small.
local function parse(text)
  local pos = 1

  local function skip() pos = text:find("%S", pos) or (#text + 1) end
  local function peek(s) skip(); return text:sub(pos, pos + #s - 1) == s end
  local function take(s)
    if peek(s) then
      pos = pos + #s
      return true
    end
    return false
  end
  local function fail(message)
    error({ when = message .. " at character " .. pos }, 0)
  end

  local orExpr

  local function value(op)
    skip()
    local c = text:sub(pos, pos)

    if op == "=~" then
      if c ~= "/" then fail("expected /pattern/") end
      -- `%/` is a slash inside the pattern, as `%.` is a dot.
      local i = pos + 1
      while i <= #text do
        local ch = text:sub(i, i)
        if ch == "%" then i = i + 2
        elseif ch == "/" then break
        else i = i + 1 end
      end
      if i > #text then fail("unterminated /pattern/") end
      local pattern = text:sub(pos + 1, i - 1)
      pos = i + 1
      -- Tried now, so a broken pattern is one parse error rather than an
      -- error thrown for every row on every keystroke.
      if not pcall(string.find, "", pattern) then fail("malformed pattern") end
      return { kind = "pattern", value = pattern }
    end

    if c == "'" or c == '"' then
      local close = text:find(c, pos + 1, true)
      if not close then fail("unterminated string") end
      local s = text:sub(pos + 1, close - 1)
      pos = close + 1
      return { kind = "string", value = s }
    end

    local word = text:match("^[%w_%.%-]+", pos)
    if not word then fail("expected a value") end
    pos = pos + #word
    return { kind = "word", value = word }
  end

  local function primary()
    if take("(") then
      local inner = orExpr()
      if not take(")") then fail("expected )") end
      return inner
    end

    skip()
    local key = text:match("^[%a_][%w_%.]*", pos)
    if not key then fail("expected a context key") end
    pos = pos + #key

    local op = (take("==") and "==") or (take("!=") and "!=") or (take("=~") and "=~")
            or (take("<=") and "<=") or (take(">=") and ">=")
            or (take("<") and "<") or (take(">") and ">")
    if not op then
      -- Words, so they need a word boundary: `index` is a key, not `in`.
      skip()
      local notIn = text:match("^not%s+in%f[^%w_]", pos)
      local isIn = not notIn and text:match("^in%f[^%w_]", pos)
      if notIn or isIn then
        pos = pos + #(notIn or isIn)
        op = notIn and "not in" or "in"
      end
    end
    if not op then
      return function(ctx) return isSet(read(ctx, key)) end
    end

    -- `a in b`: the value of key a is an element of the list, or a key of
    -- the table, that key b holds -- VS Code's `resourceFilename in
    -- supportedFolders`. The right-hand side is a key, never a literal.
    if op == "in" or op == "not in" then
      skip()
      local other = text:match("^[%a_][%w_%.]*", pos)
      if not other then fail("expected a context key after " .. op) end
      pos = pos + #other
      local function contains(ctx)
        local collection, wanted = read(ctx, other), read(ctx, key)
        if wanted == nil or type(collection) ~= "table" then return false end
        for _, element in ipairs(collection) do
          if element == wanted then return true end
        end
        return collection[wanted] ~= nil
      end
      if op == "in" then return contains end
      return function(ctx) return not contains(ctx) end
    end

    -- Numbers only, as VS Code compares them: a key that is not a number is
    -- never less or greater than anything.
    if op == "<" or op == "<=" or op == ">" or op == ">=" then
      local v = value(op)
      local limit = tonumber(v.value)
      if not limit then fail("expected a number after " .. op) end
      return function(ctx)
        local n = tonumber(read(ctx, key))
        if not n then return false end
        if op == "<" then return n < limit end
        if op == "<=" then return n <= limit end
        if op == ">" then return n > limit end
        return n >= limit
      end
    end

    local v = value(op)
    if op == "=~" then
      return function(ctx) return tostring(read(ctx, key) or ""):find(v.value) ~= nil end
    end

    local function equal(ctx)
      local actual = read(ctx, key)
      if v.kind == "word" and (v.value == "true" or v.value == "false") then
        return isSet(actual) == (v.value == "true")
      end
      return actual ~= nil and tostring(actual) == v.value
    end
    if op == "==" then return equal end
    return function(ctx) return not equal(ctx) end
  end

  local function unary()
    if peek("!") and not peek("!=") then
      pos = pos + 1
      local inner = unary()
      return function(ctx) return not inner(ctx) end
    end
    return primary()
  end

  local function andExpr()
    local left = unary()
    while take("&&") do
      local l, r = left, unary()
      left = function(ctx) return l(ctx) and r(ctx) end
    end
    return left
  end

  orExpr = function()
    local left = andExpr()
    while take("||") do
      local l, r = left, andExpr()
      left = function(ctx) return l(ctx) or r(ctx) end
    end
    return left
  end

  local fn = orExpr()
  skip()
  if pos <= #text then fail("unexpected '" .. text:sub(pos, pos) .. "'") end
  return fn
end

function M.parseWhen(text)
  if cache[text] == nil then
    local ok, fn = pcall(parse, text)
    if ok then
      cache[text] = fn
    else
      cache[text] = false
      local message = type(fn) == "table" and fn.when or tostring(fn)
      M.log.w(("when clause %q does not parse: %s"):format(text, message))
    end
  end
  return cache[text] or nil
end

-- Why a clause does not parse, or nil, without logging: the schema reports
-- it as a problem instead.
function M.whenError(text)
  local ok, err = pcall(parse, text)
  if ok then return nil end
  return type(err) == "table" and err.when or tostring(err)
end

-- Absent or empty means always. One that does not parse means never:
-- showing a command in the situation it was written to avoid is the worse
-- mistake of the two.
function M.when(text, ctx)
  if text == nil or text == "" then return true end
  if type(text) ~= "string" then return false end
  local fn = M.parseWhen(text)
  if not fn then return false end
  local ok, result = pcall(fn, ctx or {})
  return (ok and result) and true or false
end
