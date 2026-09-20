-- CommandLayer.spoon/tests/extensions/ambient.lua
-- The ambient extension's checks.

local T = ...
local check = T.check
local cl = T.layer()


local saved = { get = hs.pasteboard.getContents, types = hs.pasteboard.pasteboardTypes,
                content = hs.pasteboard.contentTypes }
hs.pasteboard.getContents = function() return "hunter2" end
hs.pasteboard.contentTypes = function() return {} end

hs.pasteboard.pasteboardTypes = function() return { "public.utf8-plain-text", "org.nspasteboard.ConcealedType" } end
local concealed = cl.buildContext().clipboard
hs.pasteboard.pasteboardTypes = function() return { "public.utf8-plain-text" } end
local plain = cl.buildContext().clipboard

hs.pasteboard.getContents, hs.pasteboard.pasteboardTypes, hs.pasteboard.contentTypes =
  saved.get, saved.types, saved.content
check("a password copied from a password manager never enters the context, other text does",
      concealed == "" and plain == "hunter2", tostring(concealed) .. " / " .. tostring(plain))

local ambient
for _, e in ipairs(cl.extensions) do
  if e.name == "ambient" then ambient = e end
end
local order = cl.startOrder and cl.startOrder() or {}
local at = {}
for i, name in ipairs(order) do at[name] = i end
check("ambient runs before finder, which reads frontmostApp, and declares its private types as a setting",
      ambient ~= nil and ambient.order == nil
      and (at.finder == nil or (at.ambient ~= nil and at.ambient < at.finder))
      and type(cl.setting("ambient", "privateTypes")) == "table",
      tostring(at.ambient) .. " / " .. tostring(at.finder))

do
  local stub, M = T.stub, cl.modules.ambient
  local flags = hs.network.reachability.flags
  check("online is a route to the internet that needs no connection brought up first",
        M.isOnline(flags.reachable) == true and M.isOnline(flags.reachable | flags.connectionRequired) == false
        and M.isOnline(0) == false and M.isOnline(nil) == nil)

  local callback, asked, stopped, named = nil, 0, 0, 0
  stub(hs.network.reachability, "internet", function()
    local r = {}
    function r.setCallback(self, fn) callback = fn; return self end
    function r.start(self) return self end
    function r.stop(self) stopped = stopped + 1; return self end
    function r.status() asked = asked + 1; return flags.reachable end
    return r
  end)
  local fires = {}
  stub(hs.timer, "doAfter", function(_, fn) fires[#fires + 1] = fn; return { stop = function() end } end)
  stub(hs.host, "localizedName", function() named = named + 1; return "Studio" end)
  M.stop()
  M.start()
  local naming = fires[#fires]
  local before = cl.buildContext()
  if naming then naming() end
  local online = cl.buildContext()
  if callback then callback(nil, 0) end
  local offline = cl.buildContext()
  cl.buildContext()
  check("online and hostname are context keys, kept by macOS's watcher and asked once, never per open",
        before.online == true and before.hostname == nil and online.hostname == "Studio"
        and offline.online == false and offline.hostname == "Studio" and asked == 1 and named == 1
        and cl.when("!online && hostname == 'Studio'", offline) and cl.when("online", online),
        ("%s %s / %s asks, %s names"):format(tostring(before.online), tostring(offline.online), asked, named))
  M.stop()
  local afterStop = cl.buildContext()
  check("stopping stops the reachability watcher, and online is no longer claimed",
        stopped == 1 and afterStop.online == nil, stopped .. " stops")
end
