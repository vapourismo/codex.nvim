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

local function assert_truthy(actual, message)
  if not actual then
    error(("%s\nactual: %s"):format(message or "expected truthy value", vim.inspect(actual)), 2)
  end
end

local function codex_winbar(selected, total)
  local parts = {}

  for index = 1, total do
    local group = index == selected and "TabLineNumSel" or "TabLineNum"
    table.insert(parts, ("%%#%s# %d %%*"):format(group, index))
  end

  return table.concat(parts, " ")
end

local function normalize_cwd(cwd)
  local uv = vim.uv or vim.loop
  local ok, realpath = pcall(uv.fs_realpath, cwd)
  if ok and type(realpath) == "string" and realpath ~= "" then
    cwd = realpath
  elseif vim.fs and type(vim.fs.normalize) == "function" then
    cwd = vim.fs.normalize(cwd)
  else
    cwd = vim.fn.fnamemodify(cwd, ":p")
  end
  if cwd ~= "/" then
    cwd = cwd:gsub("/+$", "")
  end
  return cwd
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, tmp .. "/codex")
vim.fn.setfperm(tmp .. "/codex", "rwxr-xr-x")

local old_path = vim.env.PATH
vim.env.PATH = tmp .. ":" .. old_path
local original_cwd = normalize_cwd(vim.fn.getcwd())

local calls = {}
local terminals = {}
local terminal_by_id = {}

local function terminal_id(cmd, opts)
  return vim.inspect({
    cmd = cmd,
    cwd = opts.cwd,
    env = opts.env,
    count = opts.count,
  })
end

local function reset_fake_snacks()
  calls = {}
  terminals = {}
  terminal_by_id = {}
end

