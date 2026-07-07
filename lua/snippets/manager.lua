local snippet_mod = require("snippets.snippet")
local source_mod = require("snippets.source")
local Position = require("snippets.position")
local change_mod = require("snippets.change")
local VimState = require("snippets.vim_state").VimState

local M = {}

local function open_folds_safely()
  -- `zv` opens folds created by the expansion. It must never run while in
  -- visual/select mode: there `:normal!` inserts its argument as text
  -- instead of executing it (observed live: "zv" typed over the tabstop,
  -- corrupting buffer + tree and killing all further jumps).
  local m = vim.api.nvim_get_mode().mode
  if m == "n" or m == "i" then
    vim.cmd("normal! zv")
  end
end

local function get_buf()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return lines
end

local function set_lines(start_line, end_line, lines)
  vim.api.nvim_buf_set_lines(0, start_line, end_line, false, lines)
end

local function get_line_till_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1] or ""
  return line:sub(1, cursor[2])
end

local function buf_cursor()
  local c = vim.api.nvim_win_get_cursor(0)
  return Position:new(c[1] - 1, c[2])
end

local function set_buf_cursor(pos)
  local buf_lines = vim.api.nvim_buf_line_count(0)
  if buf_lines == 0 then return end
  local line = pos.line + 1
  if line < 1 then line = 1 end
  if line > buf_lines then line = buf_lines end
  local col = pos.col
  if col < 0 then col = 0 end
  vim.api.nvim_win_set_cursor(0, { line, col })
end

