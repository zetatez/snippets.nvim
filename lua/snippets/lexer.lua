local Position = require("snippets.position")

local TextIterator = {}
TextIterator.__index = TextIterator

function TextIterator:new(text, offset)
  return setmetatable({
    _text = text,
    _line = offset.line,
    _col = offset.col,
    _idx = 1,
  }, self)
end

function TextIterator:next()
  if self._idx > #self._text then return nil end
  local ch = self._text:sub(self._idx, self._idx)
  if ch == "\n" then
    self._line = self._line + 1
    self._col = 0
  else
    self._col = self._col + 1
  end
  self._idx = self._idx + 1
  return ch
end

function TextIterator:peek(count)
  count = count or 1
  if count > 1 then
    if self._idx + count - 1 > #self._text then return self._text:sub(self._idx) end
    return self._text:sub(self._idx, self._idx + count - 1)
  end
  if self._idx > #self._text then return nil end
  return self._text:sub(self._idx, self._idx)
end

function TextIterator:pos()
  return Position:new(self._line, self._col)
end

function _parse_number(stream)
  local rv = ""
  while stream:peek() and stream:peek():match("%d") do
    rv = rv .. stream:next()
  end
  return tonumber(rv)
end

function _parse_till_closing_brace(stream)
  local rv = ""
  local in_braces = 1
  while true do
    local cs = stream:peek(2)
    if cs and #cs == 2 and cs:sub(1,1) == "\\" and cs:sub(2,2):match("[{}]") then
      rv = rv .. stream:next() .. stream:next()
    else
      local char = stream:next()
      if char == "{" then
        in_braces = in_braces + 1
      elseif char == "}" then
        in_braces = in_braces - 1
      end
      if in_braces == 0 then break end
      rv = rv .. char
    end
  end
  return rv
end

function _parse_till_unescaped_char(stream, chars)
  local rv = ""
  while true do
    local escaped = false
    local cs = stream:peek(2)
    if cs and #cs == 2 and cs:sub(1,1) == "\\" and chars:find(cs:sub(2,2), 1, true) then
      rv = rv .. stream:next() .. stream:next()
      escaped = true
    end
    if not escaped then
      local char = stream:next()
      if not char then break end
      if chars:find(char, 1, true) then
        return rv, char
      end
      rv = rv .. char
    end
  end
  return rv, ""
end

local Token = {}
Token.__index = Token

function Token:new(stream, indent)
  local obj = { initial_text = "", start = stream:pos() }
  setmetatable(obj, self)
  obj:_parse(stream, indent)
  obj.end_pos = stream:pos()
  return obj
end

function Token:_parse(stream, indent) end

local TabStopToken = setmetatable({}, { __index = Token })
TabStopToken.__index = TabStopToken

function TabStopToken.starts_here(stream)
  local p = stream:peek(10)
  return p and p:match("^%${%d+:") ~= nil
end

