local Mirror = require("snippets.text_objects.mirror")
local regex = require("snippets.regex")

local _find_closing_brace
local _split_conditional
local _replace_conditional
local _CleverReplace
local TextObjectTransformation

_find_closing_brace = function(string, start_pos)
  local bracks_open = 1
  local escaped = false
  for idx = start_pos, #string do
    local char = string:sub(idx, idx)
    if char == "(" then
      if not escaped then bracks_open = bracks_open + 1 end
    elseif char == ")" then
      if not escaped then bracks_open = bracks_open - 1 end
      if bracks_open == 0 then return idx + 1 end
    end
    escaped = (char == "\\") and not escaped or false
  end
end

_split_conditional = function(string)
  local bracks_open = 0
  local args = {}
  local carg = ""
  local escaped = false
  for idx = 1, #string do
    local char = string:sub(idx, idx)
    if char == "(" then
      if not escaped then bracks_open = bracks_open + 1 end
    elseif char == ")" then
      if not escaped then bracks_open = bracks_open - 1 end
    elseif char == ":" and bracks_open == 0 and not escaped then
      table.insert(args, carg)
      carg = ""
      escaped = false
      goto continue
    end
    carg = carg .. char
    ::continue::
    escaped = (char == "\\") and not escaped or false
  end
  table.insert(args, carg)
  return args
end

_replace_conditional = function(match_subject, string)
  local _CONDITIONAL_PATTERN = "%?%((%d+)%):"
  while true do
    local s, e, group_num = string:find(_CONDITIONAL_PATTERN)
    if not s then break end
    local start = s
    local end_pos = _find_closing_brace(string, start + 4)
    local condition_text = string:sub(start + 4, end_pos - 2)
    local args = _split_conditional(condition_text)
    local rv = ""
    if tonumber(group_num) and match_subject[tonumber(group_num)] then
      local txt = args[1]
      rv = _replace_conditional(match_subject, txt)
    elseif #args > 1 then
      local txt = args[2]
      rv = _replace_conditional(match_subject, txt)
    end
    string = string:sub(1, start - 1) .. rv .. string:sub(end_pos)
  end
  return string
end

_CleverReplace = {}
_CleverReplace.__index = _CleverReplace

function _CleverReplace:new(expression)
  return setmetatable({ _expression = expression }, self)
end

function _CleverReplace:replace(match_subject)
  local expr = self._expression
  local BSLASH = "\1"
  -- Pass 1: protect literal backslashes, expand $N group references
  local out = {}
  local i, n = 1, #expr
  while i <= n do
    local ch = expr:sub(i, i)
    if ch == "\\" and expr:sub(i + 1, i + 1) == "\\" then
      out[#out + 1] = BSLASH
      i = i + 2
    elseif ch == "$" then
      local num = expr:match("^(%d+)", i + 1)
      if num then
        local g = match_subject[tonumber(num)]
        out[#out + 1] = (g and g:gsub("\\", BSLASH)) or ""
        i = i + #num + 1
      else
        out[#out + 1] = "$"
        i = i + 1
      end
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  local transformed = table.concat(out)
  -- Pass 2: apply case switches, whitespace escapes and remaining \x
  out = {}
  i, n = 1, #transformed
  local function case_region(upper)
    local m = transformed:find(BSLASH .. "E", i + 2, true)
    local region
    if m then
      region = transformed:sub(i + 2, m - 1)
      i = m + 2
    else
      region = transformed:sub(i + 2)
      i = n + 1
    end
    return upper and region:upper() or region:lower()
  end
  while i <= n do
    local ch = transformed:sub(i, i)
    if ch == "\\" then
      local nxt = transformed:sub(i + 1, i + 1)
      if nxt == "u" or nxt == "l" then
        local c = transformed:sub(i + 2, i + 2)
        if c ~= "" then
          out[#out + 1] = (nxt == "u") and c:upper() or c:lower()
          i = i + 3
        else
          i = i + 2
        end
      elseif nxt == "U" or nxt == "L" then
        out[#out + 1] = case_region(nxt == "U")
      elseif nxt == "n" then out[#out + 1] = "\n"; i = i + 2
      elseif nxt == "t" then out[#out + 1] = "\t"; i = i + 2
      elseif nxt == "r" then out[#out + 1] = "\r"; i = i + 2
      else
        out[#out + 1] = (nxt ~= "") and nxt or "\\"
        i = i + 2
      end
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  transformed = table.concat(out)
  transformed = _replace_conditional(match_subject, transformed)
  transformed = transformed:gsub(BSLASH, "\\")
  return transformed
end

TextObjectTransformation = {}
TextObjectTransformation.__index = TextObjectTransformation

function TextObjectTransformation:new(token)
  local obj = {}
  obj._convert_to_ascii = false
  obj._find = nil
  obj._match_this_many = 1

  if token.search then
    local flags = ""
    if token.options then
      if token.options:find("g") then obj._match_this_many = 0 end
      if token.options:find("i") then flags = flags .. "i" end
      if token.options:find("m") then flags = flags .. "m" end
      if token.options:find("a") then obj._convert_to_ascii = true end
    end
    obj._find = { pattern = regex.compile(token.search, { dotall = true }), flags = flags }
    obj._replace = _CleverReplace:new(token.replace)
  end
  return setmetatable(obj, self)
end

function TextObjectTransformation:_transform(text)
  if self._convert_to_ascii then
    pcall(function()
      text = vim.fn.substitute(text, ".", "\\=iconv(submatch(0), 'utf-8', 'ascii//TRANSLIT')", "g")
    end)
  end
  if not self._find then return text end
  if not self._replace then return text end
  local r = self._replace
  local flags = self._find.flags .. (self._match_this_many == 0 and "g" or "")
  local ok, result = pcall(vim.fn.substitute, text, self._find.pattern,
    function()
      local match = {}
      for i = 0, 9 do match[i] = vim.fn.submatch(i) end
      return r:replace(match)
    end,
    flags
  )
  if not ok then
    -- Unsupported/ill-formed regex: degrade to the raw text instead of
    -- crashing the whole snippet.
    vim.notify("Snippets transformation error: " .. tostring(result), vim.log.levels.WARN)
    return text
  end
  return result
end

local Transformation = setmetatable({}, { __index = Mirror })
Transformation.__index = Transformation

function Transformation:new(parent, ts, token)
  local obj = Mirror.new(self, parent, ts, token)
  local trans = TextObjectTransformation:new(token)
  obj._convert_to_ascii = trans._convert_to_ascii
  obj._find = trans._find
  obj._replace = trans._replace
  obj._match_this_many = trans._match_this_many
  return obj
end

function Transformation:_get_text()
  return self:_transform(self._ts:current_text())
end

function Transformation:_transform(text)
  if self._find then
    local r = self._replace
    local flags = self._find.flags .. (self._match_this_many == 0 and "g" or "")
    local ok, result = pcall(vim.fn.substitute, text, self._find.pattern,
      function()
        local match = {}
        for i = 0, 9 do
          match[i] = vim.fn.submatch(i)
        end
        return r:replace(match)
      end,
      flags
    )
    if not ok then
      vim.notify("Snippets transformation error: " .. tostring(result), vim.log.levels.WARN)
      return text
    end
    return result
  end
  return text
end

Transformation.TextObjectTransformation = TextObjectTransformation

return Transformation
