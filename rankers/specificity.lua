-- How particular a row is to right now, as its extension declared.
--
-- A verb that exists because of what is in front of you is nearly always
-- more wanted than a catalogue row that is always there. `rank` is declared
-- on 0..1 -- an ambient context verb at 1, an app at 0.29 -- and is the
-- score as it stands; how much it counts is its weight in the settings.

return function()
  return {
    weight = 0.35,
    score  = function(item)
      local rank = tonumber(item.rank) or 0
      return math.max(0, math.min(rank, 1))
    end,
  }
end
