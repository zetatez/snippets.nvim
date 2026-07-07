local Position = require("snippets.position")

local TextObject = {}
TextObject.__index = TextObject

function TextObject:new(parent, start_pos, end_pos, initial_text, tiebreaker)
  local obj = {}
  obj._parent = parent
  obj._start = start_pos:copy()
  obj._end = end_pos:copy()
  obj._initial_text = initial_text or ""
  obj._tiebreaker = tiebreaker or Position:new(start_pos.line, end_pos.line)
  obj._origin = Position:new(start_pos.line, start_pos.col)
  local mt = self
  setmetatable(obj, mt)
  if parent then
    parent:_add_child(obj)
  end
  return obj
end

function TextObject:_move(pivot, diff)
  self._start:move(pivot, diff)
  self._end:move(pivot, diff)
end

function TextObject:_sort_key()
  return self._start.line, self._start.col,
         self._tiebreaker.line, self._tiebreaker.col,
         self._origin.line, self._origin.col
end

function TextObject:__lt(other)
  local a_line, a_col, a_tl, a_tc, a_ol, a_oc = self:_sort_key()
  local b_line, b_col, b_tl, b_tc, b_ol, b_oc = other:_sort_key()
  if a_line ~= b_line then return a_line < b_line end
  if a_col ~= b_col then return a_col < b_col end
  if a_tl ~= b_tl then return a_tl < b_tl end
  if a_tc ~= b_tc then return a_tc < b_tc end
  if a_ol ~= b_ol then return a_ol < b_ol end
  return a_oc < b_oc
end

function TextObject:__le(other)
  return self < other or (self._start == other._start and self._end == other._end)
end