-- Excursions into auxiliary windows (preview, quickfix/loclist, floats
-- such as completion documentation) must not kill the snippet: the user
-- is coming back (UltiSnips#IsAuxWindow parity).
local function _is_aux_window()
  local ok, cfg = pcall(vim.api.nvim_win_get_config, 0)
  if ok and type(cfg) == "table" and cfg.relative ~= "" then return true end
  local ok2, info = pcall(vim.fn.getwininfo, vim.api.nvim_get_current_win())
  if ok2 and type(info) == "table" and info[1] then
    if info[1].previewwindow == 1 or info[1].quickfix == 1 or info[1].loclist == 1 then
      return true
    end
  end
  return false
end

local function get_buffer_filetypes()  local ft = vim.bo.filetype or ""
  local fts = {}
  for s in ft:gmatch("[^.]+") do
    table.insert(fts, s)
  end
  table.insert(fts, "all")
  return fts
end

local function ask_user(items, formatted)
  if #items == 0 then return nil end
  local ok, rv = pcall(vim.fn.inputlist, formatted)
  if not ok or rv == nil or rv == 0 then return nil end
  rv = tonumber(rv)
  if not rv or rv < 1 or rv > #items then return nil end
  return items[rv]
end

local function ask_snippets(snippets)
  local display = {}
  for i, s in ipairs(snippets) do
    table.insert(display, string.format("%d: %s (%s)", i, s:description(), s:location()))
  end
  return ask_user(snippets, display)
end

local function show_warning(msg)
  vim.cmd("echohl WarningMsg")
  vim.cmd('echom "' .. msg:gsub('"', '\\"') .. '"')
  vim.cmd("echohl None")
end

local SnippetManager = {}
SnippetManager.__index = SnippetManager

function SnippetManager:new()
  local obj = {
    _active_snippets = {},
    _added_buffer_filetypes = {},
    _removed_buffer_filetypes = {},
    _autotrigger = vim.g.SnippetsAutoTrigger or 1,
    _last_change = { "", Position:new(-1, -1) },
    _inner_state_up = false,
    _snippet_buffer_number = nil,
    _snippet_sources = {},
    _ctab = nil,
    _ignore_movements = false,
    _last_typed_char = "",
    _should_update_textobjects = false,
    _should_reset_visual = false,
    _snip_expanded_in_action = false,
    _inside_action = false,
    _visual_content = { mode = "", text = "", placeholder = nil },
    _change_provider = nil,
    _vstate = nil,
    _last_failure_key = nil,
  }
  setmetatable(obj, self)

  obj._added_snippets_source = source_mod.AddedSnippetsSource:new()
  obj:register_source("snippets_files", source_mod.SnippetsFileSource:new())
  obj:register_source("added", obj._added_snippets_source)

  if vim.g.SnippetsEnableSnipMate ~= 0 then
    obj:register_source("snipmate_files", source_mod.SnipMateFileSource:new())
  end

  return obj
end

function SnippetManager:register_source(name, source)
  table.insert(self._snippet_sources, { name, source })
end

function SnippetManager:unregister_source(name)
  for i, pair in ipairs(self._snippet_sources) do
    if pair[1] == name then
      table.remove(self._snippet_sources, i)
      break
    end
  end
end

function SnippetManager:get_buffer_filetypes()
  local bufnr = vim.api.nvim_get_current_buf()
  local removed = self._removed_buffer_filetypes[bufnr] or {}
  local added = self._added_buffer_filetypes[bufnr] or {}
  local fts = {}
  for _, ft in ipairs(added) do table.insert(fts, ft) end
  for _, ft in ipairs(get_buffer_filetypes()) do table.insert(fts, ft) end
  local result = {}
  for _, ft in ipairs(fts) do
    if not removed[ft] then table.insert(result, ft) end
  end
  return result
end

function SnippetManager:add_buffer_filetypes(filetypes)
  local bufnr = vim.api.nvim_get_current_buf()
  if not self._added_buffer_filetypes[bufnr] then
    self._added_buffer_filetypes[bufnr] = {}
  end
  if not self._removed_buffer_filetypes[bufnr] then
    self._removed_buffer_filetypes[bufnr] = {}
  end
  local fts = self._added_buffer_filetypes[bufnr]
  local removed = self._removed_buffer_filetypes[bufnr]
  for raw in filetypes:gmatch("[^.]+") do
    local ft = raw:match("^%s*(.-)%s*$") or raw
    if ft ~= "" then
      removed[ft] = nil
      local found = false
      for _, v in ipairs(fts) do if v == ft then found = true; break end end
      if not found then table.insert(fts, ft) end
    end
  end
end

function SnippetManager:remove_buffer_filetypes(filetypes)
  local bufnr = vim.api.nvim_get_current_buf()
  if not self._added_buffer_filetypes[bufnr] then
    self._added_buffer_filetypes[bufnr] = {}
  end
  if not self._removed_buffer_filetypes[bufnr] then
    self._removed_buffer_filetypes[bufnr] = {}
  end
  local removed = self._removed_buffer_filetypes[bufnr]
  local fts = self._added_buffer_filetypes[bufnr]
  for raw in filetypes:gmatch("[^.]+") do
    local ft = raw:match("^%s*(.-)%s*$") or raw
    if ft ~= "" then
      removed[ft] = true
      for i, v in ipairs(fts) do
        if v == ft then table.remove(fts, i); break end
      end
    end
  end
end

function SnippetManager:expand()
  vim.g.snippets_expand_res = 1
  if not self:_try_expand() then
    vim.g.snippets_expand_res = 0
    self:_handle_failure(vim.g.SnippetsExpandTrigger or "<tab>", true)
  end
end

function SnippetManager:expand_or_jump()
  vim.g.snippets_expand_or_jump_res = 1
  local rv = self:_try_expand()
  if not rv then
    vim.g.snippets_expand_or_jump_res = 2
    rv = self:_jump("FORWARD")
  end
  if not rv then
    vim.g.snippets_expand_or_jump_res = 0
    self:_handle_failure(vim.g.SnippetsExpandTrigger or "<tab>", true)
  end
end

function SnippetManager:jump_or_expand()
  -- UltiSnips JumpOrExpandTrigger semantics: jump first, expand as fallback
  -- (the reverse of expand_or_jump).
  vim.g.snippets_jump_or_expand_res = 1
  local rv = self:_jump("FORWARD")
  if not rv then
    vim.g.snippets_jump_or_expand_res = 2
    rv = self:_try_expand()
  end
  if not rv then
    vim.g.snippets_jump_or_expand_res = 0
    self:_handle_failure(vim.g.SnippetsJumpOrExpandTrigger or vim.g.SnippetsJumpForwardTrigger or "<c-j>", true)
  end
end

function SnippetManager:jump_forwards()
  vim.g.snippets_jump_forwards_res = 1
  vim.cmd("let &g:undolevels = &g:undolevels")
  if not self:_jump("FORWARD") then
    vim.g.snippets_jump_forwards_res = 0
    self:_handle_failure(vim.g.SnippetsJumpForwardTrigger or "<c-j>")
  end
end

function SnippetManager:jump_backwards()
  vim.g.snippets_jump_backwards_res = 1
  vim.cmd("let &g:undolevels = &g:undolevels")
  if not self:_jump("BACKWARD") then
    vim.g.snippets_jump_backwards_res = 0
    self:_handle_failure(vim.g.SnippetsJumpBackwardTrigger or "<c-k>")
  end
end

function SnippetManager:_current_snippet()
  if #self._active_snippets == 0 then return nil end
  return self._active_snippets[#self._active_snippets]
end

function SnippetManager:_snips(before, partial, autotrigger_only)
  local filetypes = {}
  for _, ft in ipairs(self:get_buffer_filetypes()) do
    table.insert(filetypes, ft)
  end
  -- reverse
  local rev = {}
  for i = #filetypes, 1, -1 do table.insert(rev, filetypes[i]) end
  filetypes = rev

  for _, pair in ipairs(self._snippet_sources) do
    pair[2]:ensure(filetypes)
  end

  local clear_priority = nil
  local cleared = {}
  for _, pair in ipairs(self._snippet_sources) do
    local scp = pair[2]:get_clear_priority(filetypes)
    if scp and (not clear_priority or scp > clear_priority) then
      clear_priority = scp
    end
    for key, value in pairs(pair[2]:get_cleared(filetypes)) do
      if not cleared[key] or value > cleared[key] then
        cleared[key] = value
      end
    end
  end

  local matching = {}
  for _, pair in ipairs(self._snippet_sources) do
    local snips = pair[2]:get_snippets(filetypes, before, partial, autotrigger_only, self._visual_content)
    for _, s in ipairs(snips) do
      local ok = true
      if clear_priority and s:priority() <= clear_priority then ok = false end
      if cleared[s:trigger()] and s:priority() <= cleared[s:trigger()] then ok = false end
      if ok then
        if not matching[s:trigger()] then matching[s:trigger()] = {} end
        table.insert(matching[s:trigger()], s)
      end
    end
  end

  local snippets = {}
  for _, snips in pairs(matching) do
    local maxp = snips[1]:priority()
    for _, s in ipairs(snips) do
      if s:priority() > maxp then maxp = s:priority() end
    end
    for _, s in ipairs(snips) do
      if s:priority() == maxp then table.insert(snippets, s) end
    end
  end

  if partial then return snippets end

  if #snippets == 0 then return snippets end
  local maxp = snippets[1]:priority()
  for _, s in ipairs(snippets) do
    if s:priority() > maxp then maxp = s:priority() end
  end
  local result = {}
  for _, s in ipairs(snippets) do
    if s:priority() == maxp then table.insert(result, s) end
  end
  return result
end

function SnippetManager:_try_expand(autotrigger_only)
  if #self._active_snippets > 0 then
    self:_cursor_moved()
  end

  local before = get_line_till_cursor()
  local snippets = self:_snips(before, false, autotrigger_only)

  if #snippets == 0 then return false end

  local with_context = {}
  for _, s in ipairs(snippets) do
    -- NB: context is a method; `s.context` without call is always truthy.
    if s:context() then table.insert(with_context, s) end
  end
  if #with_context > 0 then snippets = with_context end

  vim.cmd("let &g:undolevels = &g:undolevels")

  local snippet
  if #snippets == 1 then
    snippet = snippets[1]
  else
    snippet = ask_snippets(snippets)
    if not snippet then return true end
  end

  self:_do_snippet(snippet, before)
  vim.cmd("let &g:undolevels = &g:undolevels")
  return true
end

function SnippetManager:_do_snippet(snippet, before)
  self:_setup_inner_state()
  self._snip_expanded_in_action = false
  self._should_update_textobjects = false

  local text_before = before
  if snippet:matched() ~= "" and snippet:matched() ~= snippet:trigger() then
    text_before = before:sub(1, -#snippet:matched() - 1)
  elseif snippet:matched() == snippet:trigger() then
    text_before = before:sub(1, -#snippet:matched() - 1)
  end

  -- Run pre_expand action; a set snip.cursor re-anchors the expansion
  -- (UltiSnips parity). Errors abort the expansion.
  local ok_pre, new_cursor = pcall(snippet.do_pre_expand, snippet, self._visual_content, self._active_snippets)
  if not ok_pre then
    vim.notify("Snippets pre_expand error: " .. tostring(new_cursor), vim.log.levels.ERROR)
    return
  end
  local cursor_pos
  if new_cursor then
    vim.api.nvim_win_set_cursor(0, { new_cursor.line + 1, new_cursor.col })
    before = get_line_till_cursor()
    text_before = before
  end
  cursor_pos = buf_cursor()
  local start_pos = Position:new(cursor_pos.line, #text_before)
  local end_pos = Position:new(cursor_pos.line, #before)

  local parent = nil
  if self:_current_snippet() then
    if not new_cursor then
      -- Handle trigger overlapping with parent text objects. Skipped when
      -- pre_expand moved the cursor (its position is authoritative).
      -- It could be that our trigger contains the content of
      -- TextObjects in our containing snippet. If this is indeed
      -- the case, we have to make sure that those are properly killed.
      local edit_actions = {
        { "D", start_pos.line, start_pos.col, snippet:matched() },
        { "I", start_pos.line, start_pos.col, snippet:matched() },
      }
      self._active_snippets[1]:replay_user_edits(edit_actions)
    end
    parent = self:_current_snippet():find_parent_for_new_to(start_pos)
  end

  local snippet_instance = snippet:launch(
    text_before, self._visual_content, parent, start_pos, end_pos
  )

  open_folds_safely()
  self._visual_content = { mode = "", text = "", placeholder = nil }
  table.insert(self._active_snippets, snippet_instance)

  -- Park cursor at snippet end (ignore CursorMovedI triggered by this)
  self._ignore_movements = true
  set_buf_cursor(Position:new(snippet_instance._end.line, snippet_instance._end.col))

  snippet:do_post_expand(snippet_instance._start, snippet_instance._end, self._active_snippets)

  if self._vstate then
    self._vstate:remember_buffer(snippet_instance)
  end
  if self._change_provider then
    -- Discard our own launch writes (UltiSnips `reset()` parity): they were
    -- recorded by on_bytes but are already reflected in the remembered
    -- snapshot above; replaying them later as user edits corrupts the tree.
    self._change_provider:reset()
  end

  -- Jump to first tabstop
  self:_jump("FORWARD")
end

function SnippetManager:_cursor_moved()
  self._should_update_textobjects = false

  if self._ignore_movements then
    self._ignore_movements = false
    return
  end

  if #self._active_snippets == 0 then return end

  local cur_buf = vim.api.nvim_get_current_buf()
  if cur_buf ~= self._snippet_buffer_number then
    if _is_aux_window() then return end
    self:_leaving_buffer()
    return
  end

  local snip = self:_current_snippet()
  if not snip then return end

  -- Consume edits from change provider
  if self._change_provider and self._vstate then
    local buf = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local edits = self._change_provider:consume_edits(buf, snip, self._vstate)
    if edits == change_mod.DROP_SNIPPET then
      -- Buffer diverged beyond reconciliation: abandon everything cleanly
      -- (UltiSnips parity), never leave half-dead nested state behind.
      while #self._active_snippets > 0 do
        self:_current_snippet_done()
      end
      self:_reinit()
      return
    end
    if edits and #edits > 0 then
      -- Replay edits and update text objects
      snip:replay_user_edits(edits, self._ctab)
      snip:update_textobjects(nil, self._ctab)
    else
      -- No edits, just update text objects
      snip:update_textobjects(nil, self._ctab)
    end
    -- Remember buffer state for next comparison
    self._vstate:remember_buffer(snip)
  end

  self:_check_if_still_inside()
end

function SnippetManager:_check_if_still_inside()
  if not self:_current_snippet() then return end
  local cursor = buf_cursor()
  local snip = self:_current_snippet()
  if not (snip._start <= cursor and cursor <= snip._end) then
    self:_current_snippet_done()
    self:_reinit()
    -- Recurse: the outer snippet of a nest may now be outside too
    -- (UltiSnips parity).
    self:_check_if_still_inside()
  end
end

function SnippetManager:_reinit()
  -- Reset transient per-snippet state (UltiSnips _reinit parity). A stale
  -- _ctab would poison replays in a later snippet (tab numbers repeat!);
  -- a stale _ignore_movements would swallow the next snippet's first
  -- event; a stale typed char would fake a future auto-trigger.
  self._ctab = nil
  self._ignore_movements = false
  self._last_typed_char = ""
end

function SnippetManager:_current_snippet_done()
  if #self._active_snippets == 0 then return end
  local si = self._active_snippets[#self._active_snippets]
  si.snippet:do_post_finish(si)
  table.remove(self._active_snippets)
  self:_reinit()
  if #self._active_snippets == 0 then
    self:_teardown_inner_state()
  end
end

function SnippetManager:_jump(direction)
  if self._should_update_textobjects then
    self._should_reset_visual = false
    self:_cursor_moved()
  end

  vim.opt.virtualedit = "onemore"
  local jumped = false
  local stack_for_action = {}
  for _, s in ipairs(self._active_snippets) do table.insert(stack_for_action, s) end

  local ntab = nil
  local snippet_for_action = nil
  if self:_current_snippet() then
    snippet_for_action = self:_current_snippet()
  elseif #stack_for_action > 0 then
    snippet_for_action = stack_for_action[#stack_for_action]
  end

  local move_cmd = ""
  if self:_current_snippet() then
    ntab = self:_current_snippet():select_next_tab(direction)
    if ntab then
      if self:_current_snippet().snippet:has_option("s") then
        local line = vim.api.nvim_buf_get_lines(0, ntab._start.line, ntab._start.line + 1, false)[1] or ""
        vim.api.nvim_buf_set_lines(0, ntab._start.line, ntab._start.line + 1, false, { (line:gsub("%s+$", "")) })
      end
      self._ignore_movements = true
      -- Leaving insert synchronously is impossible here (both the queued
      -- C-\ C-N and :stopinsert are silent no-ops inside the auto-trigger
      -- autocmd), and a queued <Esc> exits insert with a one-left shift.
      -- So from insert: queue nothing at all (not even the C-\ C-N: it
      -- would run after return and strand us in normal mode). The API
      -- cursor below is already exact and we are already in insert.
      -- From visual/select the queued keys exit without shifting
      -- (verified exact), so queue them.
      local origin_insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
      -- Leave visual/select synchronously FIRST (UltiSnips parity via
      -- feedkeys "nx"): moving the cursor or writing marks while a live
      -- selection exists extends it, and the later <Esc> writes the
      -- extended range back into '< '> clobbering our marks (observed:
      -- jump re-selected (0,0)-(0,16) instead of the tabstop).
      if not origin_insert then
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes([[<C-\><C-N>]], true, true, true),
          "nx", false
        )
      end
      set_buf_cursor(ntab._start)
      jumped = true
      self._ctab = ntab
      self._visual_content.placeholder = {
        current_text = ntab:current_text(),
        start = ntab._start,
        end_pos = ntab._end,
      }
      self:_current_snippet().current_placeholder = self._visual_content.placeholder
      self._should_reset_visual = false
      self._active_snippets[1]:update_textobjects(nil, self._ctab)
      open_folds_safely()

      local finish_normal = false
      if ntab._number == 0 and #self._active_snippets > 0 then
        finish_normal = self:_current_snippet().snippet:has_option("x")
        self:_current_snippet_done()
        if finish_normal then
          vim.cmd([[call feedkeys("\<Esc>", "in")]])
          move_cmd = ""
        end
      end
      -- Place the user on the tabstop (also for a final $0: the snippet is
      -- done but the user still lands in a sane mode). Non-empty ranges are
      -- re-selected via marks + gv: no Ex command may run between entering
      -- and leaving visual mode (a mid-visual `:call` drops back to normal
      -- and strands a trailing <C-g> as a no-op). Empty tabstops stay in
      -- insert via i/a -- mirroring UltiSnips' vim_helper.select().
      -- Skipped only for the `x` option (finish in normal mode).
      if not finish_normal and ntab._start < ntab._end then
        -- gv is inclusive: end mark sits on the last included byte
        -- (end is exclusive), not one past it.
        local el, ec = ntab._end.line, ntab._end.col
        if ec == 0 and el > ntab._start.line then
          local pl = vim.api.nvim_buf_get_lines(0, el - 1, el, false)[1] or ""
          el, ec = el - 1, math.max(#pl - 1, 0)
        else
          ec = math.max(ec - 1, 0)
        end
        -- NOTE: never use the visual marks '< '> here. Once a linewise
        -- visual selection has existed in the session, nvim silently
        -- refuses API writes to them (read-back keeps stale MAXCOL), so a
        -- jump after e.g. `Vjj d` would re-select whole lines. Plain `a`/`b`
        -- marks have no such problem; the user's values are saved at
        -- snippet start and restored at teardown (see below).
        vim.api.nvim_buf_set_mark(0, "a", ntab._start.line + 1, ntab._start.col, {})
        vim.api.nvim_buf_set_mark(0, "b", el + 1, ec, {})
        -- Select via explicit charwise `v` + mark motions (UltiSnips
        -- parity): a bare `gv` would inherit the *mode* of the last visual
        -- selection, so after e.g. `Vjj d` every jump re-selected whole
        -- lines. No Ex command may run between entering and leaving
        -- visual mode (a mid-visual `:call` drops back to normal and
        -- strands a trailing <C-g> as a no-op).
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<Esc>`av`b<C-g>", true, true, true),
          "n", false
        )
      elseif not finish_normal then
        -- Empty tabstop: place the cursor absolutely, then enter insert.
        -- From visual/select the queued <Esc> exits first (no shift), so
        -- `i`/`A` below land exactly. From insert nothing is queued at
        -- all (see origin_insert above): the API cursor is already exact.
        -- End-of-line uses `A` (append at EOL).
        local l = vim.api.nvim_buf_get_lines(0, ntab._start.line, ntab._start.line + 1, false)[1] or ""
        local ecol = ntab._start.col
        local k
        if ecol == 0 or ecol < #l then
          k = "i"
          set_buf_cursor({ line = ntab._start.line, col = ecol })
        else
          k = "A"
          set_buf_cursor({ line = ntab._start.line, col = math.max(#l - 1, 0) })
        end
        if not origin_insert then
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>" .. k, true, true, true),
            "n", false
          )
        else
          -- No motion was queued above to consume it.
          self._ignore_movements = false
        end
        -- From insert: cursor is already exact via the API set above and
        -- we are already in insert mode, so no keys are queued (the <Esc>
        -- would exit with a one-left shift and misplace the cursor).
      end
    else
      self:_current_snippet_done()
      jumped = self:_jump(direction)
    end
  end

  if jumped and ntab then
    snippet_for_action.snippet:do_post_jump(
      ntab._number,
      direction == "FORWARD" and 1 or -1,
      stack_for_action,
      snippet_for_action
    )
  end

  -- _jump borrows virtualedit=onemore while computing; give the user's
  -- own value back afterwards (a final $0 may already have torn the
  -- session down above -- re-applying the saved value here is harmless).
  vim.opt.virtualedit = self._saved_virtualedit or ""

  return jumped
end

function SnippetManager:_setup_inner_state()
  if self._inner_state_up then return end

  self._change_provider = change_mod.NvimChangeProvider:new()
  self._vstate = VimState:new()

  vim.cmd("silent doautocmd <nomodeline> User SnippetsEnterFirstSnippet")
  self._snippet_buffer_number = vim.api.nvim_get_current_buf()
  self._change_provider:attach(self._snippet_buffer_number)
  self._inner_state_up = true

  -- _jump borrows virtualedit=onemore and leaves ""; remember the user's
  -- value so teardown restores it (a `set ve=all` user would otherwise
  -- lose their setting after the first snippet).
  self._saved_virtualedit = vim.opt.virtualedit:get()

  -- Tabstop selection uses plain `a`/`b` marks (visual marks freeze after
  -- linewise selections, see _jump); stash the user's values for restore
  -- at teardown.
  self._saved_marks = {}
  for _, name in ipairs({ "a", "b" }) do
    local ok, pos = pcall(vim.api.nvim_buf_get_mark, self._snippet_buffer_number, name)
    if ok then self._saved_marks[name] = pos end
  end

  -- Setup autocommands
  local augroup = vim.api.nvim_create_augroup("SnippetsLua", { clear = true })
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    callback = function() self:_cursor_moved() end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    callback = function() self:_cursor_moved() end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function() end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      vim.defer_fn(function()
        self:_leaving_buffer()
      end, 0)
    end,
  })
  vim.api.nvim_create_autocmd({ "CmdwinEnter", "CmdwinLeave" }, {
    group = augroup,
    callback = function()
      self:_leaving_buffer()
    end,
  })
  -- Setup jump keymaps (buffer-local, active only during snippet).
  -- x-mode is the safety net: if the tabstop-select key chain ever leaves
  -- the user in visual instead of select mode, the jump keys still work
  -- (_jump's key chain starts with <Esc>, so calling from visual is safe).
  local jump_fwd = vim.g.SnippetsJumpForwardTrigger
  local jump_bwd = vim.g.SnippetsJumpBackwardTrigger
  local buf = self._snippet_buffer_number
  if jump_fwd and #tostring(jump_fwd) > 0 then
    pcall(vim.keymap.set, "i", jump_fwd, function() self:jump_forwards() end, { buffer = buf, silent = true })
    pcall(vim.keymap.set, "s", jump_fwd, function() self:jump_forwards() end, { buffer = buf, silent = true })
    pcall(vim.keymap.set, "x", jump_fwd, function() self:jump_forwards() end, { buffer = buf, silent = true })
  end
  if jump_bwd and #tostring(jump_bwd) > 0 then
    pcall(vim.keymap.set, "i", jump_bwd, function() self:jump_backwards() end, { buffer = buf, silent = true })
    pcall(vim.keymap.set, "s", jump_bwd, function() self:jump_backwards() end, { buffer = buf, silent = true })
    pcall(vim.keymap.set, "x", jump_bwd, function() self:jump_backwards() end, { buffer = buf, silent = true })
  end
end

function SnippetManager:_teardown_inner_state()
  if not self._inner_state_up then return end
  vim.cmd("silent doautocmd <nomodeline> User SnippetsExitLastSnippet")

  -- Remove jump keymaps
  local jump_fwd = vim.g.SnippetsJumpForwardTrigger
  local jump_bwd = vim.g.SnippetsJumpBackwardTrigger
  local buf = self._snippet_buffer_number or 0
  if jump_fwd and #tostring(jump_fwd) > 0 then
    pcall(vim.keymap.del, "i", jump_fwd, { buffer = buf })
    pcall(vim.keymap.del, "s", jump_fwd, { buffer = buf })
    pcall(vim.keymap.del, "x", jump_fwd, { buffer = buf })
  end
  if jump_bwd and #tostring(jump_bwd) > 0 then
    pcall(vim.keymap.del, "i", jump_bwd, { buffer = buf })
    pcall(vim.keymap.del, "s", jump_bwd, { buffer = buf })
    pcall(vim.keymap.del, "x", jump_bwd, { buffer = buf })
  end

  if self._change_provider then
    self._change_provider:detach()
    self._change_provider = nil
  end
  self._vstate = nil

  -- Restore the user's virtualedit (see _setup_inner_state). The field
  -- is intentionally NOT cleared: a _jump in flight re-applies it at its
  -- end (teardown can run mid-jump for a final $0); the next session's
  -- setup overwrites it anyway.
  if self._saved_virtualedit ~= nil then
    pcall(function() vim.opt.virtualedit = self._saved_virtualedit end)
  end

  -- Restore user a/b marks clobbered by tabstop selection.
  if self._saved_marks then
    local buf = self._snippet_buffer_number
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local line_count = vim.api.nvim_buf_line_count(buf)
      for _, name in ipairs({ "a", "b" }) do
        local pos = self._saved_marks[name]
        if pos then
          if pos[1] and pos[1] > 0 then
            -- Clamp: set_mark silently no-ops on out-of-range positions
            -- (same silent-drop family as the frozen '< '> marks).
            local ln = math.min(pos[1], line_count)
            local ll = vim.api.nvim_buf_get_lines(buf, ln - 1, ln, false)[1] or ""
            pcall(vim.api.nvim_buf_set_mark, buf, name, ln, math.min(pos[2] or 0, #ll), {})
          else
            -- Was unset: park on line 1 first, then delete. delmarks
            -- alone cannot clear an invalidated ("zombie") mark.
            pcall(vim.api.nvim_buf_set_mark, buf, name, 1, 0, {})
            pcall(vim.api.nvim_buf_call, buf, function()
              vim.cmd("delmarks " .. name)
            end)
          end
        end
      end
    end
    self._saved_marks = nil
  end

  local augroup = vim.api.nvim_get_autocmds({ group = "SnippetsLua" })
  if #augroup > 0 then
    pcall(vim.api.nvim_del_augroup_by_name, "SnippetsLua")
  end

  self._snippet_buffer_number = nil
  self._inner_state_up = false
end

function SnippetManager:_leaving_buffer()
  if _is_aux_window() then return end
  while #self._active_snippets > 0 do
    self:_current_snippet_done()
  end
  self:_reinit()
end

function SnippetManager:_handle_failure(trigger, pass_through)
  if trigger:lower() == "<tab>" or trigger:lower() == "<s-tab>" or
     (pass_through and vim.g.SnippetsInsertTriggerOnNoMatch ~= 0) then
    self._last_failure_key = trigger
  end
end

function SnippetManager:add_snippet(trigger, value, description, options, ft, priority, context, actions)
  ft = ft or "all"
  priority = priority or 0
  local def = snippet_mod.SnippetsSnippetDefinition:new(
    priority, trigger, value, description, options, {}, "added", context, actions
  )
  self._added_snippets_source:add_snippet(ft, def)
end

function SnippetManager:expand_anonymous(body, opts)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local start_pos = Position:new(cursor[1] - 1, cursor[2])
  local def = snippet_mod.SnippetsSnippetDefinition:new(
    0, "", body, "", opts or "", {}, "anonymous", nil, {}
  )
  def:matches(body)
  self:_setup_inner_state()
  local si = def:launch("", nil, nil, start_pos, start_pos)
  open_folds_safely()
  table.insert(self._active_snippets, si)
  if self._vstate then
    self._vstate:remember_buffer(si)
  end
  if self._change_provider then
    self._change_provider:reset()
  end
  self:_jump("FORWARD")
end

function SnippetManager:expand_anon(value, trigger, description, options, context, actions)
  trigger = trigger or ""
  description = description or ""
  options = options or ""
  local before = get_line_till_cursor()
  local snip = snippet_mod.SnippetsSnippetDefinition:new(
    0, trigger, value, description, options, {}, "", context, actions
  )
  if trigger == "" or snip:matches(before, self._visual_content) then
    self:_do_snippet(snip, before)
    return true
  end
  return false
end

function SnippetManager:can_expand()
  local before = get_line_till_cursor()
  local snippets = self:_snips(before, false, false)
  return #snippets > 0
end

function SnippetManager:can_jump(direction)
  local snip = self:_current_snippet()
  if not snip then return false end
  return snip:has_next_tab(direction)
end

function SnippetManager:can_jump_forwards()
  return self:can_jump("FORWARD")
end

function SnippetManager:can_jump_backwards()
  return self:can_jump("BACKWARD")
end

function SnippetManager:list_snippets()
  local before = get_line_till_cursor()
  local snippets = self:_snips(before, true)
  if #snippets == 0 then
    self:_handle_failure(vim.g.SnippetsListSnippets or "<c-tab>")
    return
  end
  table.sort(snippets, function(a, b) return a:trigger() < b:trigger() end)
  local snippet = ask_snippets(snippets)
  if snippet then
    self:_do_snippet(snippet, before)
  end
end

function SnippetManager:snippets_in_current_scope(search_all)
  local before = ""
  if not search_all then before = get_line_till_cursor() end
  local snippets = self:_snips(before, true)

  table.sort(snippets, function(a, b) return a:trigger() < b:trigger() end)
  local snippets_dict = {}
  local snippets_dict_info = {}
  for _, snip in ipairs(snippets) do
    local desc = snip:description()
    local loc = snip:location()
    local key = snip:trigger()
    if desc:find(key) then
      desc = desc:sub(desc:find(key) + #key + 2)
    end
    if #desc > 2 and desc:sub(1,1) == desc:sub(-1) and (desc:sub(1,1) == "'" or desc:sub(1,1) == '"') then
      desc = desc:sub(2, -2)
    end
    snippets_dict[key] = desc
    snippets_dict_info[key] = { description = desc, location = loc }
  end
  vim.g.current_snippets_dict = snippets_dict
  vim.g.current_snippets_dict_info = snippets_dict_info
end

function SnippetManager:_file_to_edit(ft, bang)
  if not ft or #ft == 0 then
    ft = vim.bo.filetype or ""
  end

  -- An explicitly configured file wins outright (no prompt).
  local extra = source_mod.find_extra_snippet_files(ft)
  if #extra == 1 then return extra[1] end
  if #extra > 1 then
    local choice = vim.fn.inputlist(extra)
    if choice >= 1 and choice <= #extra then return extra[choice] end
    return ""
  end

  -- Collect every candidate across snippet directories (UltiSnips shows a
  -- picker on ambiguity instead of silently taking the first hit).
  local candidates = {}
  local dirs = source_mod.find_all_snippet_directories()
  for _, dir in ipairs(dirs) do
    for _, f in ipairs(source_mod.find_snippet_files(ft, dir)) do
      table.insert(candidates, f)
    end
  end

  -- Deduplicate while keeping order.
  local seen, uniq = {}, {}
  for _, f in ipairs(candidates) do
    if not seen[f] then seen[f] = true; uniq[#uniq + 1] = f end
  end
  candidates = uniq

  if #candidates == 1 then return candidates[1] end
  if #candidates > 1 then
    local items = {}
    for i, f in ipairs(candidates) do
      local mark = (vim.fn.filereadable(f) == 1) and "*" or " "
      items[#items + 1] = ("%d%s %s"):format(i, mark, f)
    end
    local choice = vim.fn.inputlist(items)
    if choice >= 1 and choice <= #candidates then
      return candidates[choice]
    end
    return ""
  end

  if not bang then return "" end

  if #dirs > 0 then
    local dir = dirs[1]
    vim.fn.mkdir(dir, "p")
    return dir .. "/" .. ft .. ".snippets"
  end

  local first_rtp = vim.o.runtimepath:match("^[^,]+")
  local dir = first_rtp .. "/snippets"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. ft .. ".snippets"
end

-- Public API
M.SnippetManager = SnippetManager

function M.create()
  return SnippetManager:new()
end

return M
