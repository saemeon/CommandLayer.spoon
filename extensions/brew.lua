-- Homebrew's own verbs, run in the terminal terminal.application names, where
-- their output and questions can be seen. None lists formulae: brew takes a
-- second or more to.

local M = {}

M.verbs = {
  { id = "update",   title = "Update",   icon = "$(sync)" },
  { id = "upgrade",  title = "Upgrade",  icon = "$(arrow-up)" },
  { id = "outdated", title = "Outdated", icon = "$(list-unordered)" },
  { id = "doctor",   title = "Doctor",   icon = "$(pulse)" },
  { id = "cleanup",  title = "Cleanup",  icon = "$(trash)" },
}

-- What is typed after the prefix is one word to brew, quoted by terminal.run.
M.textVerbs = {
  { id = "install", title = "Install “${query}”", prefix = "brew install ", icon = "$(cloud-download)",
    description = "Formula or cask to install" },
  { id = "search", title = "Search for “${query}”", prefix = "brew search ", icon = "$(search)",
    description = "Search Homebrew for" },
  { id = "info", title = "Info on “${query}”", prefix = "brew info ", icon = "$(info)",
    description = "Formula or cask" },
}

function M.extension(_)
  local commands = {}
  for _, verb in ipairs(M.verbs) do
    commands[#commands + 1] = {
      id = "brew." .. verb.id, title = verb.title, category = "Brew", icon = verb.icon,
      menus = { "commandPalette", "root" },
      command = "terminal.run",
      args = { cmd = { "brew", verb.id }, title = "Brew: " .. verb.title },
    }
  end
  for _, verb in ipairs(M.textVerbs) do
    commands[#commands + 1] = {
      id = "brew." .. verb.id, title = verb.title, category = "Brew", icon = verb.icon,
      prefix = verb.prefix, menus = { "commandPalette", "root" },
      inputs = { { id = "query", description = verb.description, picker = { typed = true }, fromQuery = true } },
      command = "terminal.run",
      args = { cmd = { "brew", verb.id, "${query}" }, title = "Brew: " .. verb.id },
    }
  end

  return {
    displayName = "Homebrew",
    description = "brew update, upgrade, outdated, doctor, cleanup, install, search and info, in the terminal",
    menus       = {},
    extensionDependencies = { "terminal" },
    commands    = commands,
  }
end

return M
