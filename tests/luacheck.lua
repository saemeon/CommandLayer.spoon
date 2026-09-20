-- Runs luacheck with the Lua running this, by hand and for the harness:
--   lua tests/luacheck.lua .        (from the Spoon's folder)
-- Exits 3 when luacheck is not installed.
--
-- luacheck 1.2.0 assigns to a for loop's variable in standards.lua, which
-- Lua 5.5 refuses to compile. Where that file does not load as it is, it is
-- loaded with that one loop rewritten; a luacheck that loads is left alone.

if not package.searchpath("luacheck.main", package.path) then
  io.stderr:write("luacheck is not installed\n")
  os.exit(3)
end

table.insert(package.searchers, 2, function(name)
  if name ~= "luacheck.standards" then return nil end
  local path = package.searchpath(name, package.path)
  local handle = path and io.open(path)
  if not handle then return nil end
  local text = handle:read("a")
  handle:close()
  if load(text, "@" .. path) then return nil end

  local fixed = text:gsub("for field_name, field_def in pairs%(fields%) do\n",
                          "for field_name_, field_def_ in pairs(fields) do\n"
                          .. "local field_name, field_def = field_name_, field_def_\n")
  local chunk, err = load(fixed, "@" .. path)
  if not chunk then return "\n\t" .. tostring(err) end
  return chunk, path
end)

require("luacheck.main")
