-- Sound: which device plays it, which one listens, and muting the
-- microphones, done by macOS through hs.audiodevice.

local M = {}

local layer

-- What a prompt lists, kept from the watcher so a picker reads no device.
M.devices = { output = {}, input = {} }

-- By UID, the one name CoreAudio keeps for a device: two can share a name,
-- and a name changes with the language.
function M.list(devices, current)
  local currentUID = current and current:uid()
  local out = {}
  for _, device in ipairs(devices or {}) do
    local uid = device:uid()
    if uid then out[#out + 1] = { uid = uid, name = device:name() or uid, current = uid == currentUID } end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

function M.read()
  M.devices = {
    output = M.list(hs.audiodevice.allOutputDevices(), hs.audiodevice.defaultOutputDevice()),
    input  = M.list(hs.audiodevice.allInputDevices(), hs.audiodevice.defaultInputDevice()),
  }
end

function M.start()
  if not layer or M.watching then return M end
  M.read()
  -- hs.audiodevice.watcher is one callback for all of Hammerspoon: a config
  -- of its own that sets one replaces this, and this replaces it.
  M.watching = layer.watch({
    start = function()
      hs.audiodevice.watcher.setCallback(function() M.read() end)
      hs.audiodevice.watcher.start()
    end,
    stop = function()
      hs.audiodevice.watcher.stop()
      hs.audiodevice.watcher.setCallback(nil)
    end,
  })
  return M
end

function M.stop()
  if M.watching then M.watching.dispose() end
  M.watching = nil
  M.devices = { output = {}, input = {} }
  return M
end

function M.extension(cl)
  layer = cl

  local function options(kind)
    return function()
      local out = {}
      for _, device in ipairs(M.devices[kind]) do
        out[#out + 1] = { label = device.name, value = device.uid, description = device.current and "Current" or nil }
      end
      return out
    end
  end

  local function switch(kind, method)
    return function(args)
      local device = type(args.uid) == "string" and hs.audiodevice.findDeviceByUID(args.uid)
      if not device then
        hs.alert.show("No such " .. kind .. " device")
        return
      end
      if device[method](device) ~= true then hs.alert.show("Could not switch to " .. tostring(device:name())) end
    end
  end

  return {
    name        = "audio",
    displayName = "Audio",
    description = "Switch the sound output and input device, and mute the microphones",
    menus       = {},

    commands = {
      { id = "audio.setOutputDevice", title = "Switch output device…", category = "Audio", icon = "$(unmute)",
        menus = { "root", "commandPalette" },
        inputs = { { id = "uid", description = "Output device", picker = { options = options("output") } } },
        run = switch("output", "setDefaultOutputDevice") },

      { id = "audio.setInputDevice", title = "Switch input device…", category = "Audio", icon = "$(mic)",
        menus = { "root", "commandPalette" },
        inputs = { { id = "uid", description = "Input device", picker = { options = options("input") } } },
        run = switch("input", "setDefaultInputDevice") },

      -- Every microphone, not only the default: an app may be listening to
      -- another. `muted` says which way; without it, muted unless all are.
      { id = "audio.toggleMicrophoneMute", title = "Toggle microphone mute", category = "Audio",
        icon = "$(mic-filled)", menus = { "root", "commandPalette" },
        run = function(args)
          local devices = hs.audiodevice.allInputDevices() or {}
          local muted = args.muted
          if type(muted) ~= "boolean" then
            muted = false
            for _, device in ipairs(devices) do
              if device:inputMuted() == false then muted = true end
            end
          end
          local changed = 0
          for _, device in ipairs(devices) do
            if device:setInputMuted(muted) then changed = changed + 1 end
          end
          if changed == 0 then
            hs.alert.show("No microphone can be muted")
          else
            hs.alert.show(muted and "Microphones muted" or "Microphones on")
          end
        end },
    },
  }
end

return M
