local manager_mod = require("snippets.manager")
local change_mod = require("snippets.change")
local vim_state_mod = require("snippets.vim_state")
local snippet_mod = require("snippets.snippet")
local source_mod = require("snippets.source")

local M = {}

local manager = manager_mod.create()
M.manager = manager

local vstate = vim_state_mod.VimState:new()
M.vstate = vstate

local change_provider = change_mod.NvimChangeProvider:new()
M.change_provider = change_provider

local visual_content = vim_state_mod.VisualContentPreserver:new()
M.visual_content = visual_content

local any_buffer_file_loaded = false

local function ensure_snippet_files_loaded()
  if not any_buffer_file_loaded then
    for _, pair in ipairs(manager._snippet_sources) do
      local _, source = pair[1], pair[2]
      if source.ensure then
        source:ensure(manager:get_buffer_filetypes())
      end
    end
    any_buffer_file_loaded = true
  end
end

function M.anon(body, opts)
  manager:expand_anonymous(body, opts)
end

local function compensate_for_pum()
  if vim.fn.pumvisible() == 1 then
    manager:_cursor_moved()
  end
end

-- Define VimL-callable functions that replace the Python-based autoload
-- NOTE: These used to be in autoload/Snippets.vim but we use Lua callbacks now.
-- These are kept for backward compatibility only.
local function define_vim_functions()
end

function M.expand_snippet()
  compensate_for_pum()
  manager:expand()
end

function M.expand_or_jump()
  compensate_for_pum()
  manager:expand_or_jump()
end

function M.jump_or_expand()
  compensate_for_pum()
  manager:jump_or_expand()
end

function M.jump_forwards()
  compensate_for_pum()
  manager:jump_forwards()
end

function M.jump_backwards()
  compensate_for_pum()
  manager:jump_backwards()
end

function M.list_snippets()
  compensate_for_pum()
  manager:list_snippets()
end

function M.snippets_in_current_scope()
  compensate_for_pum()
  manager:snippets_in_current_scope(false)
end

function M.can_expand()
  return manager:can_expand()
end

function M.can_jump_forwards()
  return manager:can_jump_forwards()
end

function M.can_jump_backwards()
  return manager:can_jump_backwards()
end

function M.add_filetypes(filetypes)
  manager:add_buffer_filetypes(filetypes)
end

function M.remove_filetypes(filetypes)
  manager:remove_buffer_filetypes(filetypes)
end

function M.edit(bang, type)
  local file = manager:_file_to_edit(type or "", bang ~= "")
  if not file or #file == 0 then return end

  local mode = "e"
  if vim.g.SnippetsEditSplit then
    local split = vim.g.SnippetsEditSplit
    if split == "vertical" then
      mode = "vs"
    elseif split == "horizontal" then
      mode = "sp"
    elseif split == "tabdo" then
      mode = "tabedit"
    elseif split == "context" then
      mode = "vs"
      local tw = vim.bo.tw
      if tw == 0 then tw = 80 end
      if vim.fn.winwidth(0) <= 2 * tw then
        mode = "sp"
      end
    end
  end
  vim.cmd(mode .. " " .. vim.fn.fnameescape(file))
end

function M.save_last_visual_selection()
  visual_content:conserve()
  manager._visual_content = {
    mode = visual_content:mode(),
    text = visual_content:text(),
    placeholder = visual_content:placeholder(),
  }
end

function M.add_snippet_with_priority()
  local trigger = vim.eval("a:trigger")
  local value = vim.eval("a:value")
  local description = vim.eval("a:description")
  local options = vim.eval("a:options")
  local filetype = vim.eval("a:filetype")
  local priority = vim.eval("a:priority")
  manager:add_snippet(trigger, value, description, options, filetype, priority)
end

function M.anon_expand()
  local args = vim.eval("a:000")
  local value = vim.eval("a:value")
  manager:expand_anon(value, table.unpack(args))
end

function M.cursor_moved()
  manager:_cursor_moved()
end

function M._leaving_insert_mode()
  -- Placeholder for insert mode leave handling
