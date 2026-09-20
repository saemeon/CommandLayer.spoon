-- The Shortcuts app's shortcuts, as rows: listed by `shortcuts list` in a
-- task, run by `shortcuts run`.

local M = {}

function M.extension(cl)
  cl.tools.register("shortcuts", { "/usr/bin/shortcuts" })

  -- Asked again a minute after the last answer, never on the picker path.
  local function listed()
    return cl.cached("list", {
      seconds = 60,
      initial = {},
      refresh = function(done)
        local bin = cl.tools.path("shortcuts")
        if not bin then return done({}) end
        local task = cl.tools.run(bin, { "list" }, function(code, stdout)
          local names = {}
          if code == 0 then
            for line in tostring(stdout):gmatch("[^\r\n]+") do names[#names + 1] = line end
          end
          done(names)
        end)
        if not task then done({}) end
      end,
    })
  end

  return {
    displayName = "Shortcuts",
    rank        = 0.29,
    menus       = { "root", "commandPalette" },
    optionalExtensionDependencies = { "icons" },

    settings = {
      -- A long list is the palette's to search, not the root's to fill.
      limit = { type = "integer", default = 30, description = "How many shortcuts are rows" },
    },

    commands = {
      { id = "shortcuts.run", title = "Run shortcut", menus = {},
        run = function(args, ctx)
          local bin = cl.tools.path("shortcuts")
          if not bin then
            hs.alert.show("The Shortcuts command line tool is not there")
            return
          end
          cl.tools.run(bin, { "run", cl.resolve(args.name, ctx) })
        end },
    },

    items = function(ctx)
      local icons = cl.extension("icons")
      local image = icons and icons.action()
      local limit = cl.setting("shortcuts", "limit")
      local rows = {}
      for i, name in ipairs(listed()) do
        if i > limit then break end
        rows[#rows + 1] = {
          label       = name,
          description = "Shortcuts",
          command     = "shortcuts.run",
          args        = { name = name },
          ctx         = ctx,
          subject     = { kind = "action", name = name, command = "shortcuts.run", args = { name = name } },
          iconPath    = image,
        }
      end
      return rows
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
