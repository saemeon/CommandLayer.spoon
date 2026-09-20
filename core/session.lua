-- The session: the modal, the view stack and the picker on screen.

local M = ...

----------------------------------------------------------------------
-- SESSION
--
-- One object for what the stack, the views and running a command share
-- while the layer is open. A core file earlier than the one that fills a
-- hook reaches it through here; nothing else is reached this way.
----------------------------------------------------------------------

local session = {
  modal = hs.hotkey.modal.new(),

  -- A view is one picker's worth of state. Opening a declared view
  -- replaces the list; cmd+k and each collected argument add to it.
  stack = {},

  -- Held here: a picker kept only as a function-local can be
  -- garbage-collected while still on screen.
  picker = nil,

  -- What entering the layer should do instead of opening the default
  -- picker: commands that entered it to ask for their arguments. A list, so
  -- a second one arriving before the layer has opened does not replace the
  -- first.
  pendingEntries = {},

  -- The context a command run while the layer was closed was given, for
  -- the view it opens: capturing again would cost a key that enters the
  -- layer every capture twice.
  outsideContext = nil,

  -- Rows being built right now, which a refresh from inside them must not
  -- rebuild.
  buildingRows = 0,

  -- True while a presenter's show() runs, when what it reports is dropped.
  showing = false,

  -- Filled by views: open a declared view over the current one.
  push = nil,
  -- Filled by views: the rows a view is built with, in a context.
  rowsOfView = nil,
  -- Filled by inputs: ask for what a row's command is missing; true when
  -- something was asked.
  collect = nil,
}

M.session = session
M.modal = session.modal

-- Reassigned every time pickers switch, so other files ask for it when
-- they need it instead of keeping a copy that goes stale.
M.activePicker = function() return session.picker end

-- Likewise the stack, which opening a declared view replaces.
M.topView = function() return session.stack[#session.stack] end
