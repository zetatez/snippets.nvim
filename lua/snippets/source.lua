local snippet_mod = require("snippets.snippet")

local SnippetDictionary = {}
SnippetDictionary.__index = SnippetDictionary

function SnippetDictionary:new()
  return setmetatable({
    _snippets = {},
    _cleared = {},
    _clear_priority = -math.huge,
  }, self)
end

function SnippetDictionary:add_snippet(snippet)
  table.insert(self._snippets, snippet)
end

function SnippetDictionary:get_matching_snippets(trigger, potentially, autotrigger_only, visual_content)
  local all = self._snippets
  if autotrigger_only then
    local filtered = {}
    for _, s in ipairs(all) do
      if s:has_option("A") then table.insert(filtered, s) end
    end
    all = filtered
  end

  local result = {}
  if not potentially then
    for _, s in ipairs(all) do
      if s:matches(trigger, visual_content) then
        table.insert(result, s)
      end
    end
  else
    for _, s in ipairs(all) do
      if s:could_match(trigger) then
        table.insert(result, s)
      end
    end
  end
  return result
end

function SnippetDictionary:clear_snippets(priority, triggers)
  if not triggers or #triggers == 0 then
    if priority > self._clear_priority then
      self._clear_priority = priority
    end
  else
    for _, trigger in ipairs(triggers) do
      if not self._cleared[trigger] or priority > self._cleared[trigger] then
        self._cleared[trigger] = priority
      end
    end
  end
end

function SnippetDictionary:__len()
  return #self._snippets
end

function SnippetDictionary:__pairs()
  return ipairs(self._snippets)
end

local SnippetSource = {}
SnippetSource.__index = SnippetSource

function SnippetSource:new()
  return setmetatable({
    _snippets = {},
    _extends = {},
  }, self)
end

function SnippetSource:ensure(filetypes) end
function SnippetSource:refresh() end

function SnippetSource:get_all_snippet_files_for(ft)
  return {}
end

function SnippetSource:_get_existing_deep_extends(base_filetypes)
  local deep = self:get_deep_extends(base_filetypes)
  local result = {}
  for _, ft in ipairs(deep) do
    if self._snippets[ft] then table.insert(result, ft) end
  end
  return result
end

function SnippetSource:get_snippets(filetypes, before, possible, autotrigger_only, visual_content)
  local result = {}
  for _, ft in ipairs(self:_get_existing_deep_extends(filetypes)) do
    local snips = self._snippets[ft]
    if snips then
      local matches = snips:get_matching_snippets(before, possible, autotrigger_only, visual_content)
      for _, s in ipairs(matches) do
        table.insert(result, s)
      end
    end
  end
  return result
end

function SnippetSource:get_clear_priority(filetypes)
  local pri = nil
  for _, ft in ipairs(self:_get_existing_deep_extends(filetypes)) do
    local snips = self._snippets[ft]
    if snips and (not pri or snips._clear_priority > pri) then
      pri = snips._clear_priority
    end
  end
  return pri
end

function SnippetSource:get_cleared(filetypes)
  local cleared = {}
  for _, ft in ipairs(self:_get_existing_deep_extends(filetypes)) do
    local snips = self._snippets[ft]
    if snips then
      for key, value in pairs(snips._cleared) do
        if not cleared[key] or value > cleared[key] then
          cleared[key] = value
        end
      end
    end
  end
  return cleared
end

function SnippetSource:update_extends(child_ft, parent_fts)
  if not self._extends[child_ft] then self._extends[child_ft] = {} end
  for _, ft in ipairs(parent_fts) do
    self._extends[child_ft][ft] = true
  end
end

function SnippetSource:get_deep_extends(base_filetypes)
  local seen = {}
  for _, ft in ipairs(base_filetypes) do
    seen[ft] = true
  end
  local todo = {}
  for k, _ in pairs(seen) do table.insert(todo, k) end
  while #todo > 0 do
    local ft = table.remove(todo, 1)
    local parents = self._extends[ft]
    if parents then
      for parent_ft, _ in pairs(parents) do
        if not seen[parent_ft] then
          seen[parent_ft] = true
          table.insert(todo, parent_ft)
        end
      end
    end
  end
  local result = {}
  for _, ft in ipairs(base_filetypes) do table.insert(result, ft) end
  for ft, _ in pairs(seen) do
    local already = false
    for _, bft in ipairs(base_filetypes) do
      if ft == bft then already = true; break end
    end
    if not already then table.insert(result, ft) end
  end
  return result
