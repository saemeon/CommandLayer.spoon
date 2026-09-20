-- Weight 0 by default. Raise it and lower frecency for a list that does
-- not reorder under you.

return function()
  return {
    weight = 0,

    score = function(item, _, context)
      if context.count < 2 then return 0 end
      return 1 - ((context.alphabetical[item] or 1) - 1) / (context.count - 1)
    end,
  }
end
