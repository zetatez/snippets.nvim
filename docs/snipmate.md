# SnipMate Compatibility

Snippets loads classic SnipMate-style snippets from `snippets/` directories on
the `runtimepath`. Enable/disable with `g:SnippetsEnableSnipMate` (default 1):

```lua
vim.g.SnippetsEnableSnipMate = 0
```

## Layouts

Everything lives under `<runtimepath>/snippets/`:

```
snippets/_.snippets            snippets for every filetype ("_" = all)
snippets/c.snippets            snippets for filetype c
snippets/c/for.snippet         single-snippet file (trigger = basename)
snippets/c/functions.snippets  multi-snippet file for c
snippets/c/sub/*.snippet       single-snippet files under a sub-path
```

### `.snippets` text files

```
snippet for
    for (${1:i} = 0; $1 < ${2:n}; $1++) {
        $0
    }

snippet if
    if (${1:cond}) {
        $0
    }
```

- Content lines must be tab-indented; one leading tab is stripped.
- A snippet ends at the first non-empty, non-tab line (or next `snippet`).
- `extends ft1, ft2` is honoured between snipMate files.

### Single `.snippet` files

`snippets/{ft}/{trigger}.snippet` — the trigger is the file base name; the
file's content is the body.

## Semantic differences vs Snippets files

- SnipMate definitions are forced to option `w` and priority `-1000`, so a
  Snippets snippet for the same trigger always wins.
- Backtick code in SnipMate bodies is evaluated as **VimL** (the snipMate
  convention), not shell.
- No nested tab stops / choices / transformations inside SnipMate bodies;
  such text is kept literal.
