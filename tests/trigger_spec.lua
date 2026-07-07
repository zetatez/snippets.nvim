-- Trigger-matching unit tests (port of UltiSnips test_SnippetOptions.py)
-- Covers options: (default) b i w r p A e  + multiword triggers + could_match.
-- Run: nvim --headless -u NONE -c "luafile tests/run.lua"

local t = require("tests.harness")

-- Clear snippets modules so the freshly-edited source is loaded
for k in pairs(package.loaded) do
  if k:match("^snippets") then package.loaded[k] = nil end
end
vim.opt.rtp:append(vim.fn.getcwd())

local SD = require("snippets.snippet")

-- Construct a definition directly (bypasses file parsing so we test matching
-- logic in isolation).
local function def(trigger, opts, context)
  return SD.SnippetsSnippetDefinition:new(0, trigger, "BODY", "", opts, {}, "", context, {})
end

-- matches(before): trigger is eligible at cursor-after-`before`.
local function mk(name)
  return def("test", name)
end

--------------------------------------------------------------------------------
t.describe("default option (no letter)")
do
  local s = mk("")
  t.check("bare trigger at start", s:matches("test"))
  t.check("trigger after space", s:matches("a test"))
  t.check("trigger alone w/ leading space", s:matches(" test"))
  t.check("rejects in-word 'atest'", not s:matches("atest"))
  t.check("rejects in-word 'a.test'", not s:matches("a.test"))
  t.check("rejects in-word '$test'", not s:matches("$test"))
  t.check("rejects empty", not s:matches(""))
  t.check("rejects wrong word", not s:matches("tes"))
  t.check("rejects trailing word mismatch", not s:matches("testx"))
end

--------------------------------------------------------------------------------
t.describe("option i (in-word)")
do
  local s = mk("i")
  t.check("in-word 'atest'", s:matches("atest"))
  t.check("in-word '$test'", s:matches("$test"))
  t.check("in-word '-test'", s:matches("-test"))
  t.check("in-word after space still ok", s:matches("a test"))
  t.check("bare", s:matches("test"))
  t.check("rejects prefix only", not s:matches("tes"))
  -- non-ascii prefix (UltiSnips uses ßßtest)
  t.check("in-word umlaut prefix", s:matches("\195\159\195\159test"))
end

--------------------------------------------------------------------------------
t.describe("option w (word boundary)")
do
  local s = mk("w")
  t.check("bare at start", s:matches("test"))
  t.check("after punctuation '-'", s:matches("a-test"))
  t.check("after punctuation '('", s:matches("a(test"))
  t.check("after punctuation '$'", s:matches("$test"))
  t.check("after space", s:matches("a test"))
  t.check("rejects in-word 'atest'", not s:matches("atest"))
  t.check("rejects in-word 'abtest'", not s:matches("abtest"))
  t.check("rejects prefix", not s:matches("tes"))
end

--------------------------------------------------------------------------------
t.describe("option b (beginning of line)")
do
  local s = mk("b")
  t.check("at start", s:matches("test"))
  t.check("after leading spaces", s:matches("   test"))
  t.check("after leading tab", s:matches("\ttest"))
  t.check("rejects after text", not s:matches("a test"))
  t.check("rejects after text no space", not s:matches("atest"))
end

--------------------------------------------------------------------------------
t.describe("option p (partial prefix)")
do
  local s = def("import", "p")
  t.check("full trigger", s:matches("import"))
  t.check("partial 'im'", s:matches("im"))
  t.check("partial 'imp'", s:matches("imp"))
  t.check("partial 'impo'", s:matches("impo"))
  -- only the typed prefix is matched/removed
  s:matches("imp")
  t.eq("_matched is typed prefix", s:matched(), "imp")
  -- after a word boundary
  s:matches("hello imp")
  t.eq("_matched after space", s:matched(), "imp")
  t.check("rejects non-prefix", not s:matches("tes"))
  t.check("rejects empty", not s:matches(""))
end

--------------------------------------------------------------------------------
t.describe("option r (regex trigger)")
do
  local s = def("(test)", "r")
  t.check("regex matches 'test'", s:matches("test"))
  t.eq("_matched == whole match", s:matched(), "test")
  s:matches("a test")
  t.eq("captures group1", s._last_re and s._last_re.groups[1], "test")
  -- UltiSnips docs: regex snippets CAN trigger in-word by default.
  t.check("matches in-word 'atest'", s:matches("atest"))
  t.check("must reach cursor", not s:matches("testx"))
end

--------------------------------------------------------------------------------
t.describe("option e + context (Python expr, UltiSnips parity)")
do
  -- Context is evaluated only on non-empty buffers (UltiSnips skips
  -- evaluation on a single empty line).
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "ctx" })
  local sy = def("ctx", "e", "True")
  local sn = def("ctx", "e", "False")
  local sq = def("ctx", "e", "''")
  local sz = def("ctx", "e", "0")
  local so = def("ctx", "e", "len(before) > 2")
  t.check("context True matches", sy:matches("ctx"))
  t.check("context False suppresses", not sn:matches("ctx"))
  t.check("context '' suppresses", not sq:matches("ctx"))
  t.check("context 0 suppresses (Python truthiness, unlike VimL)", not sz:matches("ctx"))
  t.check("context sees `before` local", so:matches("ctx"))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  t.check("context skipped on empty buffer", not sy:matches("ctx"))
end

--------------------------------------------------------------------------------
t.describe("option A (autotrigger-only filter via dictionary)")
do
  local D = require("snippets.source").SnippetDictionary
  local d = D:new()
  d:add_snippet(def("auto", "A"))
  d:add_snippet(def("manual", ""))
  -- autotrigger_only query must only return A snippets
  local all = d:get_matching_snippets("auto", false, false)
  t.eq("manual-mode returns all matches", #all, 1)
  local at = d:get_matching_snippets("auto", false, true)
  t.eq("autotrigger-only returns the A snippet", #at, 1)
  if at[1] then t.eq("filtered snippet is auto", at[1]:trigger(), "auto") end
  local none = d:get_matching_snippets("manual", false, true)
  t.eq("non-A manual snippet excluded from autotrigger", #none, 0)
end

--------------------------------------------------------------------------------
t.describe("multiword trigger")
do
  local s = def("multi word", "w")
  t.check("full multiword", s:matches("multi word"))
  t.check("after prefix text", s:matches("go multi word"))
  t.check("rejects in-word", not s:matches("xmulti word"))
  local q = def('"quoted trigger"', "")
  t.check("trigger may include quotes", q:matches('"quoted trigger"'))
end

--------------------------------------------------------------------------------
t.describe("could_match (partial / listing)")
do
  local s = def("hello", "")
  t.check("prefix 'hel'", s:could_match("hel"))
  t.check("empty", s:could_match(""))
  t.check("exact", s:could_match("hello"))
  t.check("rejects non-prefix", not s:could_match("xel"))

  local w = def("test", "w")
  t.check("w partial after boundary", w:could_match("-tes"))
  t.check("w partial at start", w:could_match("tes"))

  local i = def("test", "i")
  t.check("i partial mid-word", i:could_match("xte"))

  local p = def("import", "p")
  t.check("p partial", p:could_match("imp"))
  t.check("p full", p:could_match("import"))
end

--------------------------------------------------------------------------------
local ok = true
-- Report and exit handled by tests/run.lua
return ok
