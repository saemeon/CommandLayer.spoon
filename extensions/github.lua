-- Repositories, pull requests and issues, through gh.
--
-- Asynchronous and cached: a network call between a keystroke and a
-- redraw is the one thing a launcher cannot afford, so the picker shows
-- what was cached and fills in when the answer lands.

local M = {}

local layer

-- A failed call is an empty answer, kept as long as any other: asking gh
-- again on every keystroke would not make it succeed.
local function fetch(key, args, parse)
  return layer.cached(key, {
    seconds = layer.setting("github", "cacheSeconds"),
    initial = {},
    -- nil rather than {} wherever the call did not work: an empty answer
    -- would stand for the whole of `seconds`, so one failed gh would leave
    -- the picker with nothing until it expired.
    refresh = function(done)
      local gh = layer.tools.path("gh")
      if not gh then return done({}) end
      local task = layer.tools.run(gh, args(tostring(layer.setting("github", "limit"))),
        function(code, stdout)
          if code ~= 0 then return done(nil) end
          local ok, rows = pcall(hs.json.decode, tostring(stdout))
          if not (ok and type(rows) == "table") then return done(nil) end
          done(parse(rows))
        end)
      if not task then done(nil) end
    end,
  })
end

local function numbered(rows)
  local items = {}
  for _, row in ipairs(rows) do
    if row.url then
      local repo = type(row.repository) == "table"
        and (row.repository.nameWithOwner or row.repository.name) or ""
      items[#items + 1] = {
        name  = row.title or row.url,
        about = repo .. " #" .. tostring(row.number or "?"),
        url   = row.url,
      }
    end
  end
  return items
end

----------------------------------------------------------------------

function M.repos()
  return fetch("repos",
    function(limit)
      return { "repo", "list", "--limit", limit, "--json", "nameWithOwner,description,url" }
    end,
    function(rows)
      local items = {}
      for _, row in ipairs(rows) do
        if row.nameWithOwner then
          items[#items + 1] = {
            name = row.nameWithOwner,
            description = row.description or "",
            url = row.url or ("https://github.com/" .. row.nameWithOwner),
          }
        end
      end
      return items
    end)
end

-- Across every repository you can see, not just the one you are in:
-- the launcher has no working directory, and "my pull requests" is the
-- question worth answering from anywhere.
function M.pullRequests()
  return fetch("prs",
    function(limit)
      return { "search", "prs", "--author", "@me", "--state", "open",
               "--limit", limit, "--json", "title,url,repository,number" }
    end,
    numbered)
end

function M.issues()
  return fetch("issues",
    function(limit)
      return { "search", "issues", "--assignee", "@me", "--state", "open",
               "--limit", limit, "--json", "title,url,repository,number" }
    end,
    numbered)
end

local function enabled(key)
  return layer.setting("github", key) ~= false
end

-- Warmed after start so the first look is not the empty one.
function M.start()
  if not (layer and layer.tools.path("gh")) then return end
  layer.after(5, function()
    if enabled("repos") then M.repos() end
    if enabled("pullRequests") then M.pullRequests() end
    if enabled("issues") then M.issues() end
  end)
end

----------------------------------------------------------------------

function M.extension(cl)
  layer = cl
  cl.tools.register("gh", { "/opt/homebrew/bin/gh", "/usr/local/bin/gh" })

  local function row(ctx, label, description, url, name)
    return {
      label       = label,
      description = description,
      command     = "system.open",
      args        = { target = url },
      subject     = { kind = "url", value = url, name = name },
      ctx         = ctx,
    }
  end

  return {
    name        = "github",
    displayName = "GitHub",
    rank        = 0.23,
    menus       = { "root", "commandPalette" },

    settings = {
      limit = { type = "integer", default = 40, description = "The most of each gh lists" },
      -- Long enough that opening the picker twice in a row costs one call,
      -- short enough that a pull request opened five minutes ago shows up.
      cacheSeconds = { type = "integer", default = 300,
                       description = "How long gh's answers are kept, in seconds" },
      repos = { type = "boolean", default = true, description = "Your repositories" },
      pullRequests = { type = "boolean", default = true, description = "Your open pull requests" },
      issues = { type = "boolean", default = true, description = "Open issues assigned to you" },
    },

    items = function(ctx)
      if not cl.tools.path("gh") then return {} end

      local rows = {}

      if enabled("repos") then
        for _, repo in ipairs(M.repos()) do
          rows[#rows + 1] = row(ctx, repo.name,
            "Repository -- " .. (repo.description ~= "" and repo.description or repo.url),
            repo.url, repo.name)
        end
      end

      if enabled("pullRequests") then
        for _, pr in ipairs(M.pullRequests()) do
          rows[#rows + 1] = row(ctx, pr.name, "Pull request -- " .. pr.about, pr.url, pr.name)
        end
      end

      if enabled("issues") then
        for _, issue in ipairs(M.issues()) do
          rows[#rows + 1] = row(ctx, issue.name, "Issue -- " .. issue.about, issue.url, issue.name)
        end
      end

      return rows
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
