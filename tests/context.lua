-- CommandLayer.spoon/tests/context.lua
-- The context: templates, capture, subjects, arguments, gather.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local logged = T.logged
local coreSource = T.coreSource

group("resolve")
local ctx = { finderSelection = "/tmp/a.txt", clipboard = "x", frontmostApp = "Finder" }
check("substitutes a context field",
      cl.resolve("open ${finderSelection}", ctx) == "open /tmp/a.txt")
check("unknown field becomes empty",
      cl.resolve("x${nope}y", ctx) == "xy")
check("captures fill in",
      cl.resolve("issue $1", ctx, { "42" }) == "issue 42")
check("non-string passes through",
      cl.resolve(true, ctx) == true)

check("templates take VS Code's ${input:}, ${config:} and ${env:} variables", (function()
        local out = {
          cl.resolve("${input:repo}", { repo = "foo/bar" }),
          cl.resolve("${config:browser.tabOrder}", {}),
          cl.resolve("${env:HOME}", {}),
          cl.resolve("${config:nope.nothing}|${input:missing}", {}),
        }
        return out[1] == "foo/bar" and out[2] == cl.setting("browser", "tabOrder") and out[2] ~= ""
               and out[3] == os.getenv("HOME") and out[4] == "|",
               table.concat(out, " , ")
      end)())

group("context capture")
check("an extension contributed the frontmost app and the clipboard",
      (function()
        local c = cl.buildContext()
        return type(c.frontmostApp) == "string"
               and type(c.clipboard) == "string"
      end)())
check("an extension contributed the Finder selection", (function()
        return cl.buildContext().finderSelection ~= nil
      end)())
check("and another the focused window", (function()
        return cl.buildContext().focusedWindow ~= nil
      end)())

group("subject context")
local scoped = cl.subjectContext({ kind = "file", path = "/tmp/b.txt" }, ctx)
check("a file subject rewrites finderSelection",
      scoped.finderSelection == "/tmp/b.txt")
check("and inherits everything else",
      scoped.frontmostApp == "Finder")
check("the original is untouched",
      ctx.finderSelection == "/tmp/a.txt")

group("argument context")
local withArgs = cl.argContext(ctx, { query = "hello" })
check("arguments become fields", withArgs.query == "hello")
check("context still reachable", withArgs.frontmostApp == "Finder")
check("its keys are listed with the ones it reads through, sorted and once each", (function()
        local deeper = cl.argContext(withArgs, { activeView = "palette", query = "typed" })
        local keys = cl.contextKeys(deeper)
        local found, queries = {}, 0
        for _, key in ipairs(keys) do
          found[key] = true
          if key == "query" then queries = queries + 1 end
        end
        local sorted = true
        for i = 2, #keys do if keys[i] < keys[i - 1] then sorted = false end end
        return sorted and queries == 1 and found.activeView and found.query
               and found.frontmostApp and found.finderSelection,
               table.concat(keys, ", ")
      end)())

group("gather")

local gatherMark = #logged
local rows = cl.gather(ctx, { menus = { "root" } })
check("root returns rows", #rows > 0, tostring(#rows) .. " rows")

local shaped, unshaped = 0, 0
for _, row in ipairs(rows) do
  if type(row.label) == "string" and row.label ~= "" then shaped = shaped + 1
  else unshaped = unshaped + 1 end
end
check("every row has text", unshaped == 0,
      tostring(unshaped) .. " rows without text")

local runnable = 0
for _, row in ipairs(rows) do
  if type(row.run) == "function" or type(row.command) == "string" then
    runnable = runnable + 1
  end
end
check("rows carry something to run", runnable > 0,
      tostring(runnable) .. "/" .. tostring(#rows))

check("no extension threw while gathering", #logged == gatherMark,
      logged[gatherMark + 1] or "")

-- The kernel's claim is that it knows nothing about the world. If it
-- seeds even one field, an extension replacing that source has to
-- fight a default it cannot see.
check("the kernel seeds no context field", (function()
        local src = coreSource("extensions") or ""
        local body = src:match("local function buildContext%(%)(.-)\nend")
        if not body then return false, "buildContext not found" end
        return body:find("frontmostApp") == nil
               and body:find("pasteboard") == nil, body:gsub("%s+", " ")
      end)())

check("a list in a template is a line per item, or each item encoded and spaced", (function()
        local listed = { files = { "/a b/c.txt", "/d.txt" } }
        local plain = cl.resolve("${files}", listed)
        local quoted = cl.resolve("ls ${files}", listed, nil, function(s) return "'" .. s .. "'" end)
        return plain == "/a b/c.txt\n/d.txt" and quoted == "ls '/a b/c.txt' '/d.txt'", plain .. " | " .. quoted
      end)())
