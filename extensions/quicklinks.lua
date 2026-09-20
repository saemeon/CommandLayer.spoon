-- A URL with a ${query} hole is a command that takes what you type: "?"
-- with text, a fallback when nothing matches, or picking it and being
-- asked. One without a ${query} is a bookmark, a plain row.

local M = {}

M.defaults = {
  { title = "Search GitHub",
    url   = "https://github.com/search?q=${query}" },

  { title = "Search GitHub repositories",
    url   = "https://github.com/search?type=repositories&q=${query}" },

  { title = "Search npm",
    url   = "https://www.npmjs.com/search?q=${query}" },

  { title = "Search MDN",
    url   = "https://developer.mozilla.org/en-US/search?q=${query}" },

  { title = "Search Hammerspoon docs",
    url   = "https://www.hammerspoon.org/search.html?q=${query}" },

  { title = "Search Stack Overflow",
    url   = "https://stackoverflow.com/search?q=${query}" },
}

function M.extension(cl)
  -- Once, where the commands are registered, so the rows never list links the
  -- commands do not have; a change applies on reload.
  local links = cl.setting("quicklinks", "links")
  if type(links) ~= "table" then links = M.defaults end

  -- "Search Stack Overflow" -> "searchStackOverflow", for a command id.
  local function slug(text)
    local out = ""
    for word in tostring(text):gmatch("%w+") do
      out = out .. (out == "" and word:lower()
                    or word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return out
  end

  local commands = {
    { id = "quicklinks.copyURL", title = "Copy URL",
      menus = { ["view/item/context"] = true },
      inputs = { { id = "link", picker = { when = "viewItem == 'quicklink'" } } },
      run = function(args, ctx)
        local link = args.link
        if type(link) ~= "table" then return end
        cl.executeCommand("system.copy", { text = link.url }, ctx)
      end },
  }
  for _, link in ipairs(links) do
    if link.url:find("%${query}") then
      local title = link.title:find("%${query}") and link.title
                    or (link.title .. " for “${query}”")
      commands[#commands + 1] = {
        id = "quicklinks." .. slug(link.title), title = title,
        prefix = link.prefix, menus = { "root", "commandPalette" },
        inputs = { { id = "query", picker = { typed = true },
                     description = link.prompt or link.title,
                     -- It is going into a URL.
                     fromQuery = true, encode = "query" } },
        command = "system.open", args = { target = link.url, title = link.title },
      }
    end
  end

  return {
    name     = "quicklinks",
    settings = {
      links = { type = "array", default = M.defaults,
                description = "Links: { title, url, prefix }; a ${query} in the URL takes what you type" },
    },
    rank     = 0.14,
    menus    = { "root", "commandPalette" },
    commands = commands,

    items = function(ctx)
      local rows = {}
      for _, link in ipairs(links) do
        if not link.url:find("%${query}") then
          rows[#rows + 1] = {
            label       = link.title,
            description = "Quicklink",
            command     = "system.open",
            args        = { target = link.url, title = link.title },
            ctx         = ctx,
            subject     = { kind = "quicklink", name = link.title, url = link.url },
          }
        end
      end
      return rows
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
