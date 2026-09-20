-- Which profile is active, where its files are, and which profiles there are.

local M = ...

----------------------------------------------------------------------
-- WHERE THE FILES ARE
--
-- VS Code's arrangement. Shipped defaults -- config/defaults.jsonc and
-- config/defaultKeybindings.jsonc -- and a profile's own settings.json and
-- keybindings.json over them. Switching profile switches both files: the
-- default profile's settings do not apply under another.
----------------------------------------------------------------------

-- Set before start() to choose one: spoon.CommandLayer.profile = "raycast",
-- or a folder's path. Unset, ~/.config/commandlayer/profile.json decides,
-- and then "default".
M.profile = nil

-- ~/.config/commandlayer, or $XDG_CONFIG_HOME's. Set before start() to use
-- another; setup() fills it in, never loading, which reads nothing.
M.userDir = nil

function M.defaultUserDir()
  local base = os.getenv("XDG_CONFIG_HOME")
  if not base or base == "" then base = os.getenv("HOME") .. "/.config" end
  return base .. "/commandlayer"
end

local function isPath(name)
  return name:match("^[/~%.]") ~= nil
end

-- The folders a profile's settings.json and keybindings.json come from,
-- shipped first and the person's own last -- the one a change is written
-- to. The default profile's are the user folder itself; another's are
-- config/profiles/<name>/ in the Spoon and profiles/<name>/ there; a path
-- is that one folder.
function M.profileFolders(name)
  name = tostring(name or "default")
  if isPath(name) then return { (name:gsub("^~", os.getenv("HOME") or "~")) } end
  if name == "default" then return { M.userDir } end
  return { M.SPOON_DIR .. "config/profiles/" .. name, M.userDir .. "/profiles/" .. name }
end

function M.profileDir()
  local folders = M.profileFolders(M.profile)
  return folders[#folders]
end

function M.chooseProfile()
  if M.profile then return M.profile end
  local data = M.readJSONC(M.userDir .. "/profile.json")
  if type(data) == "table" and type(data.profile) == "string" then return data.profile end
  return "default"
end

----------------------------------------------------------------------
-- FILES THE PREFERENCES COMMANDS OPEN
----------------------------------------------------------------------

local function writeFile(path, text)
  M.makeDirectory(path:match("^(.*)/") or ".")
  local handle = io.open(path, "w")
  if not handle then
    M.log.w("could not write " .. path)
    return nil
  end
  handle:write(text)
  handle:close()
  return path
end

-- A person's file is made, empty, the first time it is asked for, so the
-- editor opens something to write in. Without `initial`, only where it is.
function M.profileFile(name, initial)
  local path = M.profileDir() .. "/" .. name
  if initial == nil or M.readText(path) then return path end
  return writeFile(path, initial)
end

-- Whether the active profile's settings.json or keybindings.json says
-- something other than what the layer last read or wrote. One that does not
-- parse is a problem, and nothing has changed until it parses.
function M.profileFilesChanged()
  local dir, changed = M.profileDir(), false
  for _, name in ipairs({ "settings.json", "keybindings.json" }) do
    local path = dir .. "/" .. name
    local differs, err = M.changedJSONC(path)
    if differs == nil then
      M.problem(path, "does not parse, so it was not read again: " .. tostring(err))
      return false
    end
    changed = changed or differs
  end
  return changed
end

-- A file the Spoon ships in config/: what Default Settings is built over.
function M.shippedFile(name)
  return M.SPOON_DIR .. "config/" .. tostring(name)
end

----------------------------------------------------------------------
-- THE PROFILES THERE ARE
----------------------------------------------------------------------

-- "default", then every profile folder the Spoon ships or the user folder
-- holds: a folder with a settings.json or keybindings.json in it.
function M.profileNames()
  local names, seen = { "default" }, { default = true }
  for _, dir in ipairs({ M.SPOON_DIR .. "config/profiles", M.userDir .. "/profiles" }) do
    local ok, iter, dirObj = pcall(hs.fs.dir, dir)
    if ok and iter then
      local found = {}
      for entry in iter, dirObj do
        if entry:sub(1, 1) ~= "." and not seen[entry]
           and (M.readText(dir .. "/" .. entry .. "/settings.json")
                or M.readText(dir .. "/" .. entry .. "/keybindings.json")) then
          found[#found + 1] = entry
          seen[entry] = true
        end
      end
      table.sort(found)
      for _, name in ipairs(found) do names[#names + 1] = name end
    end
  end
  return names
end
