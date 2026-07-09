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
      winbar = "",
    },
  },
  terminal = {},
}

local config = vim.deepcopy(defaults)
local termclose_group = vim.api.nvim_create_augroup("codex.nvim.termclose", { clear = false })
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
  for _, arg in ipairs(opts.args or {}) do
    table.insert(cmd, arg)
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

local function set_window_winbar(win, winbar)
  if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
    return
  end

  if type(vim.api.nvim_set_option_value) == "function" then
    pcall(vim.api.nvim_set_option_value, "winbar", winbar, { win = win })
  else
    pcall(vim.api.nvim_win_set_option, win, "winbar", winbar)
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

local function remove_session_by_buf(buf)
  for cwd, state in pairs(sessions) do
    for count, terminal in pairs(state.terminals) do
      if type(terminal) == "table" and terminal.buf == buf then
        remove_session(cwd, count)
        return
      end
    end
  end
end

local function untrack_terminal(buf)
  local cwd
  local count
  local cwd_ok, cwd_var = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_cwd")
  if cwd_ok and type(cwd_var) == "string" then
    cwd = cwd_var
  end

  local count_ok, count_var = pcall(vim.api.nvim_buf_get_var, buf, "codex_nvim_count")
  if count_ok and type(count_var) == "number" then
    count = count_var
  end

  terminals[buf] = nil

  if cwd and count then
    remove_session(cwd, count)
  else
    remove_session_by_buf(buf)
  end
end

local function prune_state(cwd)
  local state = sessions[cwd]
  if not state then
    return nil
  end

  for index = #state.counts, 1, -1 do
    local count = state.counts[index]
    local terminal = state.terminals[count]
    if not terminal or not terminal_buf(terminal) then
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

local function open_session(opts, cwd, count, snacks_terminal)
  local terminal = snacks_terminal.toggle(build_command(opts), build_terminal_opts(opts, cwd, count))
  register_session(cwd, count, terminal)
  attach_termclose(terminal)
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
  attach_termclose(terminal)

  return terminal
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
      attach_termclose(terminal)
      return terminal
    end
  end

  return open_session(opts, cwd, count, snacks_terminal)
end

attach_termclose = function(terminal)
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
        untrack_terminal(buf)
        if type(terminal.close) == "function" then
          pcall(terminal.close, terminal)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
        pcall(vim.cmd.checktime)
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

  local state = prune_state(current.cwd)
  if state and not terminal_buf(current.terminal) then
    current.terminal = state.terminals[current.count]
  end

  local replacement
  local count = replacement_count(state, current.count)
  if count then
    replacement = show_existing_session(current.cwd, count)
  end

  terminals[current.buf] = nil
  remove_session(current.cwd, current.count)
  close_terminal_buffer(current.buf, current.terminal)

  return replacement or current.terminal or true
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

return M