function TabStopToken:_parse(stream, indent)
  stream:next() -- $
  stream:next() -- {
  self.number = _parse_number(stream)
  if stream:peek() == ":" then stream:next() end
  self.initial_text = _parse_till_closing_brace(stream)
end

local VisualToken = setmetatable({}, { __index = Token })
VisualToken.__index = VisualToken

function VisualToken.starts_here(stream)
  local p = stream:peek(10)
  return p and p:match("^%${VISUAL[:}/]") ~= nil
end

function VisualToken:_parse(stream, indent)
  for _ = 1, 8 do stream:next() end
  if stream:peek() == ":" then stream:next() end
  self.alternative_text, char = _parse_till_unescaped_char(stream, "/}")
  self.alternative_text = self.alternative_text:gsub("\\(.)", "%1")
  if char == "/" then
    self.search, _ = _parse_till_unescaped_char(stream, "/")
    self.replace, _ = _parse_till_unescaped_char(stream, "/")
    self.options = _parse_till_closing_brace(stream)
  else
    self.search = nil
    self.replace = nil
    self.options = nil
  end
end

local TransformationToken = setmetatable({}, { __index = Token })
TransformationToken.__index = TransformationToken

function TransformationToken.starts_here(stream)
  local p = stream:peek(10)
  return p and p:match("^%${%d+/") ~= nil
end

function TransformationToken:_parse(stream, indent)
  stream:next() -- $
  stream:next() -- {
  self.number = _parse_number(stream)
  stream:next() -- /
  self.search = _parse_till_unescaped_char(stream, "/")
  self.replace = _parse_till_unescaped_char(stream, "/")
  self.options = _parse_till_closing_brace(stream)
end

local MirrorToken = setmetatable({}, { __index = Token })
MirrorToken.__index = MirrorToken

function MirrorToken.starts_here(stream)
  local p = stream:peek(10)
  return p and (p:match("^%$%d+") ~= nil or p:match("^%${%d+}") ~= nil)
end

function MirrorToken:_parse(stream, indent)
  stream:next() -- $
  if stream:peek() == "{" then
    stream:next() -- {
    self.number = _parse_number(stream)
    stream:next() -- }
  else
    self.number = _parse_number(stream)
  end
end

local ChoicesToken = setmetatable({}, { __index = Token })
ChoicesToken.__index = ChoicesToken

function ChoicesToken.starts_here(stream)
  local p = stream:peek(10)
  return p and p:match("^%${%d+%|") ~= nil
end

function ChoicesToken:_parse(stream, indent)
  stream:next() -- $
  stream:next() -- {
  self.number = _parse_number(stream)
  if self.number == 0 then
    error("Choices selection is not supported on $0")
  end
  stream:next() -- |
  local choices_text = _parse_till_unescaped_char(stream, "|")
  self.choice_list = {}
  for item in choices_text:gmatch("([^,]+)") do
    local clean = item:gsub("%\\,", ",")
    if #clean > 0 then
      table.insert(self.choice_list, clean)
    end
  end
  self.initial_text = "|" .. table.concat(self.choice_list, ",") .. "|"
  _parse_till_closing_brace(stream)
end

local EscapeCharToken = setmetatable({}, { __index = Token })
EscapeCharToken.__index = EscapeCharToken

function EscapeCharToken.starts_here(stream, chars)
  chars = chars or "{}\\$`"
  local cs = stream:peek(2)
  if cs and #cs == 2 and cs:sub(1,1) == "\\" and chars:find(cs:sub(2,2)) then
    return true
  end
  return false
end

function EscapeCharToken:_parse(stream, indent)
  stream:next() -- \
  self.initial_text = stream:next()
end

local ShellCodeToken = setmetatable({}, { __index = Token })
ShellCodeToken.__index = ShellCodeToken

function ShellCodeToken.starts_here(stream)
  return stream:peek() == "`"
end

function ShellCodeToken:_parse(stream, indent)
  stream:next() -- `
  self.code = _parse_till_unescaped_char(stream, "`")
end

local PythonCodeToken = setmetatable({}, { __index = Token })
PythonCodeToken.__index = PythonCodeToken

function PythonCodeToken.starts_here(stream)
  local p = stream:peek(4)
  return p and p:match("^`!p%s") ~= nil
end

function PythonCodeToken:_parse(stream, indent)
  stream:next() stream:next() stream:next() -- `!p
  if stream:peek() == " " or stream:peek() == "\t" then stream:next() end
  local code = _parse_till_unescaped_char(stream, "`")
  if #indent > 0 then
    local lines = {}
    for line in code:gmatch("([^\n]*)\n?") do
      if #line > #indent then
        table.insert(lines, line:sub(#indent + 1))
      else
        table.insert(lines, line)
      end
    end
    self.code = table.concat(lines, "\n")
  else
    self.code = code
  end
  self.indent = indent
  self.initial_text = self.code
end

local VimLCodeToken = setmetatable({}, { __index = Token })
VimLCodeToken.__index = VimLCodeToken

function VimLCodeToken.starts_here(stream)
  local p = stream:peek(4)
  return p and p:match("^`!v%s") ~= nil
end

function VimLCodeToken:_parse(stream, indent)
  for _ = 1, 4 do stream:next() end
  self.code = _parse_till_unescaped_char(stream, "`")
end

local EndOfTextToken = setmetatable({}, { __index = Token })
EndOfTextToken.__index = EndOfTextToken

function EndOfTextToken:new(stream, indent)
  local obj = { start = stream:pos(), end_pos = stream:pos() }
  return setmetatable(obj, self)
end

function tokenize(text, indent, offset, allowed_tokens)
  local stream = TextIterator:new(text, offset)
  local tokens = {}
  while true do
    local done = false
    for _, token_cls in ipairs(allowed_tokens) do
      if token_cls.starts_here(stream) then
        local tok = token_cls:new(stream, indent)
        table.insert(tokens, tok)
        done = true
        break
      end
    end
    if not done then
      local ch = stream:next()
      if not ch then break end
    end
  end
  table.insert(tokens, EndOfTextToken:new(stream, indent))
  return tokens
end

return {
  TextIterator = TextIterator,
  TabStopToken = TabStopToken,
  VisualToken = VisualToken,
  TransformationToken = TransformationToken,
  MirrorToken = MirrorToken,
  ChoicesToken = ChoicesToken,
  EscapeCharToken = EscapeCharToken,
  ShellCodeToken = ShellCodeToken,
  PythonCodeToken = PythonCodeToken,
  VimLCodeToken = VimLCodeToken,
  EndOfTextToken = EndOfTextToken,
  tokenize = tokenize,
  _parse_number = _parse_number,
  _parse_till_closing_brace = _parse_till_closing_brace,
  _parse_till_unescaped_char = _parse_till_unescaped_char,
}
