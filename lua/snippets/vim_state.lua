local Position = require("snippets.position")

local M = {}

local function byte_to_char_col(line, byte_col)
  if byte_col == 0 then return 0 end
  if byte_col >= #line then return vim.fn.strchars(line) end
  local s = string.sub(line, 1, byte_col)
  return vim.fn.strchars(s)
end

local VimPosition = {}
setmetatable(VimPosition, { __index = Position })
VimPosition.__index = VimPosition

function VimPosition:new()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local pos = Position:new(cursor[1] - 1, cursor[2])
  setmetatable(pos, self)
  pos._mode = vim.fn.mode()
  return pos
end

function VimPosition:mode()
  return self._mode
end

local VimState = {}
VimState.__index = VimState

local PRESERVED_REGISTERS = { "-", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", '"' }

function VimState:new()
  return setmetatable({
    _poss = {},
    _lvb = nil,
    _lvb_len = 0,
    _text_to_expect = "",
  }, self)
end

function VimState:remember_unnamed_register(text_to_expect)
  local escaped = self._text_to_expect:gsub("'", "''")
  local res = vim.fn.eval('@" != ' .. "'" .. escaped .. "'")
  if res == 1 then
    for _, reg in ipairs(PRESERVED_REGISTERS) do
      vim.cmd(string.format("let g:_snippets_reg_cache['%s'] = getreginfo('%s')", reg, reg))
    end
  end
  self._text_to_expect = text_to_expect
end

function VimState:restore_unnamed_register()
  if vim.fn.eval("empty(g:_snippets_reg_cache)") == 1 then return end
  for _, reg in ipairs(PRESERVED_REGISTERS) do
    vim.cmd(string.format(
      "if has_key(g:_snippets_reg_cache, '%s') | call setreg('%s', g:_snippets_reg_cache['%s']) | endif",
      reg, reg, reg
    ))
  end
end

function VimState:reset_register_cache()
  vim.g._snippets_reg_cache = {}
  self._text_to_expect = ""
end

function VimState:remember_position()
  table.insert(self._poss, VimPosition:new())
  if #self._poss > 5 then table.remove(self._poss, 1) end
end

function VimState:remember_buffer(to)
  local lines = vim.api.nvim_buf_get_lines(0, to._start.line, to._end.line + 1, false)
  -- Normalize: ensure we have at least one line
  if #lines == 0 then lines = { "" } end
  self._lvb = lines
  self._lvb_len = #vim.api.nvim_buf_get_lines(0, 0, -1, false)
  self:remember_position()
end

function VimState:pos()
  if #self._poss == 0 then return Position:new(0, 0) end
  return self._poss[#self._poss]
end

function VimState:ppos()
  if #self._poss < 2 then return Position:new(0, 0) end
  return self._poss[#self._poss - 1]
end

function VimState:remembered_buffer()
  if not self._lvb then return {} end
  local copy = {}
  for _, v in ipairs(self._lvb) do table.insert(copy, v) end
  return copy
end

function VimState:remembered_buffer_length()
  return self._lvb_len
end

local Placeholder = {}
Placeholder.__index = Placeholder

function Placeholder:new(current_text, start, end_pos)
  return setmetatable({
    current_text = current_text,
    start = start,
    ["end"] = end_pos,
  }, self)
end

local VisualContentPreserver = {}
VisualContentPreserver.__index = VisualContentPreserver

function VisualContentPreserver:new()
  return setmetatable({
    _mode = "",
    _text = "",
    _placeholder = nil,
  }, self)
end

function VisualContentPreserver:reset()
  self._mode = ""
  self._text = ""
  self._placeholder = nil
end

function VisualContentPreserver:conserve()
  local sl = tonumber(vim.fn.eval([[line("'<")]]))
  local sbyte = tonumber(vim.fn.eval([[col("'<")]]))
  local el = tonumber(vim.fn.eval([[line("'>")]]))
  local ebyte = tonumber(vim.fn.eval([[col("'>")]]))

  local sc = byte_to_char_col(vim.api.nvim_buf_get_lines(0, sl - 1, sl, false)[1] or "", sbyte - 1)
  local ec = byte_to_char_col(vim.api.nvim_buf_get_lines(0, el - 1, el, false)[1] or "", ebyte - 1)

  self._mode = vim.fn.eval("visualmode()")

  if vim.fn.eval("&selection") == "exclusive" and not (sl == el and sbyte == ebyte) then
    ec = ec - 1
  end

  local lines = vim.api.nvim_buf_get_lines(0, sl - 1, el, false)
  -- lines[1] is 1-based line sl; map a 1-based line number to its text.
  local function line_with_eol(ln)
    local l = lines[ln - sl + 1] or ""
    return l .. "\n"
  end

  local text
  if sl == el then
    text = string.sub(line_with_eol(sl), sc + 1, ec + 1)
  else
    text = string.sub(line_with_eol(sl), sc + 1)
    for cl = sl + 1, el - 1 do
      text = text .. line_with_eol(cl)
    end
    text = text .. string.sub(line_with_eol(el), 1, ec + 1)
  end
  self._text = text
end

function VisualContentPreserver:conserve_placeholder(placeholder)
  if placeholder then
    self._placeholder = Placeholder:new(
      placeholder.current_text,
      placeholder.start,
      placeholder["end"]
    )
  else
    self._placeholder = nil
  end
end

function VisualContentPreserver:text()
  return self._text
end

function VisualContentPreserver:mode()
  return self._mode
end

function VisualContentPreserver:placeholder()
  return self._placeholder
end

M.VimPosition = VimPosition
M.VimState = VimState
M.VisualContentPreserver = VisualContentPreserver
M.Placeholder = Placeholder

return M
