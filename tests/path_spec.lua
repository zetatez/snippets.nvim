-- Path-configuration tests: SnippetsSnippetDirectories (relative/absolute/~/glob)
-- and SnippetsSnippetFiles (concrete files), incl. b: override + filetype filter.
-- Run: nvim --headless -u NONE -c "luafile tests/run.lua"

local t = require("tests.harness")
for k in pairs(package.loaded) do
  if k:match("^snippets") then package.loaded[k] = nil end
end
vim.opt.rtp:append(vim.fn.getcwd())
vim.g.SnippetsEnableSnipMate = 0
vim.g.SnippetsSnippetDirectories = nil
vim.g.SnippetsSnippetFiles = nil

local source_mod = require("snippets.source")

local HOME = "/tmp/opencode/paths"
os.execute("rm -rf " .. HOME .. "; mkdir -p " .. HOME)
local ABS = HOME .. "/abs"
local RTP = HOME .. "/rtp"
local OTHER = HOME .. "/other"
local BDIR = HOME .. "/bdir"
os.execute("mkdir -p " .. ABS .. " " .. OTHER .. " " .. BDIR .. " " .. RTP .. "/snippets " .. RTP .. "/snippets/python " .. ABS .. "/cpp")

vim.fn.writefile({ 'snippet abs_one b', 'ABS1 $0', 'endsnippet' }, ABS .. "/cpp.snippets")
vim.fn.writefile({ 'snippet abs_std b', 'ABS2 $0', 'endsnippet' }, ABS .. "/cpp_std.snippets")
vim.fn.writefile({ 'snippet sub_dir b', 'SUB $0', 'endsnippet' }, ABS .. "/cpp/inc.snippets")
vim.fn.writefile({ 'snippet other_all b', 'OTHER $0', 'endsnippet' }, OTHER .. "/all.snippets")
vim.fn.writefile({ 'snippet rtp_rel b', 'RTP $0', 'endsnippet' }, RTP .. "/snippets/cpp.snippets")
vim.fn.writefile({ 'snippet py_rel b', 'PY $0', 'endsnippet' }, RTP .. "/snippets/python/extra.snippets")
vim.fn.writefile({ 'snippet b_dir b', 'BDIR $0', 'endsnippet' }, BDIR .. "/cpp.snippets")

-- deterministic runtimepath: RTP first, then the plugin repo (for deps)
vim.opt.rtp:prepend(RTP)
vim.opt.rtp:append(vim.fn.getcwd())

local function collect(ft)
  local src = source_mod.SnippetsFileSource:new()
  src:ensure({ ft })
  local names = {}
  if src._snippets[ft] then
    for _, s in ipairs(src._snippets[ft]._snippets) do
      names[s:trigger()] = true
    end
  end
  return names
end

t.describe("directories: absolute path")
do
  vim.g.SnippetsSnippetDirectories = { ABS }
  local names = collect("cpp")
  t.check("loads {ft}.snippets", names["abs_one"] == true)
  t.check("loads {ft}_*.snippets", names["abs_std"] == true)
  t.check("loads {ft}/ subdir", names["sub_dir"] == true)
end

t.describe("directories: runtimepath-relative")
do
  vim.g.SnippetsSnippetDirectories = { "snippets" }
  local names = collect("cpp")
  t.check("rtp-relative dir loads", names["rtp_rel"] == true)
end

t.describe("directories: mixed relative + absolute")
do
  vim.g.SnippetsSnippetDirectories = { "snippets", ABS }
  local names = collect("cpp")
  t.check("relative part", names["rtp_rel"] == true)
  t.check("absolute part", names["abs_one"] == true)
end

t.describe("directories: ~ expansion")
do
  -- emulate ~ by pointing at HOME via a '$VAR'
  vim.env.SNIPPETS_TEST_HOME = ABS
  vim.g.SnippetsSnippetDirectories = { "$SNIPPETS_TEST_HOME" }
  local names = collect("cpp")
  t.check("$VAR dir loads", names["abs_one"] == true)
end

t.describe("directories: buffer-local override")
do
  vim.g.SnippetsSnippetDirectories = { RTP .. "/snippets" }
  vim.b.SnippetsSnippetDirectories = { BDIR }
  local names = collect("cpp")
  t.check("b: dir used instead of g:", names["b_dir"] == true)
  t.check("g: dir ignored", names["rtp_rel"] == nil)
  vim.b.SnippetsSnippetDirectories = nil
end

t.describe("directories: glob")
do
  vim.g.SnippetsSnippetDirectories = { HOME .. "/a*" }
  local names = collect("cpp")
  t.check("glob directory loaded", names["abs_one"] == true)
end

t.describe("files: SnippetsSnippetFiles (absolute, ft + all)")
do
  vim.g.SnippetsSnippetFiles = { ABS .. "/cpp.snippets", OTHER .. "/all.snippets" }
  vim.g.SnippetsSnippetDirectories = {}
  local names = collect("cpp")
  t.check("explicit cpp file", names["abs_one"] == true)
  t.check("explicit all file", names["other_all"] == true)
  -- python ft must NOT get cpp.snippets
  local pynames = collect("python")
  t.check("ft filtered", pynames["abs_one"] == nil and pynames["other_all"] == true)
end

t.describe("files: SnippetsSnippetFiles (rtp-relative + glob)")
do
  vim.g.SnippetsSnippetFiles = { "snippets/python/*.snippets", ABS .. "/cpp_*.snippets" }
  vim.g.SnippetsSnippetDirectories = {}
  local py = collect("python")
  t.check("rtp-relative python file", py["py_rel"] == true)
  local cpp = collect("cpp")
  t.check("absolute glob file", cpp["abs_std"] == true)
  t.check("glob excluded cpp.snippets", cpp["abs_one"] == nil)
end

vim.g.SnippetsSnippetFiles = nil
vim.g.SnippetsSnippetDirectories = nil
