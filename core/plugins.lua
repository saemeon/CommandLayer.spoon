-- Finding and loading the files in the layer's folders: presenters,
-- extensions, matchers and rankers.

local M = ...

----------------------------------------------------------------------
-- MODULE LOADING
----------------------------------------------------------------------

local SPOON_DIR = M.SPOON_DIR

-- The Spoon's folder, then the user's (M.userDir, found by setup()). A
-- user's file named like a shipped one replaces it: a changed copy of a
-- shipped extension should not run beside the original.
local function roots()
  local out = { SPOON_DIR }
  if M.userDir then out[#out + 1] = M.userDir .. "/" end
  return out
end

-- Every .lua in one of the layer's folders, alphabetically so load order
-- does not depend on the filesystem. dofile rather than require: nothing
-- is cached in package.loaded, so a file wanting another asks
-- cl.modules, and two layers never share a module by accident.
local function eachModule(folder, kind, use)
  local paths = {}
  for _, root in ipairs(roots()) do
    local ok, iter, dirObj = pcall(hs.fs.dir, root .. folder)
    if ok and iter then
      for entry in iter, dirObj do
        local name = entry:match("^(.+)%.lua$")
        if name and entry:sub(1, 1) ~= "." then
          paths[name] = root .. folder .. "/" .. entry
        end
      end
    end
  end

  local names = {}
  for name in pairs(paths) do names[#names + 1] = name end
  table.sort(names)

  for _, name in ipairs(names) do
    local loaded, mod = pcall(dofile, paths[name])
    if loaded then
      use(name, mod)
    else
      M.problem(kind .. " " .. name, "did not load: " .. tostring(mod))
    end
  end
end

-- presenters and rankers share a shape: a file returning a function of the
-- layer. `install` answers whether what came back is
-- usable, since each folder wants a different field present.
local function buildFolder(folder, kind, install)
  eachModule(folder, kind, function(name, make)
    if type(make) ~= "function" then
      M.problem(kind .. " " .. name, "does not return a function of the layer")
      return
    end

    local built, spec = pcall(make, M.pluginAPI(kind, name))
    if not (built and type(spec) == "table" and install(name, spec)) then
      M.problem(kind .. " " .. name, "did not build: " .. tostring(spec))
    end
  end)
end

M.eachModule = eachModule
M.buildFolder = buildFolder

----------------------------------------------------------------------
-- PRESENTERS
----------------------------------------------------------------------

function M.loadPresenters()
  buildFolder("presenters", "presenter", function(name, spec)
    if type(spec.create) ~= "function" then return false end
    M.presenter(name, spec)
    return true
  end)
  return M
end

----------------------------------------------------------------------
-- EXTENSIONS
----------------------------------------------------------------------

M.modules = {}

function M.loadExtensions()
  eachModule("extensions", "extension", function(name, mod)
    if type(mod) ~= "table" or type(mod.extension) ~= "function" then
      M.problem("extension " .. name, "has no extension(cl)")
      return
    end

    M.modules[name] = mod

    -- Named by its file, which is what its API, its settings and its
    -- commands' namespace are keyed by.
    local built, ext = pcall(mod.extension, M.pluginAPI("extension", name))
    if built and type(ext) == "table" and ext.name ~= nil and ext.name ~= name then
      M.problem("extension " .. name, ("is named %q; an extension's name is its file's"):format(tostring(ext.name)))
      M.disposeExtension(name)
    elseif built and type(ext) == "table" then
      ext.name = name
      M.register(ext, mod)
    else
      M.problem("extension " .. name, "did not build: " .. tostring(ext))
    end
  end)

  M.resolveRequires()
  return M
end

----------------------------------------------------------------------
-- MATCHERS AND RANKERS
----------------------------------------------------------------------

-- Everything in matchers/ is loaded. A file there returns a function
-- taking the layer and giving back match(items, query, callback), which
-- returns false to decline -- an unavailable tool, an empty query -- and
-- calls back with the rows kept, best first, and optionally how well each
-- matched: scores[i], 0..1, for rows[i].
function M.loadMatchers()
  eachModule("matchers", "matcher", function(name, make)
    if type(make) ~= "function" then
      M.problem("matcher " .. name, "does not return a function of the layer")
      return
    end

    local built, match = pcall(make, M.pluginAPI("matcher", name))
    if built and type(match) == "function" then
      M.matcher(name, match)
    else
      M.problem("matcher " .. name, "did not build: " .. tostring(match))
    end
  end)
  return M
end

-- A ranker file may also keep track of picks (`picked`, `lastUsed`, `forget`,
-- `reset`) and declare settings, read under its name.
function M.loadRankers()
  buildFolder("rankers", "ranker", function(name, spec)
    if not spec.score then return false end
    M.ranker(name, spec.weight or 1, spec.score)
    for _, entry in ipairs(M.rankers) do
      if entry.name == name then
        entry.settings, entry.picked, entry.lastUsed = spec.settings, spec.picked, spec.lastUsed
        entry.forget, entry.reset = spec.forget, spec.reset
        entry.description, entry.spec = spec.description, spec
      end
    end
    return true
  end)
  return M
end

----------------------------------------------------------------------
-- VIEW FILES
----------------------------------------------------------------------

-- A picker is data, so a Lua file in the user folder's views/ is never run;
-- left there silently, it would look like a picker that stopped working.
function M.noticeViewFiles()
  if not M.userDir then return M end
  local folder = M.userDir .. "/views"
  local ok, iter, dirObj = pcall(hs.fs.dir, folder)
  if not (ok and iter) then return M end
  local names = {}
  for entry in iter, dirObj do
    if entry:match("%.lua$") and entry:sub(1, 1) ~= "." then names[#names + 1] = entry end
  end
  table.sort(names)
  for _, entry in ipairs(names) do
    M.problem(folder .. "/" .. entry, ("views/%s is not read: a picker is declared in settings.json's views, "
                                       .. "and an extension feeds its menus"):format(entry))
  end
  return M
end

----------------------------------------------------------------------
-- UNLOADING
----------------------------------------------------------------------

local function empty(t)
  for k in pairs(t) do t[k] = nil end
end

-- What loading the folders made, undone so they can be loaded again: every
-- extension unregistered with everything it registered, so a file removed
-- since leaves nothing behind, and the other registries emptied.
function M.unloadPlugins()
  local names = {}
  for _, ext in ipairs(M.extensions) do names[#names + 1] = ext.name end
  for _, name in ipairs(names) do M.unregisterExtension(name) end
  empty(M.declaredExtensions)
  empty(M.modules)
  empty(M.presenters)
  empty(M.rankers)
  empty(M.views)
  M.matchers, M.loadedMatchers = {}, nil
  return M
end
