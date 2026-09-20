-- CommandLayer.spoon/tests/extensions/audio.lua
-- The audio extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
local M = cl.modules.audio

local calls = {}
-- muted nil is a device that cannot be muted.
local function device(uid, name, muted)
  local d = { muted = muted }
  function d.uid() return uid end
  function d.name() return name end
  function d.setDefaultOutputDevice() calls[#calls + 1] = "output " .. uid; return true end
  function d.setDefaultInputDevice() calls[#calls + 1] = "input " .. uid; return true end
  function d.inputMuted() return d.muted end
  function d.setInputMuted(_, value)
    if d.muted == nil then return false end
    d.muted = value
    return true
  end
  return d
end

local speakers = device("BuiltInSpeakerDevice", "MacBook Pro Speakers")
local airpods  = device("AA-BB:output", "AirPods")
local display  = device("HDMI-1", "studio Display")
local mic      = device("BuiltInMicrophoneDevice", "MacBook Pro Microphone", false)
local yeti     = device("USB-MIC", "Blue Yeti", true)
local line     = device("LINE-IN", "Line in")
local byUID = {}
for _, d in ipairs({ speakers, airpods, display, mic, yeti, line }) do byUID[d.uid()] = d end

local outputs, inputs, defaultOut, reads = { speakers, airpods }, { mic, yeti, line }, speakers, 0
stub(hs.audiodevice, "allOutputDevices", function() reads = reads + 1; return outputs end)
stub(hs.audiodevice, "allInputDevices", function() return inputs end)
stub(hs.audiodevice, "defaultOutputDevice", function() return defaultOut end)
stub(hs.audiodevice, "defaultInputDevice", function() return mic end)
stub(hs.audiodevice, "findDeviceByUID", function(uid) return byUID[uid] end)
local callback, watching = nil, 0
stub(hs.audiodevice, "watcher", {
  setCallback = function(fn) callback = fn end,
  start = function() watching = watching + 1 end,
  stop = function() watching = watching - 1 end,
})

local function optionsOf(id)
  local out = {}
  for _, o in ipairs(cl.getCommand(id).inputs[1].picker.options(cl.buildContext(), {})) do
    out[#out + 1] = o.label .. (o.description and (" (" .. o.description .. ")") or "")
  end
  return table.concat(out, ", ")
end

M.stop()
M.start()
local first = optionsOf("audio.setOutputDevice")
local readsOpening = reads
outputs, defaultOut = { speakers, airpods, display }, airpods
local stale = optionsOf("audio.setOutputDevice")
if callback then callback("dev#") end
local changed = optionsOf("audio.setOutputDevice")
check("output devices are listed by name, the current one marked, read at start and again when macOS says",
      first == "AirPods, MacBook Pro Speakers (Current)" and readsOpening == 1 and stale == first
      and changed == "AirPods (Current), MacBook Pro Speakers, studio Display" and watching == 1,
      first .. " / " .. changed .. " / " .. readsOpening .. " reads")
check("and the input devices the same way",
      optionsOf("audio.setInputDevice") == "Blue Yeti, Line in, MacBook Pro Microphone (Current)",
      optionsOf("audio.setInputDevice"))

local alerts = {}
stub(hs.alert, "show", function(text) alerts[#alerts + 1] = tostring(text) end)
cl.executeCommand("audio.setOutputDevice", { uid = "HDMI-1" }, {})
cl.executeCommand("audio.setInputDevice", { uid = "USB-MIC" }, {})
cl.executeCommand("audio.setOutputDevice", { uid = "GONE" }, {})
check("a device is switched to by its UID, through macOS, and one gone since is said so",
      table.concat(calls, ", ") == "output HDMI-1, input USB-MIC" and alerts[1] == "No such output device",
      table.concat(calls, ", ") .. " / " .. table.concat(alerts, " | "))

alerts = {}
local function state() return tostring(mic.muted) .. "/" .. tostring(yeti.muted) end
cl.executeCommand("audio.toggleMicrophoneMute", {}, {})
local afterFirst = state()
cl.executeCommand("audio.toggleMicrophoneMute", {}, {})
local afterSecond = state()
cl.executeCommand("audio.toggleMicrophoneMute", { muted = false }, {})
local afterForced = state()
check("Toggle mutes every microphone while any is on, turns all on when all are muted, and muted says which",
      afterFirst == "true/true" and afterSecond == "false/false" and afterForced == "false/false"
      and alerts[1] == "Microphones muted" and alerts[2] == "Microphones on",
      afterFirst .. " " .. afterSecond .. " " .. afterForced .. " / " .. table.concat(alerts, " | "))

inputs = { line }
cl.executeCommand("audio.toggleMicrophoneMute", {}, {})
M.stop()
check("with no microphone that can be muted it says so, and stopping stops the watcher and lets its callback go",
      alerts[#alerts] == "No microphone can be muted" and watching == 0 and callback == nil,
      tostring(alerts[#alerts]) .. " / " .. watching)
