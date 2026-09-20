-- A folder, or a command line in a folder, in the terminal the
-- `terminal.application` setting names.

local M = {}

-- Single quotes take everything literally but a single quote, which
-- closes, is written escaped, and opens again.
function M.quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Inside an AppleScript string only a backslash and a double quote are
-- special.
function M.appleScriptString(text)
  return '"' .. tostring(text):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- macOS refusing Hammerspoon control of an app: -1743 not allowed, -1744
-- allowing it would need a prompt the process could not put up.
function M.refused(stderr)
  local text = tostring(stderr or "")
  return text:find("-1743", 1, true) ~= nil or text:find("-1744", 1, true) ~= nil
end

M.AUTOMATION = "Allow Hammerspoon to control Terminal: System Settings > Privacy & Security > Automation"

-- Terminal.app is reached through `open` and its own scripting, the rest
-- through their binaries: `open` names the arguments that open a folder,
-- `run` those that run `shell -lc line` there. With a `bundleID`,
-- `notRunning` holds the same two for /usr/bin/open while that app is not
-- running, and the app is brought to the front once its binary succeeds.
M.terminals = {
  terminal = { title = "Terminal" },
  wezterm = { title = "WezTerm", tool = "wezterm", bundleID = "com.github.wez.wezterm",
    open = function(dir, newWindow)
      local args = { "cli", "spawn" }
      if newWindow then args[#args + 1] = "--new-window" end
      args[#args + 1] = "--cwd"
      args[#args + 1] = dir
      return args
    end,
    run = function(dir, shell, line, newWindow)
      local args = M.terminals.wezterm.open(dir, newWindow)
      for _, arg in ipairs({ "--", shell, "-lc", line }) do args[#args + 1] = arg end
      return args
    end,
    -- cli spawn reaches the GUI through its socket, and fails with no GUI
    -- running. Started through LaunchServices rather than as `wezterm start`
    -- in a task, which would make the GUI the task's child, ended when the
    -- extension stops.
    notRunning = {
      open = function(dir) return { "-na", "WezTerm", "--args", "start", "--cwd", dir } end,
      run = function(dir, shell, line)
        local args = M.terminals.wezterm.notRunning.open(dir)
        for _, arg in ipairs({ "--", shell, "-lc", line }) do args[#args + 1] = arg end
        return args
      end,
    } },
  kitty = { title = "kitty", tool = "kitty",
    open = function(dir) return { "--directory", dir } end,
    run = function(dir, shell, line) return { "--directory", dir, shell, "-lc", line } end },
  alacritty = { title = "Alacritty", tool = "alacritty",
    open = function(dir) return { "--working-directory", dir } end,
    run = function(dir, shell, line) return { "--working-directory", dir, "-e", shell, "-lc", line } end },
}

function M.extension(cl)
  local tools = cl.tools

  -- For another extension's command that runs in the terminal, as its
  -- `when`: unset while this one is off, since what it set goes with it.
  cl.setContext("terminalAvailable", true)

  tools.register("open",      { "/usr/bin/open" })
  tools.register("osascript", { "/usr/bin/osascript" })
  tools.register("wezterm",   { "/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm",
                                "/Applications/WezTerm.app/Contents/MacOS/wezterm" })
  tools.register("kitty",     { "/opt/homebrew/bin/kitty", "/usr/local/bin/kitty",
                                "/Applications/kitty.app/Contents/MacOS/kitty" })
  tools.register("alacritty", { "/opt/homebrew/bin/alacritty", "/usr/local/bin/alacritty",
                                "/Applications/Alacritty.app/Contents/MacOS/alacritty" })

  local function failed(what, detail)
    hs.alert.show("Failed: " .. what)
    cl.log.e(what .. " -> " .. tostring(detail))
  end

  -- The terminal chosen, and its binary; nil, having said so, when that
  -- one is not installed. Never another in its place.
  local function chosen()
    local name = cl.setting("terminal", "application")
    local terminal = M.terminals[name]
    if not terminal then
      failed("terminal", ("terminal.application %q is not a terminal"):format(tostring(name)))
      return nil
    end
    if not terminal.tool then return terminal end
    local bin = tools.path(terminal.tool)
    if not bin then
      hs.alert.show(terminal.title .. " is not installed")
      cl.log.w(("terminal.application is %q, which is not installed"):format(tostring(name)))
      return nil
    end
    return terminal, bin
  end

  local function folder(target, ctx)
    local dir = cl.resolve(target, ctx)
    if type(dir) == "table" then dir = dir.path end
    if type(dir) ~= "string" or dir == "" then dir = os.getenv("HOME") or "/" end
    return dir
  end

  local function start(what, bin, argv, succeeded)
    local task = tools.run(bin, argv, function(code, _, stderr)
      if code ~= 0 then failed(what, stderr) elseif succeeded then succeeded() end
    end)
    if not task then failed(what, "could not start " .. tostring(bin)) end
    return task
  end

  -- By bundle id: a lookup by name searches every window when it misses.
  local function running(terminal)
    local lookup = hs.application.applicationsForBundleID
    local found = lookup and lookup(terminal.bundleID)
    return found ~= nil and found[1] ~= nil
  end

  -- `how` is "open" or "run". cli spawn adds a window to WezTerm without
  -- activating it, so the app is brought forward once the binary succeeds.
  local function inTerminal(what, terminal, bin, how, ...)
    if terminal.notRunning and not running(terminal) then
      return start(what, tools.path("open") or "/usr/bin/open", terminal.notRunning[how](...))
    end
    local front = terminal.bundleID and function()
      hs.application.launchOrFocusByBundleID(terminal.bundleID)
    end
    return start(what, bin, terminal[how](...), front)
  end

  -- As shell.run takes `cmd`: a list is every element resolved and quoted,
  -- a string has every value substituted into it quoted.
  local function commandLine(cmd, ctx)
    if type(cmd) == "table" then
      local words = {}
      for i, element in ipairs(cmd) do words[i] = M.quote(cl.resolve(element, ctx)) end
      return table.concat(words, " ")
    end
    if type(cmd) ~= "string" then return nil end
    return cl.resolve(cmd, ctx, nil, M.quote)
  end

  local function shell()
    local configured = cl.setting("terminal", "shell")
    if type(configured) == "string" and configured ~= "" then return configured end
    return os.getenv("SHELL") or "/bin/zsh"
  end

  -- Straight to osascript rather than through applescript.run, which
  -- fills templates in its script again: a value substituted here that
  -- held ${...} would be filled in a second time, unquoted.
  local function inTerminalApp(what, dir, line, keepOpen)
    local typed = "cd " .. M.quote(dir) .. " && " .. line
    if keepOpen == false then typed = typed .. "\nexit" end
    local script = 'tell application "Terminal"\n  activate\n  do script '
                   .. M.appleScriptString(typed) .. "\nend tell"
    local task = tools.run(tools.path("osascript") or "/usr/bin/osascript", { "-e", script },
      function(code, _, stderr)
        if code == 0 then return end
        if M.refused(stderr) then
          hs.alert.show(M.AUTOMATION, 6)
          cl.log.e("Terminal refused " .. what .. " -> " .. tostring(stderr))
        else
          failed(what, stderr)
        end
      end)
    if not task then failed(what, "osascript did not start") end
    return task
  end

  return {
    displayName = "Terminal",
    description = "Open a folder, or run a command line, in the terminal you choose",
    menus       = {},

    settings = {
      application = { type = "string", default = "terminal",
        enum = { "terminal", "wezterm", "kitty", "alacritty" },
        enumDescriptions = {
          "Terminal.app; running a command needs Hammerspoon allowed to control it, "
            .. "in System Settings > Privacy & Security > Automation",
          "WezTerm: wezterm cli spawn while it runs, else started through open",
          "kitty",
          "Alacritty",
        },
        description = "The terminal a folder opens in and a command runs in" },
      shell = { type = "string", default = "",
        description = "The shell a command runs in, as a login shell; empty for $SHELL" },
    },

    commands = {
      { id = "terminal.open", title = "Open in terminal", menus = {},
        run = function(args, ctx)
          local terminal, bin = chosen()
          if not terminal then return end
          local dir = folder(args.target, ctx)
          if not terminal.tool then
            return start("Open in Terminal", tools.path("open") or "/usr/bin/open", { "-a", "Terminal", dir })
          end
          return inTerminal("Open in " .. terminal.title, terminal, bin, "open", dir, args.newWindow)
        end },

      -- `cmd` in the folder `target`. The window stays open once a command
      -- ends, on a login shell of its own, unless `keepOpen` is false: an
      -- interactive program is left by quitting it.
      { id = "terminal.run", title = "Run in terminal", menus = {},
        run = function(args, ctx)
          local line = commandLine(args.cmd, ctx)
          local what = args.title or "Run in terminal"
          if not line or line == "" then return failed(what, "no command line") end
          local terminal, bin = chosen()
          if not terminal then return end
          local dir = folder(args.target, ctx)
          if not terminal.tool then return inTerminalApp(what, dir, line, args.keepOpen) end

          local sh = shell()
          if args.keepOpen ~= false then line = line .. "\nexec " .. M.quote(sh) .. " -l" end
          return inTerminal(what, terminal, bin, "run", dir, sh, line, args.newWindow)
        end },
    },
  }
end

return M
