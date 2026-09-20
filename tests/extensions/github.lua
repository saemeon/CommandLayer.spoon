-- CommandLayer.spoon/tests/extensions/github.lua
-- The github extension's checks.

local T = ...
local check = T.check
local cl = T.layer({ ["github.enabled"] = true })


do
  local ext
  for _, e in ipairs(cl.extensions) do
    if e.name == "github" then ext = e end
  end
  if not ext then return check("github extension is registered", false) end

  local asked = {}
  local saved = { new = hs.task.new, path = cl.tools.path, settings = cl.userSettings,
                  decode = hs.json.decode }
  cl.tools.path = function(name)
    if name == "gh" then return "/fake/gh" end
    return saved.path(name)
  end
  -- Only gh's: an answer landing redraws the picker, whose other rows start
  -- tasks of their own.
  hs.task.new = function(program, done, _, args)
    if program == "/fake/gh" then asked[#asked + 1] = { args = args, done = done } end
    return { start = function(t) return t end, terminate = function() end,
             setInput = function() end, closeInput = function() end }
  end
  hs.json.decode = function(text) return load("return " .. text)() end
  cl.stopRunning("github")
  cl.userSettings = { ["github.issues"] = false }

  local before = ext.items({})
  local lists = {}
  local first = {}
  for i, a in ipairs(asked) do
    first[i] = a
    lists[#lists + 1] = a.args[1] .. " " .. a.args[2]
  end
  for _, a in ipairs(first) do
    if a.args[1] == "repo" then
      a.done(0, [[{ { nameWithOwner = "a/b", description = "", url = "https://github.com/a/b" } }]], "")
    else
      a.done(0, [[{ { title = "Fix", url = "https://github.com/a/b/pull/7",
                      repository = { nameWithOwner = "a/b" }, number = 7 } }]], "")
    end
  end
  local rows = ext.items({})
  local again = #asked

  cl.userSettings = saved.settings
  hs.task.new, cl.tools.path, hs.json.decode = saved.new, saved.path, saved.decode
  cl.stopRunning("github")

  check("gh is asked once for each list switched on, and its answers are rows that open them",
        #before == 0 and table.concat(lists, ", ") == "repo list, search prs" and again == 2
        and #rows == 2 and rows[1].label == "a/b" and rows[1].command == "system.open"
        and rows[1].args.target == "https://github.com/a/b"
        and rows[2].description == "Pull request -- a/b #7",
        ("%s / %d before, %d asks, %d rows: %s %s %s / %s"):format(table.concat(lists, ", "),
          #before, again, #rows, tostring(rows[1] and rows[1].label),
          tostring(rows[1] and rows[1].command), tostring(rows[1] and rows[1].args and rows[1].args.target),
          tostring(rows[2] and rows[2].description)))
end
