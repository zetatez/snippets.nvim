# Python Bridge (`!p`)

`!p` blocks execute Python through Neovim's `py3eval`. This is the only part
of Snippets that touches Python; everything else is pure Lua. If you never use
`!p` snippets, no Python runtime is needed.

## Available names

 | Name                                    | Description                                                                   |
 | ---                                     | ---                                                                           |
 | `snip.rv`                               | (set) replaced placeholder text                                               |
 | `snip.c`                                | current text of this `!p` placeholder                                         |
 | `snip.fn`                               | current file name                                                             |
 | `snip.path`                             | full path of current file                                                     |
 | `snip.basename`                         | file name without extension                                                   |
 | `snip.ft`                               | filetype                                                                      |
 | `snip.vim`                              | thin proxy: `.eval()`, `.exists()`                                            |
 | `snip.v` / `snip.visual`                | visual content: `.mode`, `.text`                                              |
 | `snip.opt(name, default)`               | read a Vim option/global with default                                         |
 | `snip.indent` / `snip.shiftwidth`       | current snippet indentation                                                   |
 | `snip.mkline(line, indent)`             | build an indented line                                                        |
 | `snip.shift(n=1)` / `snip.unshift(n=1)` | shift the snippet indent                                                      |
 | `snip.reset_indent()`                   | reset indent to the launch-time indent                                        |
 | `snip += "line"`                        | append (newline-separated, indent-aware)                                      |
 | `snip >> 1` / `snip << 1`               | shift/unshift by `shiftwidth`                                                 |
 | `t[n]`                                  | read/write tab stop `n` (missing tab stops read as `""`)                      |
 | `fn`, `path`, `basename`, `ft`, `ct`    | bare shorthands                                                               |
 | `res`, `cur`                            | result accumulator / current text; final text is `snip.rv` if set, else `res` |
 | `match`                                 | regex match object for `r` snippets: `.group(n)`, `.groups()`, `.groupdict()` |

Pre-imported modules: `os`, `json`, `re`, `string`, `random`, `sys`.

## Examples

```snippets
snippet upper "Uppercase"
`!p snip.rv = t[1].upper()`
endsnippet

snippet date "Insert date"
`!p import time; snip.rv = time.strftime("%Y-%m-%d")`
endsnippet

snippet tpl "Title-case a name"
${1:name}
`!p t[1] = t[1].title()
snip.rv = ""`
endsnippet
```

### Shared globals

`global !p` blocks run before every `!p` in the same file:

```snippets
global !p
def greet(name):
    return f"Hello, {name}!"
endglobal

snippet hi "Greeting"
`!p snip.rv = greet(t[1])`
endsnippet
```

### Regex `match`

With an `r` snippet the regex match is available (named groups included):

```
snippet ([a-z]+)(\d+) r
`!p snip.rv = match.group(1) + "-" + match.group(2)`
endsnippet

snippet (?P<word>[a-z]+)=(?P<val>.*) r
`!p snip.rv = match.group("val") + " is " + match.groupdict()["word"]`
endsnippet
```

## Notes

- Final text is `snip.rv` when assigned, else the (possibly reassigned)
  `res` (which starts, like `cur`, as the current text) — UltiSnips parity.
- `t[n]` reads all tabstops including `t[0]`; writes apply immediately.
- `match` offers `group()`/`groups()`/`groupdict()` (no `span()`/`expand()`).
- Errors inside `!p` raise a notification with trigger, location and the
  Python traceback.
- Locals persist across multiple `!p` blocks and across edits of the same
  snippet instance; JSON-safe `global !p` variables additionally persist
  across update rounds (functions are re-created from `global !p` each
  round, as upstream effectively does).
