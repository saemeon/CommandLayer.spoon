-- Text in a place you choose -- a folder, or a single file -- searched with
-- ripgrep as you type; a hit opens in the editor at its line.

local M = {}

-- rg has no limit on the lines it prints in all, so head ends the listing and
-- rg with it. hs.task stops a search by sending TERM to zsh alone, which
-- passes it on: `wait` is interrupted by a signal, where a head in the
-- foreground would hold the trap back until it finished. rg's own exit is
-- passed on -- 1 for nothing found, 2 for an error -- unless rg ended by a
-- signal, which is the cut at the limit rather than a failure.
M.CAPPED = [[
limit=$1; shift
coproc "$@"
producer=$!
trap 'kill $producer 2>/dev/null; exit 143' TERM
head -n $limit <&p &
wait $!
kill $producer 2>/dev/null
wait $producer
code=$?
(( code > 128 )) && exit 0
exit $code
]]

-- How many of VS Code's recent folders are offered as places.
M.RECENT_FOLDERS = 5

local layer

local function whole(value, fallback)
  local n = tonumber(value)
  return n and n >= 1 and math.floor(n) or fallback
end

local function home()
  return os.getenv("HOME") or ""
end

local function expand(path)
  return (tostring(path):gsub("^~", home()))
end

local function bare(path)
  local out = tostring(path):gsub("/+$", "")
  return out == "" and "/" or out
end

