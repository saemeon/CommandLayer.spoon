-- An AppleScript, with values from the context filled in.
--
-- Run by /usr/bin/osascript in a process of its own, never hs.osascript:
-- that waits on Hammerspoon's one thread until the scripted app answers,
-- and an app that is busy, or putting up macOS's Automation prompt, can
-- take seconds.

local M = {}

-- The output as the script returned it: osascript ends it with a newline.
function M.output(stdout)
  return (tostring(stdout or ""):gsub("\r?\n$", ""))
end

function M.extension(cl)
  cl.tools.register("osascript", { "/usr/bin/osascript" })

  return {
    displayName = "AppleScript",
    description = "Run an AppleScript",
    menus       = {},

    commands = {
      -- `done(ok, output, stderr)`, for a caller in Lua that needs what the
      -- script returned; it comes once the process exits. A caller with
      -- `done` says what went wrong itself, so only a script run without
      -- one alerts.
      { id = "applescript.run", title = "Run AppleScript", menus = {},
        run = function(args, ctx)
          local done = type(args.done) == "function" and args.done or nil
          local script = cl.resolve(args.script, ctx)
          if type(script) ~= "string" or script == "" then
            if done then done(false, "", "no script") end
            return
          end

          local function failed(why)
            cl.log.e("AppleScript failed -> " .. tostring(why))
            if not done then hs.alert.show("AppleScript failed") end
          end

          local task = cl.tools.run(cl.tools.path("osascript") or "/usr/bin/osascript", { "-e", script },
            function(code, stdout, stderr)
              if code ~= 0 then failed(stderr) end
              if done then done(code == 0, M.output(stdout), stderr) end
            end)
          if not task then
            failed("osascript did not start")
            if done then done(false, "", "osascript did not start") end
          end
          return task
        end },
    },
  }
end

return M
