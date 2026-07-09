local M = {}

local defaults = {
  command = "codex",
  args = {},
  cwd = function()
    return vim.fn.getcwd()
  end,
  count = 1,
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

local function track_terminal(terminal)
  local buf = terminal_buf(terminal)
  if not buf then
    return
  end

  terminals[buf] = terminal
  pcall(vim.api.nvim_buf_set_var, buf, "codex_nvim_terminal", true)
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

  return cwd
end

local function build_command(opts)
  local cmd = { opts.command }
  for _, arg in ipairs(opts.args or {}) do
    table.insert(cmd, arg)
  end
  return cmd
end

local function attach_termclose(terminal)
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
        terminals[buf] = nil
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
  vim.g.loaded_codex = nil
  vim.g.loaded_codex_nvim = nil
  config = vim.deepcopy(defaults)
  return M
end

function M.toggle(opts)
  local opts_merged = merge_options(config, opts)

  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks) ~= "table" or type(snacks.terminal) ~= "table" or type(snacks.terminal.toggle) ~= "function" then
    notify_error("folke/snacks.nvim is required")
    return nil
  end

  if vim.fn.executable(opts_merged.command) ~= 1 then
    notify_error(("executable not found: %s"):format(opts_merged.command))
    return nil
  end

  local cwd = resolve_cwd(opts_merged.cwd)
  if not cwd then
    return nil
  end

  local win = vim.tbl_deep_extend("force", {}, opts_merged.win or {})
  local terminal_opts = vim.tbl_deep_extend("force", {}, opts_merged.terminal or {}, {
    cwd = cwd,
    count = opts_merged.count,
    win = win,
    auto_close = false,
  })

  local terminal = snacks.terminal.toggle(build_command(opts_merged), terminal_opts)
  attach_termclose(terminal)
  return terminal
end

return M
