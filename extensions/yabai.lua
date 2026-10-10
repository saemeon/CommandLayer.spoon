-- yabai's spaces, as `yabai -m query --spaces` gives them: a row each,
-- focused through `yabai -m space --focus`. Asked in a task, kept a few
-- seconds; nothing without yabai.

local M = {}

M.seconds = 3

-- `yabai -m query --spaces` -> { index, label, display, focused } per space.
function M.parse(list)
  local out = {}
  for _, entry in ipairs(type(list) == "table" and list or {}) do
    if type(entry) == "table" and tonumber(entry.index) then
      local label = type(entry.label) == "string" and entry.label ~= "" and entry.label or nil
      out[#out + 1] = { index = tonumber(entry.index), label = label, display = tonumber(entry.display),
                        focused = entry["has-focus"] == true }
    end
  end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end

function M.extension(cl)
  cl.tools.register("yabai", { "/opt/homebrew/bin/yabai", "/usr/local/bin/yabai" })

  local function spaces()
    return cl.cached("spaces", { seconds = M.seconds, initial = {}, refresh = function(done)
      local yabai = cl.tools.path("yabai")
      if not yabai then return done({}) end
      cl.tools.run(yabai, { "-m", "query", "--spaces" }, function(code, stdout)
        if code ~= 0 then return done(nil) end
        local ok, list = pcall(cl.decodeJSONC, stdout)
        done(ok and M.parse(list) or nil)
      end)
    end })
  end

  return {
    name        = "yabai",
    displayName = "yabai",
    description = "yabai's spaces as rows, each focused when picked; needs yabai",
    menus       = { "root" },
    viewItems   = { "yabaiSpace" },
    rank        = 0.2,

    commands = {
      { id = "yabai.focusSpace", title = "Focus space", category = "yabai", menus = {},
        run = function(args)
          local yabai = cl.tools.path("yabai")
          if not yabai or not tonumber(args.space) then return end
          cl.tools.run(yabai, { "-m", "space", "--focus", tostring(args.space) }, function(code, _, stderr)
            if code ~= 0 then hs.alert.show("yabai: " .. tostring(stderr):match("[^\n]*")) end
          end)
        end },
    },

    items = function(ctx)
      if not cl.tools.path("yabai") then return {} end
      local rows = {}
      for _, space in ipairs(spaces()) do
        rows[#rows + 1] = {
          label = "Space " .. space.index .. (space.label and (" -- " .. space.label) or ""), ctx = ctx,
          icon = "$(window)",
          description = "yabai space" .. (space.display and (" on display " .. space.display) or "")
                        .. (space.focused and ", in front" or ""),
          command = "yabai.focusSpace", args = { space = space.index },
          subject = { kind = "yabaiSpace", id = space.index, name = space.label },
        }
      end
      return rows
    end,
  }
end

return M
