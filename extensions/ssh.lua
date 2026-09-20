-- The hosts in your ssh config: connected to by ssh in the terminal, or
-- opened as a remote window by the editor.

local M = {}

M.configPath = (os.getenv("HOME") or "") .. "/.ssh/config"

-- An editor saves by writing a new file and renaming it over the old one.
M.readDelay = 0.5

local hosts, readModified = {}, nil

function M.forget()
  hosts, readModified = {}, nil
end

-- A pattern ("*", "?", "!negated") is not somewhere to connect to. A name
-- starting with a dash would reach ssh as an option, and a "$" would be
-- filled as a template by the command it is handed to.
function M.concrete(name)
  return type(name) == "string" and name ~= "" and not name:find("[%*%?!%$%s]")
         and name:sub(1, 1) ~= "-"
end

-- ssh_config's words: whitespace between them, double quotes around one
-- holding spaces.
local function words(text)
  local list, at = {}, 1
  while true do
    local start = text:find("%S", at)
    if not start then break end
    if text:sub(start, start) == '"' then
      local finish = text:find('"', start + 1, true) or (#text + 1)
      list[#list + 1] = text:sub(start + 1, finish - 1)
      at = finish + 1
    else
      local finish = text:find("%s", start) or (#text + 1)
      list[#list + 1] = text:sub(start, finish - 1)
      at = finish
    end
  end
  return list
end

-- The concrete hosts, in the file's order. As ssh reads a config, the first
-- value given for a keyword is the one that counts, and a Match block ends
-- the Host block before it. Include is not followed.
function M.parse(text)
  local out, byName, current = {}, {}, {}
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\r?\n") do
    local keyword, rest = line:match("^%s*([%a]+)%s*=?%s*(.-)%s*$")
    keyword = keyword and keyword:lower()
    if keyword == "host" then
      current = {}
      for _, name in ipairs(words(rest)) do
        if M.concrete(name) then
          local host = byName[name]
          if not host then
            host = { name = name }
            byName[name] = host
            out[#out + 1] = host
          end
          current[#current + 1] = host
        end
      end
    elseif keyword == "match" then
      current = {}
    elseif keyword == "hostname" or keyword == "user" then
      local field = keyword == "hostname" and "hostName" or "user"
      local value = words(rest)[1]
      for _, host in ipairs(current) do
        if host[field] == nil then host[field] = value end
      end
    end
  end
  return out
end

-- Read again only when the file was written since: at start, and when a
-- change in its folder names it. A picker reads the hosts kept.
function M.read()
  local modified = hs.fs.attributes(M.configPath, "modification")
  if type(modified) == "table" then modified = modified.modification end
  if not modified then
    M.forget()
    return false
  end
  if modified == readModified then return false end
  readModified = modified
  local handle = io.open(M.configPath, "r")
  if not handle then return false end
  local text = handle:read("a")
  handle:close()
  hosts = M.parse(text)
  return true
end

-- A host row's subject, or a remote project's, which carries the host too.
local function hostOf(value)
  if type(value) == "table" then value = value.host end
  return M.concrete(value) and value or nil
end

function M.extension(cl)
  local readTimer

  -- The folder rather than the file, so a file replaced rather than written
  -- into is still seen; known_hosts is written there by every connection.
  M.start = function()
    M.read()
    if not hs.pathwatcher then return end
    local folder, file = M.configPath:match("^(.*)/([^/]+)$")
    if not folder then return end
    local watcher = hs.pathwatcher.new(folder, function(paths)
      local named = type(paths) ~= "table"
      for _, path in ipairs(type(paths) == "table" and paths or {}) do
        if tostring(path):match("([^/]+)$") == file then named = true end
      end
      if not named or readTimer then return end
      readTimer = cl.after(M.readDelay, function()
        readTimer = nil
        if M.read() then cl.refresh() end
      end)
    end)
    if watcher then cl.watch(watcher) end
  end

  M.stop = function()
    readTimer = nil
  end

  return {
    name        = "ssh",
    displayName = "SSH",
    description = "The hosts in ~/.ssh/config: ssh in the terminal, or a remote window in the editor",
    rank        = 0.14,
    menus       = { "root" },

    commands = {
      { id = "ssh.connect", title = "Connect in terminal", category = "SSH", icon = "$(terminal)",
        menus = { "commandPalette" }, when = "terminalAvailable",
        inputs = { { id = "host", description = "Which host",
                     picker = { when = "viewItem == 'sshHost' || viewItem == 'remoteProject'", menus = { "root" } } } },
        run = function(args, ctx)
          local host = hostOf(args.host)
          if not host then return end
          return cl.executeCommand("terminal.run",
            { cmd = { "ssh", host }, title = "SSH: Connect to " .. host }, ctx)
        end },

      -- VS Code's Remote - SSH extension answers the authority; the editor
      -- extension runs the CLI.
      { id = "ssh.connectInEditor", title = "Connect in editor", category = "SSH", icon = "$(remote)",
        menus = { "commandPalette" },
        inputs = { { id = "host", description = "Which host",
                     picker = { when = "viewItem == 'sshHost'", menus = { "root" } } } },
        run = function(args, ctx)
          local host = hostOf(args.host)
          if not host then return end
          return cl.executeCommand("editor.open", { remote = "ssh-remote+" .. host }, ctx)
        end },
    },

    items = function(ctx)
      local rows = {}
      for _, host in ipairs(hosts) do
        local address = host.hostName and ((host.user and (host.user .. "@") or "") .. host.hostName)
        rows[#rows + 1] = {
          -- "SSH: alpha", as a command row reads "Category: Title": the
          -- category is what groups them when you type it.
          label       = "SSH: " .. host.name,
          -- A subtitle is never matched, so what the row is called -- "ssh",
          -- and the address it stands for -- is matched beside the name.
          keywords    = address and { "SSH", address } or { "SSH" },
          description = "SSH host" .. (address and (" -- " .. address) or ""),
          iconPath    = "$(remote)",
          command     = ctx and ctx.terminalAvailable and "ssh.connect" or "ssh.connectInEditor",
          args        = { host = { kind = "sshHost", name = host.name, host = host.name } },
          subject     = { kind = "sshHost", name = host.name, host = host.name },
          ctx         = ctx,
        }
      end
      return rows
    end,
  }
end

return M
