-- macOS itself: opening and revealing things, Open With, locking the
-- screen, its own Emoji & Symbols picker and its screenshots.

local M = {}

-- Launch Services' own answer to which apps open a thing, as Finder's Open
-- With lists them: NSWorkspace, through JavaScript for Automation in a
-- process of its own. It scripts no app, so there is no Automation prompt.
-- The thing is an argument, never part of the script's text. One line per
-- app: bundle id, path, display name, "default" for the one that opens it
-- now.
M.HANDLERS_SCRIPT = [[
ObjC.import('AppKit');
function run(argv) {
  var target = argv[0];
  var url = target.charAt(0) === '/' ? $.NSURL.fileURLWithPath(target) : $.NSURL.URLWithString(target);
  if (!url || url.isNil()) return '';
  var workspace = $.NSWorkspace.sharedWorkspace;
  var files = $.NSFileManager.defaultManager;
  var lines = [];
  function add(app, preferred) {
    if (!app || app.isNil()) return;
    var bundle = $.NSBundle.bundleWithURL(app);
    var id = (bundle && !bundle.isNil() && ObjC.unwrap(bundle.bundleIdentifier)) || '';
    var path = ObjC.unwrap(app.path) || '';
    var name = ObjC.unwrap(files.displayNameAtPath(app.path)) || '';
    lines.push([id, path, name, preferred ? 'default' : ''].join('\t'));
  }
  add(workspace.URLForApplicationToOpenURL(url), true);
  var apps = workspace.URLsForApplicationsToOpenURL(url);
  for (var i = 0; i < apps.count; i++) add(apps.objectAtIndex(i), false);
  return lines.join('\n');
}
]]

