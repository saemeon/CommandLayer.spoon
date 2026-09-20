-- CommandLayer.spoon/tests/jsonc.lua
-- Reading JSON with comments, and editing it in place.

local T = ...
local check, group = T.check, T.group
local cl = T.layer()

group("jsonc")
check("JSON with comments and trailing commas reads as VS Code's settings files do", (function()
        local value = cl.decodeJSONC([[
          // a line comment
          { "a": [1, 2.5, -3e2, true, false, null, ],   /* a block comment */
            "s": "tab\tquote\" é 😀",
            "o": { "n": {}, }, }]])
        return type(value) == "table" and value.a[1] == 1 and value.a[2] == 2.5
               and value.a[3] == -300 and value.a[4] == true and value.a[5] == false
               and #value.a == 5 and value.s == "tab\tquote\" é 😀"
               and type(value.o) == "table" and type(value.o.n) == "table",
               type(value) == "table" and tostring(value.s) or "no value"
      end)())

check("a file that does not parse gives nothing, and says where", (function()
        local value, err = cl.decodeJSONC('{ "a": 1 "b": 2 }')
        local unclosed = cl.decodeJSONC('{ "a": /* never closed ')
        return value == nil and tostring(err):find("character", 1, true) ~= nil and unclosed == nil,
               tostring(err)
      end)())

check("removing a key keeps the rest as written: its lines go, a comment after it goes, the comma before "
      .. "the last goes, every entry for a repeated key goes, and a key not there changes nothing", (function()
        local cases = {
          { '{\n  "a": 1,\n  "b": 2\n}', { "a" }, '{\n  "b": 2\n}' },
          { '{\n  "a": 1,\n  "b": 2\n}', { "b" }, '{\n  "a": 1\n}' },
          { '{\n  "a": 1,\n  "b": 2,\n}', { "b" }, '{\n  "a": 1,\n}' },
          { '{\n  // about a\n  "a": 1, // one\n  "b": 2\n}', { "a" }, '{\n  // about a\n  "b": 2\n}' },
          { '{\n  "a": 1, // one\n  "b": 2 // two\n}', { "b" }, '{\n  "a": 1 // one\n}' },
          { '{\n  "a": {\n    "b": 1\n  },\n  "c": 3\n}', { "a" }, '{\n  "c": 3\n}' },
          { '{\n  "a": {\n    "b": 1,\n    "c": 2\n  }\n}', { "a", "b" }, '{\n  "a": {\n    "c": 2\n  }\n}' },
          { '{\n  "a": 1, "b": 2\n}', { "b" }, '{\n  "a": 1\n}' },
          { '{ "a": 1, "b": 2 }', { "a" }, '{ "b": 2 }' },
          { '{ "a": 1, "b": 2 }', { "b" }, '{ "a": 1 }' },
          { '{ "a": 1 }', { "a" }, '{}' },
          { '{\n  "a": 1\n}\n', { "a" }, '{\n}\n' },
          { '{ "a": 1, "a": 2 }', { "a" }, '{}' },
          { '{ "a": 1 }', { "b" }, '{ "a": 1 }' },
          { '{ "a": 5 }', { "a", "b" }, '{ "a": 5 }' },
        }
        for i, case in ipairs(cases) do
          local out = cl.editJSONC(case[1], case[2], nil)
          if out ~= case[3] then return false, ("case %d: %q"):format(i, tostring(out)) end
        end
        return true
      end)())

