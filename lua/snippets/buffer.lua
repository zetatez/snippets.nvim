local Position = require("snippets.position")
local M = {}

function M.use_proxy_buffer(snippets_stack, vstate, change_provider, fn)
  local buffer_proxy = M.VimBufferProxy:new(snippets_stack, vstate)
  change_provider:suppress()
  local ok, err = pcall(fn, buffer_proxy)
  change_provider:unsuppress()
  if not ok then error(err) end
  buffer_proxy:validate_buffer()
end

function M.suspend_proxy_edits(buffer_proxy, fn)
  if not buffer_proxy or type(buffer_proxy) ~= "table" or not buffer_proxy._buffer then
    return fn()
  end
  buffer_proxy:_disable_edits()
  local ok, err = pcall(fn)
  buffer_proxy:_enable_edits()
  if not ok then error(err) end
end

local VimBufferProxy = {}
VimBufferProxy.__index = VimBufferProxy

function VimBufferProxy:new(snippets_stack, vstate)
  return setmetatable({
    _snippets_stack = snippets_stack,
    _buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    _change_tick = vim.b.changedtick,
    _forward_edits = true,
    _vstate = vstate,
  }, self)
end

function VimBufferProxy:is_buffer_changed_outside()
  return self._change_tick < vim.b.changedtick
end

function VimBufferProxy:validate_buffer()
  if self:is_buffer_changed_outside() then
    error("buffer was modified using vim.command or " ..
      "vim.current.buffer; that changes are untrackable and leads to " ..
      "errors in snippet expansion; use special variable `snip.buffer` " ..
      "for buffer modifications.\n\n" ..
      "See :help Snippets-buffer-proxy for more info.")
  end
end

function VimBufferProxy:set_lines(start, stop, value)
  value = value or {}
  local changes = {}
  for line_number = start, stop - 1 do
    table.insert(changes, { "D", line_number, 0, self._buffer[line_number + 1] })
  end
  for line_number = 1, #value do
    table.insert(changes, { "I", start + line_number - 1, 0, value[line_number] })
  end

  vim.api.nvim_buf_set_lines(0, start, stop, false, value)
  self._buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  self._change_tick = self._change_tick + 1

  if self._forward_edits then
    for _, change in ipairs(changes) do
      self:_apply_change(change)
    end
    if #self._snippets_stack > 0 then
      self._vstate:remember_buffer(self._snippets_stack[1])
    end
  end
end

function VimBufferProxy:set_line(line_number, value)
  local before = self._buffer[line_number + 1]
  local changes = {}
  if before == "" then
    for change in self:_get_changes_for_line(line_number, line_number + 1, { value }) do
      table.insert(changes, change)
    end
  else
    local diff_result = require("snippets.change").diff(before, value)
    for _, change in ipairs(diff_result) do
      table.insert(changes, { change[1], line_number, change[3], change[4] })
    end
  end

  vim.api.nvim_buf_set_lines(0, line_number, line_number + 1, false, { value })
  self._buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  self._change_tick = self._change_tick + 1

  if self._forward_edits then
    for _, change in ipairs(changes) do
      self:_apply_change(change)
    end
    if #self._snippets_stack > 0 then
      self._vstate:remember_buffer(self._snippets_stack[1])
    end
  end
end

function VimBufferProxy:get_line(line_number)
  return self._buffer[line_number + 1]
end

function VimBufferProxy:__len()
  return #self._buffer
end

function VimBufferProxy:append(line, line_number)
  if line_number == nil then line_number = #self._buffer end
  if type(line) ~= "table" then line = { line } end
  self:set_lines(line_number, line_number, line)
end

function VimBufferProxy:remove(key)
  if type(key) == "table" then
    self:set_lines(key[1], key[2], {})
  else
    self:set_lines(key, key + 1, {})
  end
end

function VimBufferProxy:_apply_change(change)
  if #self._snippets_stack == 0 then return end

  local change_type = change[1]
  local line_number = change[2]
  local column_number = change[3]
  local change_text = change[4]

  local snippet = self._snippets_stack[1]
  local pos = Position:new(line_number, column_number)
  if pos <= snippet._start then
    local direction = 1
    if change_type == "D" then direction = -1 end
    local diff = Position:new(direction, 0)
    if #change < 5 then
      diff = Position:new(0, direction * #change_text)
    end
    snippet:_move(pos, diff)
  elseif pos >= snippet._end then
    return
  else
    snippet:_do_edit({ change_type, line_number, column_number, change_text })
  end
end

function VimBufferProxy:_disable_edits()
  self._forward_edits = false
end

function VimBufferProxy:_enable_edits()
  self._forward_edits = true
end

M.VimBufferProxy = VimBufferProxy

return M
