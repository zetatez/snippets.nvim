local NTO = require("snippets.text_object").NoneditableTextObject

local Mirror = setmetatable({}, { __index = NTO })
Mirror.__index = Mirror

function Mirror:new(parent, tabstop, token)
  local obj = NTO.new(self, parent, token.start, token.end_pos, token.initial_text)
  obj._ts = tabstop
  return obj
end

function Mirror:_update(done, buf)
  if self._ts:is_killed() then
    self:overwrite(buf, "")
    self._parent:_del_child(self)
    return true
  end
  if not done[self._ts] then return false end
  self:overwrite(buf, self:_get_text())
  return true
end

function Mirror:_get_text()
  return self._ts:current_text()
end

return Mirror