function TextObject:current_text()
  local buf = vim.api.nvim_buf_get_lines(0, self._start.line, self._end.line + 1, false)
  if self._start.line == self._end.line then
    local line = buf[1] or ""
    return line:sub(self._start.col + 1, self._end.col)
  end
  local parts = {}
  local first = buf[1] or ""
  table.insert(parts, first:sub(self._start.col + 1))
  for i = 2, #buf - 1 do
    table.insert(parts, buf[i])
  end
  local last = buf[#buf] or ""
  table.insert(parts, last:sub(1, self._end.col))
  return table.concat(parts, "\n")
end

function TextObject:overwrite_with_initial_text(buf)
  self:overwrite(buf, self._initial_text)
end

local function _replace_text(buf, start, end_pos, text)
  local lines = {}
  for s in text:gmatch("([^\n]*)\n?") do
    table.insert(lines, s)
  end
  if text == "" then lines = {""} end
  if #lines == 0 then lines = {""} end

  -- Remove trailing empty line artifact from gmatch when text ends with \n
  if #lines > 1 and lines[#lines] == "" then
    table.remove(lines)
  end

  local new_end
  if #lines == 1 then
    new_end = Position:new(start.line, start.col + #lines[1])
  else
    new_end = Position:new(start.line + #lines - 1, #lines[#lines])
  end

  local buflines = vim.api.nvim_buf_get_lines(0, start.line, end_pos.line + 1, false)
  local before = buflines[1]:sub(1, start.col)
  local last_idx = math.min(#buflines, end_pos.line - start.line + 1)
  local after = buflines[last_idx]:sub(end_pos.col + 1)

  local new_lines = {}
  table.insert(new_lines, before .. lines[1])
  for i = 2, #lines do
    table.insert(new_lines, lines[i])
  end
  new_lines[#new_lines] = new_lines[#new_lines] .. after

  vim.api.nvim_buf_set_lines(0, start.line, end_pos.line + 1, false, new_lines)
  return new_end
end

TextObject._replace_text = _replace_text

function TextObject:overwrite(buf, gtext)
  if self:current_text() == gtext then return end
  local old_end = self._end:copy()
  self._end = _replace_text(buf, self._start, self._end, gtext)
  if self._children then
    for _, child in ipairs(self._children) do
      if child._tiebreaker and child._tiebreaker == Position:new(-1, -1) then
        child._start = self._end:copy()
        child._end = self._end:copy()
      end
    end
  end
  if self._parent then
    for i, child in ipairs(self._parent._children) do
      if child == self then
        local min_end = old_end < self._end and old_end or self._end
        self._parent:_child_has_moved(i, min_end, self._end:delta(old_end))
        break
      end
    end
  end
end

function TextObject:_update(done, buf)
  error("Must be implemented by subclass")
end

local EditableTextObject = setmetatable({}, { __index = TextObject })
EditableTextObject.__index = EditableTextObject
EditableTextObject.__lt = TextObject.__lt
EditableTextObject.__le = TextObject.__le

function EditableTextObject:new(...)
  local obj = TextObject:new(...)
  obj._children = {}
  obj._tabstops = {}
  return setmetatable(obj, self)
end

function EditableTextObject:children()
  return self._children
end

function EditableTextObject:_editable_children()
  local result = {}
  for _, child in ipairs(self._children) do
    if rawget(child, "_tabstops") ~= nil then
      table.insert(result, child)
    end
  end
  return result
end

function EditableTextObject:find_parent_for_new_to(pos)
  for _, child in ipairs(self:_editable_children()) do
    if child._start <= pos and pos < child._end then
      return child:find_parent_for_new_to(pos)
    end
    if child._start == pos and pos == child._end then
      return child:find_parent_for_new_to(pos)
    end
  end
  return self
end

function EditableTextObject:_do_edit(cmd, ctab)
  local ctype, line, col, text = cmd[1], cmd[2], cmd[3], cmd[4]
  if text == nil then return end
  local pos = Position:new(line, col)

  local to_kill = {}
  local new_cmds = {}

  for _, child in ipairs(self._children) do
    if ctype == "I" then
      if child._start < pos and pos < Position:new(child._end.line, child._end.col)
         and rawget(child, "_tabstops") == nil then
        table.insert(to_kill, child)
        table.insert(new_cmds, cmd)
        break
      end
      if child._start <= pos and pos <= child._end
         and rawget(child, "_tabstops") ~= nil then
        if pos == child._end and #(child._children or {}) == 0 then
          if ctab and child._number and ctab._number ~= child._number then
            goto continue_child
          end
        end
        child:_do_edit(cmd, ctab)
        return
      end
      ::continue_child::
    else
      local delend
      if text ~= "\n" then
        delend = pos + Position:new(0, #text)
      else
        delend = Position:new(line + 1, 0)
      end
      if (child._start <= pos and pos < child._end) and
         (child._start < delend and delend <= child._end) then
        if rawget(child, "_tabstops") == nil then
          table.insert(to_kill, child)
          table.insert(new_cmds, cmd)
          break
        end
        child:_do_edit(cmd, ctab)
        return
      end
      if (pos < child._start and child._end <= delend and child._start < delend) or
         (pos <= child._start and child._end < delend) then
        table.insert(to_kill, child)
        table.insert(new_cmds, cmd)
        break
      end
      if pos < child._start and (child._start < delend and delend <= child._end) then
        local my_text = text:sub(1, (child._start - pos).col)
        local c_text = text:sub((child._start - pos).col + 1)
        table.insert(new_cmds, { ctype, line, col, my_text })
        table.insert(new_cmds, { ctype, line, col, c_text })
        break
      end
      if delend >= child._end and (child._start <= pos and pos < child._end) then
        local c_text = text:sub((child._end - pos).col + 1)
        local my_text = text:sub(1, (child._end - pos).col)
        table.insert(new_cmds, { ctype, line, col, c_text })
        table.insert(new_cmds, { ctype, line, col, my_text })
        break
      end
    end
  end

  for _, child in ipairs(to_kill) do
    self:_del_child(child)
  end
  if #new_cmds > 0 then
    for _, ncmd in ipairs(new_cmds) do
      self:_do_edit(ncmd)
    end
    return
  end

  local delta
  if text == "\n" then
    delta = Position:new(1, 0)
  else
    delta = Position:new(0, #text)
  end
  if ctype == "D" then
    if self._start == self._end then return end
    delta.line = -delta.line
    delta.col = -delta.col
  end
  local pivot = Position:new(line, col)

  local idx = -1
  for cidx, child in ipairs(self._children) do
    if child._start < pivot and pivot <= child._end then
      idx = cidx
      break
    end
  end

  if ctype == "I" and idx == -1 and self._parent == nil and pivot >= self._end then
    return
  end

  self:_child_has_moved(idx, pivot, delta)
end

function EditableTextObject:_move(pivot, diff)
  TextObject._move(self, pivot, diff)
  for _, child in ipairs(self._children) do
    child:_move(pivot, diff)
  end
end

function EditableTextObject:_child_has_moved(idx, pivot, diff)
  self._end:move(pivot, diff)
  for i = math.max(idx + 1, 1), #self._children do
    self._children[i]:_move(pivot, diff)
  end
  if self._parent then
    for i, child in ipairs(self._parent._children) do
      if child == self then
        self._parent:_child_has_moved(i, pivot, diff)
        break
      end
    end
  end
end

function EditableTextObject:_get_next_tab(number)
  local tno_max = -1
  for k, _ in pairs(self._tabstops) do
    if k > tno_max then tno_max = k end
  end
  if tno_max == -1 then return nil end

  local possible_sol = {}
  for i = number + 1, tno_max do
    if self._tabstops[i] then
      table.insert(possible_sol, { i, self._tabstops[i] })
      break
    end
  end

  for _, child in ipairs(self:_editable_children()) do
    local r = child:_get_next_tab(number)
    if r then
      table.insert(possible_sol, r)
    end
  end

  if #possible_sol == 0 then return nil end
  table.sort(possible_sol, function(a, b) return a[1] < b[1] end)
  return possible_sol[1]
end

function EditableTextObject:_get_prev_tab(number)
  local tno_min = math.huge
  for k, _ in pairs(self._tabstops) do
    if k < tno_min then tno_min = k end
  end
  if tno_min == math.huge then return nil end

  local possible_sol = {}
  for i = number - 1, math.max(1, tno_min), -1 do
    if self._tabstops[i] then
      table.insert(possible_sol, { i, self._tabstops[i] })
      break
    end
  end

  for _, child in ipairs(self:_editable_children()) do
    local r = child:_get_prev_tab(number)
    if r then
      table.insert(possible_sol, r)
    end
  end

  if #possible_sol == 0 then return nil end
  table.sort(possible_sol, function(a, b) return a[1] > b[1] end)
  return possible_sol[1]
end

function EditableTextObject:_get_tabstop(requester, number)
  if self._tabstops[number] then
    return self._tabstops[number]
  end
  for _, child in ipairs(self:_editable_children()) do
    if child ~= requester then
      local rv = child:_get_tabstop(self, number)
      if rv then return rv end
    end
  end
  if self._parent and requester ~= self._parent then
    return self._parent:_get_tabstop(self, number)
  end
  return nil
end

function EditableTextObject:_update(done, buf)
  for _, child in ipairs(self._children) do
    if not done[child] then return true end
  end
  done[self] = true
  return true
end

function EditableTextObject:_add_child(child)
  table.insert(self._children, child)
  table.sort(self._children, function(a, b)
    local a_line, a_col, a_tl, a_tc, a_ol, a_oc = a:_sort_key()
    local b_line, b_col, b_tl, b_tc, b_ol, b_oc = b:_sort_key()
    if a_line ~= b_line then return a_line < b_line end
    if a_col ~= b_col then return a_col < b_col end
    if a_tl ~= b_tl then return a_tl < b_tl end
    if a_tc ~= b_tc then return a_tc < b_tc end
    if a_ol ~= b_ol then return a_ol < b_ol end
    return a_oc < b_oc
  end)
end

function EditableTextObject:_del_child(child)
  child._parent = nil
  for i, c in ipairs(self._children) do
    if c == child then
      table.remove(self._children, i)
      break
    end
  end
  if child._number then
    self._tabstops[child._number] = nil
  end
end

local NoneditableTextObject = setmetatable({}, { __index = TextObject })
NoneditableTextObject.__index = NoneditableTextObject
NoneditableTextObject.__lt = TextObject.__lt
NoneditableTextObject.__le = TextObject.__le

function NoneditableTextObject:new(...)
  local obj = TextObject:new(...)
  return setmetatable(obj, self)
end

function NoneditableTextObject:_update(done, buf)
  return true
end

return {
  TextObject = TextObject,
  EditableTextObject = EditableTextObject,
  NoneditableTextObject = NoneditableTextObject,
  _replace_text = _replace_text,
}
