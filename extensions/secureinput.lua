-- Secure Input: while a password field, or a terminal's Secure Keyboard
-- Entry, holds it, macOS drops every keystroke Hammerspoon makes, so a
-- paste or a pressed shortcut fails without a sound. This notices it and
-- names the app holding it, for a command that presses keys to say so.

local M = {}

-- Which app holds it is asked again after this long: a field gains and
-- loses it as focus moves, and ioreg writes the whole registry root.
local HOLDER_SECONDS = 10

-- ioreg's console sessions, one { } each; the session on the console is
-- the one at the keyboard, where a second logged-in user may hold another.
function M.holderPID(output)
  local users = tostring(output or ""):match('"IOConsoleUsers"%s*=%s*(%b())')
  if not users then return nil end
  local first
  for session in users:gmatch("%b{}") do
    local pid = tonumber(session:match('"kCGSSessionSecureInputPID"%s*=%s*(%d+)') or "")
    if pid and session:find('"kCGSSessionOnConsoleKey"%s*=%s*Yes') then return pid end
    first = first or pid
  end
  return first
end

function M.extension(cl)
  cl.tools.register("ioreg", { "/usr/sbin/ioreg" })

  local holder, heardAt
  local waiting

  -- In-process and cheap, so it may be asked on every open.
  local function on()
    return hs.eventtap.isSecureInputEnabled ~= nil and hs.eventtap.isSecureInputEnabled() == true
  end

  local function answer(name)
    holder, heardAt = name, os.time()
    local callbacks = waiting or {}
    waiting = nil
    for _, callback in ipairs(callbacks) do callback(name) end
  end

  local function lookup(callback)
    if heardAt and os.time() - heardAt < HOLDER_SECONDS then
      if callback then callback(holder) end
      return
    end
    if waiting then
      waiting[#waiting + 1] = callback
      return
    end
    waiting = { callback }
    local task = cl.tools.run(cl.tools.path("ioreg") or "/usr/sbin/ioreg", { "-l", "-w", "0", "-d", "1" },
      function(code, stdout)
        local pid = code == 0 and M.holderPID(stdout) or nil
        local app = pid and hs.application.applicationForPID(pid)
        answer(app and app:name() or nil)
      end)
    if not task and waiting then answer(nil) end
  end

  -- `ctx.secureInput` is how it stood when the layer opened: by the time a
  -- command runs the picker has taken focus, and the field that held Secure
  -- Input has let it go until focus returns.
  local function warn(what, ctx)
    if not ((type(ctx) == "table" and ctx.secureInput) or on()) then return false end
    lookup(function(name)
      hs.alert.show(tostring(what) .. ": Secure Input is on" .. (name and (" in " .. name) or ""))
    end)
    return true
  end

  return {
    displayName = "Secure Input",
    description = "Notice when macOS's Secure Input would drop the keys a command presses, and say which app holds it",
    menus       = {},

    -- Looked up as the layer opens, so the name is there by the time a
    -- command asks.
    capture = function(ctx)
      if not on() then return end
      ctx.secureInput = true
      lookup()
    end,

    -- For an extension listing "secureinput" in optionalExtensionDependencies:
    -- warn(what, ctx) alerts and answers true while Secure Input is on.
    exports = { warn = warn },
  }
end

return M
