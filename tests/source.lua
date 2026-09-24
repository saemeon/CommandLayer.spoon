-- CommandLayer.spoon/tests/source.lua
-- Claims about the code itself, read from the source.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()
local noop = T.noop

local coreSource = T.coreSource
local coreFiles = T.coreFiles
local sourceFiles = T.sourceFiles
local readSource = T.readSource
local SOURCE = T.SOURCE
local pluginCode = T.pluginCode
local eachCodeLine = T.eachCodeLine
local writesField = T.writesField

group("source")
-- A timer nobody holds can be collected before it fires: the windows list
-- once came up empty after a reload that way.
check("every timer the layer starts is held", (function()
        local unheld = {}
        for _, path in ipairs(sourceFiles(SOURCE)) do
          do
            local n = 0
            for line in (readSource(path) .. "\n"):gmatch("(.-)\n") do
              n = n + 1
              for start in line:gmatch("()hs%.timer%.do%a+%(") do
                local before = line:sub(1, start - 1):gsub("%s+$", "")
                if not (before:match("[^=<>~]=$") or before:match("return$") or before:match("[%(,]$")) then
                  unheld[#unheld + 1] = path .. ":" .. n
                end
              end
            end
          end
        end
        return #unheld == 0, table.concat(unheld, ", ")
      end)())

-- hs.application.get searches every window's title when a name matches no
-- running app: close to a second, and it froze cmd+r once.
check("nothing looks an app up through hs.application.get", (function()
        local found = {}
        for _, path in ipairs(sourceFiles(SOURCE)) do
          if readSource(path):find("hs%.application%.get%(") then
            found[#found + 1] = path
          end
        end
        return #found == 0, table.concat(found, ", ")
      end)())

check("no extension starts a timer of its own, where stopping it would not stop it", (function()
        local found = {}
        for _, file in ipairs(pluginCode({ "extensions" })) do
          eachCodeLine(file, function(code, n)
            if code:find("hs%.timer%.do") then found[#found + 1] = file.path .. ":" .. n end
          end)
        end
        return #found == 0, table.concat(found, ", ")
      end)())

check("no extension declares order: before and after say where it runs", (function()
        local found = {}
        for _, file in ipairs(pluginCode({ "extensions" })) do
          eachCodeLine(file, function(code, n, isLocal)
            if not isLocal and writesField(code, "order") then found[#found + 1] = file.path .. ":" .. n end
          end)
        end
        return #found == 0, table.concat(found, ", ")
      end)())

-- What is written with those names and is not a row: system.copy's text, a
-- snippet's own record, a canvas element, a parameter trimmed in place, an
-- extension's exports.
local NOT_ROWS = {
  text   = { "args", "executeCommand", "text%s*=%s*row%.phrase", "text%s*=%s*body",
             "text%s*=%s*hs%.styledtext", "text%s*=%s*tostring%(text" },
  action = { "exports" },
}

check("no extension writes a row's old names", (function()
        local found = {}
        for _, file in ipairs(pluginCode({ "extensions" })) do
          eachCodeLine(file, function(code, n, isLocal)
            if isLocal then return end
            local names = {}
            if code:find("commandId") then names[#names + 1] = "commandId" end
            for _, name in ipairs({ "text", "subText", "image", "action" }) do
              local exempt = false
              for _, pattern in ipairs(NOT_ROWS[name] or {}) do
                if code:find(pattern) then exempt = true end
              end
              if not exempt and writesField(code, name) then names[#names + 1] = name end
            end
            if #names > 0 then
              found[#found + 1] = file.path .. ":" .. n .. " " .. table.concat(names, "/")
            end
          end)
        end
        return #found == 0, table.concat(found, ", ")
      end)())

-- An input names its picker, or the command answering it. The schema check's
-- own fixture writes the old names on purpose, to see them refused, and the
-- tasks extension reads them in VS Code's tasks.json, where they are the names.
local OLD_INPUT_TYPES = { "pickItem", "pickString", "promptString", "search", "command" }
local READS_TASKS_JSON = { ["extensions/tasks.lua"] = true }

check("no extension or check writes an input's old type", (function()
        local found = {}
        local files = pluginCode({ "extensions" })
        for _, path in ipairs(sourceFiles({ "tests", "tests/extensions" })) do
          if path ~= "tests/schema.lua" then files[#files + 1] = { path = path, text = readSource(path) } end
        end
        for _, file in ipairs(files) do
          if not READS_TASKS_JSON[file.path] then
            eachCodeLine(file, function(code, n)
              for _, name in ipairs(OLD_INPUT_TYPES) do
                if code:find("type%s*=+%s*[\"']" .. name .. "[\"']") then
                  found[#found + 1] = file.path .. ":" .. n .. " " .. name
                end
              end
            end)
          end
        end
        return #found == 0, table.concat(found, ", ")
      end)())

-- Hammerspoon has one thread, and a plugin's code runs on the picker path:
-- a call that waits for a process or a script freezes the launcher while it
-- waits. These wait. Known debt, by file; anything else goes through
-- tools.run. An entry here that no longer calls is taken out.
local WAITING_CALLS = { "hs%.execute%f[^%w_]", "hs%.osascript%.%a+", "io%.popen%f[^%w_]", "os%.execute%f[^%w_]" }
local KNOWN_WAITING = {}

check("no plugin waits for a process or a script, but the known debt", (function()
        local found, seen = {}, {}
        for _, file in ipairs(pluginCode({ "extensions", "presenters", "matchers", "rankers" })) do
          eachCodeLine(file, function(code, n)
            for _, pattern in ipairs(WAITING_CALLS) do
              for call in code:gmatch("(" .. pattern .. ")") do
                local key = file.path .. " " .. call
                seen[key] = true
                if not KNOWN_WAITING[key] then found[#found + 1] = file.path .. ":" .. n .. " " .. call end
              end
            end
          end)
        end
        for key in pairs(KNOWN_WAITING) do
          if not seen[key] then found[#found + 1] = key .. " no longer waits: take it out of the list" end
        end
        table.sort(found)
        return #found == 0, table.concat(found, ", ")
      end)())

check("nothing in core/ runs a shell through os.execute", (function()
        local found = {}
        for _, path in ipairs(sourceFiles({ "core" })) do
          if readSource(path):find("os%.execute%(") then found[#found + 1] = path end
        end
        return #found == 0, table.concat(found, ", ")
      end)())

-- A print has no level, so logLevel cannot quiet it nor the console filter it.
check("nothing logs through print: every line goes through the layer's logger", (function()
        local found = {}
        for _, path in ipairs(sourceFiles(SOURCE)) do
          local n = 0
          for line in (readSource(path) .. "\n"):gmatch("(.-)\n") do
            n = n + 1
            if line:find("^%s*print%(") or line:find("[^%w_\"'%.]print%(") then
              found[#found + 1] = path .. ":" .. n
            end
          end
        end
        return #found == 0, table.concat(found, ", ")
      end)())

check("a hook that fails logs an error, a mistake found a warning", (function()
        cl.register({ name = "test-loglevel", menus = { "commandPalette" },
                      items = function() error("boom") end })
        cl.gather(cl.buildContext(), { menus = { "commandPalette" } })
        local failed = cl.log.lastLevel
        cl.unregisterExtension("test-loglevel")
        cl.executeCommand("no.such.loglevel")
        local mistake = cl.log.lastLevel
        return failed == "error" and mistake == "warning", tostring(failed) .. " / " .. tostring(mistake)
      end)())

-- A pipe Hammerspoon writes into raises SIGPIPE once its reader has gone --
-- fzf or bc terminated for a newer query -- and Hammerspoon dies of it.
check("nothing writes into a process's stdin: tools.run hands input over as a file", (function()
        local found = {}
        for _, file in ipairs(pluginCode(SOURCE)) do
          eachCodeLine(file, function(code, n)
            if code:find("%f[%w_]setInput%f[^%w_]") or code:find("%f[%w_]closeInput%f[^%w_]") then
              found[#found + 1] = file.path .. ":" .. n
            end
          end)
        end
        return #found == 0, table.concat(found, ", ")
      end)())

-- A task with no streaming callback never drains its pipes, so a child
-- writing more than the pipe buffer never exits: the browser's history
-- refresh hung that way. Every process goes through tools.run, which streams.
check("nothing starts a process but tools.run", (function()
        local found = {}
        for _, path in ipairs(sourceFiles(SOURCE)) do
          if path ~= "core/tools.lua" and readSource(path):find("hs%.task%.new%(") then
            found[#found + 1] = path
          end
        end
        return #found == 0, table.concat(found, ", ")
      end)())

do
  local savedNew = hs.task.new
  local made, startAnswer = {}, nil
  hs.task.new = function(program, complete, stream, args)
    local t = { program = program, complete = complete, stream = stream, args = args, calls = {} }
    function t:setInput(text) t.calls[#t.calls + 1] = "setInput"; t.input = text; return self end
    function t:closeInput() t.calls[#t.calls + 1] = "closeInput"; return self end
    function t:start()
      t.calls[#t.calls + 1] = "start"
      if startAnswer == false then return false end
      return self
    end
    function t:terminate() t.terminated = true; return self end
    made[#made + 1] = t
    return t
  end
  local function streamed(t, stdout, stderr)
    return t.stream and t.stream(t, stdout, stderr)
  end

  local heard = {}
  local task = cl.tools.run("/fake/tool", { "a" }, function(code, stdout, stderr)
    heard[#heard + 1] = { code = code, stdout = stdout, stderr = stderr }
  end)
  local t = made[#made]
  local held = task ~= nil and cl.tools.running[task] == true
  local kept = streamed(t, "first ", "") == true
  streamed(t, "second ", "warn 1 ")
  streamed(t, "", "warn 2 ")
  t.complete(0, "last", "warn 3")
  check("tools.run gives done every streamed chunk and the final one, whole",
        #heard == 1 and heard[1].code == 0 and heard[1].stdout == "first second last" and kept,
        heard[1] and heard[1].stdout)
  check("and stderr the same way",
        heard[1] ~= nil and heard[1].stderr == "warn 1 warn 2 warn 3", heard[1] and heard[1].stderr)
  check("the task is held until it exits, and let go after",
        held and cl.tools.running[task] == nil)

  local function contents(path)
    local handle = type(path) == "string" and io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("a")
    handle:close()
    return text
  end
  local function shellQuoted(value) return "'" .. value:gsub("'", "'\\''") .. "'" end

  local spans, savedSpan = {}, cl.span
  cl.span = function(name, ...)
    spans[#spans + 1] = name
    return savedSpan(name, ...)
  end
  local awkward = "one 'two' \"three\" $HOME `id` \\ ;|&\n\tfour"
  local fedHandle = cl.tools.run("/fake/fzf", { "--filter", "x y" }, function() end, { input = awkward })
  cl.span = savedSpan
  local fed = made[#made]
  local fedFile = fed.args[4]
  local tmp = os.getenv("TMPDIR")
  check("input goes to a file a shell redirects into the program, each value an argument of its own",
        fed.program == "/bin/sh" and fed.args[1] == "-c" and fed.args[2] == cl.tools.INPUT_SCRIPT
        and fed.args[3] == "sh" and fed.args[5] == "/fake/fzf" and fed.args[6] == "--filter"
        and fed.args[7] == "x y" and #fed.args == 7 and type(fedFile) == "string"
        and (not tmp or fedFile:find(tmp:gsub("/$", "") .. "/commandlayer/", 1, true) == 1),
        fed.program .. " " .. table.concat(fed.args, " | "))
  check("the file holds the input, nothing is written to the task's stdin, and the span names the program",
        contents(fedFile) == awkward and table.concat(fed.calls, " ") == "start"
        and spans[#spans] == "task.fzf",
        table.concat(fed.calls, " ") .. " / " .. tostring(spans[#spans]))
  local heldWhileRunning = fedHandle ~= nil and cl.tools.running[fed] == true
  fed.complete(0, "", "")
  check("the input file is removed once the task exits, and the task let go",
        heldWhileRunning and contents(fedFile) == nil and cl.tools.running[fed] == nil, tostring(fedFile))

  local stopped = cl.tools.run("/fake/bc", { "-l" }, function() end, { input = "1+1\n" })
  local stoppedTask = made[#made]
  local stoppedFile = stoppedTask.args[4]
  local presentBefore = contents(stoppedFile) == "1+1\n"
  local answered = stopped and stopped:terminate()
  check("terminating a task with input removes its file at once and terminates the task",
        presentBefore and contents(stoppedFile) == nil and stoppedTask.terminated == true and answered == stopped,
        tostring(stoppedFile))
  stoppedTask.complete(15, "", "")

  -- The argv run for real, outside Hammerspoon: a program path, arguments and
  -- input holding spaces, quotes, $ and backquotes must all arrive as written.
  do
    local folder = (tmp or "/tmp"):gsub("/$", "") .. "/commandlayer/prog dir 'q' $x"
    local program = folder .. '/my "sh"'
    T.popen(("mkdir -p %s && ln -sf /bin/sh %s"):format(shellQuoted(folder), shellQuoted(program)))
    local text = "line 'one' \"two\" $HOME `id` \\ ;|&\n\tlast"
    cl.tools.run(program, { "-c", 'printf "%s|" "$@"; cat', "zero", "a b", "'q'", "$HOME", "`id`" },
                 function() end, { input = text })
    local real = made[#made]
    local words = { shellQuoted(real.program) }
    for i, value in ipairs(real.args) do words[i + 1] = shellQuoted(value) end
    local output = T.popen(table.concat(words, " "))
    real.complete(0, "", "")
    T.popen(("rm -f %s && rmdir %s"):format(shellQuoted(program), shellQuoted(folder)))
    check("that argv, run by a real shell, hands the program its arguments and the input as written",
          output == "a b|'q'|$HOME|`id`|" .. text, output)
  end

  -- fzf and bc are the callers with input; each still gets it through the file.
  do
    local fzf
    for _, m in ipairs(cl.matchers) do
      if m.name == "fzf" then fzf = m.match end
    end
    local savedPath = cl.tools.path
    cl.tools.path = function(name) return name == "fzf" and "/fake/fzf" or savedPath(name) end
    local got
    local items = { { label = "Tab" }, { label = "Other" } }
    local taken = fzf and fzf(items, "tab", function() end)
    local first = made[#made]
    local firstFile = first.args[4]
    local sent = contents(firstFile)
    if fzf then fzf(items, "ta", function(rows) got = rows end) end
    local second = made[#made]
    local firstGone = contents(firstFile) == nil and first.terminated == true
    second.complete(0, "1\tTab\t\n", "")
    first.complete(15, "", "")
    cl.tools.path = savedPath
    check("fzf's rows reach it through a file, and a newer query removes the older one's",
          taken == true and first.program == "/bin/sh" and first.args[5] == "/fake/fzf"
          and first.args[6] == "--filter=tab" and sent == "1\tTab\t\n2\tOther\t" and firstGone
          and contents(second.args[4]) == nil and got ~= nil and got[1] == items[1],
          tostring(sent))
  end

  startAnswer = false
  local failedDone = 0
  local refused = cl.tools.run("/fake/refused", {}, function() failedDone = failedDone + 1 end)
  local notStarted = made[#made]
  notStarted.complete(1, "", "")
  streamed(notStarted, "late", "")
  startAnswer = nil
  local twice = 0
  cl.tools.run("/fake/twice", {}, function() twice = twice + 1 end)
  made[#made].complete(0, "", "")
  made[#made].complete(0, "", "")
  check("a task that does not start gives nil, is not held, and done is never called twice",
        refused == nil and cl.tools.running[notStarted] == nil and failedDone <= 1 and twice == 1,
        ("%s, %d and %d calls"):format(tostring(refused), failedDone, twice))

  -- sqlite3's JSON for a long history arrives in several chunks; the
  -- refresh has to finish with all of them.
  local browser = cl.modules.browser
  if browser and browser.refreshHistory then
    local saved = { attributes = hs.fs.attributes, doAfter = hs.timer.doAfter,
                    decode = hs.json.decode, profiles = browser.profiles }
    hs.fs.attributes = function(path)
      return path:find("CommandLayerStreamTest/", 1, true) and { mode = "file" } or nil
    end
    hs.timer.doAfter = function() return { stop = noop } end
    local decoded
    hs.json.decode = function(text) decoded = text; return {} end
    browser.profiles = { { name = "Streamed", dir = "CommandLayerStreamTest/One" } }
    made = {}
    local finished
    browser.refreshHistory("/usr/bin/sqlite3", function(items) finished = items end)
    local copy = made[1]
    if copy then copy.complete(0, "", "") end
    local query = made[2]
    local whole = '[{"url":"https://a.example","title":"A"},{"url":"https://b.example","title":"B"}]'
    if query then
      streamed(query, whole:sub(1, 20), "")
      streamed(query, whole:sub(21, 50), "")
      query.complete(0, whole:sub(51), "")
    end
    check("the browser's history refresh finishes when sqlite3 answers in streamed chunks",
          query ~= nil and query.program == "/usr/bin/sqlite3" and finished ~= nil and decoded == whole,
          tostring(decoded))
    hs.fs.attributes, hs.timer.doAfter = saved.attributes, saved.doAfter
    hs.json.decode, browser.profiles = saved.decode, saved.profiles
    browser.forget()
  end
  hs.task.new = savedNew
end

check("nothing in core/ reaches for hs.chooser", (function()
        for _, name in ipairs(coreFiles()) do
          if coreSource(name):find("hs.chooser", 1, true) then
            return false, "core/" .. name .. ".lua"
          end
        end
        return true
      end)())

-- Undefined globals, unused locals and shadowing, as .luacheckrc says. Only
-- where luacheck is installed: the kernel needs nothing installed, and
-- neither does its harness.
do
  local lua = arg and arg[-1] or "lua"
  local handle = io.popen(("cd %q && %q tests/luacheck.lua --no-color --formatter plain --codes . 2>&1; echo \"exit $?\"")
                          :format(T.dir, lua))
  local out = handle:read("a")
  handle:close()
  local code = tonumber(out:match("exit (%d+)%s*$"))
  if code == 3 then
    print("  --   luacheck is not installed, so it was not run")
  else
    check("luacheck finds nothing", code == 0, (out:gsub("\n?exit %d+%s*$", ""):gsub("\n", " | ")))
  end
end
