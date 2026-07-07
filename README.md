# Snippets

A pure-Lua snippet engine for Neovim. UltiSnips-compatible `.snippets`
files, live mirrors/transformations, auto-trigger, and SnipMate support —
no Python dependency beyond Neovim's built-in `py3eval` (only used by
`` `!p`` blocks).

## Features

- **Familiar syntax** — `extends`, `clearsnippets`, `priority`, `context`,
  `global !p`; multi-word triggers work.
- **Tab stops & mirrors** — `${1}`, `${1:default}`, `$0`, live `$1` mirrors.
- **Transformations** — `${1/regex/repl/flags}`; **choices** `${1|a,b|}`;
  **visual** `${VISUAL}`.
- **Inline code** — shell `` `...` ``, `` `!v`` VimL, `` `!p`` Python.
- **Trigger options** — `b i w r p e A`; body options `t m s x`.
- **Auto-trigger** — `A` snippets expand as you type; **SnipMate** dirs load too.

## Requirements

- Neovim ≥ 0.8
- Python 3 provider, only if you use `` `!p`` snippets

## Installation

```lua
-- lazy.nvim
{
  "zetatez/snippets.nvim",
  event = { "InsertEnter" },
  config = function()
    require("snippets").setup() -- optional; see Configuration
  end,
}
```

```vim
" vim-plug
Plug 'zetatez/snippets.nvim'
```

`setup()` only (re)creates commands and keymaps; everything else works
with defaults. Full options: [docs/configuration.md](docs/configuration.md).

## Usage

Snippets live in `snippets/` on your `runtimepath`
(`~/.config/nvim/snippets/all.snippets`):

```snippets
snippet hello "Say hello" b
Hello, world!
endsnippet
```

Type `hello`, press `<Tab>`. Jump with `<C-j>` / `<C-k>` (buffer-local,
only while a snippet is live). `A`-flag snippets need no key.
`<C-Tab>` lists matches; `:SnippetsEdit` opens the snippet file.

Point elsewhere with an absolute path:

```lua
vim.g.SnippetsSnippetDirectories = { vim.fn.expand("~/.config/nvim/snippets") }
```

One key for both jobs: `SnippetsExpandOrJumpTrigger` (expand, else jump)
or `SnippetsJumpOrExpandTrigger` (jump, else expand).

## Usage with hrsh7th/nvim-cmp

```lua
{
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    { "hrsh7th/cmp-nvim-lsp" },
    { "hrsh7th/cmp-buffer" },
    { "zetatez/snippets.nvim" }, -- dependency = load order guaranteed
  },
  config = function()
    local cmp = require("cmp")
    cmp.register_source("snippets", require("cmp_snippets")) -- before setup()
    cmp.setup({
      snippet = {
        expand = function(args) require("snippets").anon(args.body) end,
      },
      mapping = cmp.mapping.preset.insert({
        ["<C-Space>"] = cmp.mapping.complete({}),
        ["<CR>"]      = cmp.mapping.confirm({ select = true }),
        ["<C-j>"]     = cmp.mapping.select_next_item(),
        ["<C-k>"]     = cmp.mapping.select_prev_item(),
      }),
      sources = cmp.config.sources({
        { name = "snippets" },
        { name = "nvim_lsp" },
        { name = "buffer" },
      }),
    })
  end,
}
```

Notes:

- Confirming a `[Snippets]` item replaces the **whole** trigger
  (multi-word triggers included) and expands in place.
- Don't bind `<Tab>` to both snippet-expand and `cmp.mapping.confirm`;
  confirm with `<CR>`.
- `<C-j>`/`<C-k>` are shared: snippet jumps win while active (buffer-local),
  cmp gets them otherwise. Move jumps to `<C-l>`/`<C-h>` if you dislike
  sharing (`SnippetsJumpForwardTrigger` / `SnippetsJumpBackwardTrigger`).

## Documentation

- [Configuration & commands](docs/configuration.md)
- [Snippet syntax](docs/snippet-syntax.md)
- [Python bridge (`!p`)](docs/python-bridge.md)
- [SnipMate compatibility](docs/snipmate.md)
- [Development & tests](docs/development.md)

## License

MIT