check("removing a list's element keeps the rest as written: its lines go, a comment after it goes, the comma "
      .. "before the last goes, a list inside an object too, and an element or a list not there is refused",
      (function()
        local cases = {
          { '[\n  1,\n  2\n]', {}, 1, '[\n  2\n]' },
          { '[\n  1,\n  2\n]', {}, 2, '[\n  1\n]' },
          { '[\n  1,\n  2,\n]', {}, 2, '[\n  1,\n]' },
          { '[\n  // about one\n  1, // one\n  2\n]', {}, 1, '[\n  // about one\n  2\n]' },
          { '[\n  { "key": "a" }, // a\n  { "key": "b" } // b\n]\n', {}, 2, '[\n  { "key": "a" } // a\n]\n' },
          { '[\n  {\n    "key": "a"\n  },\n  3\n]', {}, 1, '[\n  3\n]' },
          { '[ 1, 2 ]', {}, 1, '[ 2 ]' },
          { '[ 1, 2 ]', {}, 2, '[ 1 ]' },
          { '[ 1 ]', {}, 1, '[]' },
          { '{\n  "a": [\n    1,\n    2\n  ]\n}', { "a" }, 1, '{\n  "a": [\n    2\n  ]\n}' },
          { '[ 1 ]', {}, 2, nil },
          { '{ "a": 1 }', {}, 1, nil },
          { '{ "a": [ 1 ] }', { "b" }, 1, nil },
        }
        for i, case in ipairs(cases) do
          local out = cl.removeJSONCElement(case[1], case[2], case[3])
          if out ~= case[4] then return false, ("case %d: %q"):format(i, tostring(out)) end
        end
        return true
      end)())

check("appending to a list keeps the rest as written: after the last element and its comment, indented like "
      .. "it, on one line after one on one line, inline in a list on one line, and keys in the order asked",
      (function()
        local entry = { command = "-x", key = "cmd+k" }
        local order = { "key", "command" }
        local cases = {
          { '[\n  1\n]', {}, 2, nil, '[\n  1,\n  2\n]' },
          { '[\n  1,\n]', {}, 2, nil, '[\n  1,\n  2\n]' },
          { '[\n  1 // one\n]\n', {}, 2, nil, '[\n  1, // one\n  2\n]\n' },
          { '[ 1 ]', {}, 2, nil, '[ 1, 2 ]' },
          { '[]', {}, entry, order, '[\n  { "key": "cmd+k", "command": "-x" }\n]' },
          { '// mine\n[\n]\n', {}, entry, order, '// mine\n[\n  { "key": "cmd+k", "command": "-x" }\n]\n' },
          { '[\n    { "key": "a", "command": "y" }\n]', {}, entry, order,
            '[\n    { "key": "a", "command": "y" },\n    { "key": "cmd+k", "command": "-x" }\n]' },
          { '[\n  {\n    "key": "a"\n  }\n]', {}, entry, order,
            '[\n  {\n    "key": "a"\n  },\n  {\n    "key": "cmd+k",\n    "command": "-x"\n  }\n]' },
          { '{\n  "a": [\n    1\n  ]\n}', { "a" }, 2, nil, '{\n  "a": [\n    1,\n    2\n  ]\n}' },
          { '{ "a": 1 }', {}, 2, nil, nil },
          { '[ 1, ', {}, 2, nil, nil },
        }
        for i, case in ipairs(cases) do
          local out = cl.appendJSONCElement(case[1], case[2], case[3], case[4])
          if out ~= case[5] then return false, ("case %d: %q"):format(i, tostring(out)) end
          if out and cl.decodeJSONC(out) == nil then return false, ("case %d does not parse"):format(i) end
        end
        return true
      end)())

check("a picker's placeholder and empty message may be templates filled from the context", (function()
        local alerts, real = {}, hs.alert.show
        hs.alert.show = function(message) alerts[#alerts + 1] = message end
        local undo = T.picker("test-template", { { label = "row" } }, { placeholder = "Hello ${frontmostApp}" })
        cl.open("test-template")
        local p = cl.viewNamed("test-template").picker
        local placeholder = p and p.placeholder
        local undoEmpty = T.picker("test-template-empty", {}, { empty = "Nothing for ${frontmostApp}" })
        cl.push("test-template-empty", { ctx = { frontmostApp = "Finder" } })
        hs.alert.show = real
        undo()
        undoEmpty()
        return placeholder == "Hello Finder" and alerts[#alerts] == "Nothing for Finder",
               tostring(placeholder) .. " / " .. tostring(alerts[#alerts])
      end)())
