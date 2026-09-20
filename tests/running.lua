-- CommandLayer.spoon/tests/running.lua
-- How a thing runs: the webview and shell commands.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()

local noop = T.noop


group("webview backend")
do
  local made = {}
  local saved = { webview = hs.webview, doAfter = hs.timer.doAfter,
                  mainScreen = hs.screen.mainScreen,
                  frontmostWindow = hs.window.frontmostWindow, focus = hs.focus }
  local focused = {}
  local where = { focus = function(self) focused[#focused + 1] = self end }

  hs.webview = { new = function(frame, _, content)
    local w = { frame = frame, content = content, calls = {} }
    for _, name in ipairs({ "windowStyle", "closeOnEscape", "deleteOnClose",
                            "allowTextEntry", "html", "url", "show" }) do
      w[name] = function(_, value) w.calls[name] = value; return w end
    end
    -- As the real one, which raises on anything but a string.
    function w:windowTitle(value)
      assert(type(value) == "string", "windowTitle wants a string, got " .. type(value))
      w.calls.windowTitle = value
      return w
    end
    function w:windowCallback(fn) w.callback = fn; return w end
    -- As the real one: deleting fires whatever closing callback is set.
    function w:delete() w.deleted = true; if w.callback then w.callback("closing", w) end end
    function w:hswindow() return nil end
    made[#made + 1] = w
    return w
  end,
  usercontent = { new = function(name)
    local content = { name = name, scripts = {} }
    function content:injectScript(script) self.scripts[#self.scripts + 1] = script; return self end
    return content
  end } }
  hs.timer.doAfter = function(_, fn) fn(); return { stop = noop } end
  hs.screen.mainScreen = function()
    return { frame = function() return { x = 0, y = 0, w = 1000, h = 800 } end }
  end
  hs.window.frontmostWindow = function() return where end
  hs.focus = noop

  local run = cl.getCommand("webview.open")
              and function(args, ctx) return cl.executeCommand("webview.open", args, ctx or {}) end

  check("it is a command of its own extension", run ~= nil)

  if run then
    check("a url opens in a closable window, titled by the row", (function()
            run({ target = "https://example.com", title = "Example" }, {})
            local w = made[#made]
            return w and w.calls.url == "https://example.com"
                   and w.calls.windowTitle == "Example" and w.calls.closeOnEscape == true,
                   w and tostring(w.calls.url)
          end)())

    check("templates in it are resolved", (function()
            run({ target = "${clipboard}", title = "Clip: ${clipboard}" },
                { clipboard = "https://clip.example" })
            return made[#made].calls.url == "https://clip.example"
                   and made[#made].calls.windowTitle == "Clip: https://clip.example",
                   made[#made].calls.windowTitle
          end)())

    check("run by id with no title of its own, the window is still titled", (function()
            run({ target = "https://example.com" }, {})
            return made[#made].calls.windowTitle == cl.modules.webview.WINDOW_TITLE,
                   tostring(made[#made].calls.windowTitle)
          end)())

    check("html is shown as it is, a file as a file url", (function()
            run({ html = "<b>hi</b>" }, {})
            local html = made[#made].calls.html
            run({ file = "~/My Notes/a.html" }, {})
            local url = made[#made].calls.url
            return html == "<b>hi</b>"
                   and url == "file://" .. os.getenv("HOME") .. "/My%20Notes/a.html",
                   tostring(url)
          end)())

    check("nothing to show opens no window", (function()
            local before = #made
            run({ target = "${notCaptured}" }, {})
            return #made == before
          end)())

    check("a second one replaces the first without stealing focus", (function()
            focused = {}
            run({ target = "https://one.example" }, {})
            local first = made[#made]
            run({ target = "https://two.example" }, {})
            return first.deleted == true and #focused == 0 and made[#made] ~= first,
                   tostring(#focused) .. " refocus"
          end)())

    check("css goes into the page before it draws, js once it is there, a value in js a string literal", (function()
            local webview = cl.modules.webview
            run({ target = "https://example.com", css = "body { color: ${color} }",
                  js = "document.title = ${clipboard};" }, { color = "white", clipboard = '"; alert(1); "' })
            local content = made[#made].content
            local scripts = content and content.scripts or {}
            local style, script = scripts[1] or {}, scripts[2] or {}
            return #scripts == 2
                   and style.source == webview.styleScript("body { color: white }")
                   and style.injectionTime == "documentStart" and style.mainFrame == true
                   and script.source == 'document.title = "\\u0022; alert(1); \\u0022";'
                   and script.injectionTime == "documentEnd",
                   tostring(script.source)
          end)())

    -- A stylesheet ahead of the page's own loses to it at the same
    -- specificity, so the same element is put back at the end as the page
    -- is parsed and once it has loaded.
    check("an injected stylesheet ends up last in the document, after the page's own", (function()
            local source = cl.modules.webview.styleScript("body { background: pink }")
            local places = 0
            for _ in source:gmatch("document%.documentElement%.appendChild%(style%)") do places = places + 1 end
            return places >= 1
                   and source:find("document.addEventListener('DOMContentLoaded', place)", 1, true) ~= nil
                   and source:find("window.addEventListener('load', place)", 1, true) ~= nil,
                   source
          end)())

    check("a string literal for JavaScript escapes quotes, backslashes, control characters and line separators",
          cl.modules.webview.jsString('a"b\\c\n\226\128\168') == '"a\\u0022b\\u005cc\\u000a\\u2028"',
          cl.modules.webview.jsString('a"b\\c\n'))

    check("with neither, no content is made", (function()
            run({ target = "https://example.com", css = "", js = "${notCaptured}" }, {})
            return made[#made].content == nil
          end)())

    check("closing it hands focus back to where you were", (function()
            focused = {}
            made[#made]:delete()
            return #focused == 1 and focused[1] == where
          end)())
  end

  hs.webview, hs.timer.doAfter = saved.webview, saved.doAfter
  hs.screen.mainScreen, hs.window.frontmostWindow = saved.mainScreen, saved.frontmostWindow
  hs.focus = saved.focus
end

group("shell backend: values cannot become shell code")
do
  -- Nothing is started: the stub records what would have run.
  local spawned = {}
  local saved = { new = hs.task.new, alert = hs.alert.show }
  hs.task.new = function(program, callback, _, args)
    local t = { program = program, callback = callback, args = args or {} }
    spawned[#spawned + 1] = t
    return { start = function(task) t.started = true; return task end, terminate = noop }
  end
  local alerts = 0
  hs.alert.show = function() alerts = alerts + 1 end

  local run = cl.getCommand("shell.run")
              and function(args, ctx) return cl.executeCommand("shell.run", args, ctx or {}) end
  local function last() return spawned[#spawned] or { args = {} } end
  local hostile = "x'; touch /tmp/pwned; echo '"

  check("it is a command of its own extension", run ~= nil)

  if run then
    check("a string cmd reaches zsh -c with each value one quoted word, the template's text as written", (function()
            run({ cmd = [[echo ${clipboard} | tr a-z A-Z; echo "$HOME"]] }, { clipboard = hostile })
            local t = last()
            local want = [[echo 'x'\''; touch /tmp/pwned; echo '\''' | tr a-z A-Z; echo "$HOME"]]
            return t.program == cl.BIN.zsh and t.args[1] == "-c" and t.args[2] == want
                   and #t.args == 2 and t.started == true,
                   tostring(t.program) .. " " .. tostring(t.args[2])
          end)())

    check("${input:}, ${env:} and ${config:} are quoted too", (function()
            run({ cmd = "a ${input:q} ${env:HOME} ${config:browser.tabOrder}" }, { q = "$(id)" })
            local want = "a '$(id)' '" .. os.getenv("HOME") .. "' '"
                         .. tostring(cl.setting("browser", "tabOrder")) .. "'"
            return last().args[2] == want, tostring(last().args[2])
          end)())

    check("a value is never scanned again, so a ${q} in it is not filled in", (function()
            run({ cmd = "echo ${clipboard} ${q}" }, { clipboard = "${q}", q = "a;b" })
            return last().args[2] == "echo '${q}' 'a;b'", tostring(last().args[2])
          end)())

    check("a list cmd is argv: a value with spaces and $(…) is one argument, and no shell runs", (function()
            local path = "/tmp/a b/$(touch /tmp/pwned); " .. hostile
            run({ cmd = { "/usr/bin/git", "-C", "${path}", "pull" } }, { path = path })
            local t, shown = last(), {}
            for i, a in ipairs(t.args) do shown[i] = tostring(a) end
            return t.program == "/usr/bin/git" and #t.args == 3 and t.args[1] == "-C"
                   and t.args[2] == path and t.args[3] == "pull" and t.started == true,
                   tostring(t.program) .. " | " .. table.concat(shown, " | ")
          end)())

    check("argv's program: an absolute path as given, a registered tool's path, else /usr/bin/env", (function()
            cl.tools.register("test-shell-tool", { "/bin/ls" })
            run({ cmd = { "/bin/echo", "hi" } }, {})
            local absolute = last()
            run({ cmd = { "test-shell-tool", "-l" } }, {})
            local registered = last()
            run({ cmd = { "test-no-such-tool", "${clipboard}" } }, { clipboard = "a b" })
            local unknown = last()
            cl.tools.candidates["test-shell-tool"] = nil
            cl.tools.forget()
            return absolute.program == "/bin/echo" and absolute.args[1] == "hi" and #absolute.args == 1
                   and registered.program == "/fake/test-shell-tool" and registered.args[1] == "-l"
                   and #registered.args == 1
                   and unknown.program == "/usr/bin/env" and unknown.args[1] == "test-no-such-tool"
                   and unknown.args[2] == "a b" and #unknown.args == 2,
                   table.concat({ tostring(absolute.program), tostring(registered.program),
                                  tostring(unknown.program) }, " , ")
          end)())

    check("a list whose program resolves to nothing runs nothing, and says so", (function()
            local before, alerted, logged, realPrint = #spawned, alerts, 0, print
            print = function() logged = logged + 1 end
            run({ cmd = { "${notCaptured}", "x" } }, {})
            print = realPrint
            return #spawned == before and alerts == alerted + 1 and logged == 1
          end)())

    check("a command that fails still alerts and logs", (function()
            local lines, realPrint = {}, print
            print = function(s) lines[#lines + 1] = tostring(s) end
            local alerted = alerts
            -- Guarded, so a broken backend fails this check with print put back.
            local ok, err = pcall(function()
              run({ cmd = { "/bin/false" }, title = "Nope" }, {})
              last().callback(1, "", "boom")
            end)
            print = realPrint
            return ok and alerts == alerted + 1 and (lines[1] or ""):match("^%[commandlayer%].*boom") ~= nil,
                   ok and lines[1] or tostring(err)
          end)())
  end

  check("resolve without an encoder leaves values as they are", (function()
          local c = { query = "a b'c;$(x)", n = 3, finderSelection = "/tmp/a b" }
          local cases = {
            { "https://example.com/?q=${query}&n=${n}&c=$1", { "4 2" },
              "https://example.com/?q=a b'c;$(x)&n=3&c=4 2" },
            { "open ${finderSelection}${nope} $1 ${input:query}", nil,
              "open /tmp/a b $1 a b'c;$(x)" },
          }
          for _, case in ipairs(cases) do
            local plain = cl.resolve(case[1], c, case[2])
            if plain ~= case[3] or cl.resolve(case[1], c, case[2], nil) ~= plain then
              return false, tostring(plain)
            end
          end
          return cl.resolve(42, c) == 42
        end)())

  hs.task.new, hs.alert.show = saved.new, saved.alert
end
