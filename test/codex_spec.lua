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
local original_cwd = vim.fn.getcwd()

local calls = {}
local terminals = {}
package.loaded.snacks = {
  terminal = {
    toggle = function(cmd, opts)
      calls[#calls + 1] = {
        cmd = vim.deepcopy(cmd),
        opts = vim.deepcopy(opts),
      }
      local terminal = {
        buf = vim.api.nvim_create_buf(false, true),
        visible = true,
        win = vim.api.nvim_get_current_win(),
        valid = function(self)
          return self.visible
        end,
        hide = function(self)
          self.hidden = (self.hidden or 0) + 1
          self.visible = false
        end,
        close = function(self)
          self.closed = true
          self.visible = false
        end,
      }
      terminals[#terminals + 1] = terminal
      return terminal
    end,
  },
}

vim.cmd.runtime("plugin/codex.lua")
assert_eq(vim.fn.exists(":CodexToggle"), 2, ":CodexToggle command should exist")
assert_eq(vim.g.loaded_codex, 1, "Lazy-compatible loaded guard should be set")
assert_eq(vim.g.loaded_codex_nvim, nil, "legacy loaded guard should not be set")

vim.g.loaded_codex = nil
vim.cmd.runtime("plugin/codex.lua")
assert_eq(vim.fn.exists(":CodexToggle"), 2, "manual re-source should preserve :CodexToggle")
assert_eq(vim.g.loaded_codex, 1, "manual re-source should restore loaded guard")

local codex = require("codex")
assert_eq(type(codex.setup), "function", "setup should be a function")
assert_eq(type(codex.toggle), "function", "toggle should be a function")
assert_eq(type(codex.deactivate), "function", "deactivate should be a function")

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
assert_eq(calls[1].opts.win.wo.winbar, "", "default terminal winbar should be empty")

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
assert_eq(calls[2].opts.win.wo.winbar, "", "default winbar should be preserved when win config merges")
assert_eq(calls[2].opts.env.CODEX_TEST, "1", "terminal config should be merged")
assert_eq(calls[2].opts.start_insert, false, "terminal options should be passed through")
assert_eq(calls[2].opts.auto_insert, false, "per-call terminal options should be merged")
assert_eq(calls[2].opts.auto_close, false, "Snacks auto_close should stay disabled")

codex.toggle({
  win = {
    wo = {
      winbar = "Codex",
    },
  },
})

assert_eq(#calls, 3, "third toggle should call Snacks again")
assert_eq(calls[3].opts.win.wo.winbar, "Codex", "per-call winbar should override the empty default")

vim.g.loaded_codex_nvim = 1

local deactivate_ok, deactivate_return = pcall(codex.deactivate)
assert_eq(deactivate_ok, true, "deactivate should not throw")
assert_eq(deactivate_return, codex, "deactivate should return the module table")
assert_eq(vim.fn.exists(":CodexToggle"), 0, "deactivate should remove :CodexToggle")
assert_eq(vim.g.loaded_codex, nil, "deactivate should clear Lazy-compatible loaded guard")
assert_eq(vim.g.loaded_codex_nvim, nil, "deactivate should clear legacy loaded guard")
assert_eq(terminals[1].closed, nil, "deactivate should not close existing terminals")
assert_eq(vim.api.nvim_buf_is_valid(terminals[1].buf), true, "deactivate should preserve terminal buffers")

codex.toggle()

assert_eq(#calls, 4, "toggle should still work after deactivate")
assert_list(calls[4].cmd, { "codex" }, "deactivate should reset configured args")
assert_eq(calls[4].opts.cwd, vim.fn.getcwd(), "deactivate should reset cwd")
assert_eq(calls[4].opts.count, 1, "deactivate should reset count")
assert_eq(calls[4].opts.win.position, "right", "deactivate should reset win position")
assert_eq(calls[4].opts.win.width, 0.4, "deactivate should reset win width")

local deactivate_again_ok, deactivate_again_return = pcall(codex.deactivate)
assert_eq(deactivate_again_ok, true, "deactivate should be idempotent")
assert_eq(deactivate_again_return, codex, "idempotent deactivate should return the module table")
assert_eq(terminals[4].closed, nil, "idempotent deactivate should not close existing terminals")
assert_eq(vim.api.nvim_buf_is_valid(terminals[4].buf), true, "idempotent deactivate should preserve terminal buffers")

package.loaded.codex = nil
vim.cmd.runtime("plugin/codex.lua")

assert_eq(vim.fn.exists(":CodexToggle"), 2, "reload should restore :CodexToggle")
assert_eq(vim.g.loaded_codex, 1, "reload should restore loaded guard")

local reloaded_codex = require("codex")
assert_eq(type(reloaded_codex.setup), "function", "reloaded setup should be a function")
assert_eq(type(reloaded_codex.toggle), "function", "reloaded toggle should be a function")
assert_eq(type(reloaded_codex.deactivate), "function", "reloaded deactivate should be a function")

reloaded_codex.setup()
reloaded_codex.toggle()

assert_eq(#calls, 5, "toggle should work after simulated reload")
assert_list(calls[5].cmd, { "codex" }, "reloaded default command should be codex")
assert_eq(calls[5].opts.cwd, vim.fn.getcwd(), "reloaded default cwd should resolve to current working directory")
assert_eq(calls[5].opts.count, 1, "reloaded default count should be stable")
assert_eq(calls[5].opts.win.position, "right", "reloaded terminal should open on the right")
assert_eq(calls[5].opts.win.width, 0.4, "reloaded terminal width should be 40 percent")

local changed_cwd = vim.fn.tempname()
vim.fn.mkdir(changed_cwd, "p")
vim.cmd("tcd " .. vim.fn.fnameescape(changed_cwd))
local resolved_changed_cwd = vim.fn.getcwd()

assert_eq(terminals[5].hidden, 1, "DirChanged should hide visible Codex terminals")
assert_eq(terminals[5].closed, nil, "DirChanged should not close Codex terminals")
assert_eq(vim.api.nvim_buf_is_valid(terminals[5].buf), true, "DirChanged should preserve terminal buffers")

reloaded_codex.toggle()

assert_eq(#calls, 6, "toggle should still create the cwd-targeted terminal after tcd")
assert_eq(calls[6].opts.cwd, resolved_changed_cwd, "toggle after tcd should use the new tab cwd")

vim.cmd("tcd " .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(changed_cwd, "rf")
vim.env.PATH = old_path
vim.fn.delete(tmp, "rf")

print("codex.nvim smoke tests passed")
