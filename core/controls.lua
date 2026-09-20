-- Named controls: what the picker does to itself.

local M = ...

local modal = M.modal
local goBack = M.goBack
local clearStack = M.clearStack
local currentPicker = M.activePicker
local showItemActions = M.showItemActions

----------------------------------------------------------------------
-- CONTROLS
--
-- What the picker does to itself, as opposed to what a row does to the
-- world. Each one is named, so the profile decides its chord.
--
-- Moving and accepting are the presenter's to do, and optional: a picker
-- that cannot be steered from outside simply ignores the chord.
----------------------------------------------------------------------

local function moveSelection(delta)
  local picker = currentPicker()
  if picker and picker.move then picker.move(delta) end
end

local function acceptSelection()
  local picker = currentPicker()
  if picker and picker.accept then picker.accept() end
end

-- Controls sharing a label are two halves of one thing, as `move` is.
-- `repeats`: a held key bound to it runs it again, as a held arrow moves on,
-- unless the keybinding says "repeat": false.
M.controls = {
  { name = "quickOpen.selectPrevious", label = "move",    fn = function() moveSelection(-1) end,
    repeats = true },
  { name = "quickOpen.selectNext",     label = "move",    fn = function() moveSelection(1)  end,
    repeats = true },
  { name = "quickOpen.accept",         label = "open",    fn = function() acceptSelection() end },
  { name = "quickOpen.showActions",    label = "actions", fn = function() showItemActions() end },

  -- Escape does this too, but through the picker reporting a dismissal
  -- rather than through a binding, so it is named here to be shown and
  -- deliberately not bound: finish() is the one place that decides what
  -- escape means, and a binding would be a second.
  { name = "quickOpen.back",           label = "back",    fn = function() goBack() end,
    unbound = "esc" },
  -- Every level at once, where escape and back leave one.
  { name = "quickOpen.hide",           label = "close",   fn = function() modal:exit() end },
}

-- At setup rather than load, like every other registration. menus = {}:
-- a control acts on the picker on screen, so as a row it would act on
-- the picker that listed it.
M.registerControls = function()
  for _, control in ipairs(M.controls) do
    local fn = control.fn
    M.registerCommand(control.name, { title = control.label, menus = {},
                                      run = function() fn() end })
  end

  M.registerCommand("quickOpen", { title = "Quick Open", menus = {},
    run = function(args)
      local view = args.view or M.defaultView
      local function show()
        if args.query or args.subject then
          return M.open(view, { query = args.query, subject = args.subject, label = args.label })
        end
        -- Without a query it is exactly a view's own chord, prefix and all.
        return M.quickOpen(view)
      end
      if M.topView() then return show() end
      -- From outside, through the modal, so the layer's own keys are live
      -- and closing it exits; entering would otherwise open the default view
      -- first.
      local pending = M.session.pendingEntries
      pending[#pending + 1] = show
      modal:enter()
    end })
end

-- Entering opens the root picker straight away, so the layer is never
-- an invisible armed state -- unless commands entered the layer to open a
-- picker or ask for their arguments. Those are the first thing on screen,
-- in the order they asked, the last on top, and escape leaves from them.
function modal:entered()
  local pending = M.session.pendingEntries
  M.session.pendingEntries = {}
  if #pending == 0 then return M.open(M.defaultView) end
  for _, ask in ipairs(pending) do ask() end
end

function modal:exited()
  clearStack()
end
