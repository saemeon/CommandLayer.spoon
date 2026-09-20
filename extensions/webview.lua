-- A page in a window of its own: a destination, as a URL is for a browser.

local M = {}

-- What a window with no title of its own is called.
M.WINDOW_TITLE = "Web view"

-- A JavaScript string literal. Quotes, backslashes and control characters
-- are all escaped the same way, and U+2028/2029 too, which end a line in
-- older engines even inside a string.
function M.jsString(text)
  local escaped = tostring(text):gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end)
  escaped = escaped:gsub("\226\128\168", "\\u2028"):gsub("\226\128\169", "\\u2029")
  return '"' .. escaped .. '"'
end

-- The document element exists before anything else does, so a style put
-- there applies before the page first draws: a dark stylesheet does not
-- flash light. It is put back at the end each time the page reaches a
-- further state, since a stylesheet ahead of the page's own loses to it
-- at the same specificity -- example.com's grey body beat a pink one.
function M.styleScript(css)
  return "(function () { var style = document.createElement('style'); style.textContent = "
         .. M.jsString(css) .. ";"
         .. " var place = function () { document.documentElement.appendChild(style); };"
         .. " place();"
         .. " document.addEventListener('DOMContentLoaded', place);"
         .. " window.addEventListener('load', place); })();"
end

function M.extension(cl)
  local resolve = cl.resolve

  -- WebKit injects these into every page the window loads, a link followed
  -- inside it included. A value filled into `js` arrives as a string
  -- literal, so a copied text can never become code in the page.
  local function userContent(args, ctx)
    local css = args.css and resolve(args.css, ctx)
    local hasCSS = type(css) == "string" and css ~= ""
    -- Judged unencoded: an empty value encodes to "", which is not nothing.
    local hasJS = type(args.js) == "string" and resolve(args.js, ctx) ~= ""
    local js = hasJS and resolve(args.js, ctx, nil, M.jsString)
    if not (hasCSS or hasJS) then return nil end

    local content = hs.webview.usercontent.new("commandlayer")
    if hasCSS then
      content:injectScript({ source = M.styleScript(css), mainFrame = true, injectionTime = "documentStart" })
    end
    if hasJS then
      content:injectScript({ source = js, mainFrame = true, injectionTime = "documentEnd" })
    end
    return content
  end

  -- One panel at a time: opening something new replaces what was shown,
  -- rather than stacking windows to close one by one.
  local panel

  -- Where you were when the first panel opened. Replacing a panel keeps
  -- it, since by then the panel itself is the frontmost window.
  local returnTo

  local function close()
    if not panel then return end
    local old = panel
    panel = nil
    -- Its closing callback would hand focus back while the replacement is
    -- opening, so it is cleared before the delete fires it.
    pcall(function()
      old:windowCallback(nil)
      old:delete()
    end)
  end

  -- One of three things to show, first match wins. A file is loaded as a
  -- page rather than read in, so its relative links and images resolve.
  local function source(args, ctx)
    local html = args.html and resolve(args.html, ctx)
    if html and html ~= "" then return "html", html end

    local file = args.file and resolve(args.file, ctx)
    if file and file ~= "" then
      -- A space is enough to make NSURL refuse the whole thing.
      local path = file:gsub("^~", os.getenv("HOME")):gsub(" ", "%%20")
      return "url", "file://" .. path
    end

    local url = resolve(args.target, ctx)
    if url and url ~= "" then return "url", url end
  end

  local function open(args, ctx)
    local kind, value = source(args, ctx)
    -- An unresolved template is not a reason to open an empty window.
    if not kind then return end

    local replacing = panel ~= nil
    close()
    if not replacing then returnTo = hs.window.frontmostWindow() end

    local screen = hs.screen.mainScreen():frame()
    local w = args.width  or screen.w * (cl.setting("webview", "width") or 60) / 100
    local h = args.height or screen.h * (cl.setting("webview", "height") or 70) / 100

    local frame = { x = screen.x + (screen.w - w) / 2, y = screen.y + (screen.h - h) / 2, w = w, h = h }
    local content = userContent(args, ctx)
    if content then
      panel = hs.webview.new(frame, {}, content)
    else
      panel = hs.webview.new(frame)
    end
    -- Titled and closable, because escape only closes a closable window.
    panel:windowStyle({ "titled", "closable", "resizable" })
    panel:closeOnEscape(true)
    panel:deleteOnClose(true)
    panel:allowTextEntry(true)
    -- windowTitle refuses anything but a string, and a command run by id
    -- from a keybinding or a URL carries no title of its own.
    local title = args.title and resolve(args.title, ctx)
    panel:windowTitle(title ~= nil and title ~= "" and title or M.WINDOW_TITLE)

    panel:windowCallback(function(action)
      if action ~= "closing" then return end
      panel = nil
      local back = returnTo
      returnTo = nil
      if back then back:focus() end
    end)

    if kind == "html" then panel:html(value) else panel:url(value) end
    panel:show()

    -- The picker has only just closed and is still handing focus back to
    -- the app you were in; taking it now would lose to that. A window
    -- from Hammerspoon only gets escape and scrolling once Hammerspoon
    -- is the app in front.
    local shown = panel
    cl.after(0.1, function()
      if panel ~= shown then return end
      hs.focus()
      local window = shown:hswindow()
      if window then window:focus() end
    end)
  end

  return {
    displayName = M.WINDOW_TITLE,
    description = "Show a page, some HTML or a file in a window of its own",
    menus       = {},

    settings = {
      width  = { type = "number", default = 60, description = "Window width, as a percentage of the screen" },
      height = { type = "number", default = 70, description = "Window height, as a percentage of the screen" },
    },

    commands = {
      { id = "webview.open", title = "Open in a window", menus = {}, run = open },
    },
  }
end

return M
