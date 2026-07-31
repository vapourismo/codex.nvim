local M = {}

local defaults = {
  command = "codex",
  args = {},
  cwd = function()
    return vim.fn.getcwd()
  end,
  count = 1,
  keys = {
    close = "<D-w>",
    new = "<D-n>",
    previous = "<D-{>",
    next = "<D-}>",
  },
  win = {
    position = "right",
    relative = "editor",
    width = 0.4,
    wo = {
      winhighlight = "Normal:NormalFloat",
      winbar = "",
      winfixwidth = false,
    },
  },
  terminal = {},
}

local config = vim.deepcopy(defaults)
local termclose_group = vim.api.nvim_create_augroup("codex.nvim.termclose", { clear = false })
local termrequest_group = vim.api.nvim_create_augroup("codex.nvim.termrequest", { clear = false })
local dirchanged_group = vim.api.nvim_create_augroup("codex.nvim.dirchanged", { clear = true })
local terminals = setmetatable({}, { __mode = "v" })
local sessions = {}

local function notify_error(message)
  vim.notify("[codex.nvim] " .. message, vim.log.levels.ERROR)
end

local function terminal_buf(terminal)
  if not terminal or type(terminal) ~= "table" or type(terminal.buf) ~= "number" then
    return nil
  end

  if not vim.api.nvim_buf_is_valid(terminal.buf) then
    return nil
  end

  return terminal.buf
end

local function terminal_is_codex(terminal)
  local buf = terminal_buf(terminal)
  if not buf then
    return false
  end

  local ok, marked = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_terminal")
  return ok and marked == true
end

local function terminal_is_visible(terminal)
  if type(terminal.valid) == "function" then
    local ok, valid = pcall(terminal.valid, terminal)
    if ok then
      return valid == true
    end
  end

  return type(terminal.win) == "number" and vim.api.nvim_win_is_valid(terminal.win)
end

local function terminal_is_in_current_tab(terminal)
  if type(terminal.win) ~= "number" or not vim.api.nvim_win_is_valid(terminal.win) then
    return true
  end

  return vim.api.nvim_win_get_tabpage(terminal.win) == vim.api.nvim_get_current_tabpage()
end

local function terminal_matches_dirchanged_scope(terminal, scope)
  if scope == "global" then
    return true
  end

  return terminal_is_in_current_tab(terminal)
end

local function track_terminal(terminal, cwd, count)
  local buf = terminal_buf(terminal)
  if not buf then
    return
  end

  terminals[buf] = terminal
  pcall(vim.api.nvim_buf_set_var, buf, "codex_nvim_terminal", true)
  if cwd then
    pcall(vim.api.nvim_buf_set_var, buf, "codex_nvim_cwd", cwd)
  end
  if count then
    pcall(vim.api.nvim_buf_set_var, buf, "codex_nvim_count", count)
  end
end

local function snacks_terminals()
  local snacks = package.loaded.snacks
  if type(snacks) ~= "table" or type(snacks.terminal) ~= "table" or type(snacks.terminal.list) ~= "function" then
    return {}
  end

  local list_ok, list = pcall(snacks.terminal.list)
  if not list_ok or type(list) ~= "table" then
    return {}
  end

  return list
end

local function hide_if_visible(terminal, scope)
  if
    terminal_is_codex(terminal)
    and terminal_is_visible(terminal)
    and terminal_matches_dirchanged_scope(terminal, scope)
    and type(terminal.hide) == "function"
  then
    pcall(terminal.hide, terminal)
  end
end

local function hide_visible_terminals(scope)
  local seen = {}

  for _, terminal in ipairs(snacks_terminals()) do
    local buf = terminal_buf(terminal)
    if buf then
      seen[buf] = true
      if terminal_is_codex(terminal) then
        terminals[buf] = terminal
        hide_if_visible(terminal, scope)
      end
    end
  end

  for buf, terminal in pairs(terminals) do
    if not terminal_is_codex(terminal) then
      terminals[buf] = nil
    elseif not seen[buf] then
      hide_if_visible(terminal, scope)
    end
  end
end

vim.api.nvim_create_autocmd("DirChanged", {
  group = dirchanged_group,
  callback = function(event)
    if type(vim.v.event) == "table" and vim.v.event.changed_window == true then
      return
    end

    local scope = event.match
    if type(vim.v.event) == "table" and type(vim.v.event.scope) == "string" then
      scope = vim.v.event.scope
    end
    hide_visible_terminals(scope)
  end,
})

