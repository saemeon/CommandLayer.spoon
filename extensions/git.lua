-- Git: clone, init, and the verbs on a repository -- pull, push, fetch,
-- stash, stash pop, checkout -- each a command taking a folder or project.
--
-- Clone is the one with no repository yet, which is what makes it global,
-- and it can only be global because it asks where to put one.

local M = {}

----------------------------------------------------------------------

-- github.com/owner/name, with or without scheme, .git, or trailing path
function M.parseRepo(url)
  if type(url) ~= "string" then return nil end

  local owner, name = url:match("github%.com[:/]([%w._-]+)/([%w._-]+)")
  if not owner or not name then return nil end

  name = name:gsub("%.git$", "")
  if name == "" then return nil end

  return owner .. "/" .. name
end

local function isURL(repo)
  return repo:find("://", 1, true) ~= nil or repo:match("^git@") ~= nil
end

local function repoName(repo)
  local last = repo:gsub("%.git$", ""):match("([^/:]+)$")
  return last or repo
end

M.repoName = repoName

----------------------------------------------------------------------

-- How long your own repositories are kept before gh is asked again, in the
-- background, while the list kept is still what is offered.
M.OWN_REPOS_SECONDS = 300

local function decodeRepos(stdout, alwaysShow)
  local ok, rows = pcall(hs.json.decode, tostring(stdout))
  local results = {}
  for _, row in ipairs(ok and type(rows) == "table" and rows or {}) do
    local full = type(row) == "table" and (row.nameWithOwner or row.fullName)
    if type(full) == "string" then
      results[#results + 1] = { label = full, description = row.description or "", value = full,
                                alwaysShow = alwaysShow }
    end
  end
  return results
end

-- gh rather than the API directly: it already holds your credentials,
-- and asking it for JSON is less code than asking GitHub for it. Nil until
-- the first read has answered.
function M.ownRepos(cl)
  return cl.cached("ownRepos", { seconds = M.OWN_REPOS_SECONDS, refresh = function(done)
    local gh = cl.tools.path("gh")
    if not gh then return done({}) end
    local limit = tostring(cl.setting("git", "searchLimit"))
    -- nil when gh failed -- offline, a token expired -- so your last list
    -- stays and the next prompt asks again, rather than none for five minutes.
    local task = cl.tools.run(gh, { "repo", "list", "--limit", limit, "--json", "nameWithOwner,description" },
      function(code, stdout)
        if code ~= 0 then return done(nil) end
        done(decodeRepos(stdout, nil))
      end)
    if not task then done(nil) end
  end })
end

-- The gh search for the query last asked about: kept while that query is
-- asked again -- a redraw as your repositories land -- rather than run twice.
local searching

