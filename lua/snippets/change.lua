local Position = require("snippets.position")

local M = {}

M.DROP_SNIPPET = {}

local PATHOLOGICAL_CHAR_DELTA = 2000

local function joined_len(lines)
  if #lines == 0 then return 0 end
  local total = #lines - 1
  for _, l in ipairs(lines) do
    total = total + #l
  end
  return total
end

local function is_pathological_diff_input(old_lines, new_lines)
  return math.abs(joined_len(new_lines) - joined_len(old_lines)) > PATHOLOGICAL_CHAR_DELTA
end

function M.diff(a, b, sline)
  sline = sline or 0
  local d = {}
  local seen = {}

  local deletion_cost = #a + #b
  local insertion_cost = #a + #b

  d[0] = { { x = 0, y = 0, line = sline, col = 0, what = {} } }
  local cost = 0

  -- Bail-out: Dijkstra over the (x, y) grid can explode on large inputs
  -- (e.g. a complex multi-line edit inside a KB-sized snippet that
  -- detect_edits could not model and whose net length delta is small
  -- enough to pass is_pathological_diff_input). Returning nil keeps the
  -- snippet alive with a stale tree instead of hanging the editor;
  -- callers treat nil as "no consumable edits".
  local MAX_DIFF_STATES = 100000
  local nstates = 0

  while true do
    local states = d[cost]
    while states and #states > 0 do
      nstates = nstates + 1
      if nstates > MAX_DIFF_STATES then return nil end
      local state = table.remove(states)
      local x, y, line, col, what = state.x, state.y, state.line, state.col, state.what

      if string.sub(a, x + 1) == string.sub(b, y + 1) then
        return what
      end

      local a_char = string.sub(a, x + 1, x + 1)
      local b_char = string.sub(b, y + 1, y + 1)

      if x < #a and y < #b and a_char == b_char then
        local ncol = col + 1
        local nline = line
        if a_char == "\n" then ncol = 0; nline = line + 1 end

        local lcost = cost + 1
        if #what > 0 and what[#what].type == "D" and what[#what].line == line and what[#what].col == col and a_char ~= "\n" then
          lcost = (deletion_cost + insertion_cost) * 1.5
        end
        local key = (x + 1) .. "," .. (y + 1)
        if not seen[key] or seen[key] > lcost then
          seen[key] = lcost
          if not d[lcost] then d[lcost] = {} end
          table.insert(d[lcost], { x = x + 1, y = y + 1, line = nline, col = ncol, what = what })
        end
      end

      if y < #b then
        local ncol = col + 1
        local nline = line
        if b_char == "\n" then ncol = 0; nline = line + 1 end

        local key = x .. "," .. (y + 1)
        if #what > 0 and what[#what].type == "I" and what[#what].line == nline and what[#what].col + #what[#what].text == col and b_char ~= "\n" then
          local new_cost = cost + math.floor((insertion_cost + ncol) / 2)
          if not seen[key] or seen[key] > new_cost then
            seen[key] = new_cost
            if not d[new_cost] then d[new_cost] = {} end
            local new_what = {}
            for _, w in ipairs(what) do table.insert(new_what, w) end
            new_what[#new_what] = { type = "I", line = what[#what].line, col = what[#what].col, text = what[#what].text .. b_char }
            table.insert(d[new_cost], { x = x, y = y + 1, line = line, col = ncol, what = new_what })
          end
        else
          local new_cost = cost + insertion_cost + ncol
          if not seen[key] or seen[key] > new_cost then
            seen[key] = new_cost
            if not d[new_cost] then d[new_cost] = {} end
            local new_what = {}
            for _, w in ipairs(what) do table.insert(new_what, w) end
            table.insert(new_what, { type = "I", line = line, col = col, text = b_char })
            table.insert(d[new_cost], { x = x, y = y + 1, line = nline, col = ncol, what = new_what })
          end
        end
      end

      if x < #a then
        local key = (x + 1) .. "," .. y
        if #what > 0 and what[#what].type == "D" and what[#what].line == line and what[#what].col == col and a_char ~= "\n" and what[#what].text ~= "\n" then
          local new_cost = cost + math.floor(deletion_cost / 2)
          if not seen[key] or seen[key] > new_cost then
            seen[key] = new_cost
            if not d[new_cost] then d[new_cost] = {} end
            local new_what = {}
            for _, w in ipairs(what) do table.insert(new_what, w) end
            new_what[#new_what] = { type = "D", line = what[#what].line, col = what[#what].col, text = what[#what].text .. a_char }
            table.insert(d[new_cost], { x = x + 1, y = y, line = line, col = col, what = new_what })
          end
        else
          local new_cost = cost + deletion_cost
          if not seen[key] or seen[key] > new_cost then
            seen[key] = new_cost
            if not d[new_cost] then d[new_cost] = {} end
            local new_what = {}
            for _, w in ipairs(what) do table.insert(new_what, w) end
            table.insert(new_what, { type = "D", line = line, col = col, text = a_char })
            table.insert(d[new_cost], { x = x + 1, y = y, line = line, col = col, what = new_what })
          end
        end
      end
    end
    cost = cost + 1
  end
end

local function byte_to_char_col(line, byte_col)
  if byte_col == 0 then return 0 end
  if byte_col >= #line then return vim.fn.strchars(line) end
  local s = string.sub(line, 1, byte_col)
  return vim.fn.strchars(s)
end

function M.on_bytes_to_edits(event, old_lines, new_buf, snippet_start)
  local start_row = event[1]
  local start_col_b = event[2]
  local old_end_row = event[3]
  local old_end_col_b = event[4]
  local new_end_row = event[5]
  local new_end_col_b = event[6]

  local rel_row = start_row - snippet_start
  if rel_row < 0 or rel_row >= #old_lines then return nil end
  if old_end_row > 0 and rel_row + old_end_row >= #old_lines then return nil end
  if new_end_row > 0 and start_row + new_end_row >= #new_buf then return nil end

  local cmds = {}
  local start_col = byte_to_char_col(old_lines[rel_row + 1], start_col_b)

  if old_end_row == 0 and old_end_col_b > 0 then
    local end_col = byte_to_char_col(old_lines[rel_row + 1], start_col_b + old_end_col_b)
    local deleted = string.sub(old_lines[rel_row + 1], start_col + 1, end_col)
    table.insert(cmds, { "D", start_row, start_col, deleted })
  elseif old_end_row > 0 then
    local rest = string.sub(old_lines[rel_row + 1], start_col + 1)
    if #rest > 0 then table.insert(cmds, { "D", start_row, start_col, rest }) end
    table.insert(cmds, { "D", start_row, start_col, "\n" })
    for i = 2, old_end_row do
      local content = old_lines[rel_row + i]
      if #content > 0 then table.insert(cmds, { "D", start_row, start_col, content }) end
      table.insert(cmds, { "D", start_row, start_col, "\n" })
    end
    local last_line = old_lines[rel_row + old_end_row + 1]
    local last_end_col = byte_to_char_col(last_line, old_end_col_b)
    local last = string.sub(last_line, 1, last_end_col)
    if #last > 0 then table.insert(cmds, { "D", start_row, start_col, last }) end
  end

  if new_end_row == 0 and new_end_col_b > 0 then
    local end_col = byte_to_char_col(new_buf[start_row + 1], start_col_b + new_end_col_b)
    local inserted = string.sub(new_buf[start_row + 1], start_col + 1, end_col)
    table.insert(cmds, { "I", start_row, start_col, inserted })
  elseif new_end_row > 0 then
    local first = string.sub(new_buf[start_row + 1], start_col + 1)
    if #first > 0 then table.insert(cmds, { "I", start_row, start_col, first }) end
    table.insert(cmds, { "I", start_row, start_col + #first, "\n" })
    for i = 2, new_end_row do
      local content = new_buf[start_row + i]
      if #content > 0 then table.insert(cmds, { "I", start_row + i - 1, 0, content }) end
      table.insert(cmds, { "I", start_row + i - 1, #content, "\n" })
    end
    local last_new_line = new_buf[start_row + new_end_row + 1]
    local last_end_col = byte_to_char_col(last_new_line, new_end_col_b)
    local last_text = string.sub(last_new_line, 1, last_end_col)
    if #last_text > 0 then table.insert(cmds, { "I", start_row + new_end_row, 0, last_text }) end
  end

  return cmds
end

local function suffix_match(old_line, new_line, prefix)
  local suffix = 0
  local max_suffix = math.min(#old_line - prefix, #new_line - prefix)
  while suffix < max_suffix and
    string.sub(old_line, #old_line - suffix) == string.sub(new_line, #new_line - suffix) do
    suffix = suffix + 1
  end
  return suffix
end

local function common_prefix_suffix(old_line, new_line)
  local prefix = 0
  local max_prefix = math.min(#old_line, #new_line)
  while prefix < max_prefix and string.byte(old_line, prefix + 1) == string.byte(new_line, prefix + 1) do
    prefix = prefix + 1
  end
  local suffix = suffix_match(old_line, new_line, prefix)
  return prefix, suffix
end

function M.detect_edits(old_lines, new_lines, start_line, cursor_line, cursor_col)
  if #old_lines == #new_lines then
    local same = true
    for i = 1, #old_lines do
      if old_lines[i] ~= new_lines[i] then same = false; break end
    end
    if same then return {} end

    local cmds = {}
    for i = 1, #old_lines do
      if old_lines[i] ~= new_lines[i] then
        local old_line = old_lines[i]
        local new_line = new_lines[i]
        local prefix, suffix = common_prefix_suffix(old_line, new_line)

        if i - 1 == cursor_line - start_line then
          local del_len = #old_line - prefix - suffix
          local ins_len = #new_line - prefix - suffix
          local max_prefix = nil
          if ins_len > del_len then
            max_prefix = cursor_col - (ins_len - del_len)
          elseif del_len > ins_len then
            max_prefix = cursor_col
          end
          if max_prefix and prefix > max_prefix then
            prefix = math.max(0, max_prefix)
            suffix = suffix_match(old_line, new_line, prefix)
          end
        end

        local abs_line = start_line + i - 1
        local deleted = suffix > 0 and string.sub(old_line, prefix + 1, #old_line - suffix) or string.sub(old_line, prefix + 1)
        local inserted = suffix > 0 and string.sub(new_line, prefix + 1, #new_line - suffix) or string.sub(new_line, prefix + 1)
        if #deleted > 0 then table.insert(cmds, { "D", abs_line, prefix, deleted }) end
        if #inserted > 0 then table.insert(cmds, { "I", abs_line, prefix, inserted }) end
      end
    end
    return cmds
  end

  local n_old = #old_lines
  local n_new = #new_lines
  local cursor_rel = cursor_line - start_line

  local top = 0
  while top < math.min(n_old, n_new) and old_lines[top + 1] == new_lines[top + 1] and top < cursor_rel do
    top = top + 1
  end

  local bot_old = n_old
  local bot_new = n_new
  while bot_old > top and bot_new > top and old_lines[bot_old] == new_lines[bot_new] and (bot_new - 1) > cursor_rel do
    bot_old = bot_old - 1
    bot_new = bot_new - 1
  end

  local rem_old = {}
  for i = top + 1, bot_old do table.insert(rem_old, old_lines[i]) end
  local rem_new = {}
  for i = top + 1, bot_new do table.insert(rem_new, new_lines[i]) end
  local base_line = start_line + top

  if n_old > n_new then
    if #rem_new == 0 and #rem_old > 0 then
      local cmds = {}
      for _, line_content in ipairs(rem_old) do
        table.insert(cmds, { "D", base_line, 0, line_content })
        table.insert(cmds, { "D", base_line, 0, "\n" })
      end
      return cmds
    end

    if #rem_new == 1 and #rem_old >= 1 then
      local cmds = {}
      local first_old = rem_old[1]
      local last_old = rem_old[#rem_old]

      local p = 0
      local max_p = math.min(#first_old, #rem_new[1])
      while p < max_p and string.sub(first_old, p + 1, p + 1) == string.sub(rem_new[1], p + 1, p + 1) do
        p = p + 1
      end

      local s = 0
      local max_s = math.min(#last_old, #rem_new[1] - p)
      while s < max_s and
        string.sub(last_old, #last_old - s) == string.sub(rem_new[1], #rem_new[1] - s) do
        s = s + 1
      end

      local kept_prefix = string.sub(first_old, 1, p)
      local kept_suffix = s > 0 and string.sub(last_old, #last_old - s + 1) or ""
      local middle_new = s > 0 and string.sub(rem_new[1], p + 1, #rem_new[1] - s) or string.sub(rem_new[1], p + 1)

      if kept_prefix .. middle_new .. kept_suffix == rem_new[1] and #middle_new == 0 then
        local deleted_from_first = string.sub(first_old, p + 1)
        if #deleted_from_first > 0 then table.insert(cmds, { "D", base_line, p, deleted_from_first }) end
        table.insert(cmds, { "D", base_line, p, "\n" })
        for i = 2, #rem_old - 1 do
          if #rem_old[i] > 0 then table.insert(cmds, { "D", base_line, p, rem_old[i] }) end
          table.insert(cmds, { "D", base_line, p, "\n" })
        end
        local deleted_from_last = s > 0 and string.sub(last_old, 1, #last_old - s) or last_old
        if #deleted_from_last > 0 then table.insert(cmds, { "D", base_line, p, deleted_from_last }) end
        return cmds
      end
    end

    return nil
  end

  if n_new > n_old then
    local added = n_new - n_old

    if #rem_old == 1 and #rem_new == added + 1 then
      local old_line = rem_old[1]

      if added == 1 then
        if rem_new[1] .. rem_new[2] == old_line then
          local split_col = #rem_new[1]
          return { { "I", base_line, split_col, "\n" } }
        end

        local p = 0
        local max_p = math.min(#old_line, #rem_new[1])
        while p < max_p and string.sub(old_line, p + 1, p + 1) == string.sub(rem_new[1], p + 1, p + 1) do
          p = p + 1
        end

        local s = 0
        local max_s = math.min(#old_line - p, #rem_new[2])
        while s < max_s and
          string.sub(old_line, #old_line - s) == string.sub(rem_new[2], #rem_new[2] - s) do
          s = s + 1
        end

        local cmds = {}
        local deleted_tail = s > 0 and string.sub(old_line, p + 1, #old_line - s) or string.sub(old_line, p + 1)
        local new_second_part = s > 0 and string.sub(rem_new[2], 1, #rem_new[2] - s) or rem_new[2]

        if #deleted_tail > 0 then table.insert(cmds, { "D", base_line, p, deleted_tail }) end
        local extra_on_first = string.sub(rem_new[1], p + 1)
        if #extra_on_first > 0 then table.insert(cmds, { "I", base_line, p, extra_on_first }) end
        table.insert(cmds, { "I", base_line, #rem_new[1], "\n" })
        if #new_second_part > 0 then table.insert(cmds, { "I", base_line + 1, 0, new_second_part }) end
        return cmds
      end

      if #old_line > 0 then
        local p = 0
        local max_p = math.min(#old_line, #rem_new[1])
        while p < max_p and string.sub(old_line, p + 1, p + 1) == string.sub(rem_new[1], p + 1, p + 1) do
          p = p + 1
        end
        local s = 0
        local max_s = math.min(#old_line - p, #rem_new[#rem_new])
        while s < max_s and
          string.sub(old_line, #old_line - s) == string.sub(rem_new[#rem_new], #rem_new[#rem_new] - s) do
          s = s + 1
        end
        local cmds = {}
        local deleted_mid = s > 0 and string.sub(old_line, p + 1, #old_line - s) or string.sub(old_line, p + 1)
        if #deleted_mid > 0 then table.insert(cmds, { "D", base_line, p, deleted_mid }) end
        local extra_on_first = string.sub(rem_new[1], p + 1)
        if #extra_on_first > 0 then table.insert(cmds, { "I", base_line, p, extra_on_first }) end
        table.insert(cmds, { "I", base_line, #rem_new[1], "\n" })
        for i = 2, #rem_new - 1 do
          if #rem_new[i] > 0 then table.insert(cmds, { "I", base_line + i - 1, 0, rem_new[i] }) end
          table.insert(cmds, { "I", base_line + i - 1, #rem_new[i], "\n" })
        end
        local last_prefix = s > 0 and string.sub(rem_new[#rem_new], 1, #rem_new[#rem_new] - s) or rem_new[#rem_new]
        if #last_prefix > 0 then table.insert(cmds, { "I", base_line + #rem_new - 1, 0, last_prefix }) end
        return cmds
      end
    end

    return nil
  end

  return nil
end

local function listener_to_edits(event, old_lines, new_buf, snippet_start, cursor_line, cursor_col)
  local lnum = event.lnum
  local end_line = event["end"]
  local added = event.added
  local col_b = event.col or 1

  local start_0 = lnum - 1
  local old_count = end_line - lnum
  local new_count = old_count + added

  local rel_start = start_0 - snippet_start
  if rel_start < 0 or rel_start + old_count > #old_lines then return nil end
  if start_0 + new_count > #new_buf then return nil end

  if old_count == 1 and new_count == 1 and col_b > 1 then
    local old_line = old_lines[rel_start + 1]
    local new_line = new_buf[start_0 + 1]
    local prefix = byte_to_char_col(old_line, col_b - 1)
    local suffix = suffix_match(old_line, new_line, prefix)
    local deleted = suffix > 0 and string.sub(old_line, prefix + 1, #old_line - suffix) or string.sub(old_line, prefix + 1)
    local inserted = suffix > 0 and string.sub(new_line, prefix + 1, #new_line - suffix) or string.sub(new_line, prefix + 1)
    local cmds = {}
    if #deleted > 0 then table.insert(cmds, { "D", start_0, prefix, deleted }) end
    if #inserted > 0 then table.insert(cmds, { "I", start_0, prefix, inserted }) end
    return cmds
  end

  local old_region = {}
  for i = rel_start + 1, rel_start + old_count do table.insert(old_region, old_lines[i]) end
  local new_region = {}
  for i = start_0 + 1, start_0 + new_count do table.insert(new_region, new_buf[i]) end
  return M.detect_edits(old_region, new_region, start_0, cursor_line, cursor_col)
end

local ChangeProvider = {}
ChangeProvider.__index = ChangeProvider

function ChangeProvider:suppressed(body)
  self:suppress()
  local ok, err = pcall(body)
  self:reset()
  self:unsuppress()
  if not ok then error(err) end
end

local NvimChangeProvider = {}
setmetatable(NvimChangeProvider, { __index = ChangeProvider })
NvimChangeProvider.__index = NvimChangeProvider

function NvimChangeProvider:new()
  return setmetatable({}, self)
end

function NvimChangeProvider:attach(bufnr)
  vim.cmd(string.format("lua require('snippets.on_bytes').attach(%d)", bufnr))
end

function NvimChangeProvider:detach()
  vim.cmd("lua require('snippets.on_bytes').detach()")
end

function NvimChangeProvider:suppress()
  vim.cmd("lua require('snippets.on_bytes').suppress()")
end

function NvimChangeProvider:unsuppress()
  vim.cmd("lua require('snippets.on_bytes').unsuppress()")
end

function NvimChangeProvider:reset()
  vim.cmd("lua require('snippets.on_bytes').reset()")
end

function NvimChangeProvider:consume_edits(buf, snippet, vstate)
  local raw = vim.g._snippets_nvim_changes
  vim.cmd("lua require('snippets.on_bytes').reset()")
  if not raw or #raw == 0 then return nil end

  local old_lines = vstate:remembered_buffer()
  local snippet_start = snippet._start.line

  if #raw == 1 then
    local event = raw[1]
    local es = M.on_bytes_to_edits(event, old_lines, buf, snippet_start)
    if es ~= nil then return es end
  end

  local new_end = snippet._end.line + (#buf - vstate:remembered_buffer_length())
  local new_lines = {}
  for i = snippet_start + 1, new_end + 1 do
    table.insert(new_lines, buf[i])
  end

  local pos = vstate:pos()
  local es = M.detect_edits(old_lines, new_lines, snippet_start, pos.line, pos.col)
  if es ~= nil then return es end
  if is_pathological_diff_input(old_lines, new_lines) then return M.DROP_SNIPPET end
  return M.diff(table.concat(old_lines, "\n"), table.concat(new_lines, "\n"), snippet_start)
end

local VimChangeProvider = {}
setmetatable(VimChangeProvider, { __index = ChangeProvider })
VimChangeProvider.__index = VimChangeProvider

function VimChangeProvider:new()
  return setmetatable({}, self)
end

function VimChangeProvider:attach(bufnr)
  vim.cmd(string.format("call Snippets#listener#Attach(%d)", bufnr))
end

function VimChangeProvider:detach()
  vim.cmd("call Snippets#listener#Detach()")
end

function VimChangeProvider:suppress()
  vim.g._snippets_listener_suppressed = 1
end

function VimChangeProvider:unsuppress()
  vim.g._snippets_listener_suppressed = 0
end

function VimChangeProvider:reset()
  vim.cmd("call Snippets#listener#Flush()")
  vim.g._snippets_listener_changes = {}
end

function VimChangeProvider:consume_edits(buf, snippet, vstate)
  vim.cmd("call Snippets#listener#Flush()")
  local raw = vim.g._snippets_listener_changes
  vim.g._snippets_listener_changes = {}
  if not raw or #raw == 0 then return nil end

  local old_lines = vstate:remembered_buffer()
  local snippet_start = snippet._start.line
  local pos = vstate:pos()

  if #raw == 1 then
    local es = listener_to_edits(raw[1], old_lines, buf, snippet_start, pos.line, pos.col)
    if es ~= nil then return es end
  end

  local new_end = snippet._end.line + (#buf - vstate:remembered_buffer_length())
  local new_lines = {}
  for i = snippet_start + 1, new_end + 1 do
    table.insert(new_lines, buf[i])
  end

  local es = M.detect_edits(old_lines, new_lines, snippet_start, pos.line, pos.col)
  if es ~= nil then return es end
  if is_pathological_diff_input(old_lines, new_lines) then return M.DROP_SNIPPET end
  return M.diff(table.concat(old_lines, "\n"), table.concat(new_lines, "\n"), snippet_start)
end

M.ChangeProvider = ChangeProvider
M.NvimChangeProvider = NvimChangeProvider
M.VimChangeProvider = VimChangeProvider

return M
