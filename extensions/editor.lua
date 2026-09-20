-- Opening a file or folder in whichever editor is installed.

local M = {}

function M.extension(cl)
  local tools = cl.tools

  tools.register("code",   { "/opt/homebrew/bin/code", "/usr/local/bin/code",
                             "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" })
  tools.register("cursor", { "/opt/homebrew/bin/cursor", "/usr/local/bin/cursor",
                             "/Applications/Cursor.app/Contents/Resources/app/bin/cursor" })
  tools.register("zed",    { "/opt/homebrew/bin/zed", "/usr/local/bin/zed",
                             "/Applications/Zed.app/Contents/MacOS/cli" })
  tools.register("subl",   { "/opt/homebrew/bin/subl", "/usr/local/bin/subl",
                             "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl" })
  tools.register("open",   { "/usr/bin/open" })

  -- Code and Cursor take a line only after --goto, which otherwise reads a
  -- colon as part of the name; Zed and Sublime take path:line as it is.
  local function atLine(o) return o.line and (o.path .. ":" .. o.line) or o.path end
  -- A remote is VS Code's authority, "ssh-remote+host", and its path is a
  -- path on that host.
  local function withGoto(o)
    local list = o.remote and { "--remote", o.remote } or {}
    if o.path and o.line then
      list[#list + 1] = "--goto"
      list[#list + 1] = atLine(o)
    elseif o.path then
      list[#list + 1] = o.path
    end
    return list
  end
  -- Declining a remote rather than opening its path on this machine.
  local function localOnly(args)
    return function(o)
      if o.remote then return nil end
      return args(o)
    end
  end

  tools.provide("editor", {
    { name = "code",   bin = "code",   args = withGoto },
    { name = "cursor", bin = "cursor", args = withGoto },
    { name = "zed",    bin = "zed",    args = localOnly(function(o) return { atLine(o) } end) },
    { name = "subl",   bin = "subl",   args = localOnly(function(o) return { atLine(o) } end) },

    -- Always present: a file opens in its default app, a directory in
    -- Finder. Not an editor, but never nothing; it has no way to a line.
    { name = "open", bin = "open", args = localOnly(function(o) return { o.path } end) },
  })

  return {
    displayName = "Editor",
    description = "Open a file or folder in the editor you have",
    menus       = {},

    commands = {
      { id = "editor.open", title = "Open in editor", menus = {},
        run = function(args, ctx)
          local path = cl.resolve(args.target, ctx)
          if type(path) ~= "string" or path == "" then path = nil end
          local remote = cl.resolve(args.remote, ctx)
          if type(remote) ~= "string" or remote == "" then remote = nil end
          local line = tonumber(cl.resolve(args.line, ctx))
          line = line and line >= 1 and math.floor(line) or nil
          local _, bin, list = tools.pick("editor", { path = path, line = line, remote = remote })
          if not bin then
            hs.alert.show(remote and "No editor here opens a remote window: VS Code or Cursor does"
                          or "No editor found")
            return
          end
          tools.run(bin, list)
        end },
    },
  }
end

return M
