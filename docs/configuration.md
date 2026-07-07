# Configuration

All options are Vim globals, set before or after `require("snippets").setup()`.

## Example (lazy.nvim)

```lua
{
  "zetatez/snippets.nvim",
  event = { "InsertEnter" },
  -- ft = { "markdown", "python" },   -- optionally limit filetypes
  -- cmd = { "SnippetsEdit" },        -- ...or load on command
  config = function()
    vim.g.SnippetsExpandTrigger = "<tab>"      -- expand snippet
    vim.g.SnippetsJumpForwardTrigger = "<c-j>" -- next tab stop
    vim.g.SnippetsJumpBackwardTrigger = "<c-k>"-- previous tab stop
    vim.g.SnippetsListSnippets = "<c-tab>"     -- list matching snippets
    -- vim.g.SnippetsExpandOrJumpTrigger = "<tab>" -- one key: expand, else jump

    vim.g.SnippetsSnippetDirectories = { "snippets", "~/mysnippets" }
    -- vim.g.SnippetsSnippetFiles = { "~/dotfiles/nvim/all.snippets" }
    vim.g.SnippetsEnableSnipMate = 1
    -- vim.b.SnippetsSnippetDirectories = {}   -- per-buffer override

    vim.g.SnippetsAutoTrigger = 1              -- allow `A`-flag expansion
    vim.g.SnippetsEditSplit = "normal"         -- :SnippetsEdit layout
    vim.g.SnippetsRemoveSelectModeMappings = 1
    vim.g.SnippetsMappingsToIgnore = {}        -- keys never mapped

    require("snippets").setup()
  end,
}
```

Bare minimum: `require("snippets").setup()` (all defaults).

### Own keymaps

`setup()` maps the defaults above. To use your own, map the public
functions and silence the built-ins via `SnippetsMappingsToIgnore`:

```lua
vim.keymap.set("i", "<C-Space>", function() require("snippets").expand_snippet() end)
vim.keymap.set("i", "<C-n>", function() require("snippets").jump_forwards() end)
vim.keymap.set("i", "<C-p>", function() require("snippets").jump_backwards() end)
```

## Options

 | Variable                             | Default          | Description                                                                           |
 | ---                                  | ---              | ---                                                                                   |
 | `g:SnippetsExpandTrigger`            | `<tab>`          | Expand a snippet                                                                      |
 | `g:SnippetsJumpForwardTrigger`       | `<c-j>`          | Next tab stop (mapped while active)                                                   |
 | `g:SnippetsJumpBackwardTrigger`      | `<c-k>`          | Previous tab stop (mapped while active)                                               |
 | `g:SnippetsListSnippets`             | `<c-tab>`        | List snippets matching the prefix                                                     |
 | `g:SnippetsExpandOrJumpTrigger`      | (none)           | One key: expand, else jump                                                            |
 | `g:SnippetsJumpOrExpandTrigger`      | (none)           | One key: jump, else expand                                                            |
 | `g:SnippetsSnippetDirectories`       | `{ "snippets" }` | rtp-relative names, absolute paths (`~`/`$VAR`), or dir globs; `{}` disables scanning |
 | `g:SnippetsSnippetFiles`             | `{}`             | Specific `.snippets` files (same path forms, globs allowed), filtered by filetype     |
 | `g:SnippetsEnableSnipMate`           | `1`              | Also load SnipMate `snippets/` dirs                                                   |
 | `g:SnippetsAutoTrigger`              | `1`              | Allow `A`-flag auto-expansion                                                         |
 | `g:SnippetsEditSplit`                | `"normal"`       | `:SnippetsEdit`: `normal`, `vertical`, `horizontal`, `tabdo`, `context`               |
 | `g:SnippetsRemoveSelectModeMappings` | `1`              | Keep select mode usable                                                               |
 | `g:SnippetsMappingsToIgnore`         | `{}`             | Keys never mapped                                                                     |
 | `b:SnippetsSnippetDirectories`       | (none)           | Per-buffer directory override                                                         |
 | `b:SnippetsSnippetFiles`             | (none)           | Per-buffer file override                                                              |

Directories scan `{ft}.snippets`, `{ft}_*.snippets`, `{ft}/*`.
`ExpandTrigger == JumpForwardTrigger` also makes one expand-or-jump key.
Unmatched keys are re-inserted, so plain `<Tab>` indenting keeps working.

## Commands

 | Command                          | Description                                                                 |
 | ---                              | ---                                                                         |
 | `:SnippetsEdit {filetype}`       | Open (or create) the snippet file; `!` forces creation; filetype completion |
 | `:SnippetsAddFiletypes {fts}`    | Extra active filetypes in this buffer                                       |
 | `:SnippetsRemoveFiletypes {fts}` | Drop active filetypes in this buffer                                        |
 | `:SnippetsListLocations`         | Snippet definitions to the quickfix list                                    |

## Filetypes

Buffer filetype, then `all`. Dotted filetypes (`c.doxygen`) split on
dots; `extends` follows parents transitively.

## Editor integration

### nvim-cmp

```lua
local cmp = require("cmp")
cmp.register_source("snippets", require("cmp_snippets")) -- before setup()
cmp.setup({
  snippet = {
    expand = function(args) require("snippets").anon(args.body) end,
  },
  sources = cmp.config.sources({ { name = "snippets" } }),
})
```

Confirming replaces the **whole** matched text (LSP `textEdit`, so
multi-word triggers don't duplicate) and expands in place. Confirm with
`<CR>`, not `<Tab>`. Full config with keymaps: README.

### Lua API

```lua
local snippets = require("snippets")
snippets.setup()

snippets.manager:add_snippet(trigger, body, desc, opts, ft, priority, context, actions)
snippets.manager:expand_anon(body, ...)   -- anonymous snippet at cursor
snippets.expand_snippet()
snippets.expand_or_jump()
snippets.jump_forwards()
snippets.jump_backwards()
snippets.list_snippets()
snippets.anon(body)                        -- nvim-cmp snippet.expand target
```
