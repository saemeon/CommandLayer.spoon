-- The view stack: the picker on screen, typing into it, and what a pick
-- does.

local M = ...

local session = M.session
local modal = session.modal
local remember = M.remember
local queryItems = M.queryItems
local rankItems = M.rankItems
local createPicker = M.createPicker
local withSeparators = M.withSeparators
local sectionsFirst = M.sectionsFirst
local recentlyUsedFirst = M.recentlyUsedFirst

----------------------------------------------------------------------
-- PICKERS
--
-- A picker is what a presenter creates to draw a view. The one on screen
-- is held on the session: one created as a function-local can be
-- garbage-collected while still on screen.
----------------------------------------------------------------------

-- Defined further down with the view stack; finish() needs them first.
local goBack, queryChanged, render, showAgain, selectRow

-- A pick or a dismissal, as the presenter that drew it reports it. Only
-- the picker on screen can report either: rows from any other belong to
-- a view that has already been left.
local function finish(picker, item, reason)
  if picker ~= session.picker then return end

  -- Dismissed rather than chosen. A picker sees escape before any hotkey we
  -- could bind does, so this is the one place that decides what it means:
  -- go back a level, and leave only from the top. Focus gone to another app
  -- is different -- the launcher was left, and stepping back would open a
  -- picker behind whatever has focus now.
  if not item then
    if reason == "away" then modal:exit() else goBack() end
    return
  end

  -- Says a search is running, and is nothing to refuse.
  local top = session.stack[#session.stack]
  if top and item == top.searchingRow then return showAgain(top, item) end
  local answering = top and top.answering

  -- Greyed out: shown so you know it is there, refused so nothing runs, and
  -- the layer stays open to pick something else.
  if item.enabled == false then
    hs.alert.show(tostring(item.label or "That") .. " is not available now")
    return showAgain(top, item)
  end

  -- A row that opens another picker rather than running something. It is
  -- remembered like any pick, so a menu you use often rises too, and the
  -- layer stays open so escape comes back to this one.
  if item.submenu and not answering then
    remember(item)
    session.push(item.submenu, { ctx = item.ctx, query = item.submenuQuery,
                                 byPrefix = item.submenuQuery })
    return
  end

  -- A row that changes what the picker shows -- a setting switched --
  -- runs and leaves it open, redrawn, instead of closing the layer.
  if item.keepOpen and not answering then
    M.runRow(item)
    M.redraw(top, item)
    return
  end

  -- Picked in a command's question, a row answers rather than runs: its
  -- value, else its subject, and the command that asked carries on. The
  -- layer stays open, so escape steps back out of a half-finished flow
  -- instead of abandoning it.
  if answering then
    local parent, input = answering.parent, answering.input
    local value = item.value
    if value == nil then value = item.subject end

    if answering.confirm then
      -- No is escape: back to where the command was chosen.
      if not value then
        goBack()
        return
      end
      parent.confirmed = true
    else
      if type(value) == "function" then
        value = value(item.ctx, parent.args)
        if value == nil then          -- cancelled, e.g. the folder dialog
          modal:exit()
          return
        end
      end

      -- The prompt stays, so the answer can be corrected rather than retyped
      -- from the start.
      local why = M.inputProblem(input, value, item.ctx, parent.args)
      if why then
        hs.alert.show(why)
        return showAgain(top, item)
      end

      -- An answer destined for a URL has to survive being put in one.
      -- Without this, "hello world" makes a malformed link.
      if input.encode == "query" then
        value = hs.http.encodeForQuery(tostring(value))
      end

      parent.args = parent.args or {}
      parent.args[input.id] = value
    end

    item = parent
  else
    -- A copy with args of its own: answers are written into what runs, and a
    -- picker left open would otherwise offer the row already answered.
    local copy = {}
    for k, v in pairs(item) do copy[k] = v end
    if type(item.args) == "table" then
      copy.args = {}
      for k, v in pairs(item.args) do copy.args[k] = v end
    end
    item = copy
    -- Where it was picked, which is where `after` keeps open or goes back from.
    item.pickedDepth = #session.stack
  end

  -- Picked, an input that prefers what is in front takes it -- the window
  -- you were in -- and asks only when there is nothing there. cmd+k on the
  -- row is how to choose instead; it asks without coming through here.
  M.normaliseRow(item)
  local command = type(item.command) == "string" and M.getCommand(item.command) or nil
  local inputs = M.inputsOf(item)
  if inputs then
    for _, input in ipairs(inputs) do
      local given = item.args or {}
      if input.preferCurrent and type(input.current) == "function" and given[input.id] == nil then
        local ok, value = pcall(input.current, item.ctx)
        if ok and value ~= nil then
          local args = {}
          for k, v in pairs(given) do args[k] = v end
          args[input.id] = value
          item.args = args
        end
      end
    end
  end

  -- An action may need something it has not been given yet, still need
  -- more after the answer just given, or a yes before it runs.
  if (inputs or (command and command.confirm)) and session.collect(item) then
    return
  end

  item.confirmed = nil
  remember(item)
  M.runAfter(command, item.pickedDepth, function() M.runRow(item) end)
end

-- A level is left when it comes off the stack, never when another is pushed
-- over it: an extension that started something for a picker stops it here.
local function leave(view)
  M.notifyLeft(view)
end

-- Takes the levels above `depth` off without drawing, top first.
local function leaveTo(depth)
  local stack = session.stack
  while #stack > depth do leave(table.remove(stack)) end
end

-- VS Code closes the quick pick once an item is accepted; a command's `after`
-- keeps it open or steps back instead, from the level it was picked in.
-- Argument prompts above that level go first. A command that closed the layer
-- or opened another picker itself has already decided.
function M.runAfter(command, depth, run)
  local after = command and command.after or "close"
  local stack = session.stack
  depth = depth or #stack
  if after == "close" or depth < 1 or depth > #stack then
    modal:exit()
    return run()
  end

  local view = stack[depth]
  local covered = #stack > depth
  leaveTo(depth)
  run()
  if session.stack[depth] ~= view or #session.stack ~= depth then return end

  if after == "back" then
    goBack()
  elseif covered then
    render(view)
  else
    M.redraw(view)
  end
end

-- The outgoing picker stops being active before it is hidden, so a
-- presenter that reports its own hide as a dismissal cannot exit the
-- layer on the way through. `closing` says the layer is closing rather than
-- switching pickers, for a presenter that hands focus back only then.
local function hideActive(closing)
  local outgoing = session.picker
  session.picker = nil
  if outgoing then outgoing.hide(closing) end
end

-- A presenter may report typing from inside its own show() -- the chooser
-- does. Switching pickers from in there, which a typed prefix does, lets
-- the outgoing picker finish showing on top of the new one, and the new
-- one, losing the key window, reports a dismissal. So reports made during
-- a show are dropped, and render() runs the query once the picker is up.
local function switchTo(picker, state)
  hideActive()
  session.picker = picker
  session.showing = true
  local stop = M.span("draw.show")
  local ok, err = pcall(picker.show, state)
  stop()
  session.showing = false
  if not ok then error(err, 0) end
end

-- Every picker reports to the same two places, whichever view it draws.
local function pickerOptions(width, rows)
  return {
    width   = width,
    rows    = rows,
    onPick  = finish,
    onQuery = function(picker, query) queryChanged(picker, query) end,

    -- The rows an `open` row leads to, for a presenter that draws a whole
    -- tree at once instead of a level at a time. Built in the row's own
    -- context, as pushing that level would be.
    expand  = function(item)
      if not (item and item.submenu and session.rowsOfView) then return nil end
      return session.rowsOfView(item.submenu, item.ctx)
    end,
  }
end

-- The one picker the kernel owns rather than a view: cmd+k and every
-- argument prompt share it.
--
-- Made on first use, not here: the profile is read at setup, so a picker
-- made at load would keep the default presenter and appearance.
-- pickerFor does the same for every view.
local sharedPicker

local function actionPicker()
  if not sharedPicker then
    sharedPicker = createPicker(nil, pickerOptions(M.appearance.actionWidth,
                                                   M.appearance.actionRows))
  end
  return sharedPicker
end

----------------------------------------------------------------------
-- VIEW STACK
--
-- A view is one picker's worth of state. cmd+k and each collected
-- argument open a child view over the current one, and escape returns
-- to the parent.
--
-- Every view is a fresh table, so an async callback can ask "am I still
-- the top view?" and get the right answer even after the layer has been
-- closed and reopened. Comparing pickers cannot tell those apart.
----------------------------------------------------------------------

local function joined(a, b)
  local out = {}
  for _, row in ipairs(a) do out[#out + 1] = row end
  for _, row in ipairs(b) do out[#out + 1] = row end
  return out
end

-- Rows made from what you typed come first: if you typed a sum, the sum
-- is the point, not whichever app happened to match the digits. Only in
-- a declared picker, though -- in the cmd+k panel or an argument prompt,
-- typing is narrowing a short list, and a calculation there is noise.
-- `ranked` with the rows in `first` moved up, behind the `skip` rows that stay
-- ahead of them (a command whose alias was typed).
local function leading(ranked, first, skip)
  local head, rest = {}, {}
  for i, row in ipairs(ranked) do
    if i > skip and first[row] then head[#head + 1] = row else rest[#rest + 1] = row end
  end
  if #head == 0 then return ranked end
  local out = {}
  for i = 1, skip do out[i] = rest[i] end
  for _, row in ipairs(head) do out[#out + 1] = row end
  for i = skip + 1, #rest do out[#out + 1] = rest[i] end
  return out
end

-- What a view's sections showed stays searchable once you type -- a section
-- may show another picker's rows, which are not among this view's own -- and
-- first among what matches. Worked out when the sections are, never per
-- keystroke: `first` holds the tables to lead with, the view's own row where
-- a section's is the same thing.
local function rememberSections(view, shown)
  local byKey, searched, first = {}, {}, {}
  for i, row in ipairs(view.items or {}) do
    searched[i] = row
    local key = M.subjectKey(row)
    if key and not byKey[key] then byKey[key] = row end
  end
  for _, row in ipairs(shown) do
    local key = M.subjectKey(row)
    local own = key and byKey[key]
    if own then
      first[own] = true
    else
      searched[#searched + 1] = row
      first[row] = true
    end
  end
  view.sectioned = { from = view.items, searched = searched, first = first }
end

local function listQuery(view, query, present)
  local direct = view.answers and queryItems(view.ctx, query) or {}
  local sectioned = query ~= "" and view.sectioned
  if sectioned and sectioned.from ~= view.items then sectioned = nil end

  rankItems(sectioned and sectioned.searched or view.items or {}, query, function(ranked, aliased)
    if sectioned then ranked = leading(ranked, sectioned.first, aliased or 0) end
    -- Typing keeps what you used lately first among what matched, as VS
    -- Code's palette does, though still after the rows made from the text,
    -- and after a command whose alias is what was typed.
    if query ~= "" and view.recentlyUsed then
      aliased = aliased or 0
      local rest = {}
      for i = aliased + 1, #ranked do rest[#rest + 1] = ranked[i] end
      local first = {}
      for i = 1, aliased do first[i] = ranked[i] end
      for _, item in ipairs(recentlyUsedFirst(rest, view.recentlyUsed)) do first[#first + 1] = item end
      ranked = first
    end
    local out = joined(direct, ranked)
    -- Nothing matched, so what was typed is probably something to search
    -- for: offer every command that takes text, as Alfred's fallbacks do.
    -- Only where a picker asks -- in `git ` or the palette, nothing matching
    -- means nothing matching.
    if #out == 0 and view.textCommands == "fallback" and query ~= "" then
      for _, row in ipairs(M.textRowsFor(view.ctx, query)) do out[#out + 1] = row end
    end
    if query == "" and type(view.sections) == "table" then
      local shown = {}
      out = sectionsFirst(view.items or {}, out, view.sections, view.ctx, view.name, shown)
      rememberSections(view, shown)
    end
    if query == "" and view.recentlyUsed then out = recentlyUsedFirst(out, view.recentlyUsed) end
    present(out)
  end)
end

-- With `textCommands: "first"` the text is a way to every engine at once --
-- "? lofi" then picks which -- so those rows lead, ordered by use alone, since
-- every one of them holds the whole text. Nothing typed, the picker is its own.
local function defaultQuery(view, query, present)
  local text = view.textCommands == "first" and (tostring(query):gsub("^%s+", "")) or ""
  if text == "" then return listQuery(view, query, present) end
  rankItems(M.textRowsFor(view.ctx, text), "", function(commands)
    -- "? lofi" is the text "lofi" to the rows below too: the space after "?"
    -- is how it is typed, not something to match.
    listQuery(view, text, function(rows) present(joined(commands, rows)) end)
  end)
end

local function capped(items)
  local limit = M.appearance.maxRows
  if not limit or #items <= limit then return items end
  local out = {}
  for i = 1, limit do out[i] = items[i] end
  return out
end

-- Bound to the query it answers. Matching and searching run through
-- hs.task, so an answer can land after you have left the view or typed
-- another letter; either way it is no longer the answer to what is on
-- screen. Guarded here, this being the only way rows reach a picker.
-- `untraced` draws without ending the trace, which is waiting for answers.
local function presentFor(view, generation, untraced)
  return function(items)
    local stack = session.stack
    if stack[#stack] ~= view or view.generation ~= generation then
      return
    end
    local picker = view.picker

    -- The same query drawn again -- a refresh, rows landing late -- keeps the
    -- row you moved to, found by its identity rather than its place. On the
    -- first row there is nothing to keep: a presenter starts there anyway,
    -- and better rows arriving should take the top.
    local kept
    if picker.select and picker.selected and view.drawnQuery == view.query then
      local ok, row = pcall(picker.selected)
      if ok and type(row) == "table" and view.shown and row ~= view.shown[1] then kept = M.rowKey(row) end
    end

    view.shown = capped(withSeparators(items or {}))
    for _, row in ipairs(view.shown) do M.normaliseRow(row) end
    local stop = M.span("draw.setItems")
    picker.setItems(view.shown, view.query)
    stop(#view.shown .. " rows")
    view.drawnQuery = view.query
    if kept then
      for i, row in ipairs(view.shown) do
        if i > 1 and row.kind ~= "separator" and M.rowKey(row) == kept then
          picker.select(i)
          break
        end
      end
    end
    if not untraced then M.traceDrawn(#(items or {})) end
  end
end

-- VS Code's busy indicator, as a row because a presenter's placeholder may
-- show only while its field is empty, and a search always has text in it.
-- One table per view, so finish() knows it when it is picked.
local function busyRow(view)
  view.searchingRow = view.searchingRow or { label = "Searching…", enabled = false }
  return view.searchingRow
end

-- Until a query's first rows land, the busy row alone. Not for a query whose
-- rows are drawn already: a refresh keeps them while it asks again. Drawn
-- without ending the trace, which waits for the answer.
local function showBusy(view, query)
  if view.drawnQuery == query then return end
  presentFor(view, view.generation, true)({ busyRow(view) })
end

M.busyRow, M.showBusy = busyRow, showBusy

-- A question's own search, asked per keystroke: the busy row until an answer
-- for this query lands, what was typed narrowing the answer. `busy` says more
-- is on its way, so the rows found so far are shown with the busy row after.
local function questionSearch(view, query, present)
  local generation, answered = view.generation, false
  view.search(query, view.ctx, view.args, function(results, busy)
    answered = true
    -- An older query's answer, not worth matching.
    if view.generation ~= generation then return end
    local rows = {}
    for _, r in ipairs(results or {}) do
      rows[#rows + 1] = M.normaliseRow({ label = r.label, description = r.description, iconPath = r.iconPath,
                                         value = r.value, alwaysShow = r.alwaysShow, ctx = view.ctx })
    end
    local function show(shown)
      present(busy and joined(shown, { busyRow(view) }) or shown)
    end
    if query == "" then return show(rows) end
    rankItems(rows, query, function(ranked) show(ranked) end)
  end)
  if not answered then showBusy(view, query) end
end

-- The rows a searching view shows with nothing typed, but for `alwaysShow`
-- ones, which speak for the empty field; worked out once per gather.
local function ownRows(view)
  if view.own and view.own.from == view.items then return view.own end
  local rows, first, keys = {}, {}, {}
  for _, row in ipairs(view.items or {}) do
    if not row.alwaysShow then
      rows[#rows + 1] = row
      first[row] = true
      local key = M.subjectKey(row)
      if key then keys[key] = true end
    end
  end
  view.own = { from = view.items, rows = rows, first = first, keys = keys }
  return view.own
end

-- A picker holding one text command: its row, with what was typed filled in.
local function commandQuery(view, query, present)
  local command = M.getCommand(view.command)
  present(command and { M.textRow(command, view.ctx, query) } or {})
end

-- For a view that asks again rather than narrowing what it has. Nothing
-- typed shows its own rows. Once you type, those of them that match stay,
-- first -- recent files beside the files found -- and too little typed asks
-- nothing, because a search on one letter is all noise and all cost.
-- Otherwise the extensions' search hooks run once typing pauses, and each
-- answer is merged with those before it and ranked again, so a slow source
-- adds rows to a fast one's.
local function searchQuery(view, query, present)
  if view.timer then view.timer:stop() end
  view.timer = nil
  for _, stop in ipairs(view.stops or {}) do pcall(stop) end
  view.stops = nil

  if query == "" then
    present(view.items or {})
    return
  end
  local own = ownRows(view)
  local function ranked(rows, done)
    rankItems(rows, query, function(out, aliased)
      if view.query == query then done(leading(out, own.first, aliased or 0)) end
    end)
  end
  if #query < (view.minQuery or 2) then
    ranked(own.rows, present)
    return
  end

  -- Traced from the pause rather than the keystroke, so the debounce is not
  -- counted as the search's time.
  view.timer = hs.timer.doAfter(view.debounce or 0.15, function()
    view.timer = nil
    M.traced("search", view.name, function()
      local found, answered, started = {}, 0, nil
      -- Until a first answer, what of its own matches, then the busy row.
      if view.drawnQuery ~= query then
        ranked(own.rows, function(rows)
          if #found > 0 or answered > 0 then return end
          presentFor(view, view.generation, true)(joined(rows, { busyRow(view) }))
        end)
      end
      view.stops, started = M.searchExtensions(view.ctx, view.menus, query, function(rows, first)
        for _, row in ipairs(rows) do
          local key = M.subjectKey(row)
          if not (key and own.keys[key]) then found[#found + 1] = row end
        end
        if first then answered = answered + 1 end
        if #found > 0 or (started and answered >= started) then ranked(joined(own.rows, found), present) end
      end)
      if #found == 0 and answered >= started then ranked(own.rows, present) end
    end)
  end)
end

-- A keystroke and a refresh both come through here, so a level never answers
-- the same query two ways.
local function answer(view, query)
  local present = view.present
  if view.kind == "search" and view.search then
    questionSearch(view, query, present)
  elseif view.kind == "search" then
    searchQuery(view, query, present)
  elseif view.rowsForQuery then
    view.rowsForQuery(query, present)
  elseif view.command then
    commandQuery(view, query, present)
  else
    defaultQuery(view, query, present)
  end
end

-- view.items is what the picker searches and is never narrowed; what a
-- query leaves on screen goes to view.shown. Each query has to search
-- every row, or deleting what you typed cannot bring any back.
render = function(view)
  if not view.picker then
    modal:exit()
    hs.alert.show("No presenter could draw this picker")
    return
  end

  view.generation = (view.generation or 0) + 1
  view.drawnQuery, view.searchingRow = nil, nil

  -- Empty, unless the view was opened with text in its field. Used once:
  -- coming back to a view should not retype what you had -- except a
  -- prefix, which is what the view is, so it goes back in.
  view.query, view.startQuery = view.startQuery or view.prefix or "", nil

  -- The only handle a view gets on the picker, so what draws one can
  -- change without every view changing with it.
  view.present = presentFor(view, view.generation)
  view.shown = capped(withSeparators(view.items or {}))
  for _, row in ipairs(view.shown) do M.normaliseRow(row) end

  switchTo(view.picker, { placeholder = view.placeholder, items = view.shown,
                          query = view.query })

  -- Always, empty included: a presenter's report during show() was
  -- dropped, and running the query is also what ranks the rows it opens
  -- with rather than leaving them in the order they were gathered.
  queryChanged(view.picker, view.query)
end

-- Typing, as a presenter reports it. Only the view on top of the stack
-- is being typed into; a report from any other picker is stale.
local function typed(view, query)
  local stack = session.stack

  -- Which view the text belongs to, chosen the way VS Code chooses a
  -- quick access provider: the longest prefix it starts with. A view
  -- opened by its prefix always takes part, so deleting the prefix gets
  -- you out; otherwise only a declared picker does, since in the cmd+k
  -- panel or an argument prompt ">" is text you mean to type.
  if M.prefixView and (view.prefix or view.answers) then
    local owner, matched = M.prefixView(query)

    -- Forgotten once the text moves on, so that view can be tried again.
    if view.declined ~= owner then view.declined = nil end

    if view.prefix and owner ~= view.name then
      -- The prefix was edited away, or grew into a longer one. The view
      -- underneath decides again, with the text as it now stands.
      local parent = stack[#stack - 1]
      if parent then
        parent.startQuery = query
        goBack()
        return
      end
    elseif view.prefix then
      -- "recent " edited into its alias "r ": still this view, and the
      -- search is whatever follows the prefix now in the field.
      view.prefix = matched
    elseif owner and owner ~= view.name and owner ~= view.declined then
      if session.push(owner, { ctx = view.ctx, query = query, byPrefix = matched }) then
        return
      end
      -- It had nothing to show. Search here instead of asking again, and
      -- alerting again, on every keystroke.
      view.declined = owner
      -- With nothing typed after the prefix, the text was only the way in --
      -- a chord like cmd+. types it -- so it is cleared, and this view opens
      -- on its own rows instead of searching for the word "context".
      if query == matched then
        view.startQuery = ""
        render(view)
        return
      end
    end
  end

  -- What follows the prefix is the search: ">lock" looks for "lock".
  view.query = view.prefix and query:sub(#view.prefix + 1) or query
  view.generation = view.generation + 1
  view.present = presentFor(view, view.generation)
  answer(view, view.query)
end

queryChanged = function(picker, query)
  if session.showing then return end
  local stack = session.stack
  local view = stack[#stack]
  if not view or view.picker ~= picker then return end
  M.traced("keystroke", view.name, typed, view, query)
end

-- Replaces the stack: the declared pickers are siblings, not children
-- of each other.
local function showView(view)
  leaveTo(0)
  session.stack = { view }
  render(view)
end

-- What stands in the field: a view reached by a prefix keeps it there, and
-- `query` is only what follows it. Handing the picker `query` alone would
-- read as the prefix deleted, which steps back to the view underneath.
local function fieldText(view)
  return (view.prefix or "") .. (view.query or "")
end

-- A pick closes the picker it was made in: the chooser hides itself before
-- it reports, and the popup's menu goes with the click. So a pick that
-- leaves the level where it is -- a row that is not available, a search
-- still running, an answer refused -- puts it back exactly as it was,
-- rather than leaving nothing on screen.
showAgain = function(view, keep)
  if not (view and view.picker) then return end
  switchTo(view.picker, { placeholder = view.placeholder, items = view.shown or {},
                          query = fieldText(view) })
  selectRow(view, keep)
end

-- The row picked is the one to come back to, found by its identity: a
-- presenter starts at the top, and the first row is where it starts anyway.
selectRow = function(view, row)
  local picker = view and view.picker
  if not (picker and picker.select and type(row) == "table") then return end
  local key = M.rowKey(row)
  for i, shown in ipairs(view.shown or {}) do
    if i > 1 and shown.kind ~= "separator" and M.rowKey(shown) == key then
      picker.select(i)
      return
    end
  end
end

-- Opens a view over the current one.
local function pushView(view)
  local stack = session.stack
  stack[#stack + 1] = view
  render(view)
end

goBack = function()
  local stack = session.stack
  if #stack > 1 then
    leave(table.remove(stack))
    render(stack[#stack])
  else
    modal:exit()
  end
end

-- For an extension whose rows arrived after the picker was drawn -- a
-- project scan, a network answer. A view keeps the function that built
-- it, so it can be asked again. The query is run again over the new
-- rows: showing all of them would ignore what is already in the field.
-- An argument prompt built nothing, but its search may read a cache that
-- has just landed, so it is asked again.
-- A level that stays open after a pick, as `keepOpen` says. The pick closed
-- the picker it was made in, so new rows alone would leave nothing on
-- screen: it is drawn again, keeping what was typed and the row picked.
function M.redraw(view, keep)
  if not view then return M.refresh() end
  if view.rebuild then view.items = view.rebuild() end
  view.startQuery = fieldText(view)
  render(view)
  selectRow(view, keep)
end

function M.refresh()
  -- Rows being built already read whatever the caller's cache holds.
  if (session.buildingRows or 0) > 0 then return end
  local view = session.stack[#session.stack]
  if not view or not (view.rebuild or view.rowsForQuery or view.search) then return end

  M.traced("refresh", view.name, function()
    if view.rebuild then view.items = view.rebuild() end
    answer(view, view.query or "")
  end)
end

-- Closing the layer takes the picker on screen, and every view, with it.
M.clearStack = function()
  M.dropTrace()
  hideActive(true)
  local stack = session.stack
  session.stack = {}
  for i = #stack, 1, -1 do leave(stack[i]) end
end

M.pickerOptions = pickerOptions
M.actionPicker  = actionPicker
M.showView      = showView
M.pushView      = pushView
M.goBack        = goBack
