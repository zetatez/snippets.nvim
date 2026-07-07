local parser = require("snippets.parser")
local SnippetInstance = require("snippets.text_objects.snippet_instance")
local Position = require("snippets.position")
local regex = require("snippets.regex")

local SnippetDefinition = {}
SnippetDefinition.__index = SnippetDefinition

-- Mirror of UltiSnips IndentUtil.ntabs_to_proper_indent(): leading tabs in a
-- snippet body become shiftwidth-spaces, converted back to hard tabs when
-- 'expandtab' is off (indent_to_spaces + spaces_to_indent round trip).
local function ntabs_to_proper_indent(ntabs)
  local line_ind = string.rep(" ", ntabs * vim.fn.shiftwidth())
  if not vim.o.expandtab then
    local ts = vim.o.tabstop
    if ts > 0 then
      line_ind = line_ind:gsub(string.rep(" ", ts), "\t")
    end
  end
  return line_ind
end

function SnippetDefinition:new(priority, trigger, value, description, options, globals, location, context, actions)
  local obj = {
    _priority = tonumber(priority) or 0,
    _trigger = trigger,
    _value = value,
    _description = description or "",
    _opts = options or "",
    _matched = "",
    _last_re = nil,
    _globals = globals or {},
    _compiled_globals = nil,
    _location = location or "",
    _context_code = context,
    _context = nil,
    _actions = actions or {},
  }
  setmetatable(obj, self)
  obj:matches(obj._trigger)
  return obj
end

