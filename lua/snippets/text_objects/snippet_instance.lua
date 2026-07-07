local ETO = require("snippets.text_object").EditableTextObject
local NTO = require("snippets.text_object").NoneditableTextObject
local TabStop = require("snippets.text_objects.tabstop")
local Position = require("snippets.position")

local SnippetInstance = setmetatable({}, { __index = ETO })
SnippetInstance.__index = SnippetInstance

function SnippetInstance:new(snippet, parent, initial_text, start_pos, end_pos, visual_content, last_re, globals, context, compiled_globals)
  start_pos = start_pos or Position:new(0, 0)
  end_pos = end_pos or Position:new(0, 0)
  local obj = ETO.new(self, parent, start_pos, end_pos, initial_text or "")
  obj.snippet = snippet
  obj._cts = 0
  obj.context = context
  obj.locals = { match = last_re, context = context }
  obj.globals = globals or {}
  obj._compiled_globals = compiled_globals
  obj.current_placeholder = nil
  if visual_content then
    obj.visual_content = { mode = visual_content.mode, text = visual_content.text }
  else
    obj.visual_content = { mode = "", text = "" }
  end
  return obj
end

function SnippetInstance:replace_initial_text(buf)
  local function _place_initial_text(obj)
    obj:overwrite_with_initial_text(buf)
    if obj._children then
      for _, child in ipairs(obj._children) do
        _place_initial_text(child)
      end
    end
  end
  _place_initial_text(self)
end

function SnippetInstance:replay_user_edits(cmds, ctab)
  for _, cmd in ipairs(cmds) do
    if cmd[4] ~= nil then
      self:_do_edit(cmd, ctab)
    end
  end
end

function SnippetInstance:update_textobjects(buf, ctab)
  local done = {}
  local not_done = {}

  local function _contains_ctab(obj)
    if not ctab then return false end
    local cur = ctab
    while cur do
      if cur == obj then return true end
      cur = cur._parent
    end
    return false
  end

  local function _find_recursive(obj)
    local cursorInsideLowest = nil
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_pos = Position:new(cursor[1] - 1, cursor[2])

    if obj._start <= cursor_pos and cursor_pos <= obj._end then
      local is_tabstop0 = false
      if obj._number and obj._number == 0 then is_tabstop0 = true end
      if not is_tabstop0 then
        cursorInsideLowest = obj
      end
    end

    local preferred = nil
    local fallback = cursorInsideLowest
    if obj._children then
      for _, child in ipairs(obj._children) do
        local child_match = _find_recursive(child)
        if child_match then
          if _contains_ctab(child) then
            preferred = child_match
          else
            fallback = child_match
          end
        end
      end
    end
    cursorInsideLowest = preferred or fallback
    not_done[obj] = true
    return cursorInsideLowest
  end

  local cursorInsideLowest = _find_recursive(self)

  local function _table_keys(t)
    local keys = {}
    for k, _ in pairs(t) do keys[#keys + 1] = k end
    return keys
  end

  local counter = 10
  while counter > 0 do
    local all_done = true
    for obj, _ in pairs(not_done) do
      if not done[obj] then all_done = false; break end
    end
    if all_done then break end

    -- UltiSnips parity: update in source order (start, tiebreaker, origin)
    -- so multi-mirror/transformation chains converge deterministically.
    -- NB: do NOT use `a < b` here: __lt is only assigned on the
    -- Editable/Noneditable base metatables, while instances carry subclass
    -- metatables where metamethod lookup misses it ("attempt to compare
    -- two table values"). Compare explicit sort keys instead.
    local keys = _table_keys(not_done)
    table.sort(keys, function(a, b)
      local al, ac, atl, atc, aol, aoc = a:_sort_key()
      local bl, bc, btl, btc, bol, boc = b:_sort_key()
      if al ~= bl then return al < bl end
      if ac ~= bc then return ac < bc end
      if atl ~= btl then return atl < btl end
      if atc ~= btc then return atc < btc end
      if aol ~= bol then return aol < bol end
      return aoc < boc
    end)
    for _, obj in ipairs(keys) do
      if not done[obj] then
        if obj:_update(done, buf) then
          done[obj] = true
        end
      end
    end
    counter = counter - 1
  end

  if counter == 0 then
    error("The snippets content did not converge: Check for Cyclic dependencies or random strings in your snippet.")
  end
end

function SnippetInstance:select_next_tab(jump_direction)
  if self._cts == nil then return nil end

  if jump_direction == "BACKWARD" then
    local current_backup = self._cts
    local res = self:_get_prev_tab(self._cts)
    if not res then
      self._cts = current_backup
      return self._tabstops[self._cts]
    end
    self._cts, ts = res[1], res[2]
    return ts
  end

  if jump_direction == "FORWARD" then
    local res = self:_get_next_tab(self._cts)
    if not res then
      self._cts = nil
      local ts = self:_get_tabstop(self, 0)
      if ts then return ts end
      local start_pos = Position:new(self._end.line, self._end.col)
      local end_pos = Position:new(self._end.line, self._end.col)
      return TabStop:new(self, 0, start_pos, end_pos)
    end
    self._cts, ts = res[1], res[2]
    return ts
  end

  error("Unknown JumpDirection: " .. tostring(jump_direction))
end

function SnippetInstance:has_next_tab(jump_direction)
  if jump_direction == "BACKWARD" then
    return self:_get_prev_tab(self._cts) ~= nil
  end
  return true
end

function SnippetInstance:_get_tabstop(requester, no)
  local cached_parent = self._parent
  self._parent = nil
  local rv = ETO._get_tabstop(self, requester, no)
  self._parent = cached_parent
  return rv
end

function SnippetInstance:get_tabstops()
  return self._tabstops
end

return SnippetInstance
