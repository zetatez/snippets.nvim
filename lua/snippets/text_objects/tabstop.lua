local ETO = require("snippets.text_object").EditableTextObject

local TabStop = setmetatable({}, { __index = ETO })
TabStop.__index = TabStop
TabStop.__lt = require("snippets.text_object").TextObject.__lt
TabStop.__le = require("snippets.text_object").TextObject.__le

function TabStop:new(parent, token_or_number, start_pos, end_pos)
  local obj
  if start_pos then
    obj = ETO.new(self, parent, start_pos, end_pos)
    obj._number = token_or_number
  else
    obj = ETO.new(self, parent, token_or_number.start, token_or_number.end_pos,
                  token_or_number.initial_text)
    obj._number = token_or_number.number
  end
  parent._tabstops[obj._number] = obj
  return obj
end

function TabStop:number()
  return self._number
end

function TabStop:is_killed()
  return self._parent == nil
end

function TabStop:__tostring()
  local ok, text = pcall(function() return self:current_text() end)
  if not ok then text = "<err>" end
  return string.format("TabStop(%d,%s->%s,%s)", self._number,
    tostring(self._start), tostring(self._end), text)
end

return TabStop