end

-- Last literally-typed character (UltiSnips _last_change debounce): auto
-- expansion is attempted only when the buffer change came from a typed char
-- still sitting at the cursor -- never for programmatic writes (including
-- our own expansion) or popup-only events. Kept on the manager so lifecycle
-- transitions (_reinit) can clear it alongside _ctab/_ignore_movements.
function M._track_change()
  if manager._autotrigger == 0 then return end
  if #manager._active_snippets > 0 then
    manager:_cursor_moved()
    return
  end
  local ok, vchar = pcall(vim.fn.eval, "v:char")
  if ok and type(vchar) == "string" and vchar ~= "" then
    -- InsertCharPre: the char is not in the buffer yet; wait for the
    -- TextChangedI/TextChangedP that follows it.
    manager._last_typed_char = vchar
    return
  end
  local last = manager._last_typed_char or ""
  manager._last_typed_char = ""
  if last == "" then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1] or ""
  local till = line:sub(1, cursor[2])
  if till:sub(-#last) ~= last then return end
  manager:_try_expand(true)
end

function M._refresh_snippets()
  any_buffer_file_loaded = false
  ensure_snippet_files_loaded()
end

function M._leaving_buffer()
  manager:_leaving_buffer()
end

function M._toggle_autotrigger()
  manager._autotrigger = manager._autotrigger == 0 and 1 or 0
  return manager._autotrigger
end

function M._file_to_edit(type, bang)
  return manager:_file_to_edit(type, bang)
end

local function set_default(var, value)
  if vim.g[var] == nil then vim.g[var] = value end
end

local function _feed_on_fail(trigger)
  if manager._last_failure_key then
    manager._last_failure_key = nil
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(trigger, true, true, true),
      "n", true
    )
  end
end

function M._map_keys()
  set_default("SnippetsExpandTrigger", "<tab>")
  set_default("SnippetsListSnippets", "<c-tab>")
  set_default("SnippetsJumpForwardTrigger", "<c-j>")
  set_default("SnippetsJumpBackwardTrigger", "<c-k>")
  set_default("SnippetsRemoveSelectModeMappings", 1)
  set_default("SnippetsMappingsToIgnore", {})
  set_default("SnippetsEditSplit", "normal")
  set_default("SnippetsSnippetDirectories", { "snippets" })
  set_default("SnippetsEnableSnipMate", 1)

  local expand = vim.g.SnippetsExpandTrigger
  local jump_fwd = vim.g.SnippetsJumpForwardTrigger
  local list_snips = vim.g.SnippetsListSnippets

  if vim.g.SnippetsExpandOrJumpTrigger ~= nil then
    local t = vim.g.SnippetsExpandOrJumpTrigger
    vim.keymap.set("i", t, function() M.expand_or_jump(); _feed_on_fail(t) end, { silent = true })
    vim.keymap.set("s", t, function() M.expand_or_jump() end, { silent = true })
  elseif vim.g.SnippetsJumpOrExpandTrigger ~= nil then
    local t = vim.g.SnippetsJumpOrExpandTrigger
    vim.keymap.set("i", t, function() M.jump_or_expand(); _feed_on_fail(t) end, { silent = true })
    vim.keymap.set("s", t, function() M.jump_or_expand() end, { silent = true })
  elseif expand == jump_fwd then
    vim.keymap.set("i", expand, function() M.expand_or_jump(); _feed_on_fail(expand) end, { silent = true })
    vim.keymap.set("s", expand, function() M.expand_or_jump() end, { silent = true })
  else
    vim.keymap.set("i", expand, function() M.expand_snippet(); _feed_on_fail(expand) end, { silent = true })
    vim.keymap.set("s", expand, function() M.expand_snippet() end, { silent = true })
  end
  -- NOTE: this must stay a `:` mapping, not a Lua callback. A Lua callback
  -- for mode "x" runs *before* visual mode exits, so '< '> still hold the
  -- *previous* selection: conserve() would capture the wrong text and the
  -- trailing gv"_s would delete the wrong range (observed: selecting "bbb"
  -- captured and deleted "aaa" from the line above). Entering command-line
  -- first folds the live selection into the marks (UltiSnips parity).
  vim.keymap.set("x", expand,
    ":<C-u>lua require('snippets').save_last_visual_selection()<CR>gv\"_s",
    { silent = true })

  if #tostring(list_snips) > 0 then
    vim.keymap.set("i", list_snips, function() M.list_snippets(); _feed_on_fail(list_snips) end, { silent = true })
    vim.keymap.set("s", list_snips, function() M.list_snippets() end, { silent = true })
  end

  vim.keymap.set("s", "<BS>", "<c-g>\"_c", { silent = true })
  vim.keymap.set("s", "<DEL>", "<c-g>\"_c", { silent = true })
  vim.keymap.set("s", "<c-h>", "<c-g>\"_c", { silent = true })
  vim.keymap.set("s", "<c-r>", "<c-g>\"_c<c-r>", { silent = true })
