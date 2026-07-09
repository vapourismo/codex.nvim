vim.opt.runtimepath:append(vim.fn.getcwd())

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(("%s\nexpected: %s\nactual: %s"):format(message or "assertion failed", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function assert_list(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\nactual: %s"):format(message or "lists differ", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, tmp .. "/codex")
vim.fn.setfperm(tmp .. "/codex", "rwxr-xr-x")

local old_path = vim.env.PATH
vim.env.PATH = tmp .. ":" .. old_path

local calls = {}
package.loaded.snacks = {
  terminal = {
    toggle = function(cmd, opts)
      calls[#calls + 1] = {
        cmd = vim.deepcopy(cmd),
        opts = vim.deepcopy(opts),
      }
      return {
        buf = vim.api.nvim_create_buf(false, true),
        close = function(self)
          self.closed = true
        end,
      }
    end,
  },
}

vim.cmd.runtime("plugin/codex.lua")
assert_eq(vim.fn.exists(":CodexToggle"), 2, ":CodexToggle command should exist")

local codex = require("codex")
assert_eq(type(codex.setup), "function", "setup should be a function")
assert_eq(type(codex.toggle), "function", "toggle should be a function")

codex.setup()
codex.toggle()

assert_eq(#calls, 1, "toggle should call Snacks once")
assert_list(calls[1].cmd, { "codex" }, "default command should be codex")
assert_eq(calls[1].opts.cwd, vim.fn.getcwd(), "default cwd should resolve to current working directory")
assert_eq(calls[1].opts.count, 1, "default count should be stable")
assert_eq(calls[1].opts.auto_close, false, "custom TermClose handling should disable Snacks auto_close")
assert_eq(calls[1].opts.win.position, "right", "default terminal should open on the right")
assert_eq(calls[1].opts.win.relative, "editor", "default terminal should be editor-relative")
assert_eq(calls[1].opts.win.width, 0.4, "default terminal width should be 40 percent")

codex.setup({
  command = "codex",
  args = { "--model", "gpt-5" },
  cwd = function()
    return "/tmp"
  end,
  count = 4,
  win = { width = 0.5 },
  terminal = {
    env = { CODEX_TEST = "1" },
    start_insert = false,
  },
})

codex.toggle({
  args = { "exec", "hello" },
  cwd = "/tmp/project",
  win = { position = "left" },
  terminal = { auto_insert = false },
})

assert_eq(#calls, 2, "second toggle should call Snacks again")
assert_list(calls[2].cmd, { "codex", "exec", "hello" }, "per-call args should replace configured args")
assert_eq(calls[2].opts.cwd, "/tmp/project", "per-call cwd should win")
assert_eq(calls[2].opts.count, 4, "configured count should be passed to Snacks")
assert_eq(calls[2].opts.win.position, "left", "per-call win config should merge")
assert_eq(calls[2].opts.win.width, 0.5, "configured win config should be preserved")
assert_eq(calls[2].opts.env.CODEX_TEST, "1", "terminal config should be merged")
assert_eq(calls[2].opts.start_insert, false, "terminal options should be passed through")
assert_eq(calls[2].opts.auto_insert, false, "per-call terminal options should be merged")
assert_eq(calls[2].opts.auto_close, false, "Snacks auto_close should stay disabled")

vim.env.PATH = old_path
vim.fn.delete(tmp, "rf")

print("codex.nvim smoke tests passed")
