-- Typing a sum answers it, through bc.
--
-- The query hook cannot wait, so bc is asked in a task and the row comes
-- from its answer: a new expression starts bc and shows nothing, and the
-- picker is redrawn when the answer lands.

local M = {}

-- bc -l's functions: sine, cosine, arctangent, natural log, exponential,
-- square root. No other letters are sent: bc is a language, and
-- `while (1) {}` is valid in it.
local FUNCTIONS = { "sqrt", "s", "c", "a", "l", "e" }

-- No %: under -l bc takes a remainder at scale 20, so 17 % 5 is 0.
local ALLOWED = "^[%d%s%+%-%*/%^%(%)%.]+$"

-- Trailing "=" is how people finish typing a sum.
local function clean(query)
  return (query:gsub("%s*=%s*$", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The expression worth asking bc about, or nil. A number and an operator,
-- or a function call: "5" alone is not a calculation.
function M.expression(query)
  local expression = clean(tostring(query or ""):lower())
  if #expression < 2 then return nil end

  local bare = expression
  for _, name in ipairs(FUNCTIONS) do
    bare = bare:gsub("%f[%a]" .. name .. "%s*%(", "(")
  end
  if not bare:match(ALLOWED) or not bare:find("%d") then return nil end
  if not bare:find("[%+%-%*/%^%(]") then return nil end
  return expression
end

-- bc prints every digit of its scale (2.50000000000000000000), a point
-- with no zero before it (-.5), and breaks a long number with a backslash.
function M.format(stdout)
  local number = tostring(stdout or ""):gsub("\\\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if not number:match("^%-?%d*%.?%d*$") or not number:find("%d") then return nil end
  if number:find(".", 1, true) then number = number:gsub("0+$", ""):gsub("%.$", "") end
  number = number:gsub("^(%-?)%.", "%10.")
  if number == "" or number == "-" or number == "-0" then number = "0" end
  return number
end

-- Expression -> its answer, or false where bc refused it.
local answers, count = {}, 0
local asking, task
-- Bumped by every ask, so a task terminated for a newer one is not heard.
local generation = 0

function M.forget()
  generation = generation + 1
  local running = task
  answers, count, asking, task = {}, 0, nil, nil
  if running then running:terminate() end
end

function M.stop() M.forget() end

local function ask(cl, expression)
  if asking == expression then return end
  generation = generation + 1
  local mine = generation
  local previous = task
  asking, task = expression, nil
  if previous then previous:terminate() end

  local bc = cl.tools.path("bc")
  if not bc then
    asking = nil
    return
  end

  local started = cl.tools.run(bc, { "-l" }, function(code, stdout, stderr)
    if generation ~= mine then return end
    asking, task = nil, nil
    local answer = code == 0 and (stderr or "") == "" and M.format(stdout) or false
    -- Only for the session's sake: no one types thousands of sums.
    if count >= 500 then answers, count = {}, 0 end
    answers[expression], count = answer, count + 1
    if answer then cl.refresh() end
  end, { input = expression .. "\n" })

  if generation ~= mine then return end
  if started and asking == expression then task = started else asking = nil end
end

----------------------------------------------------------------------

function M.extension(cl)
  cl.tools.register("bc", { "/usr/bin/bc" })

  return {
    name  = "calculator",
    -- Nothing standing; it only ever answers a query.
    menus = {},

    commands = {
      { id = "calculator.copy", title = "Copy", category = "Calculator",
        menus = { ["view/item/context"] = true },
        inputs = { { id = "number", description = "Which answer",
                     picker = { when = "viewItem == 'number'" } } },
        run = function(args, ctx)
          cl.executeCommand("system.copy", { text = args.number and args.number.value }, ctx)
        end },
    },

    query = function(query, ctx)
      local expression = M.expression(query)
      if not expression then return {} end

      local answer = answers[expression]
      if answer == nil then
        ask(cl, expression)
        return {}
      end
      if not answer then return {} end

      return {
        {
          label       = answer,
          description = "= " .. answer .. "  --  return to copy",
          ctx         = ctx,
          command     = "system.copy",
          args        = { text = answer },
          subject     = { kind = "number", name = answer, value = answer },
        },
      }
    end,
  }
end

return M
