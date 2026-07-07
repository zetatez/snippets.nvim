-- Run a single spec in its own nvim process (isolation between spec files).
-- Set vim.g.TEST_SPEC to the spec basename before running.
-- e.g. nvim --headless -u NONE -c "lua vim.g.TEST_SPEC='trigger_spec'" -c "luafile tests/single.lua"

local name = vim.g.TEST_SPEC or "trigger_spec"
package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path

local ok, err = pcall(require, "tests." .. name)
if not ok then
  print(("ERROR loading %s: %s"):format(name, err))
  vim.cmd("cquit")
else
  local passed_ok = require("tests.harness").report()
  if passed_ok then
    vim.cmd("qa!")
  else
    vim.cmd("cquit")
  end
end
