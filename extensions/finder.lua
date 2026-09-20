-- CommandLayer.spoon/extensions/finder.lua
-- What Finder has selected, as context.

local M = {}

-- A Finder that never answers would otherwise keep every later read waiting.
M.timeoutSeconds = 5

-- One path a line: every item selected, or the front window's folder when
-- nothing is. An alias list is coerced once, where asking Finder item by
-- item is an Apple Event each.
local script = [[
  tell application "Finder"
    set picked to (get selection) as alias list
    if (count of picked) is 0 then
      if not (exists window 1) then return ""
      return POSIX path of (target of front window as alias)
    end if
    set paths to {}
    repeat with f in picked
      set end of paths to POSIX path of (contents of f)
    end repeat
    set AppleScript's text item delimiters to linefeed
    return paths as text
  end tell
]]

local layer
local answer, answerText = {}, ""

-- finderSelectedFiles is unset rather than an empty list, which a `when`
-- would read as set.
local function fill(ctx, files)
  local sel = files[1] or ""
  local dir = sel
  if sel ~= "" and not sel:match("/$") then
    dir = sel:match("(.*/)") or sel
  end
  ctx.finderSelection     = sel
  ctx.finderSelectionDir  = dir
  ctx.finderSelectedFiles = files[1] and files or nil
end

function M.parse(stdout)
  local files = {}
  for line in tostring(stdout or ""):gmatch("[^\n]+") do files[#files + 1] = line end
  return files
end

-- Hammerspoon has one thread, and AppleScript run on it holds every hotkey
-- until Finder answers, so the read is a separate osascript process.
local function read()
  if M.task or not layer then return end

  local task
  task = layer.tools.run("/usr/bin/osascript", { "-e", script }, function(code, stdout)
    -- Terminated by the watchdog or by stop, which already let go of it.
    if M.task ~= task then return end
    M.task = nil
    if M.watchdog then
      M.watchdog.dispose()
      M.watchdog = nil
    end

    -- A failed read is no selection, not the last one: a stale path would
    -- aim file commands at something no longer selected.
    local files = M.parse(code == 0 and type(stdout) == "string" and stdout or "")
    local joined = table.concat(files, "\n")
    local changed = joined ~= answerText
    answer, answerText = files, joined

    -- Only the newest context is on screen, and only one built with Finder
    -- in front may carry its selection. It was filled with the answer before
    -- this one.
    local ctx = M.pendingCtx
    if ctx and ctx.frontmostApp == "Finder" and changed then
      fill(ctx, files)
      layer.refresh()
    end
  end)

  if not task then return end
  M.task = task

  M.watchdog = layer.after(M.timeoutSeconds, function()
    M.watchdog = nil
    if M.task == task then
      M.task = nil
      task:terminate()
    end
  end)
end

function M.forget()
  local task = M.task
  M.task = nil
  if task then task:terminate() end
  if M.watchdog then
    M.watchdog.dispose()
    M.watchdog = nil
  end
  M.pendingCtx = nil
  answer, answerText = {}, ""
end

M.stop = M.forget

function M.extension(cl)
  layer = cl
  return {
    name  = "finder",
    -- Reads frontmostApp, which ambient captures.
    after = { "ambient" },
    menus = {},

    capture = function(ctx)
      M.pendingCtx = ctx
      -- Only when Finder is frontmost, or a background window leaks file
      -- actions into every other app.
      if ctx.frontmostApp == "Finder" then
        fill(ctx, answer)
        read()
      else
        fill(ctx, {})
      end
    end,

    -- A file subject narrows the same fields, so an action written
    -- with ${finderSelection} works on any file row and not only on
    -- whatever Finder happens to have selected.
    scope = function(subject, scoped)
      if subject.path and (subject.kind == "file" or subject.kind == "project") then
        scoped.finderSelection     = subject.path
        scoped.finderSelectionDir  = subject.path:match("(.*/)") or subject.path
        scoped.finderSelectedFiles = { subject.path }
      end
    end,
  }
end

return M
