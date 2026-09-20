-- Another Spoon's method or chooser, with a URL to fall back to.

local M = {}

function M.extension(cl)
  return {
    displayName = "Spoons",
    description = "Call another Spoon, or open a fallback when it is not loaded",
    menus       = {},

    commands = {
      { id = "spoon.call", title = "Call a Spoon", menus = {},
        run = function(args, ctx)
          local target = spoon and spoon[args.spoon]

          if target then
            -- Some Spoons expose a method; others only their chooser.
            if args.method and target[args.method] then
              local ok, err = pcall(target[args.method], target)
              if ok then return end
              cl.log.e(tostring(args.spoon) .. ":" .. tostring(args.method) .. " -> " .. tostring(err))
            elseif args.chooser and target.chooser then
              target.chooser:show()
              return
            end
          end

          -- Degrades rather than failing, so an optional Spoon staying
          -- uninstalled still leaves the row usable.
          if args.fallback then
            hs.urlevent.openURL(cl.resolve(args.fallback, ctx))
          else
            hs.alert.show("Spoon not loaded: " .. tostring(args.spoon))
          end
        end },
    },
  }
end

return M
