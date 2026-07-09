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
  },
  terminal = {},
}

local config = vim.deepcopy(defaults)
local termclose_group = vim.api.nvim_create_augroup("codex.nvim.termclose", { clear = true })

local function notify_error(message)
  vim.notify("[codex.nvim] " .. message, vim.log.levels.ERROR)
end

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
