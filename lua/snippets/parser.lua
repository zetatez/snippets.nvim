local lexer = require("snippets.lexer")
local to = require("snippets.text_objects")
local Position = require("snippets.position")

local function resolve_ambiguity(all_tokens, seen_ts)
  for _, pair in ipairs(all_tokens) do
    local parent, token = pair[1], pair[2]
    if getmetatable(token) == lexer.MirrorToken then
      if not seen_ts[token.number] then
        seen_ts[token.number] = to.TabStop:new(parent, token)
      else
        to.Mirror:new(parent, seen_ts[token.number], token)
      end
    end
  end
end

local function tokenize_snippet_text(snippet_instance, text, indent, allowed_in_text, allowed_in_tabstops, token_to_to)
  local seen_ts = {}
  local all_tokens = {}

  local function _do_parse(parent, ptext, allowed)
    local tokens = lexer.tokenize(ptext, indent, parent._start, allowed)
    for _, token in ipairs(tokens) do
      table.insert(all_tokens, { parent, token })
      if getmetatable(token) == lexer.TabStopToken then
        local ts = to.TabStop:new(parent, token)
        seen_ts[token.number] = ts
        _do_parse(ts, token.initial_text, allowed_in_tabstops)
      else
        local klass = token_to_to[getmetatable(token)]
        if klass then
          local text_object = klass:new(parent, token)
          if text_object.number then
            seen_ts[text_object.number] = text_object
          end
        end
      end
    end
  end

  _do_parse(snippet_instance, text, allowed_in_text)
  return all_tokens, seen_ts
end

local function finalize(all_tokens, seen_ts, snippet_instance)
  if not seen_ts[0] then
    local last_token = all_tokens[#all_tokens][2]
    local mark = last_token.end_pos or last_token.start
    local m1 = Position:new(mark.line, mark.col)
    to.TabStop:new(snippet_instance, 0, mark, m1)
  end
end

local _TOKEN_TO_TEXTOBJECT_ULTI = {
  [lexer.EscapeCharToken] = to.EscapedChar,
  [lexer.VisualToken] = to.Visual,
  [lexer.ShellCodeToken] = to.ShellCode,
  [lexer.PythonCodeToken] = to.PythonCode,
  [lexer.VimLCodeToken] = to.VimLCode,
  [lexer.ChoicesToken] = to.Choices,
}

local _ALLOWED_TOKENS_ULTI = {
  lexer.EscapeCharToken,
  lexer.VisualToken,
  lexer.TransformationToken,
  lexer.ChoicesToken,
  lexer.TabStopToken,
  lexer.MirrorToken,
  lexer.PythonCodeToken,
  lexer.VimLCodeToken,
  lexer.ShellCodeToken,
}

local function _create_transformations(all_tokens, seen_ts)
  for _, pair in ipairs(all_tokens) do
    local parent, token = pair[1], pair[2]
    if getmetatable(token) == lexer.TransformationToken then
      if not seen_ts[token.number] then
        error(string.format("Tabstop %d is not known but is used by a Transformation", token.number))
      end
      to.Transformation:new(parent, seen_ts[token.number], token)
    end
  end
end

function parse_snippets(parent_to, text, indent)
  local all_tokens, seen_ts = tokenize_snippet_text(
    parent_to, text, indent,
    _ALLOWED_TOKENS_ULTI, _ALLOWED_TOKENS_ULTI, _TOKEN_TO_TEXTOBJECT_ULTI
  )
  resolve_ambiguity(all_tokens, seen_ts)
  _create_transformations(all_tokens, seen_ts)
  finalize(all_tokens, seen_ts, parent_to)
end

local _TOKEN_TO_TEXTOBJECT_SNIPMATE = {
  [lexer.EscapeCharToken] = to.EscapedChar,
  [lexer.VisualToken] = to.Visual,
  [lexer.ShellCodeToken] = to.VimLCode,
}

local _ALLOWED_TOKENS_SNIPMATE = {
  lexer.EscapeCharToken,
  lexer.VisualToken,
  lexer.TabStopToken,
  lexer.MirrorToken,
  lexer.ShellCodeToken,
}

local _ALLOWED_TOKENS_IN_TABSTOPS_SNIPMATE = {
  lexer.EscapeCharToken,
  lexer.VisualToken,
  lexer.MirrorToken,
  lexer.ShellCodeToken,
}

function parse_snipmate(parent_to, text, indent)
  local all_tokens, seen_ts = tokenize_snippet_text(
    parent_to, text, indent,
    _ALLOWED_TOKENS_SNIPMATE, _ALLOWED_TOKENS_IN_TABSTOPS_SNIPMATE,
    _TOKEN_TO_TEXTOBJECT_SNIPMATE
  )
  resolve_ambiguity(all_tokens, seen_ts)
  finalize(all_tokens, seen_ts, parent_to)
end

return {
  parse_snippets = parse_snippets,
  parse_snipmate = parse_snipmate,
}
