# Development

## Layout

```
lua/snippets/
├── init.lua                  setup, keymaps, autotrigger wiring, public API
├── manager.lua               expansion / jump engine + snippet sources registry
├── source.lua                file discovery, .snippets parsing, SnipMate source
├── parser.lua                tokens -> text-object tree
├── lexer.lua                 tokenizes snippet bodies
├── snippet.lua               SnippetDefinition: matching/options/actions/launch
├── regex.lua                 Python-re -> Vim-re (\v) translation
├── change.lua                edit diffing / on_bytes change provider
├── on_bytes.lua              nvim_buf_attach byte listener
├── text_object.lua           TextObject / EditableTextObject edit routing
├── text_objects/             tabstop, mirror, transformation, choices, visual,
│                             python_code, viml_code, shell_code, escaped_char,
│                             snippet_instance
├── position.lua, vim_state.lua, buffer.lua
└── cmp_snippets.lua           nvim-cmp completion source
```

## Running the tests

Each spec runs in its own headless Neovim process (isolation):

```bash
tests/run.sh              # all specs
tests/run.sh trigger_spec # one spec
```

 | Spec               | Covers                                            |
 | ---                | ---                                               |
 | `trigger_spec`     | option letters, `could_match`, multiword triggers |
 | `regex_spec`       | `(?:...)` / `\b` translation, regex triggers      |
 | `snipmate_spec`    | SnipMate file layouts, priorities                 |
 | `integration_spec` | `$0`, blank lines, context truthiness, captures   |
 | `behavior_spec`    | auto-trigger, jumping, mirror wiring, teardown    |
 | `misc_spec`        | `m`/`s`/`x` options, AddedSnippetsSource          |
 | `path_spec`        | snippet directory/file path configuration         |

## Notes for contributors

- **Pure Lua** is the design goal. The only Python touch-point is
  `text_objects/python_code.lua`, which shells out to `py3eval` for `!p`.
- **Regex is Vim regex** executed under very-magic (`\v`). `regex.lua`
  best-effort translates Python `(?:...)` (→ Vim `\%(...)`) and `\b`
  (→ `<`/`>`). Python-literal chars that are magic under `\v` are escaped
  (`=` → `\=`, `@` → `[@]`, `~` → `\~`); patterns are compiled once and
  cached. Trigger matching is suffix-anchored like UltiSnips
  (`re.finditer` + `match.end() == len(before)`); named groups
  `(?P<name>...)` are captured for `match.groupdict()`. Advanced
  constructs Vim cannot express — lookaround `(?=...)`, `(?<=...)` —
  are not supported; unsupported patterns degrade gracefully (no crash)
  with a warning from transformations. Transformations always match with
  DOTALL semantics.
- **Editing model**: user edits are captured (`on_bytes`) and diffed into
  `I`/`D` commands (`change.lua`), then replayed through the text-object
  tree (`text_object.lua` `_do_edit`) so tab stops/mirrors stay live.
- `nvim_buf_set_lines`/`nvim_buf_set_text` calls must never pass the
  multiple-return value of `string.gsub` inside a table constructor (wrap in
  parens) — gsub returns `(string, count)`.

## Known divergences from UltiSnips

Snippets aims to be behaviourally compatible with UltiSnips snippet files.
Documented remaining gaps:

- Context / action expressions are Python (parity achieved); the
  `snip.buffer` proxy and `snip.expand_anon` inside actions are not
  implemented yet, and match objects expose `group()`/`groups()`/
  `groupdict()` but not `span()`/`expand()`.
- Choices and `!p`/shell/`!v` interpolation match upstream behaviour, but
  regex advanced syntax (lookaround etc.) is limited to what Vim's engine
  supports (`=`, `@`, `~` are escaped for `\v`; transforms use DOTALL).
- Interactive insert/select-mode behaviours (placeholder select-overwrite,
  arrow-key exit-from-tabstop auto-jump) need a real editing session;
  headless tests cover the deterministic core.
