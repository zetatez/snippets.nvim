local NTO = require("snippets.text_object").NoneditableTextObject

local EscapedChar = setmetatable({}, { __index = NTO })
EscapedChar.__index = EscapedChar

function EscapedChar:new(parent, token)
  return NTO.new(self, parent, token.start, token.end_pos, token.initial_text)
end

return EscapedChar
