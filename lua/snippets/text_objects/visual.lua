local NTO = require("snippets.text_object").NoneditableTextObject
local TransformationMod = require("snippets.text_objects.transformation")
local TextObjectTransformation = TransformationMod.TextObjectTransformation

local _REPLACE_NON_WS = "[^ \t]"

local Visual = setmetatable({}, { __index = NTO })
Visual.__index = Visual

function Visual:new(parent, token)
  local vtext, vmode
  local snippet = parent
  while snippet do
    if snippet.visual_content then
      vtext = snippet.visual_content.text
      vmode = snippet.visual_content.mode
      break
    end
    snippet = snippet._parent
  end
  if not vtext or vtext == "" then
    vtext = token.alternative_text or ""
    vmode = "v"
  end

  local obj = NTO.new(self, parent, token.start, token.end_pos, token.initial_text)
  obj._text = vtext
  obj._mode = vmode
  local trans = TextObjectTransformation:new(token)
  obj._convert_to_ascii = trans._convert_to_ascii
  obj._find = trans._find
  obj._replace = trans._replace
  obj._match_this_many = trans._match_this_many
  return obj
end

function Visual:_transform(text)
  if self._find then
    local r = self._replace
    local flags = self._find.flags .. (self._match_this_many == 0 and "g" or "")
    local result = vim.fn.substitute(text, self._find.pattern,
      function()
        local match = {}
        for i = 0, 9 do match[i] = vim.fn.submatch(i) end
        return r:replace(match)
      end,
      flags
    )
    return result
  end
  return text
end

function Visual:_update(done, buf)
  local text
  if self._mode == "v" then
    text = self._text
  else
    local text_before = vim.api.nvim_buf_get_lines(0, self._start.line, self._start.line + 1, false)[1] or ""
    local indent = text_before:sub(1, self._start.col):gsub(_REPLACE_NON_WS, " ")
    text = ""
    local dedented = self._text:gsub("^\n", ""):gsub("^([ \t]*)", "")
    for idx, line in ipairs(vim.split(dedented, "\n", true)) do
      if idx ~= 1 then text = text .. indent end
      text = text .. line .. "\n"
    end
    text = text:sub(1, -2)
  end

  text = self:_transform(text)

  if self:_snippet_has_m_option() then
    local lines = {}
    for line in text:gmatch("([^\n]*)\n?") do
      table.insert(lines, line:gsub("%s+$", ""))
    end
    text = table.concat(lines, "\n")
  end

  self:overwrite(buf, text)
  self._parent:_del_child(self)
  return true
end

function Visual:_snippet_has_m_option()
  local obj = self._parent
  while obj do
    if obj.snippet then
      return obj.snippet:has_option("m")
    end
    obj = obj._parent
  end
  return false
end

return Visual
