-- Context keys set by hand, a run's arguments, and filling templates.

local M = ...

----------------------------------------------------------------------
-- CONTEXT
--
-- Every field in it is contributed. A reader should treat any of them
-- as possibly absent, because a profile is free to ship without the
-- extension that captures it.
----------------------------------------------------------------------

-- VS Code's `setContext`: a key an extension sets itself -- a mode switched
-- on, a count kept -- rather than one captured when a context is built.
-- Copied in before capture runs, so a capture that knows better still wins.
local contextKeys = {}

function M.setContext(key, value)
  if type(key) ~= "string" or key == "" then return false end
  contextKeys[key] = value
  return true
end

-- A fresh context holding only the keys set with setContext, for
-- buildContext to run the captures over.
function M.contextFromKeys()
  local ctx = {}
  for key, value in pairs(contextKeys) do ctx[key] = value end
  return ctx
end

-- Collected arguments join the context rather than inventing a syntax
-- of their own, so a command written with ${query} reads the same as
-- one written with ${finderSelection}.
local function argContext(ctx, args)
  if not args or next(args) == nil then return ctx end

  local scoped = setmetatable({}, { __index = ctx })
  for k, v in pairs(args) do scoped[k] = v end
  return scoped
end

M.argContext = argContext

-- Every key readable through a context: its own, and those reached through
-- the scoped copies argContext makes. `pairs` sees only the table in hand,
-- which left "Inspect Context Keys" listing `activeView` alone -- the one
-- key the scope a row carries adds. The depth is a guard, not a limit: a
-- scope of a scope is two deep.
function M.contextKeys(ctx)
  local names, seen, depth = {}, {}, 0
  while type(ctx) == "table" and depth < 16 do
    for key in pairs(ctx) do
      if type(key) == "string" and not seen[key] then
        seen[key] = true
        names[#names + 1] = key
      end
    end
    local meta = getmetatable(ctx)
    ctx = type(meta) == "table" and meta.__index or nil
    depth = depth + 1
  end
  table.sort(names)
  return names
end

----------------------------------------------------------------------
-- RESOLVE
----------------------------------------------------------------------

-- A missing field becomes "", not the literal ${name}: an unresolved
-- placeholder reaching a shell or a URL does something, and nothing is
-- the safer thing for it to do.
--
-- `encode`, when given, is applied to every substituted value and never to
-- the template's own text: the shell backend quotes each value this way.
local VARIABLE, CAPTURE = "%${([%w_]+):?([%w_%.%-]*)}", "%$(%d)"

-- VS Code's variables as well as bare context fields: ${input:repo} is an
-- answered input and ${env:HOME} the environment. What only a later part
-- of the kernel can answer -- ${command:id}, ${config:browser.tabs} -- is
-- registered by it: `fn(ctx, rest)` returns the value.
local variables = {}

function M.registerTemplateVariable(name, fn)
  variables[name] = fn
end

-- ${input:window.app} is a field of an answer that is a row's subject, so a
-- template can name what a command acts on without the kernel knowing its
-- fields.
M.registerTemplateVariable("input", function(ctx, rest)
  local value = ctx[rest]
  if value == nil and rest:find(".", 1, true) then
    value = ctx
    for part in rest:gmatch("[^%.]+") do
      value = type(value) == "table" and value[part] or nil
    end
  end
  if type(value) == "table" then return "" end
  return tostring(value or "")
end)
M.registerTemplateVariable("env", function(_, rest) return os.getenv(rest) or "" end)

local function variable(ctx, name, rest)
  if rest == "" then return ctx[name] or "" end
  local fn = variables[name]
  if fn then return fn(ctx, rest) end
  return ""
end

-- One pass over the template, so a substituted value is never scanned
-- again: a `$1` inside a clipboard would otherwise be filled in, and a
-- quoted capture landing inside a quoted value would unquote it.
local function resolve(template, ctx, captures, encode)
  if type(template) ~= "string" then return template end

  local parts, at = {}, 1
  while true do
    local vs, ve, name, rest = template:find(VARIABLE, at)
    local cs, ce, n
    if captures then cs, ce, n = template:find(CAPTURE, at) end
    if not vs and not cs then break end

    local value
    if vs and (not cs or vs < cs) then
      parts[#parts + 1] = template:sub(at, vs - 1)
      value, at = variable(ctx, name, rest), ve + 1
    else
      parts[#parts + 1] = template:sub(at, cs - 1)
      value, at = captures[tonumber(n)] or "", ce + 1
    end
    -- A list -- every file selected -- is a line per item, or under an encode
    -- each item encoded on its own and spaced, so a shell gets separate words.
    if type(value) == "table" then
      local items = {}
      for i, item in ipairs(value) do items[i] = encode and encode(tostring(item)) or tostring(item) end
      value = table.concat(items, encode and " " or "\n")
    elseif encode then
      value = encode(tostring(value))
    end
    parts[#parts + 1] = value
  end
  parts[#parts + 1] = template:sub(at)
  return table.concat(parts)
end

M.resolve = resolve
