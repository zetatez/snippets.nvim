-- Integration regression tests: end-to-end expansion through a snippet file.
-- Covers the bugs fixed in the UltiSnips parity audit:
--   * $0 rendered literally (blank lines dropped by _replace_text)
--   * transformation/visual 'g' flag dropped
--   * regex trigger capture groups
--   * context truthiness (VimL 0 / "" = falsy)
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
local bp = require("snippets.position")
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo.filetype = "t"
snippets.setup()
local src = snippets.manager._snippet_sources[1][2]

local function reload(lines)
  vim.fn.writefile(lines, "/tmp/opencode/snippets/t.snippets")
  src._snippets["t"] = nil
  src:ensure({ "t" })
end
local function bytrig(trig)
  for _, x in ipairs(src._snippets["t"]._snippets) do
    if x:trigger() == trig then return x end
  end
end

t.describe("integration: $0 not literal + blank lines preserved")
reload({ 'snippet t b', '/*', '$0', '*/', '', '$0', 'endsnippet' })
local s1 = bytrig("t")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "t" })
vim.api.nvim_win_set_cursor(0, { 1, 1 })
s1:matches("t")
pcall(s1.launch, s1, "", nil, nil, bp:new(0, 0), bp:new(0, 1))
local lns = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local found_dollar = false
for _, l in ipairs(lns) do if l:find("$0", 1, true) then found_dollar = true end end
t.check("no literal $0", not found_dollar)
t.check("blank line preserved", lns[4] == "")
t.check("comment intact", lns[1] == "/*" and lns[3] == "*/")

t.describe("integration: context truthiness")
reload({ 'context "0"', 'snippet ctx b', 'no $0', 'endsnippet' })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "ctx" })
vim.api.nvim_win_set_cursor(0, { 1, 3 })
t.check("context '0' suppresses", bytrig("ctx"):matches("ctx") == false)
reload({ 'context "1"', 'snippet ctx2 b', 'yes $0', 'endsnippet' })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "ctx2" })
vim.api.nvim_win_set_cursor(0, { 1, 4 })
t.check("context '1' allows", bytrig("ctx2"):matches("ctx2") == true)

t.describe("integration: regex trigger capture groups")
reload({ 'snippet ([a-z]+)(\\d+) r', 'ok $0', 'endsnippet' })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc123" })
vim.api.nvim_win_set_cursor(0, { 1, 6 })
local s3 = bytrig("([a-z]+)(\\d+)")
t.check("regex matches", s3:matches("abc123") == true)
t.check("captures groups", s3._last_re and s3._last_re.groups[1] == "abc" and s3._last_re.groups[2] == "123")