function SnippetDefinition:_words_for_line(trigger, before, num_words)
  if not num_words then
    if not trigger:find("%s") then
      num_words = 1
    else
      num_words = 0
      for _ in trigger:gmatch("%S+") do num_words = num_words + 1 end
    end
  end
  if num_words == 1 and not before:find("%s") then
    -- Hot path (single word trigger, single word before): identical to
    -- UltiSnips' `before.strip()` without two vim.split calls (~1.4us).
    return before or ""
  end
  local word_list = vim.split(before, "%s+")
  if #word_list <= num_words then
    return vim.trim(before or "")
  end
  local before_words = before
  for i = 1, num_words do
    local w = word_list[#word_list - i + 1]
    local left = before_words:sub(1, before_words:len() - w:len())
    left = left:gsub("%s+$", "")
    before_words = left
  end
  return before:sub(#before_words + 1):match("^%s*(.-)%s*$") or ""
end

function SnippetDefinition:has_option(opt)
  return self._opts:find(opt) ~= nil
end

-- Suffix-anchored regex match mirroring UltiSnips _re_match():
-- Python does re.finditer(pattern, before) and accepts the first match with
-- match.end() == len(before). Vim's matchend() only reports the FIRST match
-- from position 0, so e.g. trigger `a` in before `aaa` (mend=1 ~= 3) would
-- wrongly fail. Slide the start forward and take the leftmost suffix whose
-- match reaches its end. Returns matchlist or nil.
local function _suffix_regex_match(before, vim_pat)
  local n = #before
  -- A leading ^ anchors at the original string start; only offset 0 is valid
  -- (vim_pat is "\v" .. user_pattern, so user ^ sits at index 3).
  local anchored = vim_pat:sub(3, 3) == "^"
  for s = 0, n do
    local sub = before:sub(s + 1)
    local ok_mend, mend = pcall(vim.fn.matchend, sub, vim_pat)
    if ok_mend and type(mend) == "number" and mend ~= -1 and mend == #sub then
      local ok_ml, ml = pcall(vim.fn.matchlist, sub, vim_pat)
      if ok_ml and type(ml) == "table" and ml[1] ~= "" then
        return ml
      end
    end
    if anchored then break end
  end
  return nil
end

function SnippetDefinition:description()
  return ("(%s) %s"):format(self._trigger, self._description):gsub("%s+$", "")
end

function SnippetDefinition:priority()
  return self._priority
end

function SnippetDefinition:trigger()
  return self._trigger
end

function SnippetDefinition:matched()
  return self._matched
end

function SnippetDefinition:location()
  return self._location
end

function SnippetDefinition:context()
  return self._context
end

function SnippetDefinition:matches(before, visual_content)
  self._matched = ""
  self._last_re = nil
  local words = self:_words_for_line(self._trigger, before)

  local match = false
  if self:has_option("r") then
    -- regex trigger: suffix-anchored like UltiSnips _re_match(); capture
    -- groups stored for $N / match. Vim matchlist returns [whole, g1..g9]
    -- padded with "" for unused groups. Prefix "\v" (very magic) so
    -- Python-style "()" groups behave as capture groups.
    local vim_pat = regex.compile(self._trigger)
    local ml = _suffix_regex_match(before, vim_pat)
    if ml then
      local groups = {}
      for i = 2, #ml do
        groups[i - 1] = ml[i]
      end
      -- drop trailing "" padding produced by unused group slots
      while #groups > 0 and groups[#groups] == "" do
        table.remove(groups)
      end
      -- Named groups (?P<name>...) for match.groupdict(); Vim itself has
      -- no named groups, so map trigger order -> captured order.
      local group_names = {}
      for nm in self._trigger:gmatch("%(%?P<([^>]+)>") do
        group_names[#group_names + 1] = nm
      end
      self._last_re = { group0 = ml[1], groups = groups, group_names = group_names }
      self._matched = ml[1]
      match = true
    end
  elseif self:has_option("p") then
    -- Partial prefix: trigger starts with typed text
    match = self._trigger:find("^" .. vim.pesc(words)) == 1 and words ~= ""
    self._matched = words
  elseif self:has_option("w") then
    local words_len = #self._trigger
    local words_suffix = words:sub(-words_len)
    match = words_suffix == self._trigger
    if match and #before > #self._trigger then
      -- Word boundary: the char immediately before the trigger must not be a
      -- keyword char (respects 'iskeyword').
      local prev = before:sub(-#self._trigger - 1, -#self._trigger - 1)
      if prev ~= "" and vim.fn.matchstr(prev, "\\k") ~= "" then
        match = false
      end
    end
  elseif self:has_option("i") then
    match = words:sub(-#self._trigger) == self._trigger
  else
    match = words == self._trigger
  end

  if match and self._matched == "" then
    self._matched = self._trigger
  end

  if self:has_option("b") and match then
    local text_before = before:gsub("%s+$", "")
    text_before = text_before:sub(1, -#self._matched - 1)
    if text_before and text_before:match("%S") then
      self._matched = ""
      return false
    end
  end

  self._context = nil
  if match and self._context_code then
    local ctx_match = self:_context_match(visual_content, before)
    if not ctx_match then match = false end
  end

  return match
end

function SnippetDefinition:_context_match(visual_content, before)
  -- UltiSnips parity: context code is PYTHON (`snip.context = <code>`)
  -- evaluated with the documented locals; Python truthiness decides.
  -- (Previously VimL eval; no in-tree snippets use context, see docs.)
  local context_code = self._context_code
  if not context_code then return true end
  -- Skip on empty buffer, like UltiSnips _context_match.
  local buf = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if #buf == 1 and buf[1] == "" then
    self._context = nil
    return false
  end
  local bridge_ok, bridge = pcall(require, "snippets.text_objects.python_code")
  if not (bridge_ok and bridge.ensure_bridge and bridge.ensure_bridge()) then
    self._context = nil
    return false
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local vc = visual_content or {}
  local ph = vc.placeholder
  local context = {
    before = before,
    visual_mode = vc.mode or "",
    visual_text = vc.text or "",
    window = vim.api.nvim_get_current_win(),
    buffer = vim.api.nvim_get_current_buf(),
    line = cur[1] - 1,
    column = cur[2],
    cursor = { line = cur[1] - 1, col = cur[2] },
  }
  if ph then
    context.last_placeholder = {
      current_text = ph.current_text or "",
      start = { line = ph.start.line, col = ph.start.col },
      ["end"] = { line = ph["end"].line, col = ph["end"].col },
    }
  end
  if self._last_re then
    context.match = {
      group0 = self._last_re.group0 or "",
      groups = self._last_re.groups or {},
    }
  end
  local expr = "_run_ctx(" .. vim.inspect(context_code) .. ", "
    .. vim.inspect(vim.fn.json_encode(context)) .. ")"
  local ok, output = pcall(vim.fn.py3eval, expr)
  if not ok or type(output) ~= "string" then
    self._context = nil
    return false
  end
  local ok_decode, result = pcall(vim.fn.json_decode, output)
  if not ok_decode or type(result) ~= "table" then
    self._context = nil
    return false
  end
  if result.err ~= vim.NIL and result.err ~= nil and result.err ~= "" then
    vim.notify(
      ("Snippets context error [%s @ %s]:\n%s"):format(
        self._trigger, self._location, tostring(result.err)),
      vim.log.levels.ERROR)
    self._context = nil
    return false
  end
  local value = result.value
  if value == vim.NIL then value = nil end
  self._context = value
  return result.truthy == true
end

function SnippetDefinition:could_match(before)
  self._matched = ""

  before = before or ""
  -- Trailing whitespace means the user already left the word being typed:
  -- treat it as a fresh (empty) partial so only "new word" matches apply.
  before = before:gsub("%s+$", "")
  if before == "" then
    return true
  end

  local words = self:_words_for_line(self._trigger, before)
  if words == "" then return false end

  local match = false
  if self:has_option("r") then
    -- Same suffix-anchored test as matches(): UltiSnips could_match() also
    -- requires a full regex match reaching the cursor (no true partials).
    if _suffix_regex_match(before, regex.compile(self._trigger)) then
      match = true
    end
  elseif self:has_option("w") then
    -- The typed tail must be a prefix of the trigger starting at a word
    -- boundary (previous char is not a keyword char).
    for k = 1, #words do
      local suffix = words:sub(k)
      local at_start = (k == 1)
      local prev_ok = (k > 1) and (vim.fn.matchstr(words:sub(k - 1, k - 1), "\\k") == "")
      if self._trigger:find("^" .. vim.pesc(suffix)) == 1 and (at_start or prev_ok) then
        match = true
        self._matched = suffix
        break
      end
    end
  elseif self:has_option("i") then
    for i = 1, #words do
      local suffix = words:sub(i)
      if self._trigger:find("^" .. vim.pesc(suffix)) == 1 then
        match = true
        self._matched = suffix
        break
      end
    end
  else
    match = self._trigger:find("^" .. vim.pesc(words)) == 1 and #words > 0
    if match then self._matched = words end
  end

  if match and self._matched == "" then
    self._matched = words
  end

  if self:has_option("b") and match then
    local text_before = before:gsub("%s+$", "")
    text_before = text_before:sub(1, -#self._matched - 1)
    if text_before and text_before:match("%S") then
      self._matched = ""
      return false
    end
  end

  return match
end

-- Shared Python action runner (UltiSnips _execute_action parity, minus the
-- buffer proxy / expand_anon which require nested-expansion support).
-- Returns the decoded result table, or nil on bridge/error failure.
local function run_python_action(definition, action_name, ctx)
  local code = definition._actions and definition._actions[action_name]
  if not code then return nil end
  local bridge_ok, bridge = pcall(require, "snippets.text_objects.python_code")
  if not (bridge_ok and bridge.ensure_bridge and bridge.ensure_bridge()) then
    return nil
  end
  local expr = "_run_action(" .. vim.inspect(code) .. ", "
    .. vim.inspect(vim.fn.json_encode(ctx)) .. ")"
  local ok, output = pcall(vim.fn.py3eval, expr)
  if not ok or type(output) ~= "string" then return nil end
  local ok_decode, result = pcall(vim.fn.json_decode, output)
  if not ok_decode or type(result) ~= "table" then return nil end
  if result.err ~= vim.NIL and result.err ~= nil and result.err ~= "" then
    vim.notify(
      ("Snippets %s error [%s @ %s]:\n%s"):format(
        action_name, definition._trigger, definition._location,
        tostring(result.err)),
      vim.log.levels.ERROR)
    return nil
  end
  return result
end

function SnippetDefinition:do_pre_expand(visual_content, snippets_stack)
  -- Returns cursor position ({line, col} 0-based) when the action set
  -- snip.cursor, else nil. The manager moves Vim's cursor there and
  -- re-anchors (UltiSnips parity); clearing already-typed text remains
  -- the action's job (needs the buffer proxy, not yet implemented).
  if not self._actions.pre_expand then return nil end
  local vc = visual_content or {}
  local res = run_python_action(self, "pre_expand", {
    visual_mode = vc.mode or "",
    visual_text = vc.text or "",
    context = self._context,
  })
  if not res then return nil end
  self._context = (res.context ~= vim.NIL) and res.context or nil
  if res.cursor_set == true and type(res.cursor) == "table" then
    return { line = res.cursor[1] or 0, col = res.cursor[2] or 0 }
  end
  return nil
end

function SnippetDefinition:do_post_expand(start_pos, end_pos, snippets_stack)
  -- Returns cursor.is_set() (used once nested expansion lands).
  if not self._actions.post_expand then return false end
  local res = run_python_action(self, "post_expand", {
    snippet_start = { line = start_pos.line, col = start_pos.col },
    snippet_end = { line = end_pos.line, col = end_pos.col },
    context = self._context,
  })
  if not res then return false end
  self._context = (res.context ~= vim.NIL) and res.context or nil
  return res.cursor_set == true
end

function SnippetDefinition:do_post_finish(snippet_instance)
  if not self._actions.post_finish then return end
  run_python_action(self, "post_finish", {
    snippet_start = { line = snippet_instance._start.line, col = snippet_instance._start.col },
    snippet_end = { line = snippet_instance._end.line, col = snippet_instance._end.col },
    context = snippet_instance.context,
  })
end

function SnippetDefinition:do_post_jump(tabstop_number, jump_direction, snippets_stack, current_snippet)
  if not self._actions.post_jump then return end
  local vc = (current_snippet and current_snippet.visual_content) or {}
  local tabs = {}
  if current_snippet then
    local ok, list = pcall(function() return current_snippet:get_tabstops() end)
    if ok and type(list) == "table" then
      for no, ts in pairs(list) do
        tabs[tostring(no)] = {
          start = { line = ts._start.line, col = ts._start.col },
          ["end"] = { line = ts._end.line, col = ts._end.col },
          text = ts:current_text(),
        }
      end
    end
  end
  run_python_action(self, "post_jump", {
    tabstop = tabstop_number,
    jump_direction = jump_direction,
    tabstops = tabs,
    snippet_start = current_snippet and { line = current_snippet._start.line, col = current_snippet._start.col } or vim.NIL,
    snippet_end = current_snippet and { line = current_snippet._end.line, col = current_snippet._end.col } or vim.NIL,
    visual_mode = vc.mode or "",
    visual_text = vc.text or "",
    context = current_snippet and current_snippet.context or nil,
  })
end

function SnippetDefinition:launch(text_before, visual_content, parent, start_pos, end_pos)
  local indent_match = text_before:match("^[ \t]*") or ""
  local lines = {}
  for line in (self._value .. "\n"):gmatch("([^\n]*)\n?") do
    table.insert(lines, line)
  end

  local initial_text = {}
  for line_num, line in ipairs(lines) do
    local tabs = 0
    if not self:has_option("t") then
      tabs = line:match("^\t*"):len()
    end
    local line_ind = ntabs_to_proper_indent(tabs)
    if line_num ~= 1 then
      line_ind = indent_match .. line_ind
    end
    local result_line = line_ind .. line:sub(tabs + 1)
    if self:has_option("m") then
      result_line = result_line:gsub("%s+$", "")
    end
    table.insert(initial_text, result_line)
  end

  local text = table.concat(initial_text, "\n")
  text = text:gsub("\n$", "")

  local snippet_instance = SnippetInstance:new(
    self, parent, text,
    start_pos, end_pos,
    visual_content,
    self._last_re,
    self._globals,
    self._context,
    self._compiled_globals
  )

  self:instantiate(snippet_instance, text, indent_match)
  snippet_instance:replace_initial_text(vim.api.nvim_buf_get_lines)

  -- Convergence loop: run textobject updates until the snippet text stabilizes
  local last_text = nil
  for _ = 1, 10 do
    snippet_instance:update_textobjects(vim.api.nvim_buf_get_lines)
    local cur_text = snippet_instance:current_text()
    if last_text and cur_text == last_text then
      break
    end
    last_text = cur_text
  end

  return snippet_instance
end

function SnippetDefinition:instantiate(snippet_instance, initial_text, indent)
  parser.parse_snippets(snippet_instance, initial_text, indent)
end

local SnippetsSnippetDefinition = setmetatable({}, { __index = SnippetDefinition })
SnippetsSnippetDefinition.__index = SnippetsSnippetDefinition

function SnippetsSnippetDefinition:new(...)
  local obj = SnippetDefinition:new(...)
  setmetatable(obj, self)
  return obj
end

function SnippetsSnippetDefinition:instantiate(snippet_instance, initial_text, indent)
  parser.parse_snippets(snippet_instance, initial_text, indent)
end

local SnipMateSnippetDefinition = setmetatable({}, { __index = SnippetDefinition })
SnipMateSnippetDefinition.__index = SnipMateSnippetDefinition

SnipMateSnippetDefinition.SNIPMATE_PRIORITY = -1000

function SnipMateSnippetDefinition:new(trigger, value, description, location)
  local obj = SnippetDefinition:new(
    self.SNIPMATE_PRIORITY, trigger, value, description,
    "w", {}, location, nil, {}
  )
  setmetatable(obj, self)
  return obj
end

function SnipMateSnippetDefinition:instantiate(snippet_instance, initial_text, indent)
  parser.parse_snipmate(snippet_instance, initial_text, indent)
end

return {
  SnippetDefinition = SnippetDefinition,
  SnippetsSnippetDefinition = SnippetsSnippetDefinition,
  SnipMateSnippetDefinition = SnipMateSnippetDefinition,
}
