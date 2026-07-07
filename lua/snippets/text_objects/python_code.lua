local NTO = require("snippets.text_object").NoneditableTextObject

local PythonCode = setmetatable({}, { __index = NTO })
PythonCode.__index = PythonCode

local _py_initialized = false

local PY_INIT_SCRIPT = [[
py3 << PYEOF
import os, json, re, string, random, sys
class _VimProxy:
    def eval(self, expr):
        import vim
        return vim.eval(expr)
    def exists(self, name):
        import vim
        return bool(vim.eval("exists('%s')" % name))
class _VisualContent:
    def __init__(self, mode='', text=''):
        self.mode = mode or 'v'
        self.text = text or ''
class _Snip:
    def __init__(self, **k):
        self._indent = k.pop('indent', '')
        self._shiftwidth = int(k.pop('shiftwidth', 0) or 0)
        self._ct = k.pop('ct', '')
        self._fn = k.pop('fn', '')
        self._path = k.pop('path', '')
        self._basename = k.pop('basename', '')
        self._ft = k.pop('ft', '')
        self._vim = _VimProxy()
        vm = k.pop('visual_mode', '') or ''
        vt = k.pop('visual_text', '') or ''
        self.v = _VisualContent(vm, vt)
        for a, v in k.items():
            setattr(self, a, v)
        self._rv = ""
        self._rv_changed = False
        self.c = self._ct
    @property
    def rv(self):
        return self._rv
    @rv.setter
    def rv(self, v):
        self._rv = str(v)
        self._rv_changed = True
    @property
    def fn(self):
        return self._fn
    @property
    def path(self):
        return self._path
    @property
    def basename(self):
        return self._basename
    @property
    def ft(self):
        return self._ft
    @property
    def shiftwidth(self):
        return self._shiftwidth
    @property
    def indent(self):
        return self._indent
    @property
    def visual(self):
        return self.v
    @property
    def vim(self):
        return self._vim
    def opt(self, name, default=None):
        if self._vim.exists(name):
            try:
                return self._vim.eval(name)
            except Exception:
                return default
        return default
    def mkline(self, line="", indent=None):
        if indent is None:
            indent = self._indent
        return indent + line
    def shift(self, amount=1):
        self._indent = self._indent + " " * (self._shiftwidth * amount)
    def unshift(self, amount=1):
        n = self._shiftwidth * amount
        if len(self._indent) >= n:
            self._indent = self._indent[:-n]
        else:
            self._indent = ""
    def reset_indent(self):
        self._indent = self._cur_indent
    def __add__(self, other):
        s = str(other)
        if self._rv == "":
            self._rv = s
        else:
            parts = s.split("\n")
            first = parts[0]
            rest = parts[1:]
            self._rv += "\n" + first
            for p in rest:
                self._rv += "\n" + self._indent + p
        self._rv_changed = True
        return self
    def __rshift__(self, amount):
        self.shift(amount)
        return self
    def __lshift__(self, amount):
        self.unshift(amount)
        return self
    def _set_current_indent(self, indent):
        self._cur_indent = indent
class _Tabs:
    def __init__(self, vals):
        self._data = {}
        self._changed = set()
        if isinstance(vals, list):
            vals = {}
        for k, v in vals.items():
            if isinstance(k, str) and k.isdigit():
                self._data[int(k)] = v
            else:
                self._data[k] = v
    def __getitem__(self, k):
        return self._data.get(k, "")
    def __setitem__(self, k, v):
        self._data[k] = v
        self._changed.add(k)
class _Match:
    def __init__(self, group0, groups, names=None):
        self._g = [group0] + list(groups or [])
        self._names = list(names or [])
    def group(self, n=0):
        try:
            if isinstance(n, str):
                try:
                    n = self._names.index(n) + 1
                except ValueError:
                    return None
            return self._g[n] if self._g[n] is not None else ""
        except IndexError:
            return None
    def groups(self):
        return tuple(self._g[1:])
    def groupdict(self):
        return {name: (self._g[i + 1] if i + 1 < len(self._g) and self._g[i + 1] is not None else "") for i, name in enumerate(self._names)}
    def __bool__(self):
        return True
import traceback
class _Placeholder:
    def __init__(self, d):
        d = d or {}
        self.current_text = d.get('current_text', '')
        s = d.get('start') or {}
        e = d.get('end') or {}
        self.start = (s.get('line', 0), s.get('col', 0))
        self.end = (e.get('line', 0), e.get('col', 0))
class _ActionCursor:
    def __init__(self):
        self._pos = None
    def is_set(self):
        return self._pos is not None
    def set(self, line, col):
        self._pos = (int(line), int(col))
def _run_action(code, ctx_json):
    # UltiSnips _execute_action parity (minus buffer proxy / expand_anon,
    # which need nested-expansion support): runs action code with a snip
    # carrying context / cursor / tabstop info. `snip.cursor.set()` is
    # honored by the caller; anything else the action changed in the
    # buffer is its own responsibility.
    ctx = json.loads(ctx_json)
    g = globals()
    d = dict(ctx)
    snip = _Snip(**ctx)
    snip.cursor = _ActionCursor()
    if 'context' not in ctx:
        snip.context = None
    d['snip'] = snip
    if 'match' in ctx and isinstance(ctx['match'], dict):
        m = ctx['match']
        d['match'] = _Match(m.get('group0', ''), m.get('groups', []), m.get('group_names'))
    elif 'match' not in ctx:
        d['match'] = None
    err = None
    try:
        exec(code, g, d)
    except Exception:
        err = traceback.format_exc()
    cur = snip.cursor
    return json.dumps({'context': getattr(snip, 'context', None),
        'cursor_set': cur.is_set(), 'cursor': list(cur._pos) if cur.is_set() else None,
        'err': err})
def _run_ctx(code, ctx_json):
    # UltiSnips parity for `e` context: run `snip.context = (<code>)` with
    # the documented locals and report Python truthiness of the result.
    ctx = json.loads(ctx_json)
    g = globals()
    d = dict(ctx)
    d['snip'] = _Snip(**ctx)
    if 'match' in ctx and isinstance(ctx['match'], dict):
        m = ctx['match']
        d['match'] = _Match(m.get('group0', ''), m.get('groups', []))
    else:
        d['match'] = None
    if isinstance(ctx.get('last_placeholder'), dict):
        d['last_placeholder'] = _Placeholder(ctx['last_placeholder'])
    else:
        d['last_placeholder'] = None
    err = None
    try:
        exec("snip.context = (" + code + "\n)", g, d)
    except Exception:
        err = traceback.format_exc()
    snip_obj = d.get('snip', _Snip())
    val = getattr(snip_obj, 'context', None)
    try:
        return json.dumps({'value': val, 'truthy': bool(val), 'err': err})
    except Exception:
        return json.dumps({'value': None, 'truthy': False,
            'err': (err or '') + '\n[snippets] context result is not JSON-serializable; treated as no-match'})
def _run_us(code, ctx_json):
    ctx = json.loads(ctx_json)
    g = globals()
    d = dict(ctx)
    d['snip'] = _Snip(**ctx)
    d['t'] = _Tabs(ctx.get('t', {}))
    d['changed'] = False
    # UltiSnips parity: `res`/`cur` start as the current text; the final
    # value is snip.rv when assigned, else the (possibly reassigned) res.
    cur = ctx.get('ct', '')
    d.setdefault('res', cur)
    d.setdefault('cur', cur)
    if 'match' in ctx and isinstance(ctx['match'], dict):
        m = ctx['match']
        d['match'] = _Match(m.get('group0', ''), m.get('groups', []), m.get('group_names'))
    elif 'match' not in ctx:
        d['match'] = None
    d['snip']._set_current_indent(ctx.get('indent', ''))
    # Restore persisted globals from previous runs (JSON-safe values only;
    # functions are re-created by re-executing globals_code each call).
    persist_in = ctx.get('__persist') or {}
    if isinstance(persist_in, dict):
        for k, v in persist_in.items():
            d.setdefault(k, v)
    initial_keys = set(d.keys())
    err = None
    try:
        exec(code, g, d)
    except Exception:
        err = traceback.format_exc()
    snip_obj = d.get('snip', _Snip())
    if snip_obj._rv_changed:
        rv = snip_obj._rv
    else:
        rv = d.get('res', cur)
        if rv is None:
            rv = None
    # Collect newly-defined JSON-safe globals for the next run.
    persist_out = {}
    for k, v in d.items():
        if k in initial_keys or k in ('snip', 't', 'match', 'changed', 'res', 'cur'):
            continue
        try:
            json.dumps(v)
            persist_out[k] = v
        except Exception:
            pass
    tab_data = dict(d.get('t', _Tabs({}))._data)
    tab_changed = list(d.get('t', _Tabs({}))._changed)
    return json.dumps({'rv': rv, 'err': err, 'tab_data': tab_data, 'tab_changed': tab_changed, 'changed': d.get('changed', False), 'persist': persist_out})
PYEOF
]]

