-- lazygit on a project or folder, in the terminal terminal.application names.

local M = {}

function M.extension(cl)
  cl.tools.register("lazygit", { "/opt/homebrew/bin/lazygit", "/usr/local/bin/lazygit" })

  return {
    displayName = "lazygit",
    description = "Open a project or folder in lazygit, in the terminal",
    menus       = {},
    extensionDependencies = { "terminal" },

    commands = {
      { id = "lazygit.open", title = "Open in lazygit", icon = "$(source-control)",
        menus = { "commandPalette" },
        inputs = { {
          id = "folder", description = "Open in lazygit",
          picker = { when = "viewItem == 'project' || viewItem == 'folder'", menus = { "recent", "files" } },
        } },
        run = function(args, ctx)
          local path = type(args.folder) == "table" and args.folder.path or nil
          if type(path) ~= "string" or path == "" then
            hs.alert.show("No folder for lazygit")
            return
          end
          if not cl.tools.path("lazygit") then
            hs.alert.show("lazygit not found")
            return
          end
          -- Left by quitting it, so its window has nothing to stay open for.
          cl.executeCommand("terminal.run",
            { cmd = { "lazygit" }, target = path, keepOpen = false, title = "Open in lazygit" }, ctx)
        end },
    },
  }
end

return M
