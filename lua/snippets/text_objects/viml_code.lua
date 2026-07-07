local NTO = require("snippets.text_object").NoneditableTextObject

local VimLCode = setmetatable({}, { __index = NTO })
VimLCode.__index = VimLCode

function VimLCode:new(parent, token)
  local obj = NTO.new(self, parent, token.start, token.end_pos, token.initial_text)
  obj._code = token.code:gsub("\\`", "`")
  return obj
end

function VimLCode:_update(done, buf)
  local ok, result = pcall(vim.fn.eval, self._code)
  if not ok then result = "" end
  self:overwrite(buf, tostring(result))
  return true
end

return VimLCode