local function _ensure_py_init()
  if _py_initialized then return true end
  local ok, exists = pcall(vim.fn.py3eval, [['_run_us' in dir()]])
  if ok and exists then
    _py_initialized = true
    return true
  end
  local ok_err, msg = pcall(vim.cmd, PY_INIT_SCRIPT)
  if not ok_err then
    vim.notify("Snippets: failed to init Python bridge: " .. tostring(msg), vim.log.levels.ERROR)
    return false
  end
  _py_initialized = true
  return true
end

function PythonCode:new(parent, token)
  self._locals = {}
  self._visual_text = ""
  self._visual_mode = ""
  do
    local snippet = parent
    while snippet do
      if snippet.locals then
        self._locals = snippet.locals
        self._visual_text = snippet.visual_content and snippet.visual_content.text or ""
        self._visual_mode = snippet.visual_content and snippet.visual_content.mode or ""
        break
      end
      snippet = snippet._parent
    end
  end

  self._indent = token.indent
  self._code = token.code:gsub("\\`", "`")

  local obj = NTO.new(self, parent, token.start, token.end_pos, token.initial_text)
  return obj
end

function PythonCode:_update(done, buf)
  if not _ensure_py_init() then return true end

  local path = vim.fn.expand("%") or ""
  local fn = vim.fn.expand("%:t") or ""
  local basename = fn:match("^(.+)%.[^.]*$") or fn
  local ft = vim.bo.filetype or ""
  local ct = self:current_text()

  -- Build tabstop text dict for t[n] access (UltiSnips _Tabs parity:
  -- includes $0 for reading; missing numbers read back as "").
  local tabstop_texts = {}
  do
    local seen = {}
    local function collect(obj)
      if not obj or seen[obj] then return end
      seen[obj] = true
      if rawget(obj, "_tabstops") then
        for no, ts in pairs(obj._tabstops) do
          local ok, text = pcall(function() return ts:current_text() end)
          if ok then tabstop_texts[tostring(no)] = text end
        end
      end
      if obj._children then
        for _, child in ipairs(obj._children) do collect(child) end
      end
    end
    collect(self._parent)
  end

  -- Build globals code
  local globals_code = ""
  if self._locals and self._locals.globals then
    local gp = self._locals.globals["!p"]
    if gp then globals_code = table.concat(gp, "\n") .. "\n" end
  end

  -- Combine globals code with user code
  local combined_code = globals_code .. self._code

  -- Build context dict
  local indent_str = self._indent or ""
  local shiftwidth = vim.fn.shiftwidth() or 0
  local context = {
    ct = ct,
    fn = fn,
    path = path,
    basename = basename,
    ft = ft,
    t = tabstop_texts,
    indent = indent_str,
    shiftwidth = shiftwidth,
    visual_mode = self._visual_mode,
    visual_text = self._visual_text,
  }
  -- Attach regex match if present (from snippet.locals.match)
  if self._locals and self._locals.match then
    local m = self._locals.match
    context.match = {
      group0 = m.group0,
      groups = m.groups,
      group_names = m.group_names,
    }
  end
  -- Round-trip persisted globals (per-expansion mutable state).
  if self._locals and type(self._locals.globals_state) == "table" then
    context.__persist = self._locals.globals_state
  end
  local context_json = vim.fn.json_encode(context)

  -- Call _run_us via py3eval
  local code_arg = vim.inspect(combined_code)
  local ctx_arg = vim.inspect(context_json)
  local expr = "_run_us(" .. code_arg .. ", " .. ctx_arg .. ")"

  local ok, output = pcall(vim.fn.py3eval, expr)
  if not ok or not output or type(output) ~= "string" then
    return true
  end

  local ok_decode, result = pcall(vim.fn.json_decode, output)
  if not ok_decode or type(result) ~= "table" then
    return true
  end

  if result.err and result.err ~= vim.NIL and #result.err > 0 then
    local where = ""
    do
      local seen, cur = {}, self._parent
      while cur and not seen[cur] do
        seen[cur] = true
        if cur.snippet and cur.snippet._location then
          local ok, t = pcall(function() return cur.snippet:trigger() end)
          where = (" [%s @ %s]"):format(ok and t or "?", cur.snippet._location)
          break
        end
        cur = cur._parent
      end
    end
    vim.notify("Snippets !p error" .. where .. ":\n" .. tostring(result.err), vim.log.levels.ERROR)
    return true
  end

  -- Persist globals for the next round.
  if self._locals and result.persist ~= nil and result.persist ~= vim.NIL
      and type(result.persist) == "table" then
    self._locals.globals_state = result.persist
  end

  -- Apply t[] changes
  if result.tab_data and type(result.tab_data) == "table" then
    for no, text in pairs(result.tab_data) do
      local n = tonumber(no)
      if not n then n = no end
      if self._parent then
        local ts = self._parent:_get_tabstop(self, n)
        if ts then
          ts:overwrite(buf, text)
        end
      end
    end
  end

  -- Apply rv change
  local rv = result.rv
  if rv ~= vim.NIL and rv ~= nil and rv ~= ct then
    self:overwrite(buf, rv)
    return false
  end
  return true
end

-- Shared bridge initializer for other modules (context evaluation).
PythonCode.ensure_bridge = _ensure_py_init

return PythonCode
