-- "?": every picker there is a way to, and the ways -- VS Code's "?" in Quick
-- Open. Built from the declarations, so a picker a profile adds is listed
-- without anyone remembering to list it.

local M = {}

function M.extension(cl)
  return {
    displayName = "Help",
    description = "Every picker there is a way to, and how, in the ? picker",
    menus       = { "help" },

    items = function(ctx)
      local keys = {}
      for _, entry in ipairs(cl.getKeybindings()) do
        if type(entry.key) == "string" and entry.opens then
          keys[entry.opens] = keys[entry.opens] or {}
          table.insert(keys[entry.opens], entry.key)
        end
      end

      local rows = {}
      for _, view in ipairs(cl.getViews()) do
        local ways = {}
        for _, prefix in ipairs(view.prefixes) do ways[#ways + 1] = "type '" .. prefix .. "'" end
        for _, key in ipairs(keys[view.name] or {}) do ways[#ways + 1] = key end
        if view.parent then ways[#ways + 1] = "in " .. view.parent end

        -- The picker these rows are built for is where you already are.
        if view.name ~= ctx.activeView and #ways > 0 then
          -- "Actions -- Finder", as the picker reads once open, never its template.
          local placeholder = view.placeholder and cl.resolve(view.placeholder, ctx)
          rows[#rows + 1] = {
            label       = view.title or (placeholder ~= "" and placeholder) or view.name,
            description = table.concat(ways, ", "),
            submenu     = view.name,
            ctx         = ctx,
            subject     = { kind = "view", name = view.name },
          }
        end
      end
      return rows
    end,
  }
end

return M