local function validate(opts)
  opts = opts or {}

  if opts.command ~= nil and type(opts.command) ~= "string" then
    error("codex.nvim: command must be a string", 3)
  end

  if opts.args ~= nil then
    if type(opts.args) ~= "table" then
      error("codex.nvim: args must be a table", 3)
    end
    for i, arg in ipairs(opts.args) do
      if type(arg) ~= "string" then
        error(("codex.nvim: args[%d] must be a string"):format(i), 3)
      end
    end
  end

  if opts.cwd ~= nil and type(opts.cwd) ~= "string" and type(opts.cwd) ~= "function" then
    error("codex.nvim: cwd must be a string or function", 3)
  end

  if opts.count ~= nil and (type(opts.count) ~= "number" or opts.count < 1 or opts.count % 1 ~= 0) then
    error("codex.nvim: count must be a positive integer", 3)
  end

  if opts.on_notification ~= nil and type(opts.on_notification) ~= "function" then
    error("codex.nvim: on_notification must be a function", 3)
  end

  if opts.keys ~= nil and opts.keys ~= false then
    if type(opts.keys) ~= "table" then
      error("codex.nvim: keys must be a table or false", 3)
    end
    for name, lhs in pairs(opts.keys) do
      if lhs ~= false and type(lhs) ~= "string" then
        error(("codex.nvim: keys.%s must be a string or false"):format(name), 3)
      end
    end
  end

  if opts.win ~= nil and type(opts.win) ~= "table" then
    error("codex.nvim: win must be a table", 3)
  end

  if opts.terminal ~= nil and type(opts.terminal) ~= "table" then
    error("codex.nvim: terminal must be a table", 3)
  end
end

local function merge_options(base, opts)
  opts = opts or {}
  validate(opts)

  local merged = vim.tbl_deep_extend("force", {}, base or {}, opts)
  if opts.args ~= nil then
    merged.args = vim.deepcopy(opts.args)
  end

  return merged
end

local function normalize_cwd(cwd)
  local uv = vim.uv or vim.loop
  local ok, realpath = pcall(uv.fs_realpath, cwd)
  if ok and type(realpath) == "string" and realpath ~= "" then
    cwd = realpath
  elseif vim.fs and type(vim.fs.normalize) == "function" then
    cwd = vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))
  else
    cwd = vim.fn.fnamemodify(cwd, ":p")
  end

  if cwd ~= "/" then
    cwd = cwd:gsub("/+$", "")
  end

  return cwd
end

local function path_root_and_parts(path)
  path = path:gsub("\\", "/")

  local root
  local rest
  local server, share, unc_rest = path:match("^//([^/]+)/([^/]+)(.*)$")
  if server and share then
    root = "//" .. server .. "/" .. share
    rest = unc_rest
  else
    local drive, drive_rest = path:match("^([A-Za-z]:)(.*)$")
    if drive then
      root = drive:lower()
      rest = drive_rest
    elseif path:sub(1, 1) == "/" then
      root = "/"
      rest = path:sub(2)
    else
      return nil, nil
    end
  end

  local parts = {}
  for part in rest:gmatch("[^/]+") do
    table.insert(parts, part)
  end

  return root, parts
end

local function relative_path(cwd, path)
  local cwd_root, cwd_parts = path_root_and_parts(cwd)
  local path_root, path_parts = path_root_and_parts(path)
  if not cwd_root or not path_root or cwd_root:lower() ~= path_root:lower() then
    return nil
  end

  local case_insensitive = cwd_root ~= "/"
  local common = 0
  while common < #cwd_parts and common < #path_parts do
    local cwd_part = cwd_parts[common + 1]
    local path_part = path_parts[common + 1]
    if case_insensitive then
      cwd_part = cwd_part:lower()
      path_part = path_part:lower()
    end
    if cwd_part ~= path_part then
      break
    end
    common = common + 1
  end

  local parts = {}
  for _ = common + 1, #cwd_parts do
    table.insert(parts, "..")
  end
  for index = common + 1, #path_parts do
    table.insert(parts, path_parts[index])
  end

  return #parts == 0 and "." or table.concat(parts, "/")
end

