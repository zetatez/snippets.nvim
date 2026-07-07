local Position = {}
Position.__index = Position

function Position:new(line, col)
  return setmetatable({ line = line or 0, col = col or 0 }, self)
end

function Position:move(pivot, delta)
  if self < pivot then return end
  if delta.line == 0 then
    if self.line == pivot.line then
      self.col = self.col + delta.col
    end
  elseif delta.line > 0 then
    if self.line == pivot.line then
      self.col = self.col + delta.col - pivot.col
    end
    self.line = self.line + delta.line
  else
    self.line = self.line + delta.line
    if self.line == pivot.line then
      self.col = self.col + (-delta.col) + pivot.col
    end
  end
end

function Position:delta(other)
  if self.line == other.line then
    return Position:new(0, self.col - other.col)
  end
  if self > other then
    return Position:new(self.line - other.line, self.col)
  end
  return Position:new(self.line - other.line, other.col)
end

function Position:copy()
  return Position:new(self.line, self.col)
end

function Position:__add(other)
  return Position:new(self.line + other.line, self.col + other.col)
end

function Position:__sub(other)
  return Position:new(self.line - other.line, self.col - other.col)
end

function Position:__eq(other)
  return self.line == other.line and self.col == other.col
end

function Position:__lt(other)
  if self.line ~= other.line then return self.line < other.line end
  return self.col < other.col
end

function Position:__le(other)
  if self.line ~= other.line then return self.line < other.line end
  return self.col <= other.col
end

function Position:__tostring()
  return string.format("(%d,%d)", self.line, self.col)
end

return Position
