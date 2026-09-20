-- The characters you typed, in a row, anywhere in a row's text.
--
-- Needs nothing installed, so it is what answers when a better matcher
-- declines. Case-insensitive, and ordered by where the match falls: a
-- row that starts with what you typed before one where a word does,
-- before one that only contains it, before one found only by its
-- keywords -- so "saf" puts Safari first. Each row it keeps is given that
-- grade, for the relevance ranker.

local EXACT, PREFIX, WORD, INSIDE, KEYWORD = 1, 0.85, 0.7, 0.5, 0.15

-- Keywords hold URLs and bundle ids; past this they only cost time.
local KEYWORDS_LIMIT = 160

return function()
  -- A view's rows stay the same tables from one keystroke to the next, so
  -- each is lowered once rather than on every key. Weak, so rows of a
  -- closed picker are not kept.
  local lowered = setmetatable({}, { __mode = "k" })

  local function textOf(item)
    local label, keywords = item.label, item.keywords
    local entry = lowered[item]
    if entry and entry.label == label and entry.keywords == keywords then return entry end
    local words
    if type(keywords) == "table" then
      local parts = {}
      for _, word in ipairs(keywords) do
        if type(word) == "string" then parts[#parts + 1] = word end
      end
      words = table.concat(parts, " "):sub(1, KEYWORDS_LIMIT):lower()
    end
    entry = { label = label, keywords = keywords, text = tostring(label):lower(), words = words }
    lowered[item] = entry
    return entry
  end

  return function(items, query, callback)
    if query == "" then return false end

    local needle = query:lower()
    local wordStart = "%f[%w]" .. needle:gsub("%W", "%%%0")
    local exact, starts, words, inside, keyworded = {}, {}, {}, {}, {}

    for _, item in ipairs(items) do
      local entry = textOf(item)
      local text = entry.text
      local at = text:find(needle, 1, true)
      if at == 1 then
        if #text == #needle then exact[#exact + 1] = item else starts[#starts + 1] = item end
      elseif at then
        -- A word start anywhere, not only at the first hit: "code" in
        -- "Encode in VS Code" is a word.
        if text:find(wordStart) then words[#words + 1] = item else inside[#inside + 1] = item end
      elseif entry.words and entry.words:find(needle, 1, true) then
        keyworded[#keyworded + 1] = item
      end
    end

    local kept, grades = {}, {}
    local function add(bucket, grade)
      for _, item in ipairs(bucket) do
        local n = #kept + 1
        kept[n], grades[n] = item, grade
      end
    end
    add(exact, EXACT)
    add(starts, PREFIX)
    add(words, WORD)
    add(inside, INSIDE)
    add(keyworded, KEYWORD)

    callback(kept, grades)
    return true
  end
end
