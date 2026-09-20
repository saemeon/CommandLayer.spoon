-- A URL typed into the picker is a `url` subject: picking the row opens it,
-- and cmd+k offers what every link row already has -- Open with…, Copy URL,
-- cloning a repository -- from the extensions that own those verbs.

local M = {}

-- Longer than any address a person types, and the gate stays cheap.
local MAX_LENGTH = 2048

-- What reads as an address, and nothing looser: a bare `readme.md` or
-- `notes.py` is a file being searched for, not a domain.
function M.parse(query)
  if type(query) ~= "string" or #query < 4 or #query > MAX_LENGTH then return nil end
  -- Most of what is typed has neither, and this runs on every keystroke.
  if not (query:find(".", 1, true) or query:find(":", 1, true)) then return nil end

  local text = query:match("^%s*(.-)%s*$")
  if text:find("%s") then return nil end

  local url
  if text:match("^%a[%w+.-]*://[^/%s]") or text:match("^file:///.") then
    url = text
  elseif text:match("^www%.[%w-]+%.[%w.-]*%a") or text:match("^[%w-]+%.[%w.-]*%a/") then
    url = "https://" .. text
  end
  if not url then return nil end
  -- system.open fills its target as a template, and braces are not legal in
  -- a URL unencoded anyway.
  return (url:gsub("[{}]", { ["{"] = "%7B", ["}"] = "%7D" }))
end

function M.extension()
  return {
    name        = "url",
    displayName = "URL",
    description = "A typed URL: open it, or cmd+k for Open with…, Copy URL and the other link verbs",
    -- Nothing standing; it only ever answers a query.
    menus       = {},

    query = function(query, ctx)
      local url = M.parse(query)
      if not url then return {} end
      return { {
        label       = url,
        description = "Open URL",
        icon        = "$(link-external)",
        ctx         = ctx,
        command     = "system.open",
        args        = { target = url },
        subject     = { kind = "url", value = url },
      } }
    end,
  }
end

return M
