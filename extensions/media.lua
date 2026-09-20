-- Play/pause, next and previous for whatever is playing: the media keys,
-- which macOS hands to the app holding Now Playing, so no player is
-- scripted and nothing needs Automation.

local M = {}

-- hs.eventtap's names for the keys.
M.KEYS = { playPause = "PLAY", nextTrack = "NEXT", previousTrack = "PREVIOUS" }

function M.extension(cl)
  -- Media keys are system-defined events rather than keystrokes and may
  -- well reach the player through Secure Input, so they are still pressed;
  -- the warning explains it if nothing played.
  local function press(key, title, ctx)
    local secure = cl.extension("secureinput")
    if secure then secure.warn(title .. " may not have reached the player", ctx) end
    hs.eventtap.event.newSystemKeyEvent(key, true):post()
    hs.eventtap.event.newSystemKeyEvent(key, false):post()
  end

  -- The root and the palette, and not the context picker: the keys reach
  -- whatever holds Now Playing wherever you are, so they are not about the
  -- page in front, and on every page they were noise.
  local function command(id, title, icon)
    return { id = "media." .. id, title = title, category = "Media", icon = icon,
             menus = { "root", "commandPalette" },
             run = function(_, ctx) press(M.KEYS[id], title, ctx) end }
  end

  return {
    name        = "media",
    displayName = "Media",
    description = "Play/pause, next and previous track in whatever is playing, as the media keys do",
    menus       = {},
    optionalExtensionDependencies = { "secureinput" },

    commands = {
      command("playPause", "Play / pause", "$(play)"),
      command("nextTrack", "Next track", "$(triangle-right)"),
      command("previousTrack", "Previous track", "$(triangle-left)"),
    },
  }
end

return M
