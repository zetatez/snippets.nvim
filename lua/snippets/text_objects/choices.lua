local TabStop = require("snippets.text_objects.tabstop")
local Position = require("snippets.position")

local Choices = setmetatable({}, { __index = TabStop })
Choices.__index = Choices

function Choices:new(parent, token)
  local obj = TabStop.new(self, parent, token.number, token.start, token.end_pos)
  obj._number = token.number
  obj._initial_text = token.initial_text
  obj._choice_list = {}
  for _, s in ipairs(token.choice_list or {}) do
    if #s > 0 then table.insert(obj._choice_list, s) end
  end
  obj._done = false
  obj._input_chars = {}
  for ch in obj._initial_text:gmatch(".") do table.insert(obj._input_chars, ch) end
  obj._has_been_updated = false
  return obj
end

function Choices:_get_choices_placeholder()
  local segs = {}
  for i, choice in ipairs(self._choice_list) do
    table.insert(segs, string.format("%d.%s", i, choice))
  end
  return table.concat(segs, "|")
end

function Choices:_update(done, buf)
  if self._done then return true end
  if not self._has_been_updated then
    if #self._choice_list > 0 then
      self:overwrite(buf, self:_get_choices_placeholder())
    else
      self._done = true
    end
    self._has_been_updated = true
  end
  return true
end

function Choices:_do_edit(cmd, ctab)
  if self._done then
    TabStop._do_edit(self, cmd, ctab)
    return
  end

  local ctype, line, col, cmd_text = cmd[1], cmd[2], cmd[3], cmd[4]
  local cursor = vim.fn.getpos(".")

  if ctype == "I" then
    table.insert(self._input_chars, cmd_text)
  elseif ctype == "D" then
    local line_text = vim.api.nvim_buf_get_lines(0, line, line + 1, false)[1] or ""
    self._input_chars = {}
    for ch in line_text:sub(self._start.col + 1, col):gmatch(".") do
      table.insert(self._input_chars, ch)
    end
  end

  if #self._input_chars == 0 then return end

  local inputted_text = table.concat(self._input_chars)
  local is_all_digits = true
  local has_terminator = false
  local inputted_for_num = inputted_text

  for i, ch in ipairs(self._input_chars) do
    if ch == " " then
      has_terminator = true
      local chars = {}
      for j = 1, i - 1 do table.insert(chars, self._input_chars[j]) end
      inputted_for_num = table.concat(chars)
    elseif not ch:match("%d") then
      is_all_digits = false
    end
  end

  local should_continue = false
  local remained_choices = {}

  if is_all_digits or has_terminator then
    local index_strs = {}
    for i = 1, #self._choice_list do table.insert(index_strs, tostring(i)) end

    local matched = {}
    for _, s in ipairs(index_strs) do
      if s:find("^" .. inputted_for_num) then table.insert(matched, s) end
    end

    if #matched == 0 then
      remained_choices = {}
    elseif has_terminator then
      if #inputted_for_num > 0 then
        local num = tonumber(inputted_for_num)
        remained_choices = { self._choice_list[num] }
      end
    elseif #matched == 1 then
      local num = tonumber(inputted_for_num)
      remained_choices = { self._choice_list[num] }
    else
      should_continue = true
    end
  end

  if should_continue then return end

  local overwrite_text
  if #remained_choices == 0 then
    overwrite_text = inputted_for_num
    self._done = true
  elseif #remained_choices == 1 then
    overwrite_text = remained_choices[1]
    self._done = true
  end

  if overwrite_text then
    local old_end_col = self._end.col
    local displayed_end_col = self._start.col + #inputted_text
    self._end.col = displayed_end_col
    self:overwrite(vim.api.nvim_buf_get_lines, overwrite_text)

    local pos = Position:new(line, old_end_col)
    local diff_col = displayed_end_col - old_end_col
    local self_idx
    for i, child in ipairs(self._parent._children) do
      if child == self then self_idx = i; break end
    end
    self._parent:_child_has_moved(
      self_idx or 0,
      pos, Position:new(0, diff_col)
    )

    vim.fn.setpos(".", { cursor[1], cursor[2], self._end.col + 1, cursor[4] })
  end
end

return Choices
