-- SnipMate source tests (loading layout + single-file trigger extraction)
-- Run: nvim --headless -u NONE -c "luafile tests/run.lua"

local t = require("tests.harness")
for k in pairs(package.loaded) do
  if k:match("^snippets") then package.loaded[k] = nil end
end
vim.opt.rtp:append(vim.fn.getcwd())

local tmp = "/tmp/opencode/snipmate"
os.execute("rm -rf " .. tmp .. "; mkdir -p " .. tmp)
vim.g.SnippetsSnippetDirectories = {}
vim.g.SnippetsEnableSnipMate = 1

local source_mod = require("snippets.source")

-- Build a fake runtimepath containing only our temp snippets dir
vim.opt.rtp:remove(vim.fn.getcwd())
vim.opt.rtp:prepend(tmp)
vim.opt.rtp:append(vim.fn.getcwd())

-- Create snipMate snippets
os.execute("mkdir -p " .. tmp .. "/snippets/c")
local okwrite = vim.fn.writefile({ "hello world" }, tmp .. "/snippets/c/hello.snippet")
vim.fn.writefile({
  "snippet for",
  "\tfor (${1:i} = 0; $1 < ${2:n}; $1++) {",
  "\t\t$0",
  "\t}",
  "snippet if",
  "\tif (${1:cond}) {",
  "\t\t$0",
  "\t}",
}, tmp .. "/snippets/c.snippets")

t.describe("snipmate single .snippet file (snippets/{ft}/{trig}.snippet)")
do
  local src = source_mod.SnipMateFileSource:new()
  src:ensure({ "c" })
  local dict = src._snippets["c"]
  t.check("dictionary exists", dict ~= nil)
  local found = false
  if dict then
    for _, s in ipairs(dict._snippets) do
      if s:trigger() == "hello" then
        found = true
        t.eq("content is the file body", s._value, "hello world")
        t.eq("priority is -1000 (snipmate)", s:priority(), -1000)
        t.check("forced w option", s:has_option("w"))
      end
    end
  end
  t.check("hello.snippet loaded under trigger 'hello'", found)
end

t.describe("snipmate .snippets text file")
do
  local src = source_mod.SnipMateFileSource:new()
  src:ensure({ "c" })
  local dict = src._snippets["c"]
  local names = {}
  if dict then
    for _, s in ipairs(dict._snippets) do
      names[s:trigger()] = true
    end
  end
  t.check("for snippet parsed", names["for"] == true)
  t.check("if snippet parsed", names["if"] == true)
end