local function resolve_cwd(cwd)
  if type(cwd) == "function" then
    local ok, resolved = pcall(cwd)
    if not ok then
      notify_error("cwd option failed: " .. tostring(resolved))
      return nil
    end
    cwd = resolved
  end

  if type(cwd) ~= "string" or cwd == "" then
    notify_error("cwd must resolve to a non-empty string")
    return nil
  end

  return normalize_cwd(cwd)
end

local function build_command(opts)
  local cmd = { opts.command }
  local notification_config = { "--config", 'tui.notification_method="osc9"' }
  local inserted_notification_config = false

  for _, arg in ipairs(opts.args or {}) do
    if arg == "--" and not inserted_notification_config then
      vim.list_extend(cmd, notification_config)
      inserted_notification_config = true
    end
    table.insert(cmd, arg)
  end

  if not inserted_notification_config then
    vim.list_extend(cmd, notification_config)
  end

  return cmd
end

local attach_termclose

local function get_snacks_terminal()
  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks) ~= "table" or type(snacks.terminal) ~= "table" or type(snacks.terminal.toggle) ~= "function" then
    notify_error("folke/snacks.nvim is required")
    return nil
  end

  return snacks.terminal
end

local function ensure_executable(command)
  if vim.fn.executable(command) ~= 1 then
    notify_error(("executable not found: %s"):format(command))
    return false
  end

  return true
end

local function codex_win_keys(keys)
  if keys == false then
    return {}
  end

  keys = keys or {}

  local specs = {}
  local function add(name, lhs, action, desc)
    if lhs == false or lhs == nil then
      return
    end

    specs["codex_" .. name] = {
      lhs,
      action,
      mode = { "n", "t" },
      desc = desc,
    }
  end

  add("new", keys.new, function()
    return M.new()
  end, "New Codex session")

  add("close", keys.close, function()
    return M.close()
  end, "Close Codex session")

  add("previous", keys.previous, function()
    return M.previous()
  end, "Previous Codex session")

  add("next", keys.next, function()
    return M.next()
  end, "Next Codex session")

  return specs
end

local function counts_with_selected(cwd, selected_count)
  local state = sessions[cwd]
  local counts = {}

  if state then
    for _, count in ipairs(state.counts) do
      table.insert(counts, count)
    end
  end

  if selected_count then
    local found = false
    for _, count in ipairs(counts) do
      if count == selected_count then
        found = true
        break
      end
    end
    if not found then
      table.insert(counts, selected_count)
    end
  end

  return counts
end

local function render_winbar(counts, selected_count)
  if #counts < 2 then
    return ""
  end

  local parts = {}

  for index, count in ipairs(counts) do
    local group = "TabLineNum"
    if count == selected_count then
      group = "TabLineNumSel"
    end
    table.insert(parts, ("%%#%s# %d %%*"):format(group, index))
  end

  return table.concat(parts, " ")
end

local function codex_winbar(cwd, selected_count)
  return render_winbar(counts_with_selected(cwd, selected_count), selected_count)
end

local function set_window_option(win, name, value)
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
    return
  end

  if type(vim.api.nvim_set_option_value) == "function" then
    pcall(vim.api.nvim_set_option_value, name, value, { win = win })
  else
    pcall(vim.api.nvim_win_set_option, win, name, value)
  end
end

local function set_window_winbar(win, winbar)
  set_window_option(win, "winbar", winbar)
end

local function preserve_window_option(win, name)
  local value = win.wo[name]
  local on_win = win.on_win

  win.on_win = function(snacks_win)
    if type(snacks_win) == "table" then
      if type(snacks_win.opts) == "table" then
        snacks_win.opts.wo = type(snacks_win.opts.wo) == "table" and snacks_win.opts.wo or {}
        snacks_win.opts.wo[name] = value
      end
      set_window_option(snacks_win.win, name, value)
    end

    if type(on_win) == "function" then
      return on_win(snacks_win)
    end
  end
end

local function refresh_cwd_winbars(cwd)
  local state = sessions[cwd]
  if not state then
    return
  end

  for _, count in ipairs(state.counts) do
    local terminal = state.terminals[count]
    if terminal_is_codex(terminal) and terminal_is_visible(terminal) then
      set_window_winbar(terminal.win, render_winbar(state.counts, count))
    end
  end
end