end

local SnippetFileSource = setmetatable({}, { __index = SnippetSource })
SnippetFileSource.__index = SnippetFileSource

function SnippetFileSource:new()
  local obj = SnippetSource:new()
  setmetatable(obj, self)
  return obj
end

function SnippetFileSource:ensure(filetypes)
  for _, ft in ipairs(self:get_deep_extends(filetypes)) do
    if self:_needs_update(ft) then
      self:_load_snippets_for(ft)
    end
  end
end

function SnippetFileSource:get_snippets(filetypes, before, possible, autotrigger_only, visual_content)
  local seen = {}
  local result = {}
  for _, snippet in ipairs(SnippetSource.get_snippets(self, filetypes, before, possible, autotrigger_only, visual_content)) do
    local key = snippet:trigger() .. "|" .. snippet:location()
    if not seen[key] then
      seen[key] = true
      table.insert(result, snippet)
    end
  end
  return result
end

function SnippetFileSource:refresh()
  return self:new()
end

function SnippetFileSource:get_all_snippet_files_for(ft)
  error("Must be implemented by subclass")
end

function SnippetFileSource:_needs_update(ft)
  return not self._snippets[ft]
end

function SnippetFileSource:_load_snippets_for(ft)
  for _, fn in ipairs(self:get_all_snippet_files_for(ft)) do
    self:_parse_snippets(ft, fn)
  end
  for _, parent_ft in ipairs(self:get_deep_extends({ ft })) do
    if parent_ft ~= ft and self:_needs_update(parent_ft) then
      self:_load_snippets_for(parent_ft)
    end
  end
  if not self._snippets[ft] then
    self._snippets[ft] = SnippetDictionary:new()
  end
end

function SnippetFileSource:_parse_snippets(ft, filename)
  local file, err = io.open(filename, "r")
  if not file then return end
  local data = file:read("*a")
  file:close()

  if not self._snippets[ft] then
    self._snippets[ft] = SnippetDictionary:new()
  end

  self:_parse_snippet_file(data, filename, ft)
end

function SnippetFileSource:_parse_snippet_file(data, filename, ft)
  error("Must be implemented by subclass")
end

local function normalize_file_path(path)
  local ok, result = pcall(vim.fn.resolve, path)
  if ok then return result end
  return path
end

local function find_snippet_files(ft, directory)
  local patterns = {
    ("%s.snippets"):format(ft),
    ("%s_*.snippets"):format(ft),
    ("%s/*"):format(ft),
  }
  local result = {}
  for _, pattern in ipairs(patterns) do
    local fullpattern = directory .. "/" .. pattern
    local files = vim.fn.glob(fullpattern, false, true)
    for _, fn in ipairs(files) do
      local name = fn:match("[^/]+$") or fn
      if name:sub(1, 1) ~= "." then
        result[normalize_file_path(fn)] = true
      end
    end
  end
  local list = {}
  for k, _ in pairs(result) do table.insert(list, k) end
  return list
end

