-- Fuzzy matching, through fzf.
--
-- hs.chooser matches plain substrings, so typing "ovc" never finds
-- "Open in VS Code". fzf is a tuned matcher that already exists on many
-- machines, so this pipes candidates through `fzf --filter` and reads
-- back the ranked order rather than implementing scoring here.
--
--   brew install fzf
--
-- Declines when fzf is absent, which leaves the kernel's substring
-- fallback.

-- fzf --filter prints an order and no scores, so each row it keeps is
-- graded here by how its label holds the query, for the relevance ranker:
-- fzf's order decides within a grade, and a row fzf found only through its
-- keywords grades lowest.
local EXACT, PREFIX, WORD, INSIDE, INORDER, KEYWORD = 1, 0.85, 0.7, 0.5, 0.3, 0.15

-- Keywords hold URLs and bundle ids; past this they only cost time.
local KEYWORDS_LIMIT = 160

-- fzf's own query syntax around a term: 'exact, ^prefix, suffix$.
local function bareTerm(term)
  return (term:gsub("^['^]+", ""):gsub("%$$", ""))
end

local function grade(text, term)
  if text == term.text then return EXACT end
  local at = text:find(term.text, 1, true)
  if at == 1 then return PREFIX end
  if at then return text:find(term.wordStart) and WORD or INSIDE end
  local from = 1
  for i = 1, #term.text do
    from = text:find(term.text:sub(i, i), from, true)
    if not from then return KEYWORD end
    from = from + 1
  end
  return INORDER
end

return function(cl)
  cl.tools.register("fzf", { "/opt/homebrew/bin/fzf", "/usr/local/bin/fzf" })

  local task

  -- A view's rows stay the same tables from one keystroke to the next, so
  -- each row's line is made once rather than on every key. Weak, so rows
  -- of a closed picker are not kept.
  local lines = setmetatable({}, { __mode = "k" })

  -- `index<TAB>label<TAB>keywords`, searched from the second field on, so a
  -- row comes back by its index however many rows share its label.
  local function lineOf(item, index)
    local label, keywords = item.label, item.keywords
    local entry = lines[item]
    if not (entry and entry.label == label and entry.keywords == keywords) then
      local words = ""
      if type(keywords) == "table" then
        local parts = {}
        for _, word in ipairs(keywords) do
          if type(word) == "string" then parts[#parts + 1] = word end
        end
        words = table.concat(parts, " "):sub(1, KEYWORDS_LIMIT)
      end
      local text = tostring(label)
      entry = { label = label, keywords = keywords, lowered = text:lower(),
                text = (text:gsub("[\t\r\n]", " ")) .. "\t" .. words:gsub("[\t\r\n]", " ") }
      lines[item] = entry
    end
    if entry.index ~= index then
      entry.index, entry.line = index, index .. "\t" .. entry.text
    end
    return entry
  end

  return function(items, query, callback)
    -- Before declining, not after: deleting back to an empty query must
    -- not leave the previous search running for nothing.
    if task then
      task:terminate()
      task = nil
    end

    local fzf = cl.tools.path("fzf")
    if not fzf or query == "" or #items == 0 then return false end

    local input = {}
    for i, item in ipairs(items) do input[i] = lineOf(item, i).line end

    local whole = query:lower()
    local terms = {}
    for word in whole:gmatch("%S+") do
      local text = bareTerm(word)
      -- A negated term or fzf's | says what a row lacks, not how it matched.
      if text ~= "" and not word:find("^!") and word ~= "|" then
        terms[#terms + 1] = { text = text, wordStart = "%f[%w]" .. text:gsub("%W", "%%%0") }
      end
    end

    task = cl.tools.run(fzf, { "--filter=" .. query, "--delimiter=\t", "--nth=2.." }, function(_, stdout)
      local ranked, grades = {}, {}
      for line in tostring(stdout):gmatch("[^\r\n]+") do
        local tab = line:find("\t", 1, true)
        local item = tab and items[tonumber(line:sub(1, tab - 1))]
        if item then
          local n = #ranked + 1
          local lowered = lines[item] and lines[item].lowered or tostring(item.label):lower()
          local score = 0
          if lowered == whole then
            score = EXACT
          elseif #terms > 0 then
            for _, term in ipairs(terms) do score = score + grade(lowered, term) end
            score = score / #terms
          end
          ranked[n], grades[n] = item, score
        end
      end
      callback(ranked, grades)
    end, { input = table.concat(input, "\n") })

    return true
  end
end