package.loaded.snacks = {
  terminal = {
    toggle = function(cmd, opts)
      calls[#calls + 1] = {
        cmd = vim.deepcopy(cmd),
        opts = vim.deepcopy(opts),
      }

      local id = terminal_id(cmd, opts)
      local existing = terminal_by_id[id]
      if existing and vim.api.nvim_buf_is_valid(existing.buf) then
        if existing.visible then
          existing:hide()
        else
          existing:show()
        end
        return existing
      end

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
        show = function(self)
          self.shown = (self.shown or 0) + 1
          self.visible = true
          self.win = vim.api.nvim_get_current_win()
          return self
        end,
        focus = function(self)
          self.focused = (self.focused or 0) + 1
        end,
        close = function(self)
          self.closed = true
          self.visible = false
        end,
      }
      terminal_by_id[id] = terminal
      terminals[#terminals + 1] = terminal
      return terminal
    end,
    list = function()
      local listed = {}
      for _, terminal in ipairs(terminals) do
        if vim.api.nvim_buf_is_valid(terminal.buf) then
          listed[#listed + 1] = terminal
        end
      end
      return listed
    end,
  },
}

vim.cmd.runtime("plugin/codex.lua")
assert_eq(vim.fn.exists(":CodexToggle"), 2, ":CodexToggle command should exist")
assert_eq(vim.fn.exists(":CodexNew"), 2, ":CodexNew command should exist")
assert_eq(vim.fn.exists(":CodexPrevious"), 2, ":CodexPrevious command should exist")
assert_eq(vim.fn.exists(":CodexNext"), 2, ":CodexNext command should exist")
assert_eq(vim.g.loaded_codex, 1, "Lazy-compatible loaded guard should be set")
assert_eq(vim.g.loaded_codex_nvim, nil, "legacy loaded guard should not be set")

vim.g.loaded_codex = nil
vim.cmd.runtime("plugin/codex.lua")
assert_eq(vim.fn.exists(":CodexToggle"), 2, "manual re-source should preserve :CodexToggle")
assert_eq(vim.fn.exists(":CodexNew"), 2, "manual re-source should preserve :CodexNew")
assert_eq(vim.fn.exists(":CodexPrevious"), 2, "manual re-source should preserve :CodexPrevious")
assert_eq(vim.fn.exists(":CodexNext"), 2, "manual re-source should preserve :CodexNext")
assert_eq(vim.g.loaded_codex, 1, "manual re-source should restore loaded guard")

local codex = require("codex")
assert_eq(type(codex.setup), "function", "setup should be a function")
assert_eq(type(codex.toggle), "function", "toggle should be a function")
assert_eq(type(codex.new), "function", "new should be a function")
assert_eq(type(codex.previous), "function", "previous should be a function")
assert_eq(type(codex.next), "function", "next should be a function")
assert_eq(type(codex.deactivate), "function", "deactivate should be a function")

codex.setup()
codex.toggle()

assert_eq(#calls, 1, "toggle should call Snacks once")
assert_list(calls[1].cmd, { "codex" }, "default command should be codex")
assert_eq(calls[1].opts.cwd, original_cwd, "default cwd should resolve to current working directory")
assert_eq(calls[1].opts.count, 1, "default count should be stable")
assert_eq(calls[1].opts.auto_close, false, "custom TermClose handling should disable Snacks auto_close")
assert_eq(calls[1].opts.win.position, "right", "default terminal should open on the right")
assert_eq(calls[1].opts.win.relative, "editor", "default terminal should be editor-relative")
assert_eq(calls[1].opts.win.width, 0.4, "default terminal width should be 40 percent")
assert_eq(type(calls[1].opts.win.wo.winbar), "string", "Codex winbar should be a static string")
assert_eq(calls[1].opts.win.wo.winbar:find("%{", 1, true), nil, "Codex winbar should not be an expression")
assert_eq(calls[1].opts.win.wo.winbar, codex_winbar(1, 1), "default terminal winbar should show session 1")
assert_eq(calls[1].opts.win.keys.codex_new[1], "<D-n>", "default new key should be installed")
assert_eq(calls[1].opts.win.keys.codex_previous[1], "<D-{>", "default previous key should be installed")
assert_eq(calls[1].opts.win.keys.codex_next[1], "<D-}>", "default next key should be installed")
assert_list(calls[1].opts.win.keys.codex_new.mode, { "n", "t" }, "Codex keys should be normal and terminal mode")
assert_eq(type(calls[1].opts.win.keys.codex_new[2]), "function", "Codex key rhs should be callable")

codex.setup({
  command = "codex",
  args = { "--model", "gpt-5" },
  cwd = function()
    return "/tmp"
  end,
  count = 4,
  keys = {
    new = "<leader>cn",
    previous = false,
    next = "<leader>cN",
  },
  win = {
    width = 0.5,
    keys = {
      q = "hide",
    },
  },
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
assert_eq(calls[2].opts.cwd, normalize_cwd("/tmp/project"), "per-call cwd should win")
assert_eq(calls[2].opts.count, 4, "configured count should be passed to Snacks")
assert_eq(calls[2].opts.win.position, "left", "per-call win config should merge")
assert_eq(calls[2].opts.win.width, 0.5, "configured win config should be preserved")
assert_eq(calls[2].opts.win.wo.winbar, codex_winbar(1, 1), "Codex winbar should be generated when win config merges")
assert_eq(calls[2].opts.win.keys.q, "hide", "user Snacks keys should be preserved")
assert_eq(calls[2].opts.win.keys.codex_new[1], "<leader>cn", "custom new key should be installed")
assert_eq(calls[2].opts.win.keys.codex_previous, nil, "false should disable a Codex key")
assert_eq(calls[2].opts.win.keys.codex_next[1], "<leader>cN", "custom next key should be installed")
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
assert_eq(calls[3].opts.win.wo.winbar, codex_winbar(1, 1), "Codex should reserve and override per-call winbar")

vim.g.loaded_codex_nvim = 1

local deactivate_ok, deactivate_return = pcall(codex.deactivate)
assert_eq(deactivate_ok, true, "deactivate should not throw")
assert_eq(deactivate_return, codex, "deactivate should return the module table")
assert_eq(vim.fn.exists(":CodexToggle"), 0, "deactivate should remove :CodexToggle")
assert_eq(vim.fn.exists(":CodexNew"), 0, "deactivate should remove :CodexNew")
assert_eq(vim.fn.exists(":CodexPrevious"), 0, "deactivate should remove :CodexPrevious")
assert_eq(vim.fn.exists(":CodexNext"), 0, "deactivate should remove :CodexNext")
assert_eq(vim.g.loaded_codex, nil, "deactivate should clear Lazy-compatible loaded guard")
assert_eq(vim.g.loaded_codex_nvim, nil, "deactivate should clear legacy loaded guard")
assert_eq(terminals[1].closed, nil, "deactivate should not close existing terminals")
assert_eq(vim.api.nvim_buf_is_valid(terminals[1].buf), true, "deactivate should preserve terminal buffers")

codex.toggle()

assert_eq(#calls, 4, "toggle should still work after deactivate")
assert_list(calls[4].cmd, { "codex" }, "deactivate should reset configured args")
assert_eq(calls[4].opts.cwd, original_cwd, "deactivate should reset cwd")
assert_eq(calls[4].opts.count, 1, "deactivate should reset count")
assert_eq(calls[4].opts.win.position, "right", "deactivate should reset win position")
assert_eq(calls[4].opts.win.width, 0.4, "deactivate should reset win width")
assert_eq(calls[4].opts.win.wo.winbar, codex_winbar(1, 1), "deactivate should reset to the Codex winbar")
assert_eq(calls[4].opts.win.keys.codex_new[1], "<D-n>", "deactivate should reset keys")

local deactivate_again_ok, deactivate_again_return = pcall(codex.deactivate)
assert_eq(deactivate_again_ok, true, "deactivate should be idempotent")
assert_eq(deactivate_again_return, codex, "idempotent deactivate should return the module table")
assert_eq(terminals[1].closed, nil, "idempotent deactivate should not close existing terminals")
assert_eq(vim.api.nvim_buf_is_valid(terminals[1].buf), true, "idempotent deactivate should preserve terminal buffers")

package.loaded.codex = nil
vim.cmd.runtime("plugin/codex.lua")

assert_eq(vim.fn.exists(":CodexToggle"), 2, "reload should restore :CodexToggle")
assert_eq(vim.fn.exists(":CodexNew"), 2, "reload should restore :CodexNew")
assert_eq(vim.fn.exists(":CodexPrevious"), 2, "reload should restore :CodexPrevious")
assert_eq(vim.fn.exists(":CodexNext"), 2, "reload should restore :CodexNext")
assert_eq(vim.g.loaded_codex, 1, "reload should restore loaded guard")

local reloaded_codex = require("codex")
assert_eq(type(reloaded_codex.setup), "function", "reloaded setup should be a function")
assert_eq(type(reloaded_codex.toggle), "function", "reloaded toggle should be a function")
assert_eq(type(reloaded_codex.new), "function", "reloaded new should be a function")
assert_eq(type(reloaded_codex.previous), "function", "reloaded previous should be a function")
assert_eq(type(reloaded_codex.next), "function", "reloaded next should be a function")
assert_eq(type(reloaded_codex.deactivate), "function", "reloaded deactivate should be a function")

reset_fake_snacks()
reloaded_codex.setup()
local first = reloaded_codex.toggle()
local second = reloaded_codex.new()
local third = reloaded_codex.new()

assert_eq(#calls, 3, "new should create new Snacks identities")
assert_eq(calls[1].opts.count, 1, "first session should use configured count")
assert_eq(calls[2].opts.count, 2, "second session should use the next count")
assert_eq(calls[3].opts.count, 3, "third session should use the next count")
assert_eq(calls[1].opts.win.wo.winbar, codex_winbar(1, 1), "first session should be selected in its winbar")
assert_eq(calls[2].opts.win.wo.winbar, codex_winbar(2, 2), "second session should be selected in its winbar")
assert_eq(calls[3].opts.win.wo.winbar, codex_winbar(3, 3), "third session should be selected in its winbar")
assert_eq(first.hidden, 1, "new should hide the previously visible session")
assert_eq(second.hidden, 1, "new should hide the previously visible new session")
assert_eq(third.visible, true, "newest session should be visible")
assert_eq(
  vim.api.nvim_get_option_value("winbar", { win = third.win }),
  codex_winbar(3, 3),
  "visible terminal window should select the third session"
)

reloaded_codex.previous()
assert_eq(#calls, 3, "previous should show existing sessions without creating terminals")
assert_eq(third.hidden, 1, "previous should hide the active session")
assert_eq(second.visible, true, "previous should show the previous session")
assert_eq(second.shown, 1, "previous should call show on the target")
assert_eq(
  vim.api.nvim_get_option_value("winbar", { win = second.win }),
  codex_winbar(2, 3),
  "previous should update the visible winbar selection"
)

reloaded_codex.previous()
assert_eq(first.visible, true, "previous should wrap to the first session")
assert_eq(first.shown, 1, "wrapped previous should show the target")
assert_eq(
  vim.api.nvim_get_option_value("winbar", { win = first.win }),
  codex_winbar(1, 3),
  "wrapped previous should update the visible winbar selection"
)

reloaded_codex.next()
assert_eq(#calls, 3, "next should show existing sessions without creating terminals")
assert_eq(second.visible, true, "next should wrap forward through sessions")
assert_eq(second.shown, 2, "next should show the target again")
assert_eq(
  vim.api.nvim_get_option_value("winbar", { win = second.win }),
  codex_winbar(2, 3),
  "next should update the visible winbar selection"
)

local dir_a = vim.fn.tempname()
local dir_b = vim.fn.tempname()
vim.fn.mkdir(dir_a, "p")
vim.fn.mkdir(dir_b, "p")
local resolved_a = normalize_cwd(dir_a)
local resolved_b = normalize_cwd(dir_b)

reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({
  cwd = dir_a,
  count = 4,
})

reloaded_codex.toggle()
reloaded_codex.new()
reloaded_codex.toggle({ cwd = dir_b })
reloaded_codex.new({ cwd = dir_b })

assert_eq(#calls, 4, "separate directories should create their own Snacks sessions")
assert_eq(calls[1].opts.cwd, resolved_a, "first directory should use resolved cwd")
assert_eq(calls[1].opts.count, 4, "first directory should use configured first count")
assert_eq(calls[2].opts.cwd, resolved_a, "new session should stay in first directory")
assert_eq(calls[2].opts.count, 5, "first directory should allocate its next count")
assert_eq(calls[3].opts.cwd, resolved_b, "second directory should use its own cwd")
assert_eq(calls[3].opts.count, 4, "second directory should reuse configured count independently")
assert_eq(calls[4].opts.cwd, resolved_b, "new session should stay in second directory")
assert_eq(calls[4].opts.count, 5, "second directory should allocate independently")

local normal_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(normal_buf)
reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local terminal_from_a = reloaded_codex.toggle()
reloaded_codex.setup({ cwd = dir_b })
vim.api.nvim_set_current_buf(terminal_from_a.buf)
reloaded_codex.new()

assert_eq(calls[2].opts.cwd, resolved_a, "new from a Codex buffer should use that buffer's cwd")
assert_eq(calls[2].opts.count, 2, "new from a Codex buffer should advance that cwd's count")

reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_b })
vim.api.nvim_set_current_buf(terminal_from_a.buf)
reloaded_codex.previous()

assert_eq(calls[3].opts.cwd, resolved_a, "navigation from an untracked Codex buffer should use that buffer's cwd")
assert_eq(calls[3].opts.count, 1, "navigation fallback should use the first count for that cwd")

vim.api.nvim_set_current_buf(normal_buf)
reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local close_first = reloaded_codex.toggle()
local close_second = reloaded_codex.new()
vim.api.nvim_exec_autocmds("TermClose", { buffer = close_second.buf, modeline = false, data = { status = 0 } })
assert_truthy(vim.wait(1000, function()
  return close_second.closed == true and not vim.api.nvim_buf_is_valid(close_second.buf)
end), "TermClose cleanup should run")
reloaded_codex.new()

assert_eq(close_first.closed, nil, "TermClose should not close sibling sessions")
assert_eq(calls[3].opts.count, 2, "TermClose should remove the closed count from tracking")

reset_fake_snacks()
reloaded_codex.deactivate()
vim.cmd.runtime("plugin/codex.lua")
reloaded_codex.setup()
local dirchanged_terminal = reloaded_codex.toggle()

local changed_cwd = vim.fn.tempname()
vim.fn.mkdir(changed_cwd, "p")
vim.cmd("tcd " .. vim.fn.fnameescape(changed_cwd))
local resolved_changed_cwd = normalize_cwd(vim.fn.getcwd())

assert_eq(dirchanged_terminal.hidden, 1, "DirChanged should hide visible Codex terminals")
assert_eq(dirchanged_terminal.closed, nil, "DirChanged should not close Codex terminals")
assert_eq(vim.api.nvim_buf_is_valid(dirchanged_terminal.buf), true, "DirChanged should preserve terminal buffers")

reloaded_codex.toggle()

assert_eq(#calls, 2, "toggle should still create the cwd-targeted terminal after tcd")
assert_eq(calls[2].opts.cwd, resolved_changed_cwd, "toggle after tcd should use the new tab cwd")

vim.cmd("tcd " .. vim.fn.fnameescape(original_cwd))
vim.fn.delete(changed_cwd, "rf")
vim.fn.delete(dir_a, "rf")
vim.fn.delete(dir_b, "rf")
vim.api.nvim_buf_delete(normal_buf, { force = true })
vim.env.PATH = old_path
vim.fn.delete(tmp, "rf")

print("codex.nvim smoke tests passed")
