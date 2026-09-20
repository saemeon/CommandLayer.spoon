-- How well a row matched what you typed.
--
-- A matcher that grades its rows (`quality`, 0..1 per matched row) is
-- scored mostly by that grade, so an exact or prefix match stays clear of
-- what frecency and specificity add; its order breaks ties within a grade,
-- falling off with position rather than with the length of the list, where
-- the 50th of 2000 matches would still score near 1. A matcher that gives
-- only an order is scored by position in it.

-- How much of the score is the grade; the rest is the order.
local GRADE = 0.8
-- The position at which the order's part has halved.
local HALF = 10

return function(cl)
  -- Albert's exact-match boost: a share of the score given to a row whose
  -- label is exactly what was typed, over and above its grade. 0 as
  -- shipped, which leaves the grades alone.
  local function boost()
    local value = cl and cl.setting("relevance", "exactMatchBoost")
    if type(value) ~= "number" then return 0 end
    return math.max(0, math.min(value, 1))
  end

  return {
    weight = 1,
    settings = {
      exactMatchBoost = { type = "number", default = 0,
        description = "0..1: how much more a row counts when its label is exactly what was typed" },
    },

    score = function(item, _, context)
      -- Nothing typed, so nothing matched: relevance has no opinion, and the
      -- order a picker was given is not one either. Scoring by that order
      -- froze it -- the first verb on cmd+k scored 1 and the second 0, which
      -- no weight frecency has could ever answer.
      if (context.query or "") == "" then return 1 end

      local position = context.position[item]
      if not position then return 0 end
      local quality = context.quality and tonumber(context.quality[position])
      if quality then
        quality = math.max(0, math.min(quality, 1))
        local score = GRADE * quality + (1 - GRADE) * (HALF - 1) / (HALF - 2 + position)
        local share = boost()
        if share > 0 then score = (1 - share) * score + share * (quality >= 1 and 1 or 0) end
        return score
      end
      if context.matched < 2 then return 1 end
      return 1 - (position - 1) / (context.matched - 1)
    end,
  }
end
