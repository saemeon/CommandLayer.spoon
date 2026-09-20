-- VS Code's Preferences and Profiles commands, under VS Code's own ids, so a
-- keybinding written for one reads the same here.

local M = {}

-- Long enough for an editor's save -- a write, or a new file renamed over the
-- old -- to have landed before the files are read.
M.settleSeconds = 0.3

-- A keybinding's own fields, in the order VS Code writes them.
local ENTRY_FIELDS = { "key", "command", "when", "args", "global", "repeat" }

function M.extension(cl)
  local function open(path)
    if path then cl.executeCommand("editor.open", { target = path, title = path }, {}) end
  end

  local function readText(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("a")
    handle:close()
    return text
  end

  -- With every folder on the way: the user folder may not exist yet.
  local function writeFile(path, text)
    local built = path:sub(1, 1) == "/" and "" or "."
    for part in (path:match("^(.*)/") or ""):gmatch("[^/]+") do
      built = built .. "/" .. part
      if not hs.fs.attributes(built) then hs.fs.mkdir(built) end
    end
    local handle = io.open(path, "w")
    if not handle then
      cl.log.w("could not write " .. path)
      return nil
    end
    handle:write(text)
    handle:close()
    return path
  end

  -- The generated files are views of what is in effect, made again each time
  -- and never read back; they live outside the settings folder so nobody takes
  -- them for something to edit.
  function M.writeGenerated(name, text)
    local base = (os.getenv("TMPDIR") or "/tmp/"):gsub("/$", "")
    return writeFile(base .. "/commandlayer/" .. name, text)
  end

  -- The shipped defaults and, inside the same object, every extension's
  -- declared settings with their defaults -- the whole of what settings.json
  -- can override, as VS Code's Default Settings is built from core and every
  -- extension's contributions.
  function M.defaultSettingsText()
    local text = readText(cl.shippedFile("defaults.jsonc")) or "{\n}"
    local shipped = cl.decodeJSONC(text)
    shipped = type(shipped) == "table" and shipped or {}
    local lines = {}

    for _, ext in ipairs(cl.getSettingOwners()) do
      lines[#lines + 1] = ""
      lines[#lines + 1] = "  // " .. ext.displayName
                          .. (ext.description and (": " .. ext.description) or "")
      if ext.kind == "extension" then
        local key = ext.name .. ".enabled"
        -- Written once, in the extension's own part: a key twice in one object
        -- is what an editor underlines.
        if shipped[key] ~= nil then text = cl.editJSONC(text, { key }, nil) or text end
        lines[#lines + 1] = ("  %s: %s,"):format(cl.encodeJSON(key), tostring(shipped[key] ~= false))
        if ext.menus then
          local pairsText = {}
          for i, menu in ipairs(ext.menus) do pairsText[i] = cl.encodeJSON(menu) .. ": true" end
          lines[#lines + 1] = "  // The pickers its rows are in; true adds one, false takes one out."
          lines[#lines + 1] = ("  %s: { %s },"):format(cl.encodeJSON(ext.name .. ".menus"),
                                                        table.concat(pairsText, ", "))
        end
      end
      local keys = {}
      for key in pairs(type(ext.settings) == "table" and ext.settings or {}) do keys[#keys + 1] = key end
      table.sort(keys, function(a, b) return cl.settingBefore(ext.settings, a, b) end)
      for _, key in ipairs(keys) do
        local decl = ext.settings[key]
        if type(decl) == "table" then
          local about = decl.markdownDescription or decl.description
          if type(decl.enum) == "table" then
            local options = {}
            for i, option in ipairs(decl.enum) do
              local meaning = type(decl.enumDescriptions) == "table" and decl.enumDescriptions[i]
              options[#options + 1] = tostring(option) .. (meaning and (" (" .. meaning .. ")") or "")
            end
            about = (about and (about .. " -- ") or "") .. table.concat(options, ", ")
          end
          if about then lines[#lines + 1] = "  // " .. about end
          if type(decl.deprecationMessage) == "string" then
            lines[#lines + 1] = "  // Deprecated: " .. decl.deprecationMessage
          end
          lines[#lines + 1] = ("  %s: %s,"):format(cl.encodeJSON(ext.name .. "." .. key),
                                                    decl.default == nil and "null" or cl.encodeJSON(decl.default))
        end
      end
    end

    -- Inside the defaults' own object, before its last brace, so the whole is
    -- still one object.
    local last = text:match(".*()}")
    if not last then return text end
    local before = text:sub(1, last - 1):gsub("%s*$", "")
    return before .. ",\n\n  // The extensions, presenters and rankers, and the settings each declares.\n"
           .. table.concat(lines, "\n") .. "\n}\n"
  end

  -- The keybindings in effect before the profile's: the shipped file's. One
  -- entry per line, keys in the order VS Code writes them.
  function M.defaultKeybindingsText()
    local out = {
      "// The keybindings in effect before your keybindings.json, from",
      "// config/defaultKeybindings.jsonc. Generated; edits here are not read.",
      "[",
    }
    local list = cl.readJSONC(cl.shippedFile("defaultKeybindings.jsonc"))
    for _, entry in ipairs(type(list) == "table" and list or {}) do
      if type(entry) == "table" then
        local fields = {}
        for _, name in ipairs(ENTRY_FIELDS) do
          if entry[name] ~= nil then
            fields[#fields + 1] = cl.encodeJSON(name) .. ": " .. cl.encodeJSON(entry[name], true)
          end
        end
        out[#out + 1] = "  { " .. table.concat(fields, ", ") .. " },"
      end
    end
    out[#out + 1] = "]"
    return table.concat(out, "\n") .. "\n"
  end

  -- Chosen in profile.json, and applied by reloading: every extension's
  -- watchers and every chord belong to the profile that started them.
  function M.switchProfile(name)
    if type(name) ~= "string" or name == "" then return false end
    if not writeFile(cl.userDir .. "/profile.json", cl.encodeJSON({ profile = name }) .. "\n") then
      return false
    end
    hs.alert.show("Profile: " .. name)
    cl.after(0.2, function() hs.reload() end)
    return true
  end

  local menus = { "root", "commandPalette" }

  -- A row picked as an answer gives its subject, which is what a row is remembered by.
  cl.itemContextKey("recentlyUsed", function(subject)
    return cl.lastUsed({ subject = subject }) > 0
  end)

  local pending

  -- The folder rather than the files, so a file an editor replaces rather
  -- than writes into is still seen, as is one made after start.
  M.start = function()
    local folder = cl.profileFile("settings.json"):match("^(.*)/[^/]+$")
    if not (hs.pathwatcher and folder and hs.fs.attributes(folder)) then return end
    cl.watch(hs.pathwatcher.new(folder, function(paths)
      local named = type(paths) ~= "table"
      for _, path in ipairs(type(paths) == "table" and paths or {}) do
        local name = tostring(path):match("[^/]+$")
        if name == "settings.json" or name == "keybindings.json" then named = true end
      end
      if not named then return end
      -- From the last change, so a burst of writes reloads once.
      if pending then pending.dispose() end
      pending = cl.after(M.settleSeconds, function()
        pending = nil
        if cl.setting("workbench", "autoReload") and cl.reload({ ifChanged = true }) then
          hs.alert.show("Command Layer: settings reloaded")
        end
      end)
    end))
  end

  M.stop = function()
    pending = nil
  end

  return {
    displayName = "Preferences",
    description = "Open the settings and keybindings files, switch profile, list problems, "
                  .. "and forget what was picked",
    menus       = {},
    optionalExtensionDependencies = { "settings" },

    settings = {
      autoReload = { type = "boolean", default = true,
                     description = "Reload when settings.json or keybindings.json changes" },
    },

    commands = {
      -- VS Code's settings editor offers this on a modified setting's gear.
      { id = "workbench.action.resetSetting", title = "Reset Setting",
        icon = "$(discard)", menus = { ["view/item/context"] = true },
        inputs = { { id = "setting", description = "Reset setting",
                     picker = { when = "viewItem == 'setting' && modified" } } },
        run = function(args)
          local settings = cl.extension("settings")
          if not settings then
            hs.alert.show("Reset Setting: the settings extension is switched off, so settings.json was not changed")
            return
          end
          settings.update(args.setting.name, args.setting.key, nil)
        end },

      { id = "workbench.action.removeFromRecentlyUsed", title = "Remove from Recently Used",
        icon = "$(close)", menus = { ["view/item/context"] = true },
        inputs = { { id = "item", description = "Remove from recently used",
                     picker = { when = "recentlyUsed" } } },
        run = function(args) cl.removeRecentlyUsed({ subject = args.item }) end },

      -- Asks first, as VS Code does: every pick recorded goes, and ranking with it.
      { id = "workbench.action.clearCommandHistory", title = "Clear Command History",
        icon = "$(clear-all)", menus = menus,
        inputs = { {
          id = "confirm",
          description = "Forget every row picked, so none is recently used or ranked by use?",
          picker = { options = { { label = "Clear Command History", value = "clear" } } },
        } },
        run = function(args)
          if args.confirm == "clear" then cl.clearRecentlyUsed() end
        end },

      { id = "workbench.action.openSettingsJson", title = "Open User Settings (JSON)",
        category = "Preferences", icon = "$(settings-gear)", menus = menus,
        run = function() open(cl.profileFile("settings.json", "{\n}\n")) end },

      { id = "workbench.action.openGlobalKeybindingsFile", title = "Open Keyboard Shortcuts (JSON)",
        category = "Preferences", icon = "$(file-code)", menus = menus,
        run = function() open(cl.profileFile("keybindings.json", "[\n]\n")) end },

      -- The Keyboard Shortcuts picker, as VS Code's opens its editor.
      { id = "workbench.action.openGlobalKeybindings", title = "Open Keyboard Shortcuts",
        category = "Preferences", icon = "$(keyboard)", menus = menus,
        command = "quickOpen", args = { view = "keybindings" } },

      { id = "workbench.action.openRawDefaultSettings", title = "Open Default Settings (JSON)",
        category = "Preferences", icon = "$(settings-gear)", menus = menus,
        run = function() open(M.writeGenerated("defaultSettings.jsonc", M.defaultSettingsText())) end },

      { id = "workbench.action.openDefaultKeybindingsFile", title = "Open Default Keyboard Shortcuts (JSON)",
        category = "Preferences", icon = "$(file-code)", menus = menus,
        run = function() open(M.writeGenerated("defaultKeybindings.jsonc", M.defaultKeybindingsText())) end },

      { id = "workbench.profiles.actions.switchProfile", title = "Switch Profile…",
        category = "Profiles", icon = "$(account)", menus = menus,
        inputs = { {
          id = "profile", description = "Switch to profile",
          picker = { options = function()
            local options = {}
            for _, name in ipairs(cl.profileNames()) do
              options[#options + 1] = { label = name, value = name,
                                        description = name == cl.profile and "Current profile" or nil }
            end
            return options
          end },
        } },
        run = function(args) M.switchProfile(args.profile) end },

      { id = "workbench.actions.view.problems", title = "Show Problems",
        category = "View", icon = "$(warning)", menus = menus,
        inputs = { {
          id = "problem", description = "Problems",
          picker = { options = function()
            local options = {}
            for _, p in ipairs(cl.getProblems()) do
              options[#options + 1] = { label = p.message, value = p.file, description = p.file }
            end
            if #options == 0 then options[1] = { label = "No problems have been detected", value = "" } end
            return options
          end },
        } },
        -- A problem in a file opens it; one about an extension or a picker names no file.
        run = function(args)
          local path = type(args.problem) == "string"
                       and args.problem:gsub("^~/", (os.getenv("HOME") or "~") .. "/") or ""
          if path ~= "" and hs.fs.attributes(path) then open(path) end
        end },
    },
  }
end

return M