-- The default first, then by name, each app once.
function M.parseHandlers(output)
  local list, seen, default = {}, {}, nil
  for line in tostring(output or ""):gmatch("[^\r\n]+") do
    local id, path, name, preferred = line:match("^([^\t]*)\t([^\t]+)\t([^\t]*)\t?([^\t]*)$")
    if path and not seen[path] then
      seen[path] = true
      name = (name ~= "" and name or path:match("([^/]+)$") or path):gsub("%.app$", "")
      local app = { id = id ~= "" and id or nil, path = path, name = name }
      if preferred == "default" and not default then default = app else list[#list + 1] = app end
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  if default then
    default.default = true
    table.insert(list, 1, default)
  end
  return list
end

-- What to open, and what the list of apps for it is kept under: a folder's
-- apps, a file extension's, a URL scheme's. A file with no extension is
-- kept under its own path, since it may as well be a folder.
function M.openWithTarget(subject)
  if type(subject) ~= "table" then return nil end
  if subject.kind == "url" then
    local url = subject.value
    local scheme = type(url) == "string" and url:match("^(%a[%w+.-]*):")
    if not scheme then return nil end
    return url, "scheme:" .. scheme:lower()
  end
  local path = subject.path
  if type(path) ~= "string" or path == "" then return nil end
  if subject.kind == "folder" or subject.kind == "project" or path:match("/$") then
    return path, "folder"
  end
  local extension = path:match("%.([^./]+)$")
  if extension then return path, "file:" .. extension:lower() end
  return path, "path:" .. path
end

-- By bundle id: the app has lived in /Applications/Utilities and in
-- /System/Applications/Utilities.
M.SCREENSHOT_BUNDLE = "com.apple.screenshot.launcher"

-- Long enough that asking again while choosing costs nothing, short enough
-- that an app installed since is offered.
local HANDLER_SECONDS = 300

function M.extension(cl)
  cl.tools.register("open", { "/usr/bin/open" })
  cl.tools.register("osascript", { "/usr/bin/osascript" })

  -- /usr/bin/open, which takes anything Launch Services knows; hs.urlevent
  -- does not take every scheme -- x-apple.systempreferences: does nothing
  -- through it.
  local function open(args, ctx, flags, verb)
    local bundleOnly = args.target == nil and type(args.bundle) == "string" and args.bundle ~= ""
    local target = not bundleOnly and cl.resolve(args.target, ctx) or nil
    -- Bare `open` opens a Finder window, so an unresolved template would
    -- look like it worked.
    if not bundleOnly and (not target or target == "") then return end
    local argv = {}
    for _, flag in ipairs(flags) do argv[#argv + 1] = flag end
    -- Which app, as Finder's Open With chooses: the bundle id before a name
    -- or path, since two apps can share a name.
    if type(args.bundle) == "string" and args.bundle ~= "" then
      argv[#argv + 1] = "-b"
      argv[#argv + 1] = args.bundle
    elseif type(args.app) == "string" and args.app ~= "" then
      argv[#argv + 1] = "-a"
      argv[#argv + 1] = args.app
    end
    argv[#argv + 1] = target
    cl.tools.run(cl.tools.path("open") or "/usr/bin/open", argv, function(code, _, stderr)
      if code ~= 0 then
        hs.alert.show("Could not " .. verb .. " " .. tostring(args.title or target or args.bundle))
        cl.log.e("open " .. table.concat(argv, " ") .. " -> " .. tostring(stderr))
      end
    end)
  end

  local handlers, lookups = {}, {}

  -- A failed answer is handed on but not kept, so the next ask tries again.
  local function handlersFor(target, key, callback)
    local known = handlers[key]
    if known and os.time() - known.at < HANDLER_SECONDS then return callback(known.list) end
    if lookups[key] then
      table.insert(lookups[key], callback)
      return
    end
    lookups[key] = { callback }
    local function answer(list, keep)
      if keep then handlers[key] = { list = list, at = os.time() } end
      local callbacks = lookups[key] or {}
      lookups[key] = nil
      for _, fn in ipairs(callbacks) do fn(list) end
    end
    local task = cl.tools.run(cl.tools.path("osascript") or "/usr/bin/osascript",
      { "-l", "JavaScript", "-e", M.HANDLERS_SCRIPT, target },
      function(code, stdout, stderr)
        if code ~= 0 then
          cl.log.e("listing the apps that open " .. key .. " failed -> " .. tostring(stderr))
          return answer({}, false)
        end
        answer(M.parseHandlers(stdout), true)
      end)
    if not task and lookups[key] then answer({}, false) end
  end

  -- A key pressed while Secure Input is on is dropped without a sound, so
  -- it is said instead; true when it was.
  local function secureInputBlocks(what, ctx)
    local secure = cl.extension("secureinput")
    return secure ~= nil and secure.warn(what, ctx) == true
  end

  -- macOS's own capture shortcuts, so the system takes the picture and
  -- Hammerspoon never needs Screen Recording. Pressed once the launcher has
  -- closed, or the whole screen would have the picker in it.
  local function capture(id, title, mods, key)
    return { id = "system." .. id, title = title, category = "Screenshot", icon = "$(device-camera)",
      menus = { "root", "commandPalette" },
      run = function(_, ctx)
        cl.after(0.1, function()
          if secureInputBlocks(title .. " did not start", ctx) then return end
          hs.eventtap.keyStroke(mods, key, 0)
        end)
      end }
  end

  return {
    name        = "system",
    displayName = "System",
    description = "Open and reveal things, Open With, lock the screen, macOS's Emoji & Symbols and its screenshots",
    menus       = {},
    optionalExtensionDependencies = { "secureinput" },

    commands = {
      { id = "system.open", title = "Open", menus = {},
        run = function(args, ctx) open(args, ctx, {}, "open") end },
      { id = "system.reveal", title = "Reveal in Finder", menus = {},
        run = function(args, ctx)
          open({ target = args.target, title = args.title }, ctx, { "-R" }, "reveal")
        end },

      -- The apps arrive when Launch Services answers: a search picker
      -- presents whenever it is told, where options are read once, before
      -- any answer could land.
      { id = "system.openWith", title = "Open with…", icon = "$(link-external)",
        menus = { commandPalette = true, ["view/item/context"] = true },
        inputs = {
          { id = "target", description = "Open what",
            picker = {
              when = "viewItem == 'file' || viewItem == 'folder' || viewItem == 'project' || viewItem == 'url'",
              menus = { "files", "recent" } } },
          -- Every app, whatever was typed: the layer's matcher narrows them.
          { id = "app", description = "Open with",
            picker = { kind = "search", search = function(_, _, args, done)
              local target, key = M.openWithTarget(args.target)
              if not target then return done({}) end
              handlersFor(target, key, function(list)
                local results = {}
                for _, app in ipairs(list) do
                  results[#results + 1] = {
                    label = app.name,
                    description = app.default and "Default" or app.path,
                    value = { id = app.id, path = app.path, name = app.name },
                  }
                end
                done(results)
              end)
            end } },
        },
        run = function(args, ctx)
          local target = M.openWithTarget(args.target)
          local app = args.app
          if not target or type(app) ~= "table" then return end
          open({ target = target, bundle = app.id, app = not app.id and app.path or nil, title = app.name },
               ctx, {}, "open")
        end },

      -- The text as it is: a copied value is never a template.
      { id = "system.copy", title = "Copy", menus = {},
        run = function(args) hs.pasteboard.setContents(tostring(args.text or "")) end },
      -- Through the clipboard rather than eventtap.keyStrokes, which drops
      -- characters on long text and mangles anything non-ASCII. The text is
      -- left on the clipboard: restoring it means racing the paste. Still
      -- pasted under Secure Input: the text is on the clipboard either way,
      -- where a cmd+v of your own does reach the app.
      { id = "system.paste", title = "Paste", menus = {},
        run = function(args, ctx)
          local text = tostring(args.text or "")
          if text == "" then return end
          secureInputBlocks("Copied, not pasted", ctx)
          hs.pasteboard.setContents(text)
          -- The picker has focus as this runs; the keystroke has to arrive
          -- after it closes and focus returns.
          cl.after(0.1, function() hs.eventtap.keyStroke({ "cmd" }, "v", 0) end)
        end },

      { id = "system.lockScreen", title = "Lock screen", category = "System", icon = "$(lock)",
        menus = { "root", "commandPalette" },
        run = function() hs.caffeinate.lockScreen() end },

      -- ctrl+cmd+space opens it in whatever has focus, so it is pressed once
      -- the launcher has handed focus back.
      { id = "system.emojiAndSymbols", title = "Emoji & Symbols", category = "System",
        icon = "$(smiley)", menus = { "root", "commandPalette" },
        run = function(_, ctx)
          cl.after(0.1, function()
            if secureInputBlocks("Emoji & Symbols did not open", ctx) then return end
            hs.eventtap.keyStroke({ "ctrl", "cmd" }, "space", 0)
          end)
        end },

      -- Screenshot.app is the toolbar cmd+shift+5 shows: every capture and
      -- recording, the timer and where pictures are saved.
      { id = "system.screenshotToolbar", title = "Show toolbar", category = "Screenshot",
        icon = "$(device-camera)", menus = { "root", "commandPalette" },
        run = function(_, ctx)
          cl.executeCommand("system.open", { bundle = M.SCREENSHOT_BUNDLE, title = "Screenshot" }, ctx)
        end },
      capture("captureScreen", "Capture entire screen", { "cmd", "shift" }, "3"),
      capture("captureSelection", "Capture selected portion", { "cmd", "shift" }, "4"),
      capture("copyScreen", "Copy entire screen", { "ctrl", "cmd", "shift" }, "3"),
      capture("copySelection", "Copy selected portion", { "ctrl", "cmd", "shift" }, "4"),
    },
  }
end

return M
