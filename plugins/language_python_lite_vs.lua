-- priority:150
-- mod-version:3
-- Python grammar tuned for the bundled dark workbench theme.
-- Kept in the user directory so Lite XL updates cannot overwrite it.

local syntax = require "core.syntax"

local function table_merge(a, b)
  local result = {}
  for _, value in ipairs(a) do result[#result + 1] = value end
  for _, value in ipairs(b) do result[#result + 1] = value end
  return result
end

local python_symbols = {
  -- Storage and declaration keywords stay blue.
  ["class"] = "keyword",
  ["def"] = "keyword",
  ["async"] = "keyword",
  ["lambda"] = "keyword",
  ["nonlocal"] = "keyword",
  ["global"] = "keyword",
  ["del"] = "keyword",
  ["assert"] = "keyword",

  -- Control-flow and import scopes are purple.
  ["finally"] = "keyword2",
  ["return"] = "keyword2",
  ["continue"] = "keyword2",
  ["for"] = "keyword2",
  ["try"] = "keyword2",
  ["except"] = "keyword2",
  ["await"] = "keyword2",
  ["from"] = "keyword2",
  ["while"] = "keyword2",
  ["with"] = "keyword2",
  ["as"] = "keyword2",
  ["elif"] = "keyword2",
  ["if"] = "keyword2",
  ["else"] = "keyword2",
  ["match"] = "keyword2",
  ["case"] = "keyword2",
  ["import"] = "keyword2",
  ["pass"] = "keyword2",
  ["break"] = "keyword2",
  ["raise"] = "keyword2",
  ["yield"] = "keyword2",

  -- Python word operators use the standard keyword blue.
  ["is"] = "keyword",
  ["and"] = "keyword",
  ["not"] = "keyword",
  ["or"] = "keyword",
  ["in"] = "keyword",

  ["self"] = "literal",
  ["cls"] = "literal",
  ["None"] = "literal",
  ["True"] = "literal",
  ["False"] = "literal",
  ["NotImplemented"] = "literal",
  ["Ellipsis"] = "literal",

  -- Common annotation and runtime type names use the theme's type teal.
  ["Any"] = "type",
  ["Callable"] = "type",
  ["ClassVar"] = "type",
  ["Dict"] = "type",
  ["Final"] = "type",
  ["Iterable"] = "type",
  ["Iterator"] = "type",
  ["List"] = "type",
  ["Literal"] = "type",
  ["Mapping"] = "type",
  ["Optional"] = "type",
  ["Protocol"] = "type",
  ["Sequence"] = "type",
  ["Set"] = "type",
  ["Tuple"] = "type",
  ["Type"] = "type",
  ["TypeVar"] = "type",
  ["Union"] = "type",
  ["bool"] = "type",
  ["bytes"] = "type",
  ["complex"] = "type",
  ["dict"] = "type",
  ["float"] = "type",
  ["frozenset"] = "type",
  ["int"] = "type",
  ["list"] = "type",
  ["object"] = "type",
  ["set"] = "type",
  ["str"] = "type",
  ["tuple"] = "type",
  ["type"] = "type",
}

local python_fstring = {
  patterns = {
    { pattern = "\\.", type = "string" },
    { pattern = [=[[^"\\{}']+]=], type = "string" },
  },
  symbols = {},
}

local python_patterns = {
  -- F-string expressions retain their own Python colours. The state leak was
  -- caused by colon-terminated statement subsyntaxes below, not by the
  -- interpolation itself.
  { pattern = { '[fF][rR]?"""', '"""', '\\' }, type = "string", syntax = python_fstring },
  { pattern = { "[fF][rR]?'''", "'''", '\\' }, type = "string", syntax = python_fstring },
  { pattern = { '[rR][fF]"""', '"""', '\\' }, type = "string", syntax = python_fstring },
  { pattern = { "[rR][fF]'''", "'''", '\\' }, type = "string", syntax = python_fstring },
  { pattern = { '[fF][rR]?"', '"', '\\' }, type = "string", syntax = python_fstring },
  { pattern = { "[fF][rR]?'", "'", '\\' }, type = "string", syntax = python_fstring },
  { pattern = { '[rR][fF]"', '"', '\\' }, type = "string", syntax = python_fstring },
  { pattern = { "[rR][fF]'", "'", '\\' }, type = "string", syntax = python_fstring },

  { pattern = { '[rRuUbB]?"""', '"""', '\\' }, type = "string" },
  { pattern = { "[rRuUbB]?'''", "'''", '\\' }, type = "string" },
  { pattern = { '[rRuUbB]?"', '"', '\\' }, type = "string" },
  { pattern = { "[rRuUbB]?'", "'", '\\' }, type = "string" },

  { pattern = "%d+[%d%.eE_]*", type = "number" },
  { pattern = "0[xboXBO][%da-fA-F_]+", type = "number" },
  { pattern = "%.?%d+", type = "number" },
  { pattern = "%f[-%w_]-%f[%d%.]", type = "number" },

  { pattern = "[%+%-=/%*%^%%<>!~|&@]", type = "operator" },

  -- Imports are namespaces in Dark+, while the imported names remain variables.
  { pattern = "from()%s+()[%a_][%w_%.]*", type = { "keyword2", "normal", "type" } },
  { pattern = "import()%s+()[%a_][%w_%.]*", type = { "keyword2", "normal", "type" } },

  { pattern = "[%a_][%w_]*%f[(]", type = "function" },
  { pattern = "%u[%u%d_]*", type = "keyword3" },
  { pattern = "%u[%l%d_][%w_]*", type = "type" },
  { pattern = "[%a_][%w_]*", type = "symbol" },
}

local python_fexpr = {
  patterns = table_merge({}, python_patterns),
  symbols = python_symbols,
}

table.insert(python_fstring.patterns, 1,
  { pattern = { "{", "}" }, syntax = python_fexpr })

syntax.add {
  name = "Python (Lite VS Dark+)",
  files = { "%.py$", "%.pyw$", "%.rpy$", "%.pyi$" },
  headers = "^#!.*[ /]python",
  comment = "#",
  block_comment = { '"""', '"""' },

  patterns = table_merge({
    { pattern = "#.*", type = "comment" },
    { pattern = { '^%s*"""', '"""' }, type = "comment" },

    -- These used to be colon-terminated subsyntaxes. A colon inside a quoted
    -- condition (for example "://") ended the statement early and left its
    -- closing quote active on the next line. Captures colour the declaration
    -- without introducing any cross-line tokenizer state.
    { pattern = "class()%s+()[%a_][%w_]*",
      type = { "keyword", "normal", "type" } },
    { pattern = "def()%s+()[%a_][%w_]*",
      type = { "keyword", "normal", "function" } },
  }, python_patterns),

  symbols = python_symbols,
}
