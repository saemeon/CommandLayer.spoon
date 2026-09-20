-- What a plugin registered and started, undone together.

local M = ...

----------------------------------------------------------------------
-- DISPOSABLES
--
-- What an extension registers lives until it is switched off; what it
-- starts -- timers, watchers, tasks -- until it stops. Each is a
-- disposable in one of two sets, undone together.
----------------------------------------------------------------------

local owners = {}

function M.ownerOf(kind, name)
  local key = kind .. ":" .. name
  if not owners[key] then
    owners[key] = { kind = kind, name = name, registrations = {}, running = {}, caches = {} }
  end
  return owners[key]
end

function M.track(set, undo)
  local d = {}
  function d.dispose()
    if not set[d] then return end
    set[d] = nil
    local ok, err = pcall(undo)
    if not ok then M.log.e("disposing -> " .. tostring(err)) end
  end
  set[d] = true
  return d
end

-- What a registration that did not happen returns, so a caller can always
-- dispose what it was given.
M.nothingToDispose = { dispose = function() end }

local function disposeAll(set)
  local list = {}
  for d in pairs(set) do list[#list + 1] = d end
  for _, d in ipairs(list) do d.dispose() end
end

-- For the kernel's own registrations made on an extension's behalf, undone
-- with the rest of what it registered.
function M.trackRegistration(name, undo)
  return M.track(M.ownerOf("extension", tostring(name)).registrations, undo)
end

-- Stopped with the extension; started again by its start().
function M.stopRunning(name)
  local owner = owners["extension:" .. tostring(name)]
  if not owner then return end
  disposeAll(owner.running)
  owner.caches = {}
end

-- Switched off: everything it started, and everything it registered.
function M.disposeExtension(name)
  local owner = owners["extension:" .. tostring(name)]
  if not owner then return end
  M.stopRunning(name)
  disposeAll(owner.registrations)
end
