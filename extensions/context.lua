-- What the world is pointing at, and the verbs for it.
--
-- This extension names the subjects; every other extension supplies
-- verbs for the kinds it cares about. That is why a git extension can
-- put "Clone" on a clipboard URL without either of them knowing the
-- other exists.
--
-- The fields it reads are captured elsewhere -- ambient.lua, finder.lua
-- -- so each is guarded: a profile without those extensions gets no
-- subjects rather than subjects with nothing in them.

local M = {}

function M.extension(cl)
  -- A row that is already an action -- a subject carrying the command it
  -- runs -- has one obvious verb.
  local takesAction = {
    id = "subject", description = "Which action",
    picker = { when = "viewItem == 'action'" },
  }

  return {
    name  = "context",
    rank  = 1,
    menus = { "root", "commandPalette", "context" },

    commands = {
      { id = "context.run", title = "Run", menus = { ["view/item/context"] = { when = "command" } },
        inputs = { takesAction },
        run = function(args, ctx)
          local subject = args.subject
          if type(subject) == "table" and type(subject.command) == "string" then
            cl.executeCommand(subject.command, subject.args or {}, ctx)
          end
        end },

      { id = "context.copyTitle", title = "Copy title", menus = { ["view/item/context"] = { when = "name" } },
        inputs = { takesAction },
        run = function(args, ctx)
          local subject = args.subject
          if type(subject) == "table" and subject.name then
            cl.executeCommand("system.copy", { text = subject.name }, ctx)
          end
        end },
    },

    subjects = function(ctx)
      local subjects = {}

      if (ctx.finderSelection or "") ~= "" then
        subjects[#subjects + 1] = {
          kind = "file", path = ctx.finderSelection, label = "Selection",
        }
      end

      -- The frontmost app is deliberately not an ambient subject: it
      -- would put Launch / Quit / Hide / Reveal in the root on every
      -- open. Its verbs are still a cmd+k away on the app row.

      if (ctx.clipboard or "") ~= "" then
        subjects[#subjects + 1] = {
          kind = "clipboard", value = ctx.clipboard, label = "Clipboard",
        }
        -- A URL on the clipboard is two subjects at once: the text, and
        -- the link. Anything answering for url gets a turn.
        if ctx.clipboard:match("^https?://") then
          subjects[#subjects + 1] = {
            kind = "url", value = ctx.clipboard, label = "Clipboard URL",
          }
        end
      end

      return subjects
    end,

    items = function(ctx)
      local items = {}

      for _, subject in ipairs(cl.ambientSubjects(ctx)) do
        for _, item in ipairs(cl.itemActions(subject, ctx) or {}) do
          -- Say which subject the verb belongs to, since the root list
          -- shows several subjects' verbs side by side.
          item.description, item.detail = subject.label or subject.kind, nil
          items[#items + 1] = item
        end
      end

      return items
    end,
  }
end

-- Checks for this extension, run by test.lua.

return M
