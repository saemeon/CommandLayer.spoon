-- The text selected in the app in front, as a subject, read through
-- Accessibility rather than the clipboard. Pressing cmd+c to get it would
-- overwrite what you copied, so an app that gives no AXSelectedText --
-- Electron apps, browsers -- gives no selection subject.

local M = {}

-- Capture runs on Hammerspoon's one thread as the layer opens, and macOS's
-- own messaging timeout is six seconds: an app too busy to answer in this
-- long gives no selection rather than a launcher that will not open.
M.timeoutSeconds = 0.1

-- Look Up and a search take a word or a phrase. A longer selection is left
-- out rather than cut, since Copy would copy less than was selected.
M.maxLength = 1000

local SECURE = "AXSecureTextField"

-- Every byte outside RFC 3986's unreserved set, `$` and braces included: a
-- target is filled as a template, and selected text must never become one.
function M.encode(text)
  return (tostring(text):gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function trimmed(text)
  return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

-- The focused element only: walking the tree is what stalls on a busy app.
function M.read(app)
  if not (app and hs.axuielement and hs.axuielement.applicationElement) then return nil end
  -- Hammerspoon answers Accessibility requests on the thread that would be
  -- waiting for the answer, so asking itself only ever times out.
  local own = hs.processInfo and hs.processInfo.processID
  if own and type(app.pid) == "function" and app:pid() == own then return nil end

  -- An element that cannot be given a timeout is never sent a message.
  local function timed(element)
    if type(element) ~= "table" and type(element) ~= "userdata" then return nil end
    if type(element.setTimeout) ~= "function" then return nil end
    element:setTimeout(M.timeoutSeconds)
    return element
  end

  local root = timed(hs.axuielement.applicationElement(app))
  if not root then return nil end
  -- The focused element does not inherit its app's timeout.
  local focused = timed(root:attributeValue("AXFocusedUIElement"))
  if not focused then return nil end

  -- A role that cannot be read is an app not answering, or an element that
  -- could be a password field; either way the text is not asked for.
  local role = focused:attributeValue("AXRole")
  if type(role) ~= "string" or role == SECURE then return nil end
  if focused:attributeValue("AXSubrole") == SECURE then return nil end

  local text = focused:attributeValue("AXSelectedText")
  if type(text) ~= "string" or #text > M.maxLength or not text:find("%S") then return nil end
  return text
end

function M.extension(cl)
  local function selectionInput(description)
    return { { id = "text", description = description, picker = { when = "viewItem == 'selection'" } } }
  end

  local function valueOf(subject)
    local text = type(subject) == "table" and subject.value
    if type(text) ~= "string" or not text:find("%S") then return nil end
    return text
  end

  return {
    name        = "selection",
    displayName = "Selection",
    description = "The text selected in the app in front, read through Accessibility: Look Up, search, copy",
    -- secureInput is captured by secureinput, frontmostApp by ambient.
    after       = { "ambient", "secureinput" },
    menus       = {},

    commands = {
      { id = "selection.lookUp", title = "Look Up", icon = "$(book)",
        menus = { ["view/item/context"] = true },
        inputs = selectionInput("Look up what"),
        run = function(args, ctx)
          local text = valueOf(args.text)
          if not text then return end
          cl.executeCommand("system.open", { target = "dict://" .. M.encode(trimmed(text)), title = "Look Up" }, ctx)
        end },

      -- The browser's own search, so its searchURL setting decides where.
      { id = "selection.searchWeb", title = "Search the web", icon = "$(search)",
        menus = { ["view/item/context"] = true },
        inputs = selectionInput("Search for what"),
        run = function(args, ctx)
          local text = valueOf(args.text)
          if not text then return end
          local ran = cl.executeCommand("browser.searchWeb", { query = hs.http.encodeForQuery(trimmed(text)) }, ctx)
          if not ran then hs.alert.show("Search the web needs the Browser extension") end
        end },

      { id = "selection.copy", title = "Copy", icon = "$(copy)",
        menus = { ["view/item/context"] = true },
        inputs = selectionInput("Copy what"),
        run = function(args, ctx)
          local text = valueOf(args.text)
          if text then cl.executeCommand("system.copy", { text = text }, ctx) end
        end },
    },

    capture = function(ctx)
      if ctx.secureInput then return end
      ctx.selection = M.read(hs.application.frontmostApplication())
    end,

    subjects = function(ctx)
      if type(ctx.selection) ~= "string" or ctx.selection == "" then return {} end
      return { { kind = "selection", value = ctx.selection, label = "Selected text" } }
    end,

    scope = function(subject, scoped)
      if subject.kind == "selection" and type(subject.value) == "string" then scoped.selection = subject.value end
    end,
  }
end

return M
