-- Regex translation + regex-trigger unit tests
-- Run: nvim --headless -u NONE -c "luafile tests/run.lua"

local t = require("tests.harness")
for k in pairs(package.loaded) do
  if k:match("^snippets") then package.loaded[k] = nil end
end
vim.opt.rtp:append(vim.fn.getcwd())

local R = require("snippets.regex")
local SD = require("snippets.snippet")
local function def(trigger, opts)
  return SD.SnippetsSnippetDefinition:new(0, trigger, "BODY", "", opts, {}, "", nil, {})
end

t.describe("regex.compile: non-capturing (?:...)")
local function g(pat, text)
  local m = vim.fn.matchlist(text, pat)
  return m
end
do
  -- (?:x|y) must not count toward group numbers
  local m = g(R.compile("(?:cat|dog)(\\d+)"), "dog7")
  t.eq("whole matches", m[1], "dog7")
  t.eq("group1 is the captured digit", m[2], "7")
  local m2 = g(R.compile("(a)(?:b)(c)"), "abc")
  t.eq("nc in middle leaves numbering intact g1=a", m2[2], "a")
  t.eq("nc in middle leaves numbering intact g2=c", m2[3], "c")
  -- literal ) inside char class must not close the group
  local m3 = g(R.compile("(?:a[()])z(z)"), "a)zz")
  t.eq("class-paren whole", m3[1], "a)zz")
  t.eq("class-paren group1", m3[2], "z")
end

t.describe("regex trigger with (?:)")
do
  local s = def("(?:cat|dog)(\\d+)", "r")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "dog7" })
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  t.check("matches dog7", s:matches("dog7") == true)
  t.check("matched text is dog7", s:matched() == "dog7")
  t.check("captured group is 7", s._last_re and s._last_re.groups[1] == "7")
end

t.describe("regex trigger word-boundary anchoring")
do
  -- \b in python = word boundary; Vim equivalent kept as-is (best effort)
  local s = def("(\\bfoo\\b)", "r")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "bar foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  t.check("matches trailing foo at boundary", s:matches("bar foo") == true)
end
