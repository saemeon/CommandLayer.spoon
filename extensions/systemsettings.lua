-- System Settings panes.
--
-- The legacy /System/Library/PreferencePanes bundles still exist but
-- several are empty stubs, so scanning those gives a list with holes.
-- The real source is ExtensionKit: an .appex declaring
-- com.apple.Settings.extension.ui, whose bundle id is what
-- x-apple.systempreferences: wants. Apple renames these between
-- releases, hence reading them off the machine.

local M = {}

M.root = "/System/Library/ExtensionKit/Extensions"

M.extensionPoint = "com.apple.Settings.extension.ui"

local function nonEmpty(value)
  return type(value) == "string" and value ~= "" and value or nil
end

-- The name System Settings shows. Info.plist often holds a build name
-- ("AccessibilitySettingsExtension"); the one shown is localised, in
-- InfoPlist.loctable beside it.
function M.paneName(bundle, plist)
  local localised = hs.plist.read(bundle .. "/Contents/Resources/InfoPlist.loctable")
  local english = type(localised) == "table" and type(localised.en) == "table" and localised.en or {}
  return nonEmpty(english.CFBundleDisplayName) or nonEmpty(plist.CFBundleDisplayName)
      or nonEmpty(plist.CFBundleName)
end

-- A few hundred plist reads, with no process to hand them to.
function M.scan()
  local found = {}

  local ok, iter, dirObj = pcall(hs.fs.dir, M.root)
  if not ok or not iter then return found end

  for entry in iter, dirObj do
    if entry:sub(-6) == ".appex" then
      local bundle = M.root .. "/" .. entry
      local plist = hs.plist.read(bundle .. "/Contents/Info.plist")
      local attrs = plist and plist.EXAppExtensionAttributes

      if attrs and attrs.EXExtensionPointIdentifier == M.extensionPoint then
        local id = plist.CFBundleIdentifier
        if id then
          local name = M.paneName(bundle, plist)
          if name then
            found[#found + 1] = {
              name = name,
              id   = id,
              url  = "x-apple.systempreferences:" .. id,
            }
          end
        end
      end
    end
  end

  table.sort(found, function(a, b) return a.name < b.name end)
  return found
end

function M.extension(cl)
  local function panes()
    return cl.cached("panes", {
      seconds = cl.setting("systemsettings", "cacheSeconds"),
      initial = {},
      refresh = function(done) done(M.scan()) end,
    })
  end

  -- Scanned off the startup path rather than paid on the first keystroke.
  M.start = function()
    cl.after(2, panes)
  end

  local takesPane = {
    id = "pane", description = "Which pane",
    picker = { when = "viewItem == 'systemsettings'" },
  }

  return {
    name        = "systemsettings",
    displayName = "System Settings",
    rank        = 0,
    menus       = { "root" },
    optionalExtensionDependencies = { "icons" },

    settings = {
      -- Rarely changes. Long enough that it is scanned about once per session.
      cacheSeconds = { type = "integer", default = 3600,
                       description = "How long the list of panes is kept before it is read again, in seconds" },
    },

    commands = {
      { id = "systemsettings.openPane", title = "Open pane", category = "System Settings",
        menus = { ["view/item/context"] = true },
        inputs = { takesPane },
        run = function(args, ctx)
          cl.executeCommand("system.open", { target = args.pane and args.pane.url }, ctx)
        end },

      { id = "systemsettings.copyURL", title = "Copy URL", category = "System Settings",
        menus = { ["view/item/context"] = true },
        inputs = { takesPane },
        run = function(args, ctx)
          cl.executeCommand("system.copy", { text = args.pane and args.pane.url }, ctx)
        end },
    },

    items = function(ctx)
      local icons = cl.extension("icons")
      local image = icons and icons.settings()
      local items = {}
      for _, pane in ipairs(panes()) do
        items[#items + 1] = {
          label       = pane.name,
          description = "System Settings",
          command     = "system.open",
          args        = { target = pane.url },
          ctx         = ctx,
          subject     = { kind = "systemsettings", name = pane.name, url = pane.url },
          iconPath    = image,
        }
      end
      return items
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
