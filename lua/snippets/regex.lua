-- Best-effort translation of common Python-re syntax to Vim regex under "\v".
--
-- Full Python `re` parity is not feasible in pure Lua + Vim's regex engine;
-- this covers the constructs that actually appear in real snippet files and
-- that would otherwise crash or silently miscount groups:
--   * `(?:...)`   non-capturing group  -> Vim `\%(...)`
--   * `=` `@` `~` Python-literal chars that are magic under Vim `\v`
--     (`=` = 0-or-1 quantifier, `@` starts \@-items, `~` = last substitute)
-- Anything else is passed through verbatim.

local M = {}

-- Scan `pat` and rewrite balanced `(?: ... )` groups to `\%( ... )`.
-- Char classes `[...]` and backslash escapes are respected so that literal
-- parentheses inside them never confuse the paren tracker.
function M.py_to_vim(pat)
  local out = {}
  local i, n = 1, #pat
  local stack = {} -- each entry: "cap" | "nc"
  while i <= n do
    local c = pat:sub(i, i)
    if c == "\\" then
      local nxt = pat:sub(i + 1, i + 1)
      if nxt == "b" then
        -- Python word-boundary: map to Vim \< (word start) when followed by a
        -- word-like token, else \> (word end). Best-effort heuristic.
        local after = pat:sub(i + 2, i + 2)
        local wordish = after ~= "" and (after:match("[%w_]") or after == "[" or after == "(")
        out[#out + 1] = wordish and "<" or ">"
        i = i + 2
      else
        out[#out + 1] = c
        if nxt ~= "" then
          out[#out + 1] = nxt
          i = i + 1
        end
        i = i + 1
      end
    elseif c == "[" then
      -- copy the whole character class verbatim, preserving backslash
      -- escapes (e.g. the `\n` in `[^\n=]`); dropping them silently
      -- changes the class meaning.
      local j = i
      local closed = false
      while j <= n do
        if pat:sub(j, j) == "\\" and j < n then
          out[#out + 1] = pat:sub(j, j)
          out[#out + 1] = pat:sub(j + 1, j + 1)
          j = j + 2
        else
          local cc = pat:sub(j, j)
          out[#out + 1] = cc
          if cc == "]" then closed = true break end
          j = j + 1
        end
      end
      i = (closed and j + 1) or (n + 1)
    elseif c == "(" then
      local head = pat:sub(i + 1, i + 2)
      if head == "?:" then
        out[#out + 1] = "%("
        stack[#stack + 1] = "nc"
        i = i + 3
      else
        local nm_s, nm_e = pat:find("%?P<[^>]+>", i + 1)
        if nm_s == i + 1 then
          -- Named group (?P<name>...): Vim has no named groups; emit a
          -- plain capturing group (numbering stays aligned with the
          -- names extracted for match.groupdict()).
          out[#out + 1] = "("
          stack[#stack + 1] = "cap"
          i = nm_e + 1
        elseif pat:sub(i + 1, i + 1) == "?" then
          -- lookahead/lookbehind/other `(?...)` -> leave as plain group; Vim
          -- does not understand these, but translation is out of scope.
          out[#out + 1] = "("
          stack[#stack + 1] = "cap"
          i = i + 1
        else
          out[#out + 1] = "("
          stack[#stack + 1] = "cap"
          i = i + 1
        end
      end
    elseif c == ")" then
      local kind = table.remove(stack)
      if kind == "nc" then
        out[#out + 1] = ")"
      else
        out[#out + 1] = ")"
      end
      i = i + 1
    elseif c == "=" then
      -- Python literal `=`; in Vim \v it is a 0-or-1 quantifier (turning e.g.
      -- `!([^=]+)=` into `!` + optional tail, which matched a bare `!`).
      out[#out + 1] = "\\="
      i = i + 1
    elseif c == "@" then
      -- Python literal `@`; in Vim it starts \@-sequences. Match via class.
      out[#out + 1] = "[@]"
      i = i + 1
    elseif c == "~" then
      -- Python literal `~`; in Vim it recalls the last substitute string.
      out[#out + 1] = "\\~"
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

-- Prepend "\v" (very magic) so Python-style `()` are capture groups, after
-- running the non-capturing-group translation.
-- opts.dotall simulates Python re.DOTALL (UltiSnips transformations always
-- use it): a bare `.` outside [] and escapes also matches newlines.
local _compile_cache = {}

local function _dotall(pat)
  local out, n, i = {}, #pat, 1
  while i <= n do
    local c = pat:sub(i, i)
    if c == "\\" and i < n then
      out[#out + 1] = c
      out[#out + 1] = pat:sub(i + 1, i + 1)
      i = i + 2
    elseif c == "[" then
      local j = i
      while j <= n do
        out[#out + 1] = pat:sub(j, j)
        if pat:sub(j, j) == "\\" and j < n then
          out[#out + 1] = pat:sub(j + 1, j + 1)
          j = j + 2
        else
          j = j + 1
          if pat:sub(j - 1, j - 1) == "]" then break end
        end
      end
      i = j
    elseif c == "." then
      out[#out + 1] = "\\_s"
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

function M.compile(pat, opts)
  local key = pat .. "\0" .. ((opts and opts.dotall) and "s" or "")
  local hit = _compile_cache[key]
  if hit ~= nil then return hit end
  if opts and opts.dotall then pat = _dotall(pat) end
  local res = "\\v" .. M.py_to_vim(pat)
  _compile_cache[key] = res
  return res
end

return M
