local NTO = require("snippets.text_object").NoneditableTextObject

local ShellCode = setmetatable({}, { __index = NTO })
ShellCode.__index = ShellCode

function ShellCode:new(parent, token)
  local obj = NTO.new(self, parent, token.start, token.end_pos, token.initial_text)
  obj._code = token.code:gsub("\\`", "`")
  return obj
end

function ShellCode:_update(done, buf)
  local handle = io.popen(self._code, "r")
  local output = ""
  if handle then
    output = handle:read("*a")
    handle:close()
    if output:sub(-1) == "\n" then output = output:sub(1, -2) end
    if output:sub(-1) == "\r" then output = output:sub(1, -2) end
  end
  self:overwrite(buf, output)
  self._parent:_del_child(self)
  return true
end

return ShellCode
