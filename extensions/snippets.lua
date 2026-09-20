-- Snippets, where a tool that keeps them already searches, expands and
-- edits them. A provider is the extension that reaches the tool and the
-- command that opens its snippet search.

local M = {}

M.providers = {
  { name = "Raycast", extension = "raycast", command = "raycast.open",
    args = { target = "raycast://extensions/raycast/snippets/search-snippets" } },
}

function M.extension(cl)
  -- cl.extension raises for an extension not declared, so every provider's is.
  local dependencies = {}
  for _, provider in ipairs(M.providers) do
    dependencies[#dependencies + 1] = provider.extension
  end

  local function available()
    local out = {}
    for _, provider in ipairs(M.providers) do
      local exports = cl.extension(provider.extension)
      if exports and exports.installed and exports.installed() then
        out[#out + 1] = provider
      end
    end
    return out
  end

  local function named(name)
    for _, provider in ipairs(available()) do
      if name == nil or provider.name == name then return provider end
    end
  end

  return {
    name  = "snippets",
    rank  = 0.14,
    menus = { "root", "commandPalette" },
    optionalExtensionDependencies = dependencies,

    commands = {
      { id = "snippets.open", title = "Snippets", menus = {},
        run = function(args, ctx)
          local provider = named(type(args) == "table" and args.provider or nil)
          if not provider then
            hs.alert.show("No snippets app is installed")
            return
          end
          return cl.executeCommand(provider.command, provider.args, ctx)
        end },
    },

    items = function(ctx)
      local rows = {}
      for _, provider in ipairs(available()) do
        rows[#rows + 1] = {
          label       = "Snippets",
          description = provider.name,
          command     = "snippets.open",
          args        = { provider = provider.name },
          ctx         = ctx,
          subject     = { kind = "command", name = "Snippets", provider = provider.name },
        }
      end
      return rows
    end,
  }
end

return M
