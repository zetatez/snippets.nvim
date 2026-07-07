-- Tests for launch/jump option letters (m s x) and the AddedSnippetsSource.
-- Run: nvim --headless -u NONE -c "luafile tests/run.lua"

local t = require("tests.harness")
for k in pairs(package.loaded) do
  if k:match("^snippets") then package.loaded[k] = nil end
end
vim.opt.rtp:append(vim.fn.getcwd())
vim.g.SnippetsSnippetDirectories = { "/tmp/opencode/snippets" }
vim.g.SnippetsEnableSnipMate = 0
os.execute("mkdir -p /tmp/opencode/snippets")

local snippets = require("snippets")
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo.filetype = "t"
snippets.setup()
local mgr = snippets.manager
local src = mgr._snippet_sources[1][2]

local function reload(lines)
  vim.fn.writefile(lines, "/tmp/opencode/snippets/t.snippets")
  src._snippets["t"] = nil
  src:ensure({ "t" })
end
local function settext(text, col)
  vim.opt.virtualedit = "onemore"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
  vim.api.nvim_win_set_cursor(0, { 1, col or #text })
end
local function reset_manager()
  while #mgr._active_snippets > 0 do table.remove(mgr._active_snippets) end
  mgr:_teardown_inner_state()
end

t.describe("option m: trim trailing whitespace of every body line at launch")
do
  reload({ 'snippet mm mb', 'a   ', 'b\t', '', '  c  ', '$0', 'endsnippet' })
  settext("mm", 2)
  pcall(mgr._try_expand, mgr)
  local lns = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  t.eq("line1 trimmed", lns[1], "a")
  t.eq("line2 tab trimmed", lns[2], "b")
  t.eq("line3 stays empty", lns[3], "")
  t.eq("line4 leading ws kept, trailing cut", lns[4], "  c")
end
reset_manager()

t.describe("option s: strip trailing whitespace on jump landing line")
do
  reload({ 'snippet ss sb', 'foo ${1:x}    ', '$0', 'endsnippet' })
  settext("ss", 2)
  local ok, res = pcall(mgr._try_expand, mgr)
  t.check("expand ok", ok and res == true)
  local s = src._snippets["t"]._snippets[1]
  t.check("s option parsed", s:has_option("s"))
  -- landing on the first tab stop triggers the 's' rstrip of the whole line
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  t.eq("trailing spaces stripped on line 1", line, "foo x")
end
reset_manager()

t.describe("option x: finish at $0 without staying in insert mode")
do
  reload({ 'snippet xx xb', 'hi $0', 'endsnippet' })
  settext("xx", 2)
  pcall(mgr.expand, mgr)
  t.check("snippet finished", #mgr._active_snippets == 0)
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  t.eq("body present", line, "hi ")
  t.eq("in normal mode", vim.fn.mode(), "n")
end
reset_manager()

t.describe("AddedSnippetsSource: programmatic add_snippet")
do
  mgr:add_snippet("addedfoo", "ADDED $0", "desc", "", nil, 10)
  settext("addedfoo", 8)
  local ok, res = pcall(mgr._try_expand, mgr)
  t.check("expand ok", ok and res == true)
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  t.eq("added snippet expanded", line, "ADDED ")
  t.check("finished", #mgr._active_snippets == 0)
end
reset_manager()
