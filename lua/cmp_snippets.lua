local cmp_snippets = {}

local has_snippets, snippets = pcall(require, "snippets")

function cmp_snippets.is_available()
  return has_snippets
end

function cmp_snippets.get_keyword_pattern()
  -- Mirror cmp-nvim-ultisnips so symbol/regex triggers also produce candidates.
  return "\\%([^[:alnum:][:blank:]]\\|\\w\\+\\)"
end

function cmp_snippets.complete(self, params, callback)
  if not has_snippets then
    callback()
    return
  end

  local manager = snippets.manager
  -- Full line up to the cursor (byte-indexed, like UltiSnips line_till_cursor).
  -- nvim-cmp filters by label itself; delegate matching to could_match()
  -- via _snips(before, partial=true), exactly like UltiSnips
  -- fetch_current_snippets(expandable_only=True).
  local before = params.context.cursor_before_line or ""
  local cursor = params.context.cursor or {}
  -- 0-based byte offsets for the LSP range (single-line triggers only).
  local cur_line0 = (cursor.row or 1) - 1
  local cur_col0 = (cursor.col or (#before + 1)) - 1
  local items = {}

  -- Get matching snippets for current filetype (partial -> could_match).
  local snippets = manager:_snips(before, true)
  for _, s in ipairs(snippets) do
    local trigger = s:trigger()
    if trigger and #trigger > 0 then
      local description = s:description() or ""
      local is_regex = s:has_option("r")
      -- Like cmp-nvim-ultisnips: insert the trigger text; the actual
      -- expansion (with matched-length deletion) happens in execute().
      -- Never put the raw snippet body in insertText: it is UltiSnips
      -- syntax (`!p`, backticks, transforms), not LSP snippet syntax.
      local insert_text = (is_regex and s:matched() ~= "" and s:matched()) or trigger
      local item = {
        label = trigger,
        kind = 15, -- vim.lsp.protocol.CompletionItemKind.Snippet
        insertText = insert_text,
        detail = " [Snippets]",
        documentation = {
          kind = "markdown",
          value = ("```\n%s\n```\n\n%s"):format(
            s._value or "",
            description
          ),
        },
        -- Higher priority sorts first (cmp sorts ascending).
        sortText = ("%04d"):format(9999 - (s:priority() or 0)),
      }
      -- Cover the FULL matched text (not just cmp's space-split keyword):
      -- otherwise confirming "hello world" replaces only "world", leaving
      -- "hello hello world", which then fails the `b` beginning-of-line
      -- check in execute(). could_match() records the typed suffix in
      -- s:matched(); anchor the range on it.
      local matched_len = #(s:matched() or "")
      if matched_len > 0 then
        local start_col0 = math.max(cur_col0 - matched_len, 0)
        item.textEdit = {
          range = {
            start = { line = cur_line0, character = start_col0 },
            ["end"] = { line = cur_line0, character = cur_col0 },
          },
          newText = insert_text,
        }
      end
      table.insert(items, item)
    end
  end

  callback({ items = items, isIncomplete = true })
end

function cmp_snippets.resolve(self, completion_item, callback)
  callback(completion_item)
end

function cmp_snippets.execute(self, completion_item, callback)
  -- Mirror cmp-nvim-ultisnips execute(): expand now that cmp has inserted
  -- insertText; manager re-matches line_till_cursor and deletes `matched`.
  if has_snippets then
    local ok, mod = pcall(require, "snippets")
    if ok and mod.expand_snippet then
      mod.expand_snippet()
    end
  end
  callback(completion_item)
end

return cmp_snippets
