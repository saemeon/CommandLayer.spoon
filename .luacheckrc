-- luacheck's settings for the Spoon. Run with:  lua tests/luacheck.lua .
-- (from the Spoon's folder); the harness runs it too, where it is installed.

std = "lua54"
read_globals = { "hs", "spoon" }

-- A method need not use self: the modal calls entered() and exited() with it.
self = false

files["tests"] = {
  -- The harness stubs hs and traps print; a check stands in for spoon.
  globals = { "hs", "print", "spoon" },
  -- Each check is a closure of its own, reusing the names the ones before it used.
  ignore = { "411", "421", "431" },
  max_line_length = false,
}

-- The file guard wraps what changes a file.
files["tests/harness.lua"] = {
  globals = { os = { fields = { "remove", "rename", "tmpname" } }, io = { fields = { "open" } } },
}
