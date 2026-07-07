-- Minimal test harness for snippets (run under: nvim --headless -u NONE)
-- Usage: nvim --headless -u NONE -c "luafile tests/run.lua"

vim.opt.rtp:append(vim.fn.getcwd())

local M = {}

M.passed = 0
M.failed = 0
M.failures = {}
M.current = ""

local function esc(s)
  return (s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"))
end

function M.describe(name)
  M.current = name
  print("\n" .. name)
end

function M.check(name, cond)
  if cond then
    M.passed = M.passed + 1
    print("  \27[32m[PASS]\27[0m " .. name)
  else
    M.failed = M.failed + 1
    M.failures[#M.failures + 1] = ("%s > %s"):format(M.current, name)
    print("  \27[31m[FAIL]\27[0m " .. name)
  end
end

function M.eq(name, actual, expected)
  local a, e = tostring(actual), tostring(expected)
  if a == e then
    M.passed = M.passed + 1
    print("  \27[32m[PASS]\27[0m " .. name .. " (" .. esc(e) .. ")")
  else
    M.failed = M.failed + 1
    M.failures[#M.failures + 1] = ("%s > %s"):format(M.current, name)
    print("  \27[31m[FAIL]\27[0m " .. name .. " expected=" .. esc(e) .. " actual=" .. esc(a))
  end
end

function M.report()
  print(("\n==== %d passed, %d failed ===="):format(M.passed, M.failed))
  if M.failed > 0 then
    print("Failures:")
    for _, f in ipairs(M.failures) do
      print("  - " .. f)
    end
  end
  return M.failed == 0
end

return M
