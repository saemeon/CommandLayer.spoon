-- CommandLayer.spoon/tests/extensions/codicons.lua
-- The codicons extension's checks.

local T = ...
local check = T.check
local cl = T.layer()
local M = cl.modules.codicons

local canvases = {}
local saved = { new = hs.canvas and hs.canvas.new, valid = hs.styledtext.validFont }
hs.canvas = hs.canvas or {}
hs.canvas.new = function()
  local c = {}
  function c:imageFromCanvas() return { drawn = self[1] } end
  function c:delete() end
  canvases[#canvases + 1] = c
  return c
end
local fontInstalled = true
hs.styledtext.validFont = function(name) return fontInstalled and name == "codicon" end
M.forget()

check("codicon names map to the font's character codes",
      M.codepoint("repo-clone") == 0xEB3E and M.codepoint("refresh") == 0xEB37
      and M.codepoint("no-such-icon") == nil)

local first = M.image("repo-clone", true)
local again = M.image("repo-clone", true)
local text = first and first.drawn and first.drawn.text
local piece = text and text.pieces and text.pieces[1]
check("an icon is drawn once from the codicon font, then kept",
      first ~= nil and again == first and #canvases == 1
      and piece ~= nil and piece.text == utf8.char(0xEB3E)
      and piece.attrs.font.name == "codicon",
      tostring(#canvases) .. " canvases")

M.forget()
fontInstalled = false
local missing = M.image("refresh", true)
local unknown = M.image("no-such-icon", true)
local drawnWithout = #canvases - 1
fontInstalled = true
local installed = M.image("refresh", true)
check("without the font nothing is drawn, and installing it needs no reload",
      missing == nil and unknown == nil and drawnWithout == 0 and installed ~= nil,
      tostring(drawnWithout) .. " drawn without the font")

local row = cl.gather(cl.buildContext(), { menus = { "root" } })
local clone
for _, r in ipairs(row) do
  if r.command == "git.clone" then clone = r end
end
check("a command's $(icon) reaches its row through this extension",
      clone ~= nil and clone.iconPath ~= nil and clone.iconPath.drawn ~= nil
      and clone.label == "Git: Clone…", clone and tostring(clone.label))

hs.canvas.new, hs.styledtext.validFont = saved.new, saved.valid
M.forget()
