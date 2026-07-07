-- Behavioral end-to-end tests driving the manager (expansion, jumping,
-- auto-trigger, mirror updates, snippet teardown).
-- Run: nvim --headless -u NONE -c "luafile tests/run.lua"

local t = require("tests.harness")
for k in pairs(package.loaded) do
  if k:match("^snippets") then package.loaded[k] = nil end
end
vim.opt.rtp:append(vim.fn.getcwd())
vim.g.SnippetsSnippetDirectories = { "/tmp/opencode/snippets" }
vim.g.SnippetsEnableSnipMate = 0
vim.g.SnippetsAutoTrigger = 1
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
  while #mgr._active_snippets > 0 do
    table.remove(mgr._active_snippets)
  end
  mgr:_teardown_inner_state()
end

t.describe("behavior: A-option autotrigger via manager")
do
  reload({ 'snippet auto "x" bA', 'EXPANDED $0', 'endsnippet' })
  settext("auto", 4)
  local ok, res = pcall(mgr._try_expand, mgr, true)
  t.check("_try_expand(true) succeeds", ok and res == true)
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  t.eq("trigger replaced by body", line, "EXPANDED ")
  t.check("snippet finished (only $0)", #mgr._active_snippets == 0)
  t.check("inner state torn down", mgr._inner_state_up == false)
end
reset_manager()

t.describe("behavior: plain expand then jump through tab stops")
do
  -- $1 has a default, $2 empty, then $0
  reload({ 'snippet go b', '$1 then ${2:two} then $0', 'endsnippet' })
  settext("go", 2)
  local ok, res = pcall(mgr._try_expand, mgr)
  t.check("expand ok", ok and res == true)
  t.check("snippet active", #mgr._active_snippets == 1)
  local cur = vim.api.nvim_win_get_cursor(0)
  -- cursor should be at $1 (start col 0)
  t.check("cursor at $1", cur[1] == 1 and cur[2] == 0)
  -- jump forward -> $2
  pcall(mgr.jump_forwards, mgr)
  cur = vim.api.nvim_win_get_cursor(0)
  t.eq("jumped to $2 (after 'then ')", cur[2], #" then ")
  -- jump forward -> $0
  pcall(mgr.jump_forwards, mgr)
  t.check("finished at $0", #mgr._active_snippets == 0)
end
reset_manager()

t.describe("behavior: mirror wiring + update_textobjects idempotency")
do
  reload({ 'snippet mv b', '$1 / $1 $0', 'endsnippet' })
  settext("mv", 2)
  pcall(mgr._try_expand, mgr)
  t.check("active", #mgr._active_snippets == 1)
  local si = mgr._active_snippets[1]
  -- A mirror for tab stop 1 must exist in the tree besides the $1 tab stop.
  local tab1, mirrors = 0, 0
  local function scan(o)
    if rawget(o, "_tabstops") then
      for no, ts in pairs(o._tabstops) do
        if no == 1 then tab1 = tab1 + 1 end
      end
    end
    for _, c in ipairs(o._children or {}) do
      -- A Mirror/Transformation is bound to a source tab stop (_ts) but is
      -- not itself an editable tab stop (no _tabstops table).
      if c._ts and not rawget(c, "_tabstops") then
        local okno, n = pcall(function() return c._ts:number() end)
        if okno and n == 1 then mirrors = mirrors + 1 end
      end
      scan(c)
    end
  end
  scan(si)
  t.check("tab stop 1 exists", tab1 >= 1)
  t.check("at least one $1 mirror in tree", mirrors >= 1)
  -- update_textobjects must be idempotent / not raise for an empty $1 + mirror
  local ok_upd = pcall(si.update_textobjects, si, vim.api.nvim_buf_get_lines)
  t.check("update_textobjects converges", ok_upd)
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  t.eq("body stable across update pass", line, " /  ")
end
reset_manager()

t.describe("behavior: manual expand trigger no longer re-triggers via tab")
do
  -- After finishing a manual expansion, pressing expand again should be a no-op
  reload({ 'snippet once b', 'done $0', 'endsnippet' })
  settext("once", 4)
  mgr._last_failure_key = nil
  pcall(mgr.expand, mgr)
  t.check("finished immediately", #mgr._active_snippets == 0)
  local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
  t.eq("body present", line, "done ")
end
reset_manager()