end

function M.setup()
  vim.g.did_plugin_snippets_lua = 1
  vim.g._snippets_reg_cache = {}

  define_vim_functions()

  vim.api.nvim_create_user_command("SnippetsEdit", function(opts)
    M.edit(opts.bang == "bang", opts.args)
  end, { nargs = "?", complete = function(ArgLead, CmdLine, CursorPos)
    local items = vim.fn.sort(vim.fn.uniq(vim.fn.map(vim.fn.split(vim.fn.globpath(vim.o.runtimepath, "syntax/*.vim"), "\n"), "fnamemodify(v:val, ':t:r')")))
    table.insert(items, "all")
    local ret = {}
    for _, item in ipairs(items) do
      if item:find("^" .. ArgLead) then
        table.insert(ret, item)
      end
    end
    return ret
  end, bang = true })

  vim.api.nvim_create_user_command("SnippetsAddFiletypes", function(opts)
    M.add_filetypes(opts.args)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("SnippetsRemoveFiletypes", function(opts)
    M.remove_filetypes(opts.args)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("SnippetsListLocations", function()
    M.snippets_in_current_scope()
    local info = vim.g.current_snippets_dict_info or {}
    local items = {}
    for trigger, info_t in pairs(info) do
      local idx = info_t.location:match(".*():")
      if idx == nil then
        local lnum_str = info_t.location:match(":(%d+)$")
        local filename = info_t.location:match("^(.-):%d+$")
        local lnum = tonumber(lnum_str) or 0
        if lnum > 0 and filename then
          local text = trigger
          if info_t.description and #info_t.description > 0 then
            text = text .. " - " .. info_t.description
          end
          table.insert(items, { filename = filename, lnum = lnum, text = text })
        end
      end
    end
    table.sort(items, function(a, b) return a.text < b.text end)
    if #items == 0 then
      vim.notify("Snippets: no snippet definitions with file locations found.", vim.log.levels.INFO)
      return
    end
    vim.fn.setqflist({}, 'r', { title = 'Snippets snippet locations', items = items })
    vim.cmd("copen")
  end, {})

  -- Auto-trigger: InsertCharPre + TextChangedI + TextChangedP
  local auto_augroup = vim.api.nvim_create_augroup("Snippets_AutoTrigger_Lua", { clear = true })
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = auto_augroup,
    callback = function() M._track_change() end,
  })
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = auto_augroup,
    callback = function() M._track_change() end,
  })
  vim.api.nvim_create_autocmd("TextChangedP", {
    group = auto_augroup,
    callback = function() M._track_change() end,
  })

  -- Ensure snippets loaded on VimEnter
  vim.api.nvim_create_autocmd("VimEnter", {
    group = auto_augroup,
    callback = function()
      ensure_snippet_files_loaded()
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = auto_augroup,
    callback = function()
      -- Reset loaded state so sources re-ensure for new filetypes
      any_buffer_file_loaded = false
    end,
  })

  M._map_keys()

  ensure_snippet_files_loaded()
end

return M