function M.shorten(path)
  local base = home()
  path = bare(path)
  if base ~= "" and (path == base or path:sub(1, #base + 1) == base .. "/") then
    return "~" .. path:sub(#base + 1)
  end
  return path
end

-- The place "Search Text in…" gave the picker, as its subject. It is in the
-- context of that level alone, so closing the layer is what ends it.
function M.place(ctx)
  local subject = ctx and ctx.subject
  local place = type(subject) == "table" and subject.path
  if type(place) == "string" and place ~= "" then return place end
  return nil
end

-- A row saying why there is nothing to pick. alwaysShow, because the matcher
-- narrows a search's answer to rows holding what was typed.
local function notice(label, description)
  return { label = label, description = description, enabled = false, alwaysShow = true }
end

local function noPlace()
  return notice("Choose a place: Search Text in…",
                "Run it from the palette, or from cmd+k on a file or folder")
end

-- The dialog lets a file be chosen too: rg searches just that file.
local function choosePlace()
  local chosen = hs.dialog.chooseFileOrFolder("Search text in", home(), true, true, false)
  local path = chosen and (chosen["1"] or chosen[1]) or nil
  if type(path) ~= "string" then return nil end
  local kind = hs.fs.attributes(path, "mode") == "directory" and "folder" or "file"
  return { kind = kind, path = path }
end

-- What "Search Text in…" offers besides the rows it lists: grep.roots, the
-- folder Finder is showing, VS Code's recent local folders, then a dialog.
function M.places(ctx)
  local options, seen = {}, {}
  local function add(path, description)
    if type(path) ~= "string" or path == "" or seen[bare(path)] then return false end
    seen[bare(path)] = true
    options[#options + 1] = { label = M.shorten(path), description = description,
                              value = { kind = "folder", path = path } }
    return true
  end

  local set = layer.setting("grep", "roots")
  for _, root in ipairs(type(set) == "table" and set or {}) do
    if type(root) == "string" then add(expand(root), "grep.roots") end
  end
  add(ctx and ctx.finderSelectionDir, "Finder's folder")
  local vscode = layer.extension("vscode")
  local count = 0
  for _, project in ipairs(vscode and vscode.recentProjects() or {}) do
    if count >= M.RECENT_FOLDERS then break end
    if not project.remote and not project.workspace and add(project.path, "Recent in VS Code") then
      count = count + 1
    end
  end
  options[#options + 1] = { label = "Choose…", description = "Pick a folder or a file", value = choosePlace }
  return options
end

-- --with-filename: given a single file, rg leaves the path out.
function M.argv(query, place, rg)
  return {
    "-f", "-c", M.CAPPED, "zsh", tostring(whole(layer.setting("grep", "maxResults"), 200)),
    rg, "--max-count", tostring(whole(layer.setting("grep", "maxPerFile"), 5)),
    "--max-columns", tostring(whole(layer.setting("grep", "maxColumns"), 200)), "--max-columns-preview",
    "--line-number", "--with-filename", "--no-heading", "--null", "--color", "never",
    "--smart-case", "--fixed-strings", "--", query, place,
  }
end

-- A hit's path within the place searched; a place that is a file is the
-- hit's own path.
local function within(path, place)
  if path == place then return path:match("([^/]+)$") or path end
  local base = place:gsub("/$", "") .. "/"
  if path:sub(1, #base) == base then return path:sub(#base + 1) end
  return path
end

-- rg --null ends a path with a NUL, so a colon in a file name cannot be
-- taken for the one before the line number.
function M.rows(stdout, place, ctx)
  local limit = whole(layer.setting("grep", "maxResults"), 200)
  local rows = {}
  for line in tostring(stdout or ""):gmatch("[^\n]+") do
    if #rows >= limit then break end
    local path, number, text = line:match("^(.-)\0(%d+):(.*)$")
    if path then
      local shown = text:gsub("^%s+", ""):gsub("%s+$", "")
      rows[#rows + 1] = {
        label       = shown ~= "" and shown or (path:match("([^/]+)$") or path),
        description = within(path, place) .. ":" .. number,
        detail      = M.shorten(place),
        command     = "editor.open",
        args        = { target = path, line = tonumber(number) },
        subject     = { kind = "file", path = path },
        ctx         = ctx,
      }
    end
  end
  return rows
end

-- What rg's exit means: 0 found (or cut at the limit), 1 nothing found, and
-- anything else a failure, whose hits, if any, are still worth showing.
function M.answer(code, stdout, stderr, place, ctx)
  local rows = M.rows(stdout, place, ctx)
  if code ~= 0 and code ~= 1 then
    local err = tostring(stderr or "")
    local why = err:match("^%s*([^\n]-)%s*\n") or err:match("^%s*(.-)%s*$")
    if why == "" then why = "rg exited with " .. tostring(code) end
    layer.log.w("grep in " .. M.shorten(place) .. " -> exit " .. tostring(code) .. ": " .. why)
    rows[#rows + 1] = notice(why, "Searching " .. M.shorten(place) .. " failed")
  elseif #rows == 0 then
    rows[1] = notice("No results in " .. M.shorten(place))
  end
  return rows
end

function M.extension(cl)
  layer = cl

  cl.tools.register("rg", { "/opt/homebrew/bin/rg", "/usr/local/bin/rg" })
  cl.tools.register("zsh", { "/bin/zsh" })

  return {
    name        = "grep",
    displayName = "Text search",
    description = "Text in a folder or a file, searched with ripgrep as you type",
    menus       = { "grep" },
    extensionDependencies = { "editor" },
    optionalExtensionDependencies = { "vscode" },

    settings = {
      roots = { type = "array", default = {},
        description = "Folders Search Text in… offers first" },
      maxResults = { type = "integer", default = 200,
        description = "At most this many lines found, in all" },
      maxPerFile = { type = "integer", default = 5,
        description = "At most this many lines found in one file" },
      maxColumns = { type = "integer", default = 200,
        description = "A longer line found is shown cut to this many characters" },
    },

    commands = {
      { id = "grep.searchIn", title = "Search Text in…", category = "Text search", icon = "$(search)",
        menus = { "commandPalette" },
        inputs = { {
          id = "target", description = "Search text in",
          picker = {
            when = "viewItem == 'file' || viewItem == 'folder' || viewItem == 'project'",
            menus = { "files", "recent" },
            options = M.places,
          },
          preferCurrent = true,
          current = function(ctx)
            local selection = ctx and ctx.finderSelection
            if selection and selection ~= "" then return { kind = "file", path = selection } end
          end,
        } },
        run = function(args, ctx)
          local target = args.target
          if type(target) ~= "table" or type(target.path) ~= "string" then return end
          cl.executeCommand("quickOpen", { view = "grep", subject = target, label = M.shorten(target.path) }, ctx)
        end },
    },

    -- What the picker shows before anything is typed: where it will search.
    items = function(ctx)
      local place = M.place(ctx)
      if not place then return { noPlace() } end
      return { notice("Search text in " .. M.shorten(place), "Type to search") }
    end,

    -- Returns how to stop it: the kernel stops a search when a newer query
    -- arrives, and its answer is then no longer wanted.
    search = function(query, ctx, done)
      local place = M.place(ctx)
      if not place then
        done({ noPlace() })
        return
      end

      local rg, zsh = cl.tools.path("rg"), cl.tools.path("zsh")
      if not rg or not zsh then
        done({ notice("ripgrep is not installed", "Text search runs rg: brew install ripgrep") })
        return
      end

      local stopped = false
      local task = cl.tools.run(zsh, M.argv(query, place, rg), function(code, stdout, stderr)
        if not stopped then done(M.answer(code, stdout, stderr, place, ctx)) end
      end)
      if not task then
        done({ notice("Could not start rg", "Searching " .. M.shorten(place)) })
        return
      end
      return function()
        stopped = true
        task:terminate()
      end
    end,
  }
end

return M