-- Config entry helpers -------------------------------------------------------
-- Each entry of g:SnippetsSnippetDirectories / b:SnippetsSnippetDirectories may
-- be:
--   * a runtimepath-relative directory name      -> "snippets"
--   * an absolute directory or ~ / $VAR path     -> "~/mysnippets", "/x/snips"
--   * a directory glob                           -> "/x/snips/*", "*/snippets"
-- Directories are scanned for {ft}.snippets, {ft}_*.snippets and {ft}/* files.

local function _config_list(var)
  local list
  if vim.fn.exists("b:" .. var) == 1 then
    list = vim.b[var]
  elseif vim.fn.exists("g:" .. var) == 1 then
    list = vim.g[var]
  else
    return nil
  end
  if type(list) == "string" then list = { list } end
  return list or {}
end

local function _looks_absolute(expanded)
  -- expanded handles ~ and $VAR already; true when rooted at '/'
  return expanded:sub(1, 1) == "/"
end

local function _has_glob(path)
  return path:find("[*?%[]") ~= nil
end

-- Expand one configured directory entry into concrete directories (order kept).
local function _resolve_directory_entry(entry)
  local dirs = {}
  local raw = vim.fn.expand(entry)
  if _looks_absolute(raw) then
    -- absolute path, optional glob / trailing missing dir (kept for creation)
    local found = vim.fn.glob(raw, false, true)
    if #found > 0 then
      for _, g in ipairs(found) do
        if vim.fn.isdirectory(g) == 1 then dirs[#dirs + 1] = g end
      end
    elseif not _has_glob(raw) then
      dirs[#dirs + 1] = raw
    end
  else
    -- runtimepath-relative name (may itself contain a glob)
    local rtp = vim.o.runtimepath
    for dir in rtp:gmatch("[^,]+") do
      local p = vim.fn.expand(dir .. "/" .. entry)
      for _, g in ipairs(vim.fn.glob(p, false, true)) do
        if vim.fn.isdirectory(g) == 1 then dirs[#dirs + 1] = g end
      end
    end
  end
  return dirs
end

local function find_all_snippet_directories()
  local snippet_dirs = _config_list("SnippetsSnippetDirectories")
  if snippet_dirs == nil then snippet_dirs = { "snippets" } end

  local all_dirs = {}
  local seen = {}
  for _, sd in ipairs(snippet_dirs) do
    for _, dir in ipairs(_resolve_directory_entry(sd)) do
      if not seen[dir] then
        seen[dir] = true
        all_dirs[#all_dirs + 1] = dir
      end
    end
  end
  return all_dirs
end

-- Does an explicitly configured snippet *file* belong to filetype ft?
local function _file_belongs_to_ft(ft, filename)
  local base = filename:match("[^/]+$") or filename
  if base == ft .. ".snippets" then return true end
  if base == "all.snippets" then return true end
  if base:match("^" .. vim.pesc(ft) .. "_.*%.snippets$") then return true end
  if filename:match("/" .. vim.pesc(ft) .. "/") then return true end
  return false
end

-- g:SnippetsSnippetFiles / b:SnippetsSnippetFiles: concrete .snippets files
-- (absolute/~/$VAR, optionally globbed) loaded in addition to directories.
local function find_extra_snippet_files(ft)
  local entries = _config_list("SnippetsSnippetFiles") or {}
  local result = {}
  local function add(fn)
    if vim.fn.filereadable(fn) == 1 and _file_belongs_to_ft(ft, fn) then
      result[normalize_file_path(fn)] = true
    end
  end
  for _, entry in ipairs(entries) do
    local raw = vim.fn.expand(entry)
    if _looks_absolute(raw) then
      for _, fn in ipairs(vim.fn.glob(raw, false, true)) do add(fn) end
    else
      -- runtimepath-relative file or glob, e.g. "snippets/cpp.snippets"
      local rtp = vim.o.runtimepath
      for dir in rtp:gmatch("[^,]+") do
        for _, fn in ipairs(vim.fn.glob(dir .. "/" .. raw, false, true)) do add(fn) end
      end
    end
  end
  local list = {}
  for k, _ in pairs(result) do table.insert(list, k) end
  return list
end

-- Snippets File Source

local SnippetsFileSource = setmetatable({}, { __index = SnippetFileSource })
SnippetsFileSource.__index = SnippetsFileSource

function SnippetsFileSource:new()
  local obj = SnippetFileSource:new()
  setmetatable(obj, self)
  return obj
end

function SnippetsFileSource:get_all_snippet_files_for(ft)
  local result = {}
  for _, dir in ipairs(find_all_snippet_directories()) do
    if vim.fn.isdirectory(dir) == 1 then
      for _, fn in ipairs(find_snippet_files(ft, dir)) do
        result[fn] = true
      end
    end
  end
  -- explicitly configured snippet files (g:/b:SnippetsSnippetFiles)
  for _, fn in ipairs(find_extra_snippet_files(ft)) do
    result[fn] = true
  end
  local list = {}
  for k, _ in pairs(result) do table.insert(list, k) end
  return list
end

function SnippetsFileSource:_parse_snippet_file(data, filename, ft)
  local python_globals = {}
  local lines = {}
  for line in data:gmatch("([^\n]*)\n?") do
    table.insert(lines, line)
  end
  local current_priority = 0
  local actions = {}
  local context = nil
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local head = line:match("^%S+")
    local tail = head and line:sub(#head + 1):match("^%s*(.-)%s*$") or ""

    if line:match("^%s*$") then
      -- skip empty lines
    elseif head == "snippet" or head == "global" then
      local s, e, result = self:_handle_snippet_or_global(lines, i, filename, python_globals, current_priority, actions, context)
      if result then
        local event, data = result[1], result[2]
        if event == "snippet" then
          self._snippets[ft]:add_snippet(data)
        end
      end
      if e then i = e end
      actions = {}
      context = nil
    elseif head == "extends" then
      if tail then
        local fts = {}
        for p in tail:gmatch("[^,]+") do
          local ft_clean = p:match("^%s*(.-)%s*$") or p
          ft_clean = ft_clean:gsub("%.snippets$", "")
          table.insert(fts, ft_clean)
        end
        self:update_extends(ft, fts)
      end
    elseif head == "clearsnippets" then
      local triggers = {}
      if tail then
        for t in tail:gmatch("%S+") do table.insert(triggers, t) end
      end
      self._snippets[ft]:clear_snippets(current_priority, triggers)
    elseif head == "priority" then
      local prio = tail:match("%S+")
      if prio then current_priority = tonumber(prio) or 0 end
    elseif head == "context" then
      context = tail:match('^"(.-)"$') or tail
      context = context:gsub('\\"', '"'):gsub('\\\\\\\\', '\\')
    elseif head == "pre_expand" or head == "post_expand" or head == "post_jump" or head == "post_finish" then
      local act = tail:match('^"(.-)"$') or tail
      act = act:gsub('\\"', '"'):gsub('\\\\\\\\', '\\')
      actions[head] = act
    end
    i = i + 1
  end

  for _, snippet in ipairs(self._snippets[ft]._snippets) do
    snippet._precompile_globals = function() end
  end
end

local function _shlex_split(s)
  local parts = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == ' ' or c == '\t' then
      i = i + 1
    elseif c == '"' or c == "'" then
      local close = s:find(c, i + 1)
      if close then
        table.insert(parts, s:sub(i, close))
        i = close + 1
      else
        table.insert(parts, s:sub(i))
        break
      end
    else
      local next_sep = s:find("[ \t]", i)
      if next_sep then
        table.insert(parts, s:sub(i, next_sep - 1))
        i = next_sep + 1
      else
        table.insert(parts, s:sub(i))
        break
      end
    end
  end
  return parts
end

function SnippetsFileSource:_handle_snippet_or_global(lines, start_idx, filename, python_globals, priority, actions, context)
  local line = lines[start_idx]
  local snip_type = line:match("^%S+")
  local remain = line:sub(#snip_type + 1):match("^%s*(.-)$") or ""

  local opts = ""
  local descr = ""
  local trig = ""

  if #remain > 0 then
    local parts = _shlex_split(remain)
    if #parts >= 2 and parts[#parts]:match("^[a-zA-Z]+$") then
      opts = table.remove(parts)
    end
    -- Inline context: snippet trigger "descr" "expr" e
    if opts:find("e") and not context and #parts >= 2 and parts[#parts]:match('^["\'].*["\']$') then
      local ctx_raw = table.remove(parts)
      context = ctx_raw:match('^["\'](.-)["\']$') or ctx_raw
      context = context:gsub('\\"', '"'):gsub('\\\\', '\\')
    end
    if #parts >= 2 and parts[#parts]:match('^["\'].*["\']$') then
      descr = table.remove(parts)
    end
    trig = table.concat(parts, " ")
    trig = trig:match("^[\"'](.-)[\"']$") or trig
  end

  local end_tag = "end" .. snip_type
  local content_lines = {}
  local j = start_idx + 1
  local found = false
  while j <= #lines do
    if lines[j]:match("^%s*$") and lines[j]:match("^%s*" .. end_tag .. "%s*$") then
      found = true
      break
    end
    if lines[j]:match("^%s*" .. end_tag .. "%s*$") then
      found = true
      break
    end
    table.insert(content_lines, lines[j])
    j = j + 1
  end

  if not found then
    return nil, j
  end

  local content = table.concat(content_lines, "\n")
  content = content:gsub("\n$", "")

  if snip_type == "global" then
    if not python_globals[trig] then python_globals[trig] = {} end
    table.insert(python_globals[trig], content)
    return nil, j
  end

  local definition = snippet_mod.SnippetsSnippetDefinition:new(
    priority, trig, content, descr, opts,
    python_globals, filename .. ":" .. start_idx,
    context, actions
  )
  return nil, j, { "snippet", definition }
end

-- SnipMate File Source

local SnipMateFileSource = setmetatable({}, { __index = SnippetFileSource })
SnipMateFileSource.__index = SnipMateFileSource

function SnipMateFileSource:new()
  local obj = SnippetFileSource:new()
  setmetatable(obj, self)
  return obj
end

function SnipMateFileSource:get_all_snippet_files_for(ft)
  local ft_clean = ft
  if ft == "all" then ft_clean = "_" end
  local patterns = {
    ("%s.snippets"):format(ft_clean),
    ("%s/*.snippets"):format(ft_clean),
    ("%s/*.snippet"):format(ft_clean),
    ("%s/*/*.snippet"):format(ft_clean),
  }
  local result = {}
  local rtp = vim.o.runtimepath
  for dir in rtp:gmatch("[^,]+") do
    local snippets_dir = dir .. "/snippets"
    if vim.fn.isdirectory(snippets_dir) == 1 then
      for _, pattern in ipairs(patterns) do
        local full = snippets_dir .. "/" .. pattern
        local files = vim.fn.glob(full, false, true)
        for _, fn in ipairs(files) do
          local name = fn:match("[^/]+$") or fn
          if name:sub(1, 1) ~= "." then
            result[normalize_file_path(fn)] = true
          end
        end
      end
    end
  end
  local list = {}
  for k, _ in pairs(result) do table.insert(list, k) end
  return list