local function build_terminal_opts(opts, cwd, count)
  local win = vim.tbl_deep_extend("force", {}, opts.win or {})
  win.keys = vim.tbl_deep_extend("force", {}, win.keys or {}, codex_win_keys(opts.keys))
  local wo = {}
  if type(win.wo) == "table" then
    wo = vim.tbl_deep_extend("force", {}, win.wo)
  end
  win.wo = wo
  win.wo.winbar = codex_winbar(cwd, count)
  -- Snacks forces fixed dimensions for split windows after merging config.
  preserve_window_option(win, "winfixwidth")

  return vim.tbl_deep_extend("force", {}, opts.terminal or {}, {
    cwd = cwd,
    count = count,
    win = win,
    auto_close = false,
  })
end

local function state_for(cwd)
  local state = sessions[cwd]
  if not state then
    state = {
      active = nil,
      counts = {},
      terminals = {},
    }
    sessions[cwd] = state
  end
  return state
end

local function index_of_count(state, count)
  for index, existing in ipairs(state.counts) do
    if existing == count then
      return index
    end
  end
  return nil
end

local function add_count(state, count)
  if not index_of_count(state, count) then
    table.insert(state.counts, count)
  end
end

local function remove_session(cwd, count)
  local state = sessions[cwd]
  if not state then
    return
  end

  state.terminals[count] = nil
  local removed_index = index_of_count(state, count)
  if removed_index then
    table.remove(state.counts, removed_index)
  end

  if state.active == count then
    local fallback_index = removed_index or 1
    state.active = state.counts[fallback_index] or state.counts[fallback_index - 1] or state.counts[1]
  end

  if #state.counts == 0 then
    sessions[cwd] = nil
  else
    refresh_cwd_winbars(cwd)
  end
end

local function prune_state(cwd, preserved_session)
  local state = sessions[cwd]
  if not state then
    return nil
  end

  for index = #state.counts, 1, -1 do
    local count = state.counts[index]
    local terminal = state.terminals[count]
    local preserved = preserved_session
      and preserved_session.count == count
      and type(terminal) == "table"
      and terminal.buf == preserved_session.buf
    if not preserved and (not terminal or not terminal_buf(terminal)) then
      remove_session(cwd, count)
    end
  end

  return sessions[cwd]
end

local function replacement_count(state, closing_count)
  if not state or #state.counts == 0 then
    return nil
  end

  local closing_index = index_of_count(state, closing_count)
  if closing_index then
    for index = closing_index + 1, #state.counts do
      local count = state.counts[index]
      if count ~= closing_count and terminal_buf(state.terminals[count]) then
        return count
      end
    end

    for index = closing_index - 1, 1, -1 do
      local count = state.counts[index]
      if count ~= closing_count and terminal_buf(state.terminals[count]) then
        return count
      end
    end
  end

  for _, count in ipairs(state.counts) do
    if count ~= closing_count and terminal_buf(state.terminals[count]) then
      return count
    end
  end

  return nil
end

local function current_codex_session()
  local buf = vim.api.nvim_get_current_buf()
  local terminal = terminals[buf]
  local marked = terminal_is_codex(terminal)

  if not marked then
    local ok, value = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_terminal")
    marked = ok and value == true
  end

  if not marked then
    return nil
  end

  local cwd_ok, cwd = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_cwd")
  if not cwd_ok or type(cwd) ~= "string" or cwd == "" then
    return nil
  end

  local count_ok, count = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_count")
  if not count_ok or type(count) ~= "number" then
    return nil
  end

  if not terminal then
    local state = sessions[cwd]
    if state then
      terminal = state.terminals[count]
    end
  end

  return {
    buf = buf,
    cwd = cwd,
    count = count,
    terminal = terminal,
  }
end

local function allocate_count(state, first_count)
  local used = {}
  for _, count in ipairs(state.counts) do
    used[count] = true
  end

  local count = first_count
  while used[count] do
    count = count + 1
  end

  return count
end

local function current_codex_cwd()
  local buf = vim.api.nvim_get_current_buf()
  local terminal = terminals[buf]
  local marked = terminal_is_codex(terminal)

  if not marked then
    local ok, value = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_terminal")
    marked = ok and value == true
  end

  if not marked then
    return nil
  end

  local ok, cwd = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_cwd")
  if ok and type(cwd) == "string" and cwd ~= "" then
    return cwd
  end

  return nil
end

