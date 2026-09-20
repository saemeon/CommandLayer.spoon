-- CommandLayer.spoon/tests/extensions/git.lua
-- The git extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.git

local git, ctx = M, cl.buildContext()
check("parses a plain repo URL",
      git.parseRepo("https://github.com/anthropics/claude-code") == "anthropics/claude-code")
check("parses one with .git",
      git.parseRepo("https://github.com/foo/bar.git") == "foo/bar")
check("parses ssh form",
      git.parseRepo("git@github.com:foo/bar.git") == "foo/bar")
check("ignores a non-repo github URL",
      git.parseRepo("https://github.com/settings") == nil)
check("ignores a non-github URL",
      git.parseRepo("https://example.com/foo/bar") == nil)
check("ignores rubbish", git.parseRepo("nonsense") == nil)

local function cloneOn(value)
  for _, v in ipairs(cl.itemActions({ kind = "url", value = value }, ctx)) do
    if v.command == "git.cloneRepository" then return v end
  end
end
local clone = cloneOn("https://github.com/anthropics/claude-code")
check("a github url subject offers a clone verb", clone ~= nil)
if clone then
  check("with the repository already answered",
        clone.args and clone.args.url and clone.args.url.value == "https://github.com/anthropics/claude-code")
  local left = {}
  for _, input in ipairs(cl.getCommand("git.cloneRepository").inputs) do
    if clone.args[input.id] == nil then left[#left + 1] = input.id end
  end
  check("and only the destination left to ask", table.concat(left, " ") == "parent",
        table.concat(left, " "))
end

check("a non-github url offers no clone verb", cloneOn("https://example.com") == nil)

check("clone target name drops .git",
      git.repoName("https://github.com/foo/bar.git") == "bar")

local tasks, alerts = {}, {}
local saved = { new = hs.task.new, path = cl.tools.path, alert = hs.alert.show }
hs.task.new = function(_, _, _, args)
  tasks[#tasks + 1] = table.concat(args, " ")
  return { start = function(t) return t end }
end
cl.tools.path = function(name)
  if name == "git" then return "/fake/git" end
  return saved.path(name)
end
hs.alert.show = function(message) alerts[#alerts + 1] = message end
local plain = os.tmpname() .. "-plain"
local repo = os.tmpname() .. "-repo"
os.execute(("mkdir -p %q %q/.git"):format(plain, repo))

cl.executeCommand("git.init", { folder = { kind = "folder", path = plain } })
cl.executeCommand("git.init", { folder = { kind = "project", path = repo } })
local offered = {}
for _, subject in ipairs({ { kind = "folder", path = plain }, { kind = "project", path = repo },
                           { kind = "file", path = plain .. "/x" } }) do
  local found = false
  for _, v in ipairs(cl.itemActions(subject, cl.buildContext())) do
    if v.command == "git.init" then found = true end
  end
  offered[#offered + 1] = tostring(found)
end

os.execute(("rm -rf %q %q"):format(plain, repo))
hs.task.new, cl.tools.path, hs.alert.show = saved.new, saved.path, saved.alert
check("Git: Init runs git init in the folder it is given",
      tasks[1] == "-C " .. plain .. " init", tostring(tasks[1]))
check("and leaves a folder that already is a repository alone, saying so",
      #tasks == 1 and (alerts[#alerts] or ""):find("already", 1, true) ~= nil,
      tostring(alerts[#alerts]))
check("Init is offered on a folder that is not a repository, not on one that is, nor on files",
      table.concat(offered, " ") == "true false false", table.concat(offered, " "))

local ran, told, inTerminal = {}, {}, {}
local restore = { new = hs.task.new, path = cl.tools.path, alert = hs.alert.show }
hs.task.new = function(_, callback, _, args)
  local t = { args = table.concat(args, " "), done = callback, terminated = false }
  function t.start(self) return self end
  function t.terminate(self) self.terminated = true end
  ran[#ran + 1] = t
  return t
end
local gitPath = "/fake/git"
cl.tools.path = function(name)
  if name == "git" then return gitPath end
  return restore.path(name)
end
hs.alert.show = function(message) told[#told + 1] = message end
local realTerminal = cl.getCommand("terminal.run")
cl.registerCommand("terminal.run", { title = "spy", menus = {},
                                     run = function(args) inTerminal[#inTerminal + 1] = args end })
local repoDir = os.tmpname() .. "-gitrepo"
local plainDir = os.tmpname() .. "-gitplain"
os.execute(("mkdir -p %q/.git %q"):format(repoDir, plainDir))

local function offeredOn(subject)
  local ids = {}
  for _, v in ipairs(cl.itemActions(subject, cl.buildContext())) do
    if v.command then ids[v.command] = true end
  end
  return ids
end
local onRepo = offeredOn({ kind = "project", path = repoDir })
local onPlain = offeredOn({ kind = "folder", path = plainDir })
check("pull, push, fetch, stash and checkout are on a repository's cmd+k, not a plain folder's",
      onRepo["git.pull"] and onRepo["git.push"] and onRepo["git.fetch"] and onRepo["git.stash"]
      and onRepo["git.stashPop"] and onRepo["git.checkout"] and not onRepo["git.init"]
      and not onPlain["git.pull"] and onPlain["git.init"] == true)

local function shownRun(args)
  return args and ("%s @ %s (%s)"):format(table.concat(args.cmd or {}, " "), tostring(args.target),
                                          tostring(args.title)) or "nothing"
end

local settingsBefore = cl.userSettings
local startedBefore = #ran
cl.executeCommand("git.pull", { repo = { kind = "project", path = repoDir } })
cl.userSettings = { ["git.confirmPush"] = false }
cl.executeCommand("git.push", { repo = { kind = "project", path = repoDir } })
cl.userSettings = settingsBefore
cl.executeCommand("git.checkout", { repo = { kind = "project", path = repoDir }, branch = "feature" })
local pull, push, checkout = inTerminal[1], inTerminal[2], inTerminal[3]
check("Pull, Push and Checkout run git in the terminal, in the repository, nothing in the background",
      #inTerminal == 3 and #ran == startedBefore
      and shownRun(pull) == "git pull @ " .. repoDir .. " (Git: Pull)"
      and shownRun(push) == "git push @ " .. repoDir .. " (Git: Push)"
      and shownRun(checkout) == "git checkout feature @ " .. repoDir .. " (Git: Checkout)",
      shownRun(pull) .. " / " .. shownRun(push) .. " / " .. shownRun(checkout) .. " / " .. (#ran - startedBefore))

gitPath = nil
cl.executeCommand("git.pull", { repo = { kind = "project", path = repoDir } })
gitPath = "/fake/git"
check("without git, Pull runs nothing in the terminal and says so",
      #inTerminal == 3 and told[#told] == "git not found", tostring(told[#told]))

cl.executeCommand("git.fetch", { repo = { kind = "project", path = repoDir } })
local fetch = ran[#ran]
if fetch then fetch.done(0, "From github.com:a/b\n * branch main -> FETCH_HEAD\n", "") end
local fetchedSaid = told[#told]
cl.executeCommand("git.stash", { repo = { kind = "project", path = repoDir } })
local stash = ran[#ran]
if stash then stash.done(1, "", "error: could not write index\n") end
check("Fetch and Stash still run git in the background and show the last line git printed",
      #inTerminal == 3 and fetch ~= nil and fetch.args == "-C " .. repoDir .. " fetch"
      and stash ~= fetch and stash.args == "-C " .. repoDir .. " stash"
      and (fetchedSaid or ""):find("FETCH_HEAD", 1, true) ~= nil
      and (told[#told] or ""):find("could not write index", 1, true) ~= nil,
      tostring(fetch and fetch.args) .. " / " .. tostring(fetchedSaid) .. " / " .. tostring(told[#told]))

local function verbOn(subject, id)
  for _, v in ipairs(cl.itemActions(subject, cl.buildContext())) do
    if v.command == id then return v end
  end
end
local namedPush = verbOn({ kind = "project", path = repoDir, name = "layer" }, "git.push")
local folderPush = verbOn({ kind = "folder", path = repoDir .. "/" }, "git.push")
local pullRow = verbOn({ kind = "project", path = repoDir, name = "layer" }, "git.pull")
local pushCommand = cl.getCommand("git.push")
local question = cl.confirmText(pushCommand, { repo = { kind = "project", path = repoDir, name = "layer" } }, {})
cl.userSettings = { ["git.confirmPush"] = false }
local noQuestion = cl.confirmText(pushCommand, { repo = { kind = "project", path = repoDir, name = "layer" } }, {})
cl.userSettings = settingsBefore
check("Push names the repository, a folder by its last part, and asks first unless git.confirmPush is off",
      namedPush and namedPush.label == "Push -- layer"
      and folderPush and folderPush.label == "Push -- " .. repoDir:match("[^/]+$")
      and pullRow and pullRow.label == "Pull" and question == "Push layer?" and noQuestion == nil,
      ("%s / %s / %s / %s"):format(tostring(namedPush and namedPush.label), tostring(folderPush and folderPush.label),
        tostring(question), tostring(noQuestion)))

local branchInput = cl.getCommand("git.checkout").inputs[2].picker
local answers = {}
local function answer(rows) answers[#answers + 1] = rows end
local function labels(rows)
  local out = {}
  for i, row in ipairs(rows or {}) do out[i] = row.label .. "=" .. tostring(row.value) end
  return table.concat(out, " ")
end
local repoArgs = { repo = { kind = "project", path = repoDir } }
local beforeSearch = #ran
branchInput.search("", {}, repoArgs, answer)
local all = ran[#ran]
all.done(0, "main\nfeature\n", "")
branchInput.search("fea", {}, repoArgs, answer)
local narrowed = ran[#ran]
narrowed.done(0, "feature\n", "")
branchInput.search("feature", {}, repoArgs, answer)
local exact = ran[#ran]
branchInput.search("featurex", {}, repoArgs, answer)
local newer = ran[#ran]
newer.done(0, "", "")
local FORMAT = " branch --list --ignore-case --format=%(refname:short)"
check("checkout asks git for the branches in a task, narrowed by git's own pattern, nothing waiting",
      #ran - beforeSearch == 4 and #answers == 3
      and all.args == "-C " .. repoDir .. FORMAT and narrowed.args == "-C " .. repoDir .. FORMAT .. " *fea*"
      and labels(answers[1]) == "main=main feature=feature",
      tostring(all.args) .. " / " .. tostring(narrowed.args) .. " / " .. labels(answers[1]))
check("what was typed is offered as a branch name unless git listed it, and a newer query ends the older git",
      labels(answers[2]) == "feature=feature fea=fea" and labels(answers[3]) == "featurex=featurex"
      and exact.terminated and not newer.terminated,
      labels(answers[2]) .. " / " .. labels(answers[3]) .. " / " .. tostring(exact.terminated))

-- The rest of VS Code's Git commands: what may stop on a conflict or ask
-- something in the terminal, what prints a line in a task.
local beforeMore, terminalBefore = #ran, #inTerminal
cl.executeCommand("git.pullRebase", repoArgs)
cl.executeCommand("git.sync", repoArgs)
cl.executeCommand("git.merge", { repo = repoArgs.repo, branch = "feature" })
cl.executeCommand("git.rebase", { repo = repoArgs.repo, branch = "main" })
local rebased, synced = inTerminal[terminalBefore + 1], inTerminal[terminalBefore + 2]
local merged, rebasedOnto = inTerminal[terminalBefore + 3], inTerminal[terminalBefore + 4]
check("Pull (rebase), Sync, Merge branch and Rebase branch run in the terminal, in the repository",
      #inTerminal - terminalBefore == 4 and #ran == beforeMore
      and shownRun(rebased) == "git pull --rebase @ " .. repoDir .. " (Git: Pull (rebase))"
      and synced and synced.cmd == "git pull --rebase && git push"
      and shownRun(merged) == "git merge feature @ " .. repoDir .. " (Git: Merge branch…)"
      and shownRun(rebasedOnto) == "git rebase main @ " .. repoDir .. " (Git: Rebase branch…)",
      shownRun(rebased) .. " / " .. tostring(synced and synced.cmd) .. " / " .. shownRun(merged))

-- Nothing asked here: a command that confirms would push a prompt and
-- leave the layer open behind every check after this one.
local function argvOf(id, args)
  local before = #ran
  local settings = cl.userSettings
  cl.userSettings = { ["git.confirmDestructive"] = false }
  cl.executeCommand(id, args)
  cl.userSettings = settings
  local task = #ran > before and ran[#ran] or nil
  if task then task.done(0, "", "") end
  return task and task.args or "nothing"
end
check("Fetch (prune), branch and stash commands run git in a task with what git takes", (function()
        local got = {
          argvOf("git.fetchPrune", repoArgs),
          argvOf("git.fetchAll", repoArgs),
          argvOf("git.branch", { repo = repoArgs.repo, name = "spike" }),
          argvOf("git.renameBranch", { repo = repoArgs.repo, name = "spike2" }),
          argvOf("git.deleteBranch", { repo = repoArgs.repo, branch = "spike" }),
          argvOf("git.stashIncludeUntracked", repoArgs),
          argvOf("git.stashPop", { repo = repoArgs.repo, stash = "stash@{1}" }),
          argvOf("git.stashApply", { repo = repoArgs.repo, stash = "stash@{1}" }),
          argvOf("git.stashDrop", { repo = repoArgs.repo, stash = "stash@{1}" }),
          argvOf("git.undoCommit", repoArgs),
        }
        local want = {
          "fetch --prune", "fetch --all", "checkout -b spike", "branch --move spike2",
          "branch --delete spike", "stash --include-untracked", "stash pop stash@{1}",
          "stash apply stash@{1}", "stash drop stash@{1}", "reset --soft HEAD~1",
        }
        for i, argv in ipairs(want) do
          local expected = "-C " .. repoDir .. " " .. argv
          if got[i] ~= expected then return false, ("%d: %s"):format(i, tostring(got[i])) end
        end
        return true
      end)())

check("deleting a branch and dropping a stash name it and ask first, unless git.confirmDestructive is off",
      (function()
        local del, drop = cl.getCommand("git.deleteBranch"), cl.getCommand("git.stashDrop")
        local delArgs = { repo = repoArgs.repo, branch = "spike" }
        local asked = cl.confirmText(del, delArgs, {})
        local dropped = cl.confirmText(drop, { repo = repoArgs.repo, stash = "stash@{0}" }, {})
        local named = cl.targetText and cl.targetText(del, delArgs, {}) or del.targetName(delArgs)
        cl.userSettings = { ["git.confirmDestructive"] = false }
        local quiet = cl.confirmText(del, delArgs, {})
        cl.userSettings = settingsBefore
        return asked == "Delete branch spike?" and dropped == "Drop stash stash@{0}?"
               and named == "spike" and quiet == nil,
               tostring(asked) .. " / " .. tostring(dropped) .. " / " .. tostring(quiet)
      end)())

check("a stash is chosen from git stash list, and nothing stashed says so", (function()
        local rows = {}
        local stashInput = cl.getCommand("git.stashPop").inputs[2].picker
        stashInput.search("", {}, repoArgs, function(out) rows[1] = out end)
        local listing = ran[#ran]
        local argv = listing and listing.args
        listing.done(0, "stash@{0}\tWIP on main: 1a2b3c a message\nstash@{1}\tOn spike: work\n", "")
        stashInput.search("", {}, repoArgs, function(out) rows[2] = out end)
        ran[#ran].done(0, "", "")
        return argv == "-C " .. repoDir .. " stash list --format=%gd\t%gs"
               and labels(rows[1]) == "WIP on main: 1a2b3c a message=stash@{0} On spike: work=stash@{1}"
               and rows[2] and #rows[2] == 1 and rows[2][1].enabled == false,
               tostring(argv) .. " / " .. labels(rows[1])
      end)())

check("a branch name with a space is refused, one git takes is not", (function()
        local name = cl.getCommand("git.branch").inputs[2]
        return cl.inputProblem(name, "my branch", {}, {}) ~= nil
               and cl.inputProblem(name, "feature/one-2", {}, {}) == nil,
               tostring(cl.inputProblem(name, "my branch", {}, {}))
      end)())

os.execute(("rm -rf %q %q"):format(repoDir, plainDir))
hs.task.new, cl.tools.path, hs.alert.show = restore.new, restore.path, restore.alert
if realTerminal then cl.registerCommand("terminal.run", realTerminal) end

local cloned, notes = {}, {}
local back = { new = hs.task.new, path = cl.tools.path, alert = hs.alert.show,
               settings = cl.userSettings }
local installed = { git = "/fake/git", gh = "/fake/gh" }
hs.task.new = function(program, _, _, args)
  cloned[#cloned + 1] = program .. " " .. table.concat(args, " ")
  return { start = function(t) return t end, terminate = function() end }
end
cl.tools.path = function(name)
  if installed[name] ~= nil then return installed[name] or nil end
  return back.path(name)
end
hs.alert.show = function(message) notes[#notes + 1] = message end
-- Not made: a clone into a folder already there only opens it.
local parent = os.tmpname() .. "-clones"

cl.executeCommand("git.clone", { repo = "foo/bar", parent = parent })
cl.executeCommand("git.cloneRepository",
                  { url = { kind = "url", value = "https://github.com/foo/baz/pulls" }, parent = parent })
cl.executeCommand("git.clone", { repo = "https://gitlab.com/a/c.git", parent = parent })
installed.gh = false
cl.executeCommand("git.clone", { repo = "https://github.com/foo/bar.git", parent = parent })
local beforeGuess = #cloned
cl.executeCommand("git.clone", { repo = "foo/bar", parent = parent })
local guessed = #cloned - beforeGuess

cl.userSettings = { ["git.cloneRoots"] = { "~/code", "/srv/repos" } }
local roots = cl.getCommand("git.clone").inputs[2].picker.options()
cl.userSettings = back.settings
local noRoots = cl.getCommand("git.cloneRepository").inputs[2].picker.options()
hs.task.new, cl.tools.path, hs.alert.show = back.new, back.path, back.alert

check("a GitHub repository is cloned by gh repo clone, as owner/name, into the folder chosen",
      cloned[1] == "/fake/gh repo clone foo/bar " .. parent .. "/bar"
      and cloned[2] == "/fake/gh repo clone foo/baz " .. parent .. "/baz",
      tostring(cloned[1]) .. " / " .. tostring(cloned[2]))
check("a URL gh does not clone, or any URL without gh, goes to git clone as given",
      cloned[3] == "/fake/git clone https://gitlab.com/a/c.git " .. parent .. "/c"
      and cloned[4] == "/fake/git clone https://github.com/foo/bar.git " .. parent .. "/bar",
      tostring(cloned[3]) .. " / " .. tostring(cloned[4]))
check("without gh, owner/name is not made into a URL: nothing runs, and it says so",
      guessed == 0 and (notes[#notes] or ""):find("full URL", 1, true) ~= nil, tostring(notes[#notes]))
check("where to clone offers git.cloneRoots, ~ expanded, then a folder dialog; only that by default",
      #roots == 3 and roots[1].label == "~/code" and roots[1].value == os.getenv("HOME") .. "/code"
      and roots[2].value == "/srv/repos" and roots[3].label == "Choose…"
      and type(roots[3].value) == "function" and #noRoots == 1 and noRoots[1].label == "Choose…",
      tostring(#roots) .. " / " .. tostring(#noRoots))

check("the branch name typed is kept whatever the matcher makes of it; a branch git listed is matched",
      answers[2] and answers[2][2] and answers[2][2].alwaysShow == true and not answers[2][1].alwaysShow)

-- Git: Clone…'s repositories, through the prompt as the layer draws it.
cl.defaultPresenter = "recording"
local stub, layerModal = T.stub, T.layerModal
local ghTasks, decoded, ghInstalled = {}, {}, "/fake/gh"
stub(hs.task, "new", function(program, done, _, args)
  local t = { program = program, args = table.concat(args or {}, " "), done = done }
  function t.start(self) return self end
  function t.terminate(self) self.terminated = true end
  ghTasks[#ghTasks + 1] = t
  return t
end)
stub(cl.tools, "path", function(name) return name == "gh" and ghInstalled or nil end)
stub(hs.json, "decode", function(text) return decoded[text] end)
decoded.mine = { { nameWithOwner = "me/claude-notes", description = "Notes" }, { nameWithOwner = "me/dotfiles" } }
decoded.found = { { fullName = "anthropics/claude-code" }, { fullName = "Me/Claude-Notes" } }
local matchersBefore = cl.matchers
cl.matchers = T.substringOnly()

local function shownIn(p)
  local out = {}
  for i, row in ipairs(p and p.shown or {}) do
    out[i] = tostring(row.label) .. (row.enabled == false and " (disabled)" or "")
  end
  return table.concat(out, ", ")
end
local seen, listed, firstSearch, secondSearch = {}, 0, nil, nil
local enterBefore = layerModal.enter
layerModal.enter = function(m) m:entered() end
layerModal:exited()
local cloneOk, cloneErr = pcall(function()
  cl.executeCommand("git.clone", {})
  local p = T.lastRecorded()
  seen[1] = shownIn(p)
  local list = ghTasks[#ghTasks]
  if list then list.done(0, "mine", "") end
  seen[2] = shownIn(p)
  p.type("claude")
  firstSearch = ghTasks[#ghTasks]
  seen[3] = shownIn(p)
  p.type("claude-")
  secondSearch = ghTasks[#ghTasks]
  if firstSearch then firstSearch.done(0, "found", "") end
  seen[4] = shownIn(p)
  if secondSearch then secondSearch.done(0, "found", "") end
  seen[5] = shownIn(p)
  layerModal:exited()
  cl.executeCommand("git.clone", {})
  seen[6] = shownIn(T.lastRecorded())
end)
layerModal.enter = enterBefore
layerModal:exited()
cl.matchers = matchersBefore
for _, t in ipairs(ghTasks) do
  if t.args:find("^repo list") then listed = listed + 1 end
end
check("Clone… says it is searching until your repositories are read, then lists them",
      cloneOk and seen[1] == "Searching… (disabled)" and seen[2] == "me/claude-notes, me/dotfiles"
      and ghTasks[1] ~= nil and ghTasks[1].program == "/fake/gh"
      and ghTasks[1].args == "repo list --limit 25 --json nameWithOwner,description",
      tostring(cloneErr) .. " / " .. tostring(seen[1]) .. " / " .. tostring(seen[2]))
check("typing narrows your repositories and asks GitHub too, a newer query ending the older search",
      seen[3] == "me/claude-notes, Searching… (disabled)" and seen[4] == seen[3]
      and firstSearch ~= nil and firstSearch.args == "search repos claude --limit 25 --json fullName,description"
      and firstSearch.terminated == true and secondSearch ~= nil and not secondSearch.terminated,
      tostring(seen[3]) .. " / " .. tostring(seen[4]) .. " / " .. tostring(firstSearch and firstSearch.args))
check("GitHub's matches follow yours, one already yours not repeated, and your list is read once and kept",
      seen[5] == "me/claude-notes, anthropics/claude-code" and seen[6] == "me/claude-notes, me/dotfiles"
      and listed == 1,
      tostring(seen[5]) .. " / " .. tostring(seen[6]) .. " / " .. listed .. " lists")

ghInstalled = nil
local typedRows
cl.getCommand("git.clone").inputs[1].picker.search("https://gitlab.com/a/b.git", {}, {}, function(r) typedRows = r end)
check("without gh, what was typed is offered as the repository URL, whatever the matcher makes of it",
      typedRows ~= nil and #typedRows == 1 and typedRows[1].value == "https://gitlab.com/a/b.git"
      and typedRows[1].alwaysShow == true)
