-- WezTerm's panes, as `wezterm cli list` gives them: a row each, focused
-- through `wezterm cli activate-pane`, WezTerm brought forward. Asked only
-- while WezTerm runs, in a task, kept a few seconds.

local M = {}

M.bundleID = "com.github.wez.wezterm"
M.seconds = 3

-- `wezterm cli list --format json` -> { pane, title, cwd } per pane.
function M.parse(list)
  local out = {}
  for _, entry in ipairs(type(list) == "table" and list or {}) do
    if type(entry) == "table" and tonumber(entry.pane_id) then
      local cwd = type(entry.cwd) == "string" and entry.cwd:gsub("^file://[^/]*", "") or nil
      out[#out + 1] = { pane = tonumber(entry.pane_id), title = tostring(entry.title or "WezTerm"),
                        cwd = cwd ~= "" and cwd or nil }
    end
  end
  return out
end

local function running()
  local find = hs.application.applicationsForBundleID
  return find and (find(M.bundleID) or {})[1] or nil
end

function M.extension(cl)
  cl.tools.register("wezterm", { "/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm",
                                 "/Applications/WezTerm.app/Contents/MacOS/wezterm" })

  local function panes()
    return cl.cached("panes", { seconds = M.seconds, initial = {}, refresh = function(done)
      local wezterm = cl.tools.path("wezterm")
      if not wezterm or not running() then return done({}) end
      cl.tools.run(wezterm, { "cli", "list", "--format", "json" }, function(code, stdout)
        if code ~= 0 then return done(nil) end
        local ok, list = pcall(cl.decodeJSONC, stdout)
        done(ok and M.parse(list) or nil)
      end)
    end })
  end

  return {
    name        = "wezterm",
    displayName = "WezTerm",
    description = "WezTerm's panes as rows, each focused when picked; needs WezTerm",
    menus       = { "root", "recent" },
    viewItems   = { "weztermPane" },
    rank        = 0.2,

    commands = {
      { id = "wezterm.focusPane", title = "Focus pane", category = "WezTerm", menus = {},
        run = function(args)
          local wezterm = cl.tools.path("wezterm")
          if not wezterm or not tonumber(args.pane) then return end
          cl.tools.run(wezterm, { "cli", "activate-pane", "--pane-id", tostring(args.pane) }, function(code)
            if code ~= 0 then return hs.alert.show("WezTerm: that pane is gone") end
            local app = running()
            if app then app:activate() end
          end)
        end },
    },

    items = function(ctx)
      if not running() then return {} end
      local rows = {}
      for _, pane in ipairs(panes()) do
        rows[#rows + 1] = {
          label = pane.title, ctx = ctx, icon = "$(terminal)",
          description = "WezTerm pane" .. (pane.cwd and (" -- " .. pane.cwd) or ""),
          command = "wezterm.focusPane", args = { pane = pane.pane },
          subject = { kind = "weztermPane", id = pane.pane, name = pane.title, path = pane.cwd },
        }
      end
      return rows
    end,
  }
end

return M