end

function SnipMateFileSource:_parse_snippet_file(data, filename, ft)
  if filename:lower():match("%.snippet$") then
    -- Single-snippet file layout: snippets/{ft}/{trigger}.snippet
    -- The trigger is the basename (without .snippet extension); the filetype
    -- is the enclosing directory (already resolved by the caller).
    local base = filename:gsub("%.snippet$", "")
    local trigger = base:match("[^/]+$") or base
    local content = data
    if content:sub(-1) == "\n" then content = content:sub(1, -2) end
    local def = snippet_mod.SnipMateSnippetDefinition:new(trigger, content, "", filename)
    self._snippets[ft]:add_snippet(def)
  else
    local lines = {}
    for line in data:gmatch("([^\n]*)\n?") do table.insert(lines, line) end
    local i = 1
    while i <= #lines do
      local line = lines[i]
      local head = line:match("^%S+")
      local tail = head and line:sub(#head + 1):match("^%s*(.-)%s*$") or ""

      if line:match("^%s*$") then
        -- skip empty lines
      elseif head == "extends" then
        if tail then
          local fts = {}
          for p in tail:gmatch("[^,]+") do
            local ft_clean = p:match("^%s*(.-)%s*$") or p
            table.insert(fts, ft_clean)
          end
          self:update_extends(ft, fts)
        end
      elseif head == "snippet" then
        local trigger, desc = tail:match("^(%S+)%s*(.-)$")
        if not trigger and tail then trigger = tail end
        if not desc then desc = "" end
        local content_lines = {}
        local j = i + 1
        while j <= #lines do
          local cl = lines[j]
          if cl:match("^%s*$") then j = j + 1
          elseif not cl:match("^\t") and cl:match("%S") then break
          else
            if cl:sub(1, 1) == "\t" then cl = cl:sub(2) end
            table.insert(content_lines, cl)
            j = j + 1
          end
        end
        local content = table.concat(content_lines, "\n"):gsub("\n$", "")
        local def = snippet_mod.SnipMateSnippetDefinition:new(trigger, content, desc, filename .. ":" .. i)
        self._snippets[ft]:add_snippet(def)
        i = j - 1
      end
      i = i + 1
    end
  end
end

-- Added Snippets Source

local AddedSnippetsSource = setmetatable({}, { __index = SnippetSource })
AddedSnippetsSource.__index = AddedSnippetsSource

function AddedSnippetsSource:new()
  local obj = SnippetSource:new()
  setmetatable(obj, self)
  return obj
end

function AddedSnippetsSource:add_snippet(ft, snippet)
  if not self._snippets[ft] then self._snippets[ft] = SnippetDictionary:new() end
  self._snippets[ft]:add_snippet(snippet)
end

return {
  SnippetDictionary = SnippetDictionary,
  SnippetSource = SnippetSource,
  SnippetFileSource = SnippetFileSource,
  SnippetsFileSource = SnippetsFileSource,
  SnipMateFileSource = SnipMateFileSource,
  AddedSnippetsSource = AddedSnippetsSource,
  find_snippet_files = find_snippet_files,
  find_all_snippet_directories = find_all_snippet_directories,
  find_extra_snippet_files = find_extra_snippet_files,
  normalize_file_path = normalize_file_path,
}
