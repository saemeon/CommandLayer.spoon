-- Maccy, as a destination.
--
-- Hands off rather than reading: its store is a sandboxed Core Data
-- database with a write-ahead log, so listing it would mean copying a
-- whole clipboard history to a temp file on a timer.
--
--   brew install --cask maccy

local M = {}

M.appPath = "/Applications/Maccy.app"

-- Carbon modifier bits, as KeyboardShortcuts stores them.
local CARBON = {
  { 256,  "cmd"   },
  { 512,  "shift" },
  { 2048, "alt"   },
  { 4096, "ctrl"  },
}

-- Virtual key code -> name, from Hammerspoon's own map.
local function keyName(code)
  for name, value in pairs(hs.keycodes.map) do
    if value == code and type(name) == "string" and #name > 0 then
      return name
    end
  end
  return nil
end
M.keyName = keyName

-- `defaults read`'s answer:
-- { "KeyboardShortcuts_popup" : "{\"carbonKeyCode\":8,\"carbonModifiers\":768}" }
function M.decodePopup(out)
  local code = tonumber(tostring(out):match("carbonKeyCode\\?\"?%s*:%s*(%d+)"))
  local bits = tonumber(tostring(out):match("carbonModifiers\\?\"?%s*:%s*(%d+)"))
  if not code or not bits then return nil end

  local key = keyName(code)
  if not key then return nil end

  local mods = {}
  for _, pair in ipairs(CARBON) do
    if bits & pair[1] ~= 0 then mods[#mods + 1] = pair[2] end
  end
  if #mods == 0 then return nil end

  return { mods, key }
end

function M.installed()
  return hs.fs.attributes(M.appPath) ~= nil
end

----------------------------------------------------------------------

function M.extension(cl)
  cl.tools.register("defaults", { "/usr/bin/defaults" })

  -- Maccy has no URL scheme, no AppleScript dictionary and no sdef, so a
  -- keystroke is the only way in. What it does have is its shortcut in
  -- its own preferences, which means the binding can be read rather than
  -- guessed -- rebind it in Maccy and this follows.
  local configured

  local function chord()
    if configured then return configured[1], configured[2] end
    return cl.chord(cl.setting("maccy", "popupChord"))
  end

  -- The picker has focus as this runs, so the keystroke has to land
  -- after it has closed and focus has gone back.
  local function popup()
    cl.after(0.1, function()
      local mods, key = chord()
      if key then hs.eventtap.keyStroke(mods, key, 0) end
    end)
  end

  M.start = function()
    configured = nil
    if not M.installed() then return end
    local bin = cl.tools.path("defaults")
    if not bin then return end
    cl.tools.run(bin, { "read", "org.p0deje.Maccy", "KeyboardShortcuts_popup" }, function(code, stdout)
      if code == 0 then configured = M.decodePopup(stdout) end
    end)
  end

  return {
    name  = "maccy",
    rank  = 0.14,
    menus = { "root", "commandPalette" },

    settings = {
      popupChord = { type = "string", default = "cmd+shift+c",
                     description = "The chord that opens Maccy, when its own preferences cannot be read" },
    },

    items = function(ctx)
      if not M.installed() then return {} end

      return {
        {
          label       = "Clipboard history",
          description = "Maccy -- everything you have copied",
          run         = popup,
          ctx         = ctx,
          subject     = { kind = "command", name = "maccy-popup" },
        },
      }
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