local function prepare(opts, cwd)
  local opts_merged = merge_options(config, opts)
  local snacks_terminal = get_snacks_terminal()
  if not snacks_terminal or not ensure_executable(opts_merged.command) then
    return nil, nil, nil
  end

  cwd = cwd or resolve_cwd(opts_merged.cwd)
  if not cwd then
    return nil, nil, nil
  end

  return opts_merged, cwd, snacks_terminal
end

local function prepare_for_current_session(opts)
  local opts_merged = merge_options(config, opts)
  local snacks_terminal = get_snacks_terminal()
  if not snacks_terminal or not ensure_executable(opts_merged.command) then
    return nil, nil, nil
  end

  local cwd
  if not (type(opts) == "table" and opts.cwd ~= nil) then
    cwd = current_codex_cwd()
  end
  cwd = cwd or resolve_cwd(opts_merged.cwd)
  if not cwd then
    return nil, nil, nil
  end

  return opts_merged, cwd, snacks_terminal
end

local function register_session(cwd, count, terminal)
  if not terminal_buf(terminal) then
    return terminal
  end

  local state = state_for(cwd)
  add_count(state, count)
  state.terminals[count] = terminal
  state.active = count
  track_terminal(terminal, cwd, count)
  refresh_cwd_winbars(cwd)

  return terminal
end

local OSC9_PREFIX = "\27]9;"

local function termrequest_sequence(data)
  if type(data) == "string" then
    return data
  end
  if type(data) == "table" and type(data.sequence) == "string" then
    return data.sequence
  end
  return nil
end