-- Your repositories, narrowed by the layer's matcher; with text typed,
-- GitHub's own matches after them, which gh has already matched. `busy`
-- while GitHub has not answered.
function M.searchRepos(cl, query, callback)
  local gh = cl.tools.path("gh")
  if not gh then callback({}) return end

  local function answer(found, busy)
    local rows, mine = {}, {}
    for _, row in ipairs(M.ownRepos(cl) or {}) do
      rows[#rows + 1] = { label = row.label, description = row.description, value = row.value }
      mine[row.value:lower()] = true
    end
    for _, row in ipairs(found or {}) do
      if not mine[row.value:lower()] then rows[#rows + 1] = row end
    end
    callback(rows, busy)
  end

  if searching and searching.query == query then
    searching.answer = answer
    if searching.found then answer(searching.found) elseif M.ownRepos(cl) then answer(nil, true) end
    return
  end
  if searching and searching.task then searching.task:terminate() end
  searching = nil

  if query == "" then
    if M.ownRepos(cl) then answer() end
    return
  end

  local this = { query = query, answer = answer }
  searching = this
  if M.ownRepos(cl) then answer(nil, true) end
  local limit = tostring(cl.setting("git", "searchLimit"))
  this.task = cl.tools.run(gh, { "search", "repos", query, "--limit", limit, "--json", "fullName,description" },
    function(_, stdout)
      if searching ~= this then return end
      this.task, this.found = nil, decodeRepos(stdout, true)
      this.answer(this.found)
    end)
end

----------------------------------------------------------------------

function M.clone(cl, repo, parent)
  if not repo or repo == "" or not parent or parent == "" then
    hs.alert.show("Nothing to clone")
    return
  end

  local github = M.parseRepo(repo)
  local name   = repoName(github or repo)
  local target = parent .. "/" .. name

  local function openIt()
    cl.executeCommand("editor.open", { target = target })
  end

  -- Already there: opening it is what you wanted anyway.
  if hs.fs.attributes(target) then
    hs.alert.show(name .. " is already here")
    openIt()
    return
  end

  -- gh turns owner/name into a URL with the protocol you chose in it; git
  -- is given only a URL, which needs no turning into anything.
  local gh, git = cl.tools.path("gh"), cl.tools.path("git")
  local program, args
  if gh and (github or not isURL(repo)) then
    program, args = gh, { "repo", "clone", github or repo, target }
  elseif git and isURL(repo) then
    program, args = git, { "clone", repo, target }
  else
    hs.alert.show(gh == nil and git ~= nil and "gh not found: clone " .. name .. " by its full URL"
                  or "git not found")
    return
  end

  hs.alert.show("Cloning " .. name .. "...")

  cl.tools.run(program, args, function(code, _, stderr)
    if code ~= 0 then
      hs.alert.show("Clone failed: " .. name)
      cl.log.e("clone " .. repo .. " -> " .. tostring(stderr))
      return
    end
    hs.alert.show("Cloned " .. name)
    openIt()
  end)
end

----------------------------------------------------------------------

-- Runs git in the repository, and says how it went with the last line git
-- printed, which for fetch and stash is the one that matters.
function M.run(cl, path, args, title)
  if type(path) ~= "string" or path == "" then
    hs.alert.show("No repository")
    return
  end
  local git = cl.tools.path("git")
  if not git then
    hs.alert.show("git not found")
    return
  end
  local name = path:match("([^/]+)/?$") or path
  local full = { "-C", path }
  for _, arg in ipairs(args) do full[#full + 1] = arg end
  cl.tools.run(git, full, function(code, stdout, stderr)
    local last = ""
    for line in tostring(code == 0 and stdout or stderr or ""):gmatch("[^\r\n]+") do
      if line:match("%S") then last = line end
    end
    if last == "" then last = code == 0 and "done" or "failed" end
    hs.alert.show(("%s %s: %s"):format(title, name, last))
  end)
end

local branchTask

-- Local branches for checkout to offer, narrowed by git's own pattern. What
-- was typed is offered as it stands too: git checks out a remote branch by
-- its name alone.
function M.searchBranches(cl, path, query, callback)
  local git = cl.tools.path("git")
  if not git or type(path) ~= "string" or path == "" then
    callback({})
    return
  end
  if branchTask then
    branchTask:terminate()
    branchTask = nil
  end
  query = tostring(query or "")
  local args = { "-C", path, "branch", "--list", "--ignore-case", "--format=%(refname:short)" }
  if query ~= "" then args[#args + 1] = "*" .. query .. "*" end
  local task
  task = cl.tools.run(git, args, function(code, stdout)
    if branchTask == task then branchTask = nil end
    local rows, listed = {}, false
    for line in tostring(code == 0 and stdout or ""):gmatch("[^\r\n]+") do
      rows[#rows + 1] = { label = line, value = line }
      if line == query then listed = true end
    end
    if query ~= "" and not listed then
      rows[#rows + 1] = { label = query, description = "Branch name", value = query, alwaysShow = true }
    end
    callback(rows)
  end)
  branchTask = task
end

local stashTask

-- The stashes there are, for the commands that take one. `%gd` is the ref
-- git's own commands take (`stash@{0}`), `%gs` what it was made from.
function M.searchStashes(cl, path, callback)
  local git = cl.tools.path("git")
  if not git or type(path) ~= "string" or path == "" then
    callback({})
    return
  end
  if stashTask then
    stashTask:terminate()
    stashTask = nil
  end
  local task
  task = cl.tools.run(git, { "-C", path, "stash", "list", "--format=%gd\t%gs" }, function(code, stdout)
    if stashTask == task then stashTask = nil end
    local rows = {}
    for line in tostring(code == 0 and stdout or ""):gmatch("[^\r\n]+") do
      local ref, subject = line:match("^([^\t]+)\t(.*)$")
      if ref then
        rows[#rows + 1] = { label = subject ~= "" and subject or ref, description = ref, value = ref }
      end
    end
    if #rows == 0 then
      rows[1] = { label = "No stashes", description = "Nothing has been stashed here",
                  enabled = false, alwaysShow = true }
    end
    callback(rows)
  end)
  stashTask = task
end

-- A folder that already holds a repository is left alone: git would only
-- say it reinitialised one.
function M.init(cl, path)
  if type(path) ~= "string" or path == "" then
    hs.alert.show("No folder to initialise")
    return
  end
  local name = path:match("([^/]+)/?$") or path
  if hs.fs.attributes(path .. "/.git") then
    hs.alert.show(name .. " is already a repository")
    return
  end
  local git = cl.tools.path("git")
  if not git then
    hs.alert.show("git not found")
    return
  end
  cl.tools.run(git, { "-C", path, "init" }, function(code, _, stderr)
    if code ~= 0 then
      hs.alert.show("git init failed: " .. name)
      cl.log.e("git init " .. path .. " -> " .. tostring(stderr))
      return
    end
    hs.alert.show("Initialised a repository in " .. name)
  end)
end

local function chooseFolder(prompt)
  local chosen = hs.dialog.chooseFileOrFolder(prompt, os.getenv("HOME"), false, true, false)
  return chosen and (chosen["1"] or chosen[1]) or nil
end

function M.extension(cl)
  cl.tools.register("git", { "/opt/homebrew/bin/git", "/usr/bin/git" })
  cl.tools.register("gh",  { "/opt/homebrew/bin/gh", "/usr/local/bin/gh" })

  -- For `when` clauses about a folder or project row.
  cl.itemContextKey("gitRepository", function(subject)
    return type(subject.path) == "string" and hs.fs.attributes(subject.path .. "/.git") ~= nil
  end)

  -- For a url row, wherever it comes from: a GitHub URL on the clipboard.
  cl.itemContextKey("githubRepository", function(subject)
    return M.parseRepo(subject.value) ~= nil
  end)

  -- What every command on a repository asks for when run from search, and
  -- is given on a repository row's cmd+k.
  local function inRepository()
    return {
      id = "repo", description = "Which repository",
      picker = { when = "(viewItem == 'project' || viewItem == 'folder') && gitRepository",
                 menus = { "recent", "files" } },
    }
  end

  local gitMenus = { "root", "commandPalette" }

  local function repositoryCommand(id, title, icon, args)
    return {
      id = "git." .. id, title = title, category = "Git", icon = icon, menus = gitMenus,
      inputs = { inRepository() },
      run = function(a) M.run(cl, a.repo and a.repo.path, args, title) end,
    }
  end

  -- What can ask for credentials, stop on a conflict or print more than a
  -- line runs where it can be seen and answered.
  local function inTerminal(path, cmd, title, ctx)
    if type(path) ~= "string" or path == "" then
      hs.alert.show("No repository")
      return
    end
    if not cl.tools.path("git") then
      hs.alert.show("git not found")
      return
    end
    cl.executeCommand("terminal.run", { cmd = cmd, target = path, title = "Git: " .. title }, ctx)
  end

  -- The branch the command acts on, listed by git itself as Checkout lists
  -- them; what was typed is offered too, for a branch git has not got.
  local function branchInput(description)
    return {
      id = "branch", description = description or "Branch",
      picker = { kind = "search", search = function(query, _, args, callback)
        M.searchBranches(cl, type(args.repo) == "table" and args.repo.path or nil, query, callback)
      end },
    }
  end

  local function stashInput()
    return {
      id = "stash", description = "Which stash",
      picker = { kind = "search", search = function(_, _, args, callback)
        M.searchStashes(cl, type(args.repo) == "table" and args.repo.path or nil, callback)
      end },
    }
  end

  -- A name git will take: no spaces, no characters a ref cannot hold.
  local function nameInput(description)
    return {
      id = "name", description = description, pattern = "^[%w%._/%-]+$",
      picker = { typed = true },
    }
  end

  -- Where the rest of the Git commands live: the palette lists them all,
  -- the root keeps the few that are reached for.
  local paletteMenus = { "commandPalette" }

  local function paletteOnly(command)
    command.menus = paletteMenus
    return command
  end

  -- What may stop on a conflict runs in the terminal and takes a branch.
  local function branchCommand(id, title, icon, build)
    return {
      id = "git." .. id, title = title, category = "Git", icon = icon, menus = paletteMenus,
      inputs = { inRepository(), branchInput() },
      run = function(a, ctx) inTerminal(a.repo and a.repo.path, build(a.branch), title, ctx) end,
    }
  end

  -- Names what it acts on and asks first, unless git.confirmDestructive is
  -- off: the same shape Push has for what leaves the machine.
  local function destructive(command, name, verb)
    command.targetName = name
    command.confirm = function(args)
      if cl.setting("git", "confirmDestructive") == false then return nil end
      local what = name(args)
      return what and (verb .. " " .. what .. "?") or nil
    end
    return command
  end

  local function terminalCommand(id, title, icon, cmd)
    return {
      id = "git." .. id, title = title, category = "Git", icon = icon, menus = gitMenus,
      inputs = { inRepository() },
      run = function(a, ctx) inTerminal(a.repo and a.repo.path, cmd, title, ctx) end,
    }
  end

  -- A folder row has a path and no name.
  local function repositoryName(args)
    local repo = type(args.repo) == "table" and args.repo or nil
    if not repo then return nil end
    return repo.name or (type(repo.path) == "string" and repo.path:gsub("/+$", ""):match("[^/]+$")) or nil
  end

  -- What leaves the machine is named, and asked about first.
  local push = terminalCommand("push", "Push", "$(repo-push)", { "git", "push" })
  push.targetName = repositoryName
  push.confirm = function(args)
    if cl.setting("git", "confirmPush") == false then return nil end
    local name = repositoryName(args)
    return name and ("Push " .. name .. "?") or "Push this repository?"
  end

  -- Asked for last, so the repository is already known by the time you
  -- are choosing where it goes.
  local function destination()
    return {
      id          = "parent",
      description = "Clone into",
      picker      = { options = function()
        local options, home = {}, os.getenv("HOME") or ""
        for _, root in ipairs(cl.setting("git", "cloneRoots") or {}) do
          if type(root) == "string" and root ~= "" then
            options[#options + 1] = {
              label       = root,
              description = "Clone root",
              value       = root:gsub("^~", function() return home end),
            }
          end
        end
        options[#options + 1] = {
          label       = "Choose…",
          description = "Pick a folder",
          -- A function is called when chosen, and nil cancels.
          value       = function() return chooseFolder("Clone into") end,
        }
        return options
      end },
    }
  end

  -- Without gh there is nothing to search, so what you typed is the
  -- repository; the clone itself does not need gh. Decided per keystroke,
  -- because the command is registered before tools are looked for again.
  local function source()
    return {
      id          = "repo",
      description = "Repository",
      picker      = { kind = "search", search = function(query, _, _, callback)
        if cl.tools.path("gh") then
          M.searchRepos(cl, query, callback)
        elseif query ~= "" then
          callback({ { label = query, description = "Repository URL", value = query, alwaysShow = true } })
        else
          callback({})
        end
      end },
    }
  end

  return {
    name  = "git",
    rank  = 0.43,
    menus = { "root", "commandPalette" },
    extensionDependencies = { "terminal" },

    settings = {
      cloneRoots = { type = "array", default = {},
                     description = "Folders offered to clone into; ~ is your home folder" },
      searchLimit = { type = "integer", default = 25,
                      description = "The most repositories gh finds for a clone" },
      confirmPush = { type = "boolean", default = true,
                      description = "Ask before pushing" },
      confirmDestructive = { type = "boolean", default = true,
                             description = "Ask before deleting a branch or dropping a stash" },
    },

    commands = {
      { id = "git.clone", title = "Clone…", category = "Git", icon = "$(repo-clone)",
        menus = { "root", "commandPalette" },
        inputs = { source(), destination() },
        run = function(args) M.clone(cl, args.repo, args.parent) end },

      -- On a url row the repository is known, so only the destination is
      -- asked for.
      { id = "git.cloneRepository", title = "Clone repository", category = "Git",
        icon = "$(repo-clone)",
        menus = { ["view/item/context"] = { when = "githubRepository" } },
        inputs = { { id = "url", description = "Which repository",
                     picker = { when = "viewItem == 'url'" } },
                   destination() },
        run = function(args)
          M.clone(cl, type(args.url) == "table" and args.url.value or nil, args.parent)
        end },

      -- Asks for a folder when run from search; on a folder or project row
      -- (cmd+k) it has one.
      { id = "git.init", title = "Init", category = "Git", icon = "$(repo)",
        menus = { "root", "commandPalette" },
        inputs = { {
          id = "folder", description = "Initialise a repository in",
          picker = {
            when = "(viewItem == 'folder' || viewItem == 'project') && !gitRepository",
            menus = { "files", "recent" },
            options = { {
              label = "Choose…", description = "Pick a folder",
              value = function()
                local path = chooseFolder("Initialise a repository in")
                return path and { kind = "folder", path = path } or nil
              end,
            } },
          },
        } },
        run = function(args) M.init(cl, args.folder and args.folder.path) end },

      terminalCommand("pull", "Pull", "$(repo-pull)", { "git", "pull" }),
      push,
      repositoryCommand("fetch", "Fetch", "$(repo-fetch)", { "fetch" }),
      repositoryCommand("stash", "Stash", "$(git-stash)", { "stash" }),
      repositoryCommand("stashPopLatest", "Pop latest stash", "$(git-stash-pop)", { "stash", "pop" }),

      { id = "git.checkout", title = "Checkout…", category = "Git", icon = "$(source-control)",
        menus = gitMenus,
        inputs = { inRepository(), branchInput() },
        run = function(a, ctx)
          inTerminal(a.repo and a.repo.path, { "git", "checkout", a.branch }, "Checkout", ctx)
        end },

      -- The rest of VS Code's Git commands, in the palette rather than the
      -- root: the five above are the ones reached for, and fifteen more
      -- would fill a list you open on.
      terminalCommand("pullRebase", "Pull (rebase)", "$(repo-pull)", { "git", "pull", "--rebase" }),
      -- One line rather than a list, so the shell it is typed into reads the
      -- `&&`: pushing what was just rebased, as VS Code's Sync does.
      terminalCommand("sync", "Sync", "$(sync)", "git pull --rebase && git push"),
      terminalCommand("publish", "Publish branch", "$(repo-push)",
                      { "git", "push", "--set-upstream", "origin", "HEAD" }),
      paletteOnly(repositoryCommand("fetchPrune", "Fetch (prune)", "$(repo-fetch)", { "fetch", "--prune" })),
      paletteOnly(repositoryCommand("fetchAll", "Fetch from all remotes", "$(repo-fetch)",
                                    { "fetch", "--all" })),
      paletteOnly(repositoryCommand("stashIncludeUntracked", "Stash (include untracked)", "$(git-stash)",
                                    { "stash", "--include-untracked" })),

      branchCommand("merge", "Merge branch…", "$(git-merge)",
                    function(branch) return { "git", "merge", branch } end),
      branchCommand("rebase", "Rebase branch…", "$(git-merge)",
                    function(branch) return { "git", "rebase", branch } end),

      -- Made in a task: it prints a line and cannot ask anything.
      { id = "git.branch", title = "Create branch…", category = "Git", icon = "$(git-branch)",
        menus = paletteMenus,
        inputs = { inRepository(), nameInput("New branch") },
        run = function(a) M.run(cl, a.repo and a.repo.path, { "checkout", "-b", a.name }, "Create branch") end },

      { id = "git.renameBranch", title = "Rename branch…", category = "Git", icon = "$(git-branch)",
        menus = paletteMenus,
        inputs = { inRepository(), nameInput("Rename the branch to") },
        run = function(a) M.run(cl, a.repo and a.repo.path, { "branch", "--move", a.name }, "Rename branch") end },

      -- What throws work away names it and asks first, as Push does.
      destructive({ id = "git.deleteBranch", title = "Delete branch…", category = "Git", icon = "$(trash)",
        menus = paletteMenus,
        inputs = { inRepository(), branchInput("Branch to delete") },
        run = function(a) M.run(cl, a.repo and a.repo.path, { "branch", "--delete", a.branch }, "Delete branch") end },
        function(args) return type(args.branch) == "string" and args.branch or nil end,
        "Delete branch"),

      { id = "git.stashPop", title = "Pop stash…", category = "Git", icon = "$(git-stash-pop)",
        menus = paletteMenus,
        inputs = { inRepository(), stashInput() },
        run = function(a) M.run(cl, a.repo and a.repo.path, { "stash", "pop", a.stash }, "Pop stash") end },

      { id = "git.stashApply", title = "Apply stash…", category = "Git", icon = "$(git-stash-apply)",
        menus = paletteMenus,
        inputs = { inRepository(), stashInput() },
        run = function(a) M.run(cl, a.repo and a.repo.path, { "stash", "apply", a.stash }, "Apply stash") end },

      destructive({ id = "git.stashDrop", title = "Drop stash…", category = "Git", icon = "$(trash)",
        menus = paletteMenus,
        inputs = { inRepository(), stashInput() },
        run = function(a) M.run(cl, a.repo and a.repo.path, { "stash", "drop", a.stash }, "Drop stash") end },
        function(args) return type(args.stash) == "string" and args.stash or nil end,
        "Drop stash"),

      -- --soft keeps the changes staged, so nothing written is lost.
      { id = "git.undoCommit", title = "Undo last commit", category = "Git", icon = "$(discard)",
        menus = paletteMenus,
        inputs = { inRepository() },
        run = function(a) M.run(cl, a.repo and a.repo.path, { "reset", "--soft", "HEAD~1" }, "Undo") end },
    },
  }
end

return M
