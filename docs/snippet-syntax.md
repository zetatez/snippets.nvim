# Snippet Syntax

Snippet files live under one of the directories in
`g:SnippetsSnippetDirectories` (default `snippets`) on your `runtimepath`.
Files are named `<filetype>.snippets` or `<filetype>/*.snippets`, and the
special filetype `all` applies to every buffer.

## Anatomy of a snippet

```
snippet trigger "description" options
<snippet body>
endsnippet
```

- `trigger` — required. Wrap in quotes for a trigger containing spaces.
- `"description"` — optional, shown in listings.
- `options` — optional single flag word, e.g. `bwA` (see below).
- body lines are taken verbatim between `snippet` and `endsnippet`.

Example:

```
snippet hello "Say hello" b
Hello, world!
endsnippet
```

## Options

One concatenated word after the trigger/description:

| Flag | Meaning                                                                                         |
| ---  | ---                                                                                             |
| `b`  | Expand only at the beginning of a line (whitespace-only prefix).                                |
| `i`  | In-word expansion — the trigger may be preceded by word characters.                             |
| `w`  | Word boundary — the trigger must sit between non-word characters.                               |
| `r`  | The trigger is a regular expression.                                                            |
| `A`  | Auto-trigger — expands as soon as the trigger is fully typed.                                   |
| `p`  | Partial prefix — expands when only a prefix of the trigger is typed.                            |
| `e`  | Context snippet — uses the 4th positional/`context` expression.                                 |
| `t`  | Keep leading tabs; with `expandtab` they become `shiftwidth` spaces, otherwise hard tabs again. |
| `m`  | Trim trailing whitespace of every body line at expansion.                                       |
| `s`  | Trim trailing whitespace of a line when jumping to a tab stop on it.                            |
| `x`  | Finish in Normal mode after the final `$0` tab stop.                                            |

## Tab stops

```
$1              first jump stop (empty)
${1:hello}      first jump stop, default text "hello"
${1}            explicit form of $1
$0              final tab stop / exit marker (always visited last)
```

Jump order follows tab-stop *numbers*, not their position in the body.
Use `<C-j>`/`<C-k>` (or your configured jump triggers) to move between them.
When a tab stop has text, jumping to it selects it so typing replaces it.

## Mirrors

A tab stop referenced again by `$N` becomes a live mirror of tab stop `N`:

```
${1:name} and $1     typing in $1 updates $1 everywhere
```

## Transformations

```
${1/regex/replacement/flags}
```

Transform the text of tab stop `1` with a regex substitution. Replacement
supports:

| Syntax            | Meaning                               |
| ---               | ---                                   |
| `$1`..`$9`        | regex capture groups                  |
| `\u`/`\l`         | uppercase/lowercase next char         |
| `\U..\E`/`\L..\E` | uppercase/lowercase a region          |
| `\n` `\t`         | newline / tab                         |
| `(?N:yes:no)`     | `yes` if group `N` matched, else `no` |
| `\\`              | literal backslash                     |

Flags: `g` (all matches), `i` (ignore case), `m` (multi-line), `a` (ascii
transliteration).

Examples:

```
${1/.*/\U$0\E/}        UPPERCASE the tab stop
${1/(a)|(b)/(?1:A:B)/}  A when group 1 matched, else B
${1/, */, /g}           join list items with ", "
```

## Choices

```
${1|apple,banana,cherry|}
```

Displays `1.apple|2.banana|3.cherry`; type the number (1–2 digits) to pick.
Choice text is literal — not re-parsed for tab stops.

## Visual placeholders

```
${VISUAL}            insert the saved visual selection
${VISUAL:fallback}   use "fallback" when nothing was selected
${VISUAL/./\U$0\E/g} apply a transformation to the selection
```

Linewise/blockwise selections are re-indented to match the `${VISUAL}` column.

## Inline codes

```
`!p snip.rv = t[1].upper()`      Python (see python-bridge.md)
`!v tr(expand("%:t"), ".", "_")` VimL expression
`echo hello | tr a-z A-Z`        shell command
```

Python results are evaluated until stable (up to 10 passes). Shell output is
inserted verbatim (one trailing newline removed) and is *not* re-parsed.

## Escaping

| Source    | Result                    |
| ---       | ---                       |
| `\$1`     | literal `$1` (EscapeChar) |
| `\$`      | literal `$`               |
| `\\`      | literal `\`               |
| `` \` ``  | literal backtick          |
| `\{` `\}` | literal brace             |

## File-wide directives

```
extends html css js      inherit snippets from other filetypes
clearsnippets [triggers] clear snippets (optionally only named triggers)
priority 10              default priority for the rest of the file

global !p
import os
BASE = os.path.dirname(__file__)
endglobal
```

- `extends` without filetypes lists parents (for `<filetype>/*.snippets`
  auto-loading).
- `clearsnippets` without args removes snippets at/below the current
  `priority`; with args, only those triggers.
- `global !p` code runs before every `!p` block in the file.

## Context snippets (option `e`)

A context expression gates whether a snippet may expand. Two forms:

```
context "before.endswith('.py')"   header form (applies to next snippet)
snippet tag "desc" "len(before) > 3" e  4th positional form
```

Contexts are **Python** expressions, run as `snip.context = (<expr>)`.
Locals: `before`, `visual_mode`, `visual_text`, `last_placeholder`,
`match` (incl. `groupdict`), `line`/`column`/`cursor` (0-based), `window`,
`buffer`. Python truthiness decides; skipped on empty buffers; errors
report trigger + location and suppress.

## Actions

Actions are Python code with a `snip` object (`context`, `cursor`,
`tabstop`, `jump_direction`, `tabstops`, `snippet_start`/`snippet_end`,
`visual_mode`/`visual_text` as applicable):

```
pre_expand  "..."   before insert (`snip.cursor.set()` re-anchors)
post_expand "..."   after insert
post_jump   "..."   after each jump
post_finish "..."   when finished
```

Missing (UltiSnips has them): `snip.buffer` proxy, `snip.expand_anon`,
`span()`/`expand()` on matches. Clearing typed text in `pre_expand` is
the action's job.

## Matching rules

- Default: the trigger must match the end of the line. For multi-word
  triggers (quote them: `snippet "hello world" ..`), the last *N* words
  must equal the trigger, where *N* is the trigger's word count.
- `w`: last word(s) equal the trigger and the character before them is a
  non-word character.
- `i`: trigger appears at the end of a word.
- `r`: trigger is a regex that must reach the cursor (suffix-anchored,
  like UltiSnips `finditer`). Python-style `(...)` groups are supported;
  named groups `(?P<name>...)` feed `match.groupdict()`. Literal `=`,
  `@`, `~` are escaped for Vim's `\v` automatically.
- `b`: prefix may contain only whitespace.
- `p`: only a typed prefix is required; just the typed chars are removed.