local function osc9_message(sequence)
  if type(sequence) ~= "string" or sequence:sub(1, #OSC9_PREFIX) ~= OSC9_PREFIX then
    return nil
  end

  local message = sequence:sub(#OSC9_PREFIX + 1)
  if message:sub(-1) == "\7" then
    message = message:sub(1, -2)
  elseif message:sub(-2) == "\27\\" then
    message = message:sub(1, -3)
  end
  return message
end

local function attach_termrequest(terminal, cwd, count, on_notification)
  local buf = terminal_buf(terminal)
  if not buf then
    return
  end

  local ok, attached = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_termrequest")
  if ok and attached then
    return
  end

  vim.api.nvim_create_autocmd("TermRequest", {
    group = termrequest_group,
    buffer = buf,
    desc = "Handle Codex OSC 9 notifications",
    callback = function(event)
      local message = osc9_message(termrequest_sequence(event.data))
      if message == nil then
        return
      end

      on_notification({
        method = "osc9",
        message = message,
        buf = buf,
        cwd = cwd,
        count = count,
      })
    end,
  })
  pcall(vim.api.nvim_buf_set_var, buf, "codex_nvim_termrequest", true)
end

local function open_session(opts, cwd, count, snacks_terminal)
  local command = build_command(opts)
  local terminal = snacks_terminal.toggle(command, build_terminal_opts(opts, cwd, count))
  register_session(cwd, count, terminal)
  if type(opts.on_notification) == "function" then
    attach_termrequest(terminal, cwd, count, opts.on_notification)
  end
  attach_termclose(terminal, cwd, count)
  return terminal
end

local function show_existing_session(cwd, count)
  local state = sessions[cwd]
  if not state then
    return nil
  end

  local terminal = state.terminals[count]
  if not terminal_buf(terminal) then
    return nil
  end

  hide_visible_terminals("tab")

  if type(terminal.show) == "function" then
    local ok, shown = pcall(terminal.show, terminal)
    if ok then
      terminal = shown or terminal
    end
  end

  if type(terminal.focus) == "function" then
    pcall(terminal.focus, terminal)
  end

  register_session(cwd, count, terminal)
  attach_termclose(terminal, cwd, count)

  return terminal
end

local function selection_position(buf, position, linewise)
  if type(position) ~= "table" then
    return nil
  end

  local position_buf = tonumber(position[1])
  local line = tonumber(position[2])
  local column = tonumber(position[3])
  if
    not position_buf
    or (position_buf ~= 0 and position_buf ~= buf)
    or not line
    or line < 1
    or line > vim.api.nvim_buf_line_count(buf)
  then
    return nil
  end

  if linewise then
    return { line = line, column = 1 }
  end

  if not column or column < 1 then
    return nil
  end

  local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, true)[1]
  if text == nil then
    return nil
  end

  local max_column = math.max(#text, 1)
  if column == vim.v.maxcol then
    column = max_column
  elseif column > max_column then
    return nil
  end

  return { line = line, column = column, line_length = #text }
end

local function visual_selection(command)
  local mode
  local start_position
  local end_position

  if command then
    if command.range ~= 2 then
      notify_error("CodexReference must be called from Visual mode")
      return nil
    end

    mode = vim.fn.visualmode()
    start_position = vim.fn.getpos("'<")
    end_position = vim.fn.getpos("'>")
    if
      type(command.line1) ~= "number"
      or type(command.line2) ~= "number"
      or start_position[2] ~= command.line1
      or end_position[2] ~= command.line2
    then
      notify_error("CodexReference must be called from Visual mode")
      return nil
    end
  else
    mode = vim.fn.mode(1)
    start_position = vim.fn.getpos("v")
    end_position = vim.fn.getpos(".")
  end

  if mode == "\22" then
    notify_error("blockwise selections are not supported")
    return nil
  end
  if mode ~= "v" and mode ~= "V" then
    notify_error("a characterwise or linewise visual selection is required")
    return nil
  end

  local buf = vim.api.nvim_get_current_buf()
  local linewise = mode == "V"
  local first = selection_position(buf, start_position, linewise)
  local last = selection_position(buf, end_position, linewise)
  if not first or not last then
    notify_error("visual selection is missing or invalid")
    return nil
  end

  if first.line > last.line or (first.line == last.line and first.column > last.column) then
    first, last = last, first
  end

  return {
    buf = buf,
    linewise = linewise,
    first = first,
    last = last,
  }
end

local function selection_reference(selection, cwd)
  local name = vim.api.nvim_buf_get_name(selection.buf)
  if name == "" then
    notify_error("visual selection must be in a named buffer")
    return nil
  end

  local path = normalize_cwd(vim.fn.fnamemodify(name, ":p"))
  local relative = relative_path(cwd, path)
  if not relative then
    notify_error("buffer and Codex cwd are on incompatible filesystem roots")
    return nil
  end

  local first = selection.first
  local last = selection.last
  local linewise = selection.linewise
    or (first.column == 1 and last.column == math.max(last.line_length, 1))

  if linewise then
    if first.line == last.line then
      return ("%s:%d"):format(relative, first.line)
    end
    return ("%s:%d-%d"):format(relative, first.line, last.line)
  end

  return ("%s:%d:%d-%d:%d"):format(relative, first.line, first.column, last.line, last.column)
end

local function terminal_channel(terminal)
  local buf = terminal_buf(terminal)
  if not buf then
    return nil
  end

  local ok, channel
  if type(vim.api.nvim_get_option_value) == "function" then
    ok, channel = pcall(vim.api.nvim_get_option_value, "channel", { buf = buf })
  else
    ok, channel = pcall(vim.api.nvim_buf_get_option, buf, "channel")
  end

  if not ok or type(channel) ~= "number" or channel < 1 or channel % 1 ~= 0 then
    return nil
  end

  return channel
end

local function close_terminal_buffer(buf, terminal)
  if type(terminal) == "table" and type(terminal.close) == "function" then
    pcall(terminal.close, terminal)
  end

  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  pcall(vim.cmd.checktime)
end

local function close_session(session)
  local state = prune_state(session.cwd, session)
  local tracked = state and state.terminals[session.count] or nil
  local is_tracked = state
    and index_of_count(state, session.count)
    and type(tracked) == "table"
    and tracked.buf == session.buf

  if not is_tracked then
    terminals[session.buf] = nil
    if vim.api.nvim_buf_is_valid(session.buf) then
      close_terminal_buffer(session.buf, session.terminal)
    end
    return session.terminal or true
  end

  session.terminal = tracked

  local replacement
  local count = replacement_count(state, session.count)
  if count then
    replacement = show_existing_session(session.cwd, count)
  end

  terminals[session.buf] = nil
  remove_session(session.cwd, session.count)
  close_terminal_buffer(session.buf, session.terminal)

  return replacement or session.terminal or true
end

local function show_session(opts, cwd, count, snacks_terminal)
  local state = state_for(cwd)
  local terminal = state.terminals[count]

  hide_visible_terminals("tab")

  if terminal_buf(terminal) and type(terminal.show) == "function" then
    local ok, shown = pcall(terminal.show, terminal)
    if ok then
      terminal = shown or terminal
      if type(terminal.focus) == "function" then
        pcall(terminal.focus, terminal)
      end
      register_session(cwd, count, terminal)
      attach_termclose(terminal, cwd, count)
      return terminal
    end
  end

  return open_session(opts, cwd, count, snacks_terminal)
end

attach_termclose = function(terminal, cwd, count)
  if not terminal or type(terminal) ~= "table" or not terminal.buf then
    return
  end

  local buf = terminal.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  track_terminal(terminal)

  local ok, attached = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_termclose")
  if ok and attached then
    return
  end
  pcall(vim.api.nvim_buf_set_var, buf, "codex_nvim_termclose", true)

  vim.api.nvim_create_autocmd("TermClose", {
    group = termclose_group,
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        close_session({
          buf = buf,
          cwd = cwd,
          count = count,
          terminal = terminal,
        })
      end)
    end,
  })
end

function M.setup(opts)
  config = merge_options(defaults, opts)
  return M
end

function M.deactivate()
  pcall(vim.api.nvim_del_user_command, "CodexToggle")
  pcall(vim.api.nvim_del_user_command, "CodexNew")
  pcall(vim.api.nvim_del_user_command, "CodexClose")
  pcall(vim.api.nvim_del_user_command, "CodexPrevious")
  pcall(vim.api.nvim_del_user_command, "CodexNext")
  pcall(vim.api.nvim_del_user_command, "CodexReference")
  vim.g.loaded_codex = nil
  vim.g.loaded_codex_nvim = nil
  config = vim.deepcopy(defaults)
  terminals = setmetatable({}, { __mode = "v" })
  sessions = {}
  return M
end

function M.toggle(opts)
  local opts_merged, cwd, snacks_terminal = prepare(opts)
  if not opts_merged then
    return nil
  end

  local state = prune_state(cwd) or state_for(cwd)
  local count = state.active
  if not count or not index_of_count(state, count) then
    count = allocate_count(state, opts_merged.count)
  end

  return open_session(opts_merged, cwd, count, snacks_terminal)
end

function M.new(opts)
  local opts_merged, cwd, snacks_terminal = prepare_for_current_session(opts)
  if not opts_merged then
    return nil
  end

  local state = prune_state(cwd) or state_for(cwd)
  local count = allocate_count(state, opts_merged.count)

  hide_visible_terminals("tab")
  return open_session(opts_merged, cwd, count, snacks_terminal)
end

function M.close()
  local current = current_codex_session()
  if not current then
    return nil
  end

  return close_session(current)
end

local function navigate(opts, delta)
  local opts_merged, cwd, snacks_terminal = prepare_for_current_session(opts)
  if not opts_merged then
    return nil
  end

  local state = prune_state(cwd)
  if not state or #state.counts == 0 then
    state = state_for(cwd)
    local count = allocate_count(state, opts_merged.count)
    return open_session(opts_merged, cwd, count, snacks_terminal)
  end

  local active = state.active or state.counts[1]
  local index = index_of_count(state, active) or 1
  local target = ((index - 1 + delta) % #state.counts) + 1
  local count = state.counts[target]

  state.active = count
  return show_session(opts_merged, cwd, count, snacks_terminal)
end

function M.previous(opts)
  return navigate(opts, -1)
end

function M.next(opts)
  return navigate(opts, 1)
end

function M.reference(opts)
  local command = type(opts) == "table" and opts._command or nil
  local selection = visual_selection(command)
  if not selection then
    return nil
  end

  local cwd = resolve_cwd(config.cwd)
  if not cwd then
    return nil
  end

  local reference = selection_reference(selection, cwd)
  if not reference then
    return nil
  end

  local state = prune_state(cwd)
  local count = state and state.active or nil
  if not count or not terminal_buf(state.terminals[count]) then
    notify_error("no active Codex session exists for the configured directory")
    return nil
  end

  local terminal = show_existing_session(cwd, count)
  if not terminal then
    notify_error("no active Codex session exists for the configured directory")
    return nil
  end

  local channel = terminal_channel(terminal)
  if not channel then
    notify_error("active Codex terminal has no valid channel")
    return nil
  end

  local ok, err = pcall(vim.api.nvim_chan_send, channel, reference)
  if not ok then
    notify_error("failed to send reference to Codex terminal: " .. tostring(err))
    return nil
  end

  return terminal
end

return M
