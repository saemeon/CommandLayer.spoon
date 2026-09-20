-- A command line: a list run as argv with no shell, or a string through zsh
-- with every substituted value quoted.

local M = {}

function M.extension(cl)
  local tools = cl.tools
  tools.register("zsh", { "/bin/zsh" })

  -- Single quotes take everything literally but a single quote, which
  -- closes, is written escaped, and opens again.
  local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
  end

  local function failed(args, line, detail)
    hs.alert.show("Failed: " .. (args.title or "action"))
    cl.log.e(line .. " -> " .. tostring(detail))
  end

  local function start(args, program, argv, line)
    local task = tools.run(program, argv, function(code, _, stderr)
      if code ~= 0 then failed(args, line, stderr) end
    end)
    if not task then return failed(args, line, "could not start " .. program) end
  end

  -- hs.task has no PATH to search, so a bare name is a registered tool's
  -- path or is left to /usr/bin/env to find.
  local function program(name)
    if name:sub(1, 1) == "/" then return name, {} end
    local path = tools.path(name)
    if path then return path, {} end
    return "/usr/bin/env", { name }
  end

  return {
    displayName = "Shell",
    description = "Run a command line",
    menus       = {},

    commands = {
      { id = "shell.run", title = "Run a command line", menus = {},
        run = function(args, ctx)
          if type(args.cmd) == "table" then
            local argv = {}
            for i, element in ipairs(args.cmd) do
              argv[i] = tostring(cl.resolve(element, ctx))
            end
            local line = table.concat(argv, " ")
            if not argv[1] or argv[1] == "" then
              return failed(args, line, "no program")
            end

            local bin, rest = program(table.remove(argv, 1))
            for _, arg in ipairs(argv) do rest[#rest + 1] = arg end
            return start(args, bin, rest, line)
          end

          local line = cl.resolve(args.cmd, ctx, nil, quote)
          start(args, tools.path("zsh") or "/bin/zsh", { "-c", line }, line)
        end },
    },
  }
end

return M
