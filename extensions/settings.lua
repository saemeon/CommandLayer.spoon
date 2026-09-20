-- The settings picker's rows: which extensions run, and the switches each
-- one declares, toggled in place and written to settings.json.

local M = {}

function M.extension(cl)
  local function readText(path)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local text = handle:read("a")
    handle:close()
    return text
  end

  -- profileFile makes a missing file with its folders, which may not be there
  -- yet; one that is there is written over.
  local function writeOwn(name, text)
    local path = cl.profileFile(name)
    local handle = io.open(path, "r")
    if not handle then return cl.profileFile(name, text) ~= nil end
    handle:close()
    handle = io.open(path, "w")
    if not handle then return false end
    handle:write(text)
    handle:close()
    return true
  end

  -- One value in the active profile's own settings.json, changed in the
  -- file's text so comments and layout survive, as VS Code's settings editor
  -- changes one. Read from disk at the moment of writing, so a hand edit
  -- since setup is kept; refused while the file does not parse, since an
  -- edit needs to know where things are. Flat, "browser.tabOrder"; nil
  -- removes the key, as VS Code's update with undefined does.
  local function update(name, key, value)
    local path = cl.profileFile("settings.json")
    local original = readText(path)
    if value == nil and not original then return true end
    local text = original
    if not text or text:match("^%s*$") then text = "{\n}\n" end
    if type(cl.decodeJSONC(text)) ~= "table" then
      hs.alert.show("settings.json does not parse, so it was not changed")
      return false
    end

    local edited, err = cl.editJSONC(text, { name .. "." .. key }, value)
    if type(edited and cl.decodeJSONC(edited)) ~= "table" then
      cl.problem(path .. " could not be changed: " .. tostring(err))
      return false
    end
    if edited ~= original and not writeOwn("settings.json", edited) then
      cl.problem(path .. " could not be written")
      return false
    end
    cl.settingsWritten()
    return true
  end
  M.update = update

  -- What cmd+k acts on, and whether settings.json sets it: VS Code's
  -- settings editor calls such a setting modified.
  local function settingSubject(name, key)
    local _, source = cl.inspectSetting(name, key)
    return { kind = "setting", id = name .. "." .. key, name = name, key = key,
             modified = source == "settings.json" }
  end

  local function toggleRow(ctx, label, description, subject, fn)
    return {
      label       = label,
      description = description,
      subject     = subject,
      ctx         = ctx,
      -- Stays open and redraws, so you see the switch flip and can flip
      -- another.
      keepOpen    = true,
      run         = function() fn() end,
    }
  end

  -- One row for a declared setting, wherever it is declared: a switch flips,
  -- a choice -- VS Code's `enum` -- steps to its next value and past the last
  -- back to the first. `enumDescriptions` says what the current one means.
  local function settingRow(ctx, title, decl, value, source, subject, write)
    local marked = source == "settings.json" and "" or " (default)"
    if type(decl.enum) == "table" then
      local nextValue, meaning = decl.enum[1], nil
      for i, option in ipairs(decl.enum) do
        if option == value then
          nextValue = decl.enum[i % #decl.enum + 1]
          meaning = type(decl.enumDescriptions) == "table" and decl.enumDescriptions[i]
        end
      end
      return toggleRow(ctx, title,
        "Setting -- " .. tostring(value) .. marked .. (meaning and ("  --  " .. meaning) or ""),
        subject, function() write(nextValue) end)
    end
    local on = value ~= false
    return toggleRow(ctx, title, "Setting -- " .. (on and "on" or "off") .. marked,
      subject, function() write(not on) end)
  end

  return {
    displayName = "Settings",
    description = "Every extension and the switches each declares, flipped in the settings picker",
    menus       = { "settings" },
    exports     = { update = update },

    items = function(ctx)
      local rows = {}

      -- Every extension, on or off -- this one too, so it can be switched back
      -- on while it still runs -- and every presenter and ranker with settings.
      for _, owner in ipairs(cl.getSettingOwners()) do
        local label = owner.displayName

        -- Registered means running; switching one takes effect on reload,
        -- since an extension's watchers and hooks are in use.
        if owner.kind == "extension" then
          local enabled = cl.setting(owner.name, "enabled") ~= false
          local shown
          if owner.registered then
            shown = enabled and "Extension -- on" or "Extension -- off after a reload"
          else
            shown = enabled and "Extension -- on after a reload" or "Extension -- off"
          end
          rows[#rows + 1] = toggleRow(ctx, label, shown, settingSubject(owner.name, "enabled"),
            function() update(owner.name, "enabled", not enabled) end)
        end

        local settings = owner.settings or {}
        local keys = {}
        for key, decl in pairs(settings) do
          -- A deprecated setting is listed only while settings.json sets it,
          -- as VS Code's settings editor does.
          if type(decl) == "table"
             and (type(decl.default) == "boolean" or decl.type == "boolean"
                  or type(decl.enum) == "table")
             and (decl.deprecationMessage == nil
                  or select(2, cl.inspectSetting(owner.name, key)) == "settings.json") then
            keys[#keys + 1] = key
          end
        end
        table.sort(keys, function(a, b) return cl.settingBefore(settings, a, b) end)

        for _, key in ipairs(keys) do
          local decl = settings[key]
          local value, source = cl.inspectSetting(owner.name, key)
          rows[#rows + 1] = settingRow(ctx, label .. ": " .. (decl.description or decl.markdownDescription or key),
            decl, value, source, settingSubject(owner.name, key),
            function(v) update(owner.name, key, v) end)
        end
      end

      return rows
    end,
  }
end

return M
