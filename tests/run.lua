-- snippets test runner
-- Usage: nvim --headless -u NONE -c "luafile tests/run.lua"

local specs = {
  "tests.trigger_spec",
  "tests.regex_spec",
  "tests.snipmate_spec",
  "tests.integration_spec",
  "tests.behavior_spec",
  "tests.misc_spec",
}

-- register tests/ as a module root (so `require("tests.harness")` resolves)
package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path

local failed_any = false
for _, spec in ipairs(specs) do
  local ok, err = pcall(require, spec)
  if not ok then
    print(("ERROR loading %s: %s"):format(spec, err))
    failed_any = true
  end
end

local ok = require("tests.harness").report()
if failed_any or not ok then
  vim.cmd("cquit")
else
  vim.cmd("qa!")
end
