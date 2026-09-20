-- CommandLayer.spoon/tests/extensions/url.lua
-- The URL extension's checks.

local T = ...
local check, stub = T.check, T.stub
local cl = T.layer()
stub(cl.tools.paths, "open", "/usr/bin/open")
local M = cl.modules.url

for input, want in pairs({
  ["https://example.com"] = "https://example.com",
  ["  http://localhost:8080/a?b=c  "] = "http://localhost:8080/a?b=c",
  ["vscode://file/Users/me/x.lua"] = "vscode://file/Users/me/x.lua",
  ["file:///Users/me/notes.txt"] = "file:///Users/me/notes.txt",
  ["www.example.com"] = "https://www.example.com",
  ["github.com/owner/repo"] = "https://github.com/owner/repo",
  ["https://x.com/${clipboard}"] = "https://x.com/$%7Bclipboard%7D",
}) do
  check(("%q is a URL"):format(input), M.parse(input) == want, tostring(M.parse(input)))
end
for _, input in ipairs({
  "safari", "readme.md", "init.lua", "2+2", "10.5", "", "http://", "https:// x.com",
  "hello world.com/x", "localhost:8080", "www.", "12:30",
}) do
  check(("%q is not a URL"):format(input), M.parse(input) == nil, tostring(M.parse(input)))
end

local ctx = cl.buildContext()
local function urlRows(query, context)
  local out = {}
  for _, row in ipairs(cl.queryItems(context or ctx, query)) do
    if type(row.subject) == "table" and row.subject.kind == "url" then out[#out + 1] = row end
  end
  return out
end

local rows = urlRows("github.com/owner/repo")
check("a typed URL is one row that opens it, carrying a url subject; other text makes none",
      #rows == 1 and #urlRows("safari") == 0 and rows[1].command == "system.open"
      and rows[1].args.target == "https://github.com/owner/repo"
      and rows[1].subject.value == "https://github.com/owner/repo",
      rows[1] and tostring(rows[1].args and rows[1].args.target))

local verbs, copies = {}, 0
for _, row in ipairs(rows[1] and cl.itemActions(rows[1].subject, ctx) or {}) do
  verbs[row.command] = true
  if tostring(row.label):find("Copy", 1, true) then copies = copies + 1 end
end
check("cmd+k on it offers the link verbs that already exist: Open with…, Copy URL, Open in browser, Clone",
      verbs["system.openWith"] and verbs["browser.copyURL"] and verbs["browser.openInBrowser"]
      and verbs["git.cloneRepository"] and copies == 1,
      ("%d copies"):format(copies))

local opened = {}
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = args or {}, done = done }
  function t.start(self) return self end
  function t.terminate() end
  if program == "/usr/bin/open" then opened[#opened + 1] = t end
  return t
end)
local secret = { clipboard = "SECRET" }
local typed = urlRows("https://x.com/${clipboard}", secret)[1]
if typed then cl.executeCommand(typed.command, typed.args, secret) end
local target = opened[1] and opened[1].args[#opened[1].args]
check("picking it opens the address as typed, never filled in as a template",
      target == "https://x.com/$%7Bclipboard%7D", tostring(target))

-- Measured as the kernel measures every keystroke: the query.url span.
do
  stub(cl, "clock", function() return os.clock() * 1000 end)
  local function perKeystroke(query)
    local before = cl.performance()["query.url"] or { total = 0, count = 0 }
    local total, count = before.total, before.count
    for _ = 1, 2000 do cl.queryItems(ctx, query) end
    local after = cl.performance()["query.url"]
    return (after.total - total) / (after.count - count)
  end
  local plain, url = perKeystroke("visual studio code"), perKeystroke("https://github.com/owner/repo")
  check("the gate keeps a keystroke's URL check to microseconds",
        plain < 0.01 and url < 0.05, ("%.5f ms for text, %.5f ms for a URL"):format(plain, url))
end
