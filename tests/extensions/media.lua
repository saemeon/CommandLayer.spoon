-- CommandLayer.spoon/tests/extensions/media.lua
-- The media extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()

local posted = {}
stub(hs.eventtap.event, "newSystemKeyEvent", function(key, down)
  return { post = function() posted[#posted + 1] = key .. (down and " down" or " up") end }
end)
for _, id in ipairs({ "playPause", "nextTrack", "previousTrack" }) do
  cl.executeCommand("media." .. id, {}, {})
end
check("the media commands press the system's media keys, down then up",
      table.concat(posted, ", ") == "PLAY down, PLAY up, NEXT down, NEXT up, PREVIOUS down, PREVIOUS up",
      table.concat(posted, ", "))

posted = {}
local alerts, spawned = {}, {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
stub(hs.task, "new", function(program, done)
  local t = { program = program, done = done }
  function t.start(self) return self end
  function t.terminate() end
  spawned[#spawned + 1] = t
  return t
end)
cl.executeCommand("media.playPause", {}, { secureInput = true })
for _, t in ipairs(spawned) do
  if t.done then t.done(1, "", "") end
end
check("while Secure Input held the keys, the key is still pressed and the warning says it may not have reached",
      #posted == 2 and #alerts == 1
      and alerts[1]:find("Play / pause may not have reached the player: Secure Input is on", 1, true) ~= nil,
      #posted .. " posted; " .. table.concat(alerts, " | "))
