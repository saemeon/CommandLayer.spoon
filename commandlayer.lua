-- The kernel. Loading defines things and binds nothing; start() does.
--
-- Split across core/ by concern. The order below is load order, and it
-- matters: a core file may alias, as it loads, what an earlier one put
-- on M.

-- The kernel's table. The harness passes one in to read the kernel it
-- checks; Hammerspoon passes nothing, and is given only the public layer.
local given = ...
local M = type(given) == "table" and given or {}

-- From this chunk, because package.path does not reach inside a .spoon
-- bundle and require() cannot find anything in it.
M.SPOON_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"

local CORE = {
  "loading", "performance", "problems", "jsonc", "profiles", "tools", "chords", "context", "when",
  "session", "disposables", "items", "commands", "extensions", "ranking", "presenters",
  "viewregistry", "sections", "stack", "inputs", "views", "controls", "settings",
  "schema", "keybindings", "api", "plugins", "lifecycle",
}

for _, name in ipairs(CORE) do
  -- assert rather than pcall: a kernel file that does not load is a
  -- broken kernel, and carrying on would fail somewhere far less clear.
  assert(loadfile(M.SPOON_DIR .. "core/" .. name .. ".lua"))(M)
end

return M.public
