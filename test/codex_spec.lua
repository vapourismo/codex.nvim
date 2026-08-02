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

local function assert_contains(actual, expected, message)
  if type(actual) ~= "string" or not actual:find(expected, 1, true) then
    error(("%s\nexpected %s to contain: %s"):format(message or "string differs", vim.inspect(actual), expected), 2)
  end
end

local OSC9_CONFIG = 'tui.notification_method="osc9"'

local function codex_winbar(selected, total)
  if total < 2 then
    return ""
  end

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

local function simulate_snacks_on_win(call, winfixwidth)
  local win = vim.api.nvim_get_current_win()
  local snacks_win = {
    win = win,
    opts = vim.deepcopy(call.opts.win),
  }
  snacks_win.opts.wo.winfixwidth = winfixwidth
  vim.wo[win].winfixwidth = winfixwidth
  call.opts.win.on_win(snacks_win)
  return snacks_win
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
assert_eq(vim.fn.exists(":CodexClose"), 2, ":CodexClose command should exist")
assert_eq(vim.fn.exists(":CodexPrevious"), 2, ":CodexPrevious command should exist")
assert_eq(vim.fn.exists(":CodexNext"), 2, ":CodexNext command should exist")
assert_eq(vim.fn.exists(":CodexReference"), 2, ":CodexReference command should exist")
assert_eq(vim.g.loaded_codex, 1, "Lazy-compatible loaded guard should be set")
assert_eq(vim.g.loaded_codex_nvim, nil, "legacy loaded guard should not be set")

vim.g.loaded_codex = nil
vim.cmd.runtime("plugin/codex.lua")
assert_eq(vim.fn.exists(":CodexToggle"), 2, "manual re-source should preserve :CodexToggle")
assert_eq(vim.fn.exists(":CodexNew"), 2, "manual re-source should preserve :CodexNew")
assert_eq(vim.fn.exists(":CodexClose"), 2, "manual re-source should preserve :CodexClose")
assert_eq(vim.fn.exists(":CodexPrevious"), 2, "manual re-source should preserve :CodexPrevious")
assert_eq(vim.fn.exists(":CodexNext"), 2, "manual re-source should preserve :CodexNext")
assert_eq(vim.fn.exists(":CodexReference"), 2, "manual re-source should preserve :CodexReference")
assert_eq(vim.g.loaded_codex, 1, "manual re-source should restore loaded guard")

local codex = require("codex")
assert_eq(type(codex.setup), "function", "setup should be a function")
assert_eq(type(codex.toggle), "function", "toggle should be a function")
assert_eq(type(codex.new), "function", "new should be a function")
assert_eq(type(codex.close), "function", "close should be a function")
assert_eq(type(codex.previous), "function", "previous should be a function")
assert_eq(type(codex.next), "function", "next should be a function")
assert_eq(type(codex.reference), "function", "reference should be a function")
assert_eq(type(codex.deactivate), "function", "deactivate should be a function")

codex.setup()
codex.toggle()

assert_eq(#calls, 1, "toggle should call Snacks once")
assert_list(
  calls[1].cmd,
  { "codex", "--config", OSC9_CONFIG },
  "default args should enable OSC 9 notifications"
)
assert_eq(calls[1].opts.cwd, original_cwd, "default cwd should resolve to current working directory")
assert_eq(calls[1].opts.count, 1, "default count should be stable")
assert_eq(calls[1].opts.auto_close, false, "custom TermClose handling should disable Snacks auto_close")
assert_eq(calls[1].opts.win.position, "right", "default terminal should open on the right")
assert_eq(calls[1].opts.win.relative, "editor", "default terminal should be editor-relative")
assert_eq(calls[1].opts.win.width, 0.4, "default terminal width should be 40 percent")
assert_eq(type(calls[1].opts.win.wo.winbar), "string", "Codex winbar should be a static string")
assert_eq(calls[1].opts.win.wo.winbar:find("%{", 1, true), nil, "Codex winbar should not be an expression")
assert_eq(calls[1].opts.win.wo.winbar, "", "default terminal winbar should be hidden for one session")
assert_eq(
  calls[1].opts.win.wo.winhighlight,
  "Normal:NormalFloat",
  "default terminal background should use NormalFloat"
)
assert_eq(calls[1].opts.win.wo.winfixwidth, false, "default terminal width should remain adjustable")
local default_snacks_win = simulate_snacks_on_win(calls[1], true)
assert_eq(default_snacks_win.opts.wo.winfixwidth, false, "Codex should correct Snacks' stored split default")
assert_eq(vim.wo[default_snacks_win.win].winfixwidth, false, "Codex should correct Snacks' applied split default")
assert_eq(calls[1].opts.win.keys.codex_new[1], "<D-n>", "default new key should be installed")
assert_eq(calls[1].opts.win.keys.codex_close[1], "<D-w>", "default close key should be installed")
assert_eq(calls[1].opts.win.keys.codex_previous[1], "<D-{>", "default previous key should be installed")
assert_eq(calls[1].opts.win.keys.codex_next[1], "<D-}>", "default next key should be installed")
assert_list(calls[1].opts.win.keys.codex_new.mode, { "n", "t" }, "Codex keys should be normal and terminal mode")
assert_list(calls[1].opts.win.keys.codex_close.mode, { "n", "t" }, "Codex close key should be normal and terminal mode")
assert_eq(type(calls[1].opts.win.keys.codex_new[2]), "function", "Codex key rhs should be callable")
assert_eq(type(calls[1].opts.win.keys.codex_close[2]), "function", "Codex close key rhs should be callable")

local configured_on_win
codex.setup({
  command = "codex",
  args = { "--config", 'tui.notification_method="bel"', "--model", "gpt-5" },
  cwd = function()
    return "/tmp"
  end,
  count = 4,
  keys = {
    close = "<leader>cw",
    new = "<leader>cn",
    previous = false,
    next = "<leader>cN",
  },
  win = {
    width = 0.5,
    on_win = function(snacks_win)
      configured_on_win = snacks_win
    end,
    keys = {
      q = "hide",
    },
    wo = {
      winhighlight = "Normal:CursorLine",
      winfixwidth = true,
    },
  },
  terminal = {
    env = { CODEX_TEST = "1" },
    start_insert = false,
  },
})

codex.toggle({
  args = { "exec", "hello", "--", "prompt" },
  cwd = "/tmp/project",
  win = { position = "left" },
  terminal = { auto_insert = false },
})

assert_eq(#calls, 2, "second toggle should call Snacks again")
assert_list(
  calls[2].cmd,
  { "codex", "exec", "hello", "--", "prompt" },
  "per-call args should pass through unchanged, including the delimiter"
)
assert_eq(calls[2].opts.cwd, normalize_cwd("/tmp/project"), "per-call cwd should win")
assert_eq(calls[2].opts.count, 4, "configured count should be passed to Snacks")
assert_eq(calls[2].opts.win.position, "left", "per-call win config should merge")
assert_eq(calls[2].opts.win.width, 0.5, "configured win config should be preserved")
assert_eq(calls[2].opts.win.wo.winbar, "", "Codex winbar should stay hidden when win config merges")
assert_eq(
  calls[2].opts.win.wo.winhighlight,
  "Normal:CursorLine",
  "configured winhighlight should override the default"
)
assert_eq(calls[2].opts.win.wo.winfixwidth, true, "configured winfixwidth should override the default")
local configured_snacks_win = simulate_snacks_on_win(calls[2], true)
assert_eq(configured_on_win, configured_snacks_win, "configured on_win callback should be preserved")
assert_eq(vim.wo[configured_snacks_win.win].winfixwidth, true, "configured winfixwidth should remain applied")
assert_eq(calls[2].opts.win.keys.q, "hide", "user Snacks keys should be preserved")
assert_eq(calls[2].opts.win.keys.codex_new[1], "<leader>cn", "custom new key should be installed")
assert_eq(calls[2].opts.win.keys.codex_close[1], "<leader>cw", "custom close key should be installed")
assert_eq(calls[2].opts.win.keys.codex_previous, nil, "false should disable a Codex key")
assert_eq(calls[2].opts.win.keys.codex_next[1], "<leader>cN", "custom next key should be installed")
assert_eq(calls[2].opts.env.CODEX_TEST, "1", "terminal config should be merged")
assert_eq(calls[2].opts.start_insert, false, "terminal options should be passed through")
assert_eq(calls[2].opts.auto_insert, false, "per-call terminal options should be merged")
assert_eq(calls[2].opts.auto_close, false, "Snacks auto_close should stay disabled")

codex.toggle({
  win = {
    wo = {
      winhighlight = "Normal:ErrorMsg",
      winbar = "Codex",
      winfixwidth = false,
    },
  },
})

assert_eq(#calls, 3, "third toggle should call Snacks again")
assert_list(
  calls[3].cmd,
  {
    "codex",
    "--config",
    'tui.notification_method="bel"',
    "--model",
    "gpt-5",
  },
  "configured args should replace the defaults and pass through unchanged"
)
assert_eq(calls[3].opts.win.wo.winbar, "", "Codex should clear a per-call winbar for one session")
assert_eq(
  calls[3].opts.win.wo.winhighlight,
  "Normal:ErrorMsg",
  "per-call winhighlight should override setup"
)
assert_eq(calls[3].opts.win.wo.winfixwidth, false, "per-call winfixwidth should override setup")
local per_call_snacks_win = simulate_snacks_on_win(calls[3], true)
assert_eq(per_call_snacks_win.opts.wo.winfixwidth, false, "per-call winfixwidth should correct Snacks' stored value")
assert_eq(vim.wo[per_call_snacks_win.win].winfixwidth, false, "per-call winfixwidth should correct the window")

vim.g.loaded_codex_nvim = 1

local deactivate_ok, deactivate_return = pcall(codex.deactivate)
assert_eq(deactivate_ok, true, "deactivate should not throw")
assert_eq(deactivate_return, codex, "deactivate should return the module table")
assert_eq(vim.fn.exists(":CodexToggle"), 0, "deactivate should remove :CodexToggle")
assert_eq(vim.fn.exists(":CodexNew"), 0, "deactivate should remove :CodexNew")
assert_eq(vim.fn.exists(":CodexClose"), 0, "deactivate should remove :CodexClose")
assert_eq(vim.fn.exists(":CodexPrevious"), 0, "deactivate should remove :CodexPrevious")
assert_eq(vim.fn.exists(":CodexNext"), 0, "deactivate should remove :CodexNext")
assert_eq(vim.fn.exists(":CodexReference"), 0, "deactivate should remove :CodexReference")
assert_eq(vim.g.loaded_codex, nil, "deactivate should clear Lazy-compatible loaded guard")
assert_eq(vim.g.loaded_codex_nvim, nil, "deactivate should clear legacy loaded guard")
assert_eq(terminals[1].closed, nil, "deactivate should not close existing terminals")
assert_eq(vim.api.nvim_buf_is_valid(terminals[1].buf), true, "deactivate should preserve terminal buffers")

codex.toggle()

assert_eq(#calls, 4, "toggle should still work after deactivate")
assert_list(
  calls[4].cmd,
  { "codex", "--config", OSC9_CONFIG },
  "deactivate should restore the default notification args"
)
assert_eq(calls[4].opts.cwd, original_cwd, "deactivate should reset cwd")
assert_eq(calls[4].opts.count, 1, "deactivate should reset count")
assert_eq(calls[4].opts.win.position, "right", "deactivate should reset win position")
assert_eq(calls[4].opts.win.width, 0.4, "deactivate should reset win width")
assert_eq(calls[4].opts.win.wo.winbar, "", "deactivate should reset to a hidden Codex winbar")
assert_eq(calls[4].opts.win.keys.codex_new[1], "<D-n>", "deactivate should reset keys")
assert_eq(calls[4].opts.win.keys.codex_close[1], "<D-w>", "deactivate should reset the close key")

local deactivate_again_ok, deactivate_again_return = pcall(codex.deactivate)
assert_eq(deactivate_again_ok, true, "deactivate should be idempotent")
assert_eq(deactivate_again_return, codex, "idempotent deactivate should return the module table")
assert_eq(terminals[1].closed, nil, "idempotent deactivate should not close existing terminals")
assert_eq(vim.api.nvim_buf_is_valid(terminals[1].buf), true, "idempotent deactivate should preserve terminal buffers")

package.loaded.codex = nil
vim.cmd.runtime("plugin/codex.lua")

assert_eq(vim.fn.exists(":CodexToggle"), 2, "reload should restore :CodexToggle")
assert_eq(vim.fn.exists(":CodexNew"), 2, "reload should restore :CodexNew")
assert_eq(vim.fn.exists(":CodexClose"), 2, "reload should restore :CodexClose")
assert_eq(vim.fn.exists(":CodexPrevious"), 2, "reload should restore :CodexPrevious")
assert_eq(vim.fn.exists(":CodexNext"), 2, "reload should restore :CodexNext")
assert_eq(vim.fn.exists(":CodexReference"), 2, "reload should restore :CodexReference")
assert_eq(vim.g.loaded_codex, 1, "reload should restore loaded guard")

local reloaded_codex = require("codex")
assert_eq(type(reloaded_codex.setup), "function", "reloaded setup should be a function")
assert_eq(type(reloaded_codex.toggle), "function", "reloaded toggle should be a function")
assert_eq(type(reloaded_codex.new), "function", "reloaded new should be a function")
assert_eq(type(reloaded_codex.close), "function", "reloaded close should be a function")
assert_eq(type(reloaded_codex.previous), "function", "reloaded previous should be a function")
assert_eq(type(reloaded_codex.next), "function", "reloaded next should be a function")
assert_eq(type(reloaded_codex.reference), "function", "reloaded reference should be a function")
assert_eq(type(reloaded_codex.deactivate), "function", "reloaded deactivate should be a function")

reset_fake_snacks()
reloaded_codex.setup({
  keys = {
    close = false,
  },
})
reloaded_codex.toggle()
assert_eq(calls[1].opts.win.keys.codex_close, nil, "false should disable the close key")

reset_fake_snacks()
reloaded_codex.setup()
local first = reloaded_codex.toggle()
local second = reloaded_codex.new()
local third = reloaded_codex.new()

assert_eq(#calls, 3, "new should create new Snacks identities")
assert_eq(calls[1].opts.count, 1, "first session should use configured count")
assert_eq(calls[2].opts.count, 2, "second session should use the next count")
assert_eq(calls[3].opts.count, 3, "third session should use the next count")
assert_eq(calls[1].opts.win.wo.winbar, "", "first session should not display a winbar")
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
assert_eq(calls[1].opts.win.wo.winbar, "", "first directory should hide its single-session winbar")
assert_eq(calls[2].opts.cwd, resolved_a, "new session should stay in first directory")
assert_eq(calls[2].opts.count, 5, "first directory should allocate its next count")
assert_eq(calls[2].opts.win.wo.winbar, codex_winbar(2, 2), "first directory should show its two-session winbar")
assert_eq(calls[3].opts.cwd, resolved_b, "second directory should use its own cwd")
assert_eq(calls[3].opts.count, 4, "second directory should reuse configured count independently")
assert_eq(calls[3].opts.win.wo.winbar, "", "second directory should hide its single-session winbar")
assert_eq(calls[4].opts.cwd, resolved_b, "new session should stay in second directory")
assert_eq(calls[4].opts.count, 5, "second directory should allocate independently")
assert_eq(calls[4].opts.win.wo.winbar, codex_winbar(2, 2), "second directory should show its two-session winbar")

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
assert_eq(reloaded_codex.close(), nil, "close should return nil outside a Codex terminal")

reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local explicit_first = reloaded_codex.toggle()
local explicit_second = reloaded_codex.new()
local explicit_third = reloaded_codex.new()
reloaded_codex.previous()
vim.api.nvim_set_current_buf(explicit_second.buf)
local replacement = reloaded_codex.close()

assert_eq(replacement, explicit_third, "close should activate the next same-directory session")
assert_eq(#calls, 3, "close should not create a replacement Snacks terminal")
assert_eq(explicit_second.closed, true, "close should close only the current Codex terminal")
assert_eq(vim.api.nvim_buf_is_valid(explicit_second.buf), false, "close should delete the current Codex buffer")
assert_eq(explicit_first.closed, nil, "close should not close earlier same-directory sessions")
assert_eq(explicit_third.closed, nil, "close should not close the replacement session")
assert_eq(explicit_third.visible, true, "close should leave the replacement visible")
assert_eq(explicit_third.shown, 1, "close should show the replacement session")
assert_eq(explicit_third.focused, 1, "close should focus the replacement session")
assert_eq(
  vim.api.nvim_get_option_value("winbar", { win = explicit_third.win }),
  codex_winbar(2, 2),
  "close should remove the closed count from the replacement winbar"
)

vim.api.nvim_set_current_buf(explicit_third.buf)
reloaded_codex.new()
assert_eq(calls[4].opts.count, 2, "close should free the closed count for reuse")

reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local wrap_first = reloaded_codex.toggle()
local wrap_second = reloaded_codex.new()
local wrap_third = reloaded_codex.new()
vim.api.nvim_set_current_buf(wrap_third.buf)
local wrap_replacement = reloaded_codex.close()

assert_eq(wrap_replacement, wrap_second, "close should fall back to the previous session at the end of the list")
assert_eq(#calls, 3, "wrapped close should not create a replacement Snacks terminal")
assert_eq(wrap_first.closed, nil, "wrapped close should not close earlier sibling sessions")
assert_eq(wrap_second.visible, true, "wrapped close should show the previous replacement")
assert_eq(wrap_third.closed, true, "wrapped close should close the selected terminal")

local final_winbar
local close_wrap_second = wrap_second.close
wrap_second.close = function(self)
  final_winbar = vim.api.nvim_get_option_value("winbar", { win = wrap_first.win })
  return close_wrap_second(self)
end
vim.api.nvim_set_current_buf(wrap_second.buf)
local final_replacement = reloaded_codex.close()

assert_eq(final_replacement, wrap_first, "close should retain the final same-directory session")
assert_eq(final_winbar, "", "close should hide the winbar when one session remains")

reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({
  cwd = dir_a,
  count = 4,
})

local only_session = reloaded_codex.toggle()
vim.api.nvim_set_current_buf(only_session.buf)
local only_result = reloaded_codex.close()
assert_eq(only_result, only_session, "close should return the closed terminal when there is no replacement")
assert_eq(only_session.closed, true, "close should close the only session")
assert_eq(vim.api.nvim_buf_is_valid(only_session.buf), false, "close should delete the only session buffer")

reloaded_codex.toggle()
assert_eq(calls[2].opts.count, 4, "toggle after closing the only session should restart at the first count")

reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local dir_a_only = reloaded_codex.toggle()
local dir_b_session = reloaded_codex.toggle({ cwd = dir_b })
vim.api.nvim_set_current_buf(dir_a_only.buf)
reloaded_codex.close()

assert_eq(dir_a_only.closed, true, "close should close the current directory session")
assert_eq(dir_b_session.closed, nil, "close should not close sessions from other directories")
assert_eq(dir_b_session.shown, nil, "close should not activate a session from another directory")
assert_eq(dir_b_session.focused, nil, "close should not focus a session from another directory")

vim.api.nvim_set_current_buf(normal_buf)
reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local termclose_first = reloaded_codex.toggle()
local termclose_second = reloaded_codex.new()
local termclose_third = reloaded_codex.new()
reloaded_codex.previous()
local termclose_other_dir = reloaded_codex.toggle({ cwd = dir_b })

vim.api.nvim_exec_autocmds("TermClose", {
  buffer = termclose_second.buf,
  modeline = false,
  data = { status = 0 },
})
assert_truthy(vim.wait(1000, function()
  return termclose_second.closed == true and not vim.api.nvim_buf_is_valid(termclose_second.buf)
end), "TermClose cleanup should run")

assert_eq(termclose_third.visible, true, "TermClose should activate the next same-directory session")
assert_eq(termclose_third.shown, 1, "TermClose should show the next same-directory session")
assert_eq(termclose_third.focused, 1, "TermClose should focus the next same-directory session")
assert_eq(termclose_first.closed, nil, "TermClose should not close sibling sessions")
assert_eq(termclose_third.closed, nil, "TermClose should not close the replacement session")
assert_eq(termclose_other_dir.closed, nil, "TermClose should not close sessions from other directories")
assert_eq(termclose_other_dir.shown, nil, "TermClose should not activate sessions from other directories")
assert_eq(termclose_other_dir.focused, nil, "TermClose should not focus sessions from other directories")
assert_eq(
  vim.api.nvim_get_option_value("winbar", { win = termclose_third.win }),
  codex_winbar(2, 2),
  "TermClose should remove the exited session from the replacement winbar"
)

vim.api.nvim_set_current_buf(termclose_third.buf)
reloaded_codex.new()
assert_eq(calls[5].opts.count, 2, "TermClose should free the exited count for reuse")

reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local termclose_wrap_first = reloaded_codex.toggle()
local termclose_wrap_second = reloaded_codex.new()
local termclose_wrap_third = reloaded_codex.new()
vim.api.nvim_exec_autocmds("TermClose", {
  buffer = termclose_wrap_third.buf,
  modeline = false,
  data = { status = 0 },
})
assert_truthy(vim.wait(1000, function()
  return termclose_wrap_third.closed == true and not vim.api.nvim_buf_is_valid(termclose_wrap_third.buf)
end), "TermClose fallback cleanup should run")

assert_eq(termclose_wrap_second.visible, true, "TermClose should fall back to the previous session")
assert_eq(termclose_wrap_second.shown, 1, "TermClose should show the previous fallback")
assert_eq(termclose_wrap_second.focused, 1, "TermClose should focus the previous fallback")
assert_eq(termclose_wrap_first.closed, nil, "TermClose fallback should preserve earlier sibling sessions")
assert_eq(
  vim.api.nvim_get_option_value("winbar", { win = termclose_wrap_second.win }),
  codex_winbar(2, 2),
  "TermClose fallback should refresh the replacement winbar"
)

reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local termclose_only = reloaded_codex.toggle()
vim.api.nvim_exec_autocmds("TermClose", {
  buffer = termclose_only.buf,
  modeline = false,
  data = { status = 0 },
})
assert_truthy(vim.wait(1000, function()
  return termclose_only.closed == true and not vim.api.nvim_buf_is_valid(termclose_only.buf)
end), "TermClose should close the sidebar when no replacement exists")
assert_eq(termclose_only.shown, nil, "TermClose should not create a replacement for the only session")

reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_a })

local idempotent_first = reloaded_codex.toggle()
local idempotent_second = reloaded_codex.new()
local close_idempotent_first = idempotent_first.close
idempotent_first.close = function(self)
  vim.api.nvim_exec_autocmds("TermClose", {
    buffer = self.buf,
    modeline = false,
    data = { status = 0 },
  })
  return close_idempotent_first(self)
end

vim.api.nvim_set_current_buf(idempotent_first.buf)
local idempotent_replacement = reloaded_codex.close()
assert_eq(idempotent_replacement, idempotent_second, "close should still return its replacement when TermClose follows")

vim.api.nvim_set_current_buf(idempotent_second.buf)
local idempotent_reused = reloaded_codex.new()
assert_eq(calls[3].opts.count, 1, "close should permit immediate count reuse before scheduled TermClose cleanup")

local scheduled_termclose_flushed = false
vim.schedule(function()
  scheduled_termclose_flushed = true
end)
assert_truthy(vim.wait(1000, function()
  return scheduled_termclose_flushed
end), "scheduled TermClose cleanup should finish")

assert_eq(idempotent_second.shown, 1, "scheduled TermClose should not show the replacement twice")
assert_eq(idempotent_second.focused, 1, "scheduled TermClose should not focus the replacement twice")
assert_eq(idempotent_reused.closed, nil, "scheduled TermClose should not close a session reusing the exited count")
assert_eq(vim.api.nvim_buf_is_valid(idempotent_reused.buf), true, "scheduled TermClose should preserve the reused buffer")

vim.api.nvim_set_current_buf(idempotent_reused.buf)
reloaded_codex.new()
assert_eq(calls[4].opts.count, 3, "scheduled TermClose should retain the reused count in session tracking")

reset_fake_snacks()
reloaded_codex.deactivate()
vim.cmd.runtime("plugin/codex.lua")
reloaded_codex.setup()

local navigation_cwd = vim.fn.tempname()
local other_navigation_cwd = vim.fn.tempname()
vim.fn.mkdir(navigation_cwd, "p")
vim.fn.mkdir(other_navigation_cwd, "p")
vim.cmd("tcd " .. vim.fn.fnameescape(navigation_cwd))

local navigation_terminal = reloaded_codex.toggle()
local terminal_tab = vim.api.nvim_get_current_tabpage()
vim.cmd.tabnew()
local other_tab = vim.api.nvim_get_current_tabpage()
vim.cmd("tcd " .. vim.fn.fnameescape(other_navigation_cwd))
vim.api.nvim_set_current_tabpage(terminal_tab)

assert_eq(navigation_terminal.hidden, nil, "switching tabs should not hide visible Codex terminals")
assert_eq(navigation_terminal.visible, true, "switching tabs should preserve terminal visibility")

vim.api.nvim_set_current_tabpage(other_tab)
vim.cmd.tabclose()

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

local reference_root = vim.fn.tempname()
local reference_project = reference_root .. "/project"
vim.fn.mkdir(reference_project .. "/src", "p")
vim.fn.mkdir(reference_root .. "/shared", "p")

local reference_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(reference_buf, reference_project .. "/src/example.lua")
vim.api.nvim_buf_set_lines(reference_buf, 0, -1, false, { "first line", "aébc", "last" })

local outside_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(outside_buf, reference_root .. "/shared/out.lua")
vim.api.nvim_buf_set_lines(outside_buf, 0, -1, false, { "outside" })

local unnamed_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(unnamed_buf, 0, -1, false, { "unnamed" })

local incompatible_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(incompatible_buf, "//codex-server/share/incompatible.lua")
vim.api.nvim_buf_set_lines(incompatible_buf, 0, -1, false, { "incompatible" })

local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
local blockwise = vim.api.nvim_replace_termcodes("<C-v>", true, false, true)

local function leave_visual()
  local mode = vim.fn.mode(1)
  if mode == "v" or mode == "V" or mode == "\22" then
    vim.cmd.normal({ args = { escape }, bang = true })
  end
end

local function select_visual(buf, mode, start_line, start_column, end_line, end_column)
  leave_visual()
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { start_line, start_column - 1 })
  vim.cmd.normal({ args = { mode }, bang = true })
  vim.api.nvim_win_set_cursor(0, { end_line, end_column - 1 })
end

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end

local sent = {}
local channels = {}
local original_get_option_value = vim.api.nvim_get_option_value
local original_chan_send = vim.api.nvim_chan_send
vim.api.nvim_get_option_value = function(name, opts)
  if name == "channel" and type(opts) == "table" and opts.buf then
    return channels[opts.buf] or 0
  end
  return original_get_option_value(name, opts)
end
vim.api.nvim_chan_send = function(channel, data)
  sent[#sent + 1] = { channel = channel, data = data }
end

reset_fake_snacks()
reloaded_codex.deactivate()
vim.cmd.runtime("plugin/codex.lua")
reloaded_codex.setup({ cwd = reference_project })
vim.api.nvim_set_current_buf(reference_buf)
local reference_first = reloaded_codex.toggle()
channels[reference_first.buf] = 101

select_visual(reference_buf, "V", 1, 1, 2, 1)
local linewise_result = reloaded_codex.reference()
assert_eq(linewise_result, reference_first, "linewise reference should return the active terminal")
assert_eq(sent[#sent].channel, 101, "linewise reference should target the active terminal channel")
assert_eq(sent[#sent].data, "src/example.lua:1-2", "linewise reference should include the selected line range")
assert_eq(reference_first.shown, 1, "reference should show the existing active terminal")
assert_eq(reference_first.focused, 1, "reference should focus the existing active terminal")
assert_eq(#calls, 1, "reference should not create another terminal")

select_visual(reference_buf, "v", 2, 2, 2, 4)
reloaded_codex.reference()
assert_eq(
  sent[#sent].data,
  "src/example.lua:2:2-2:4",
  "characterwise reference should use 1-based byte columns for multibyte text"
)

select_visual(reference_buf, "v", 2, 1, 2, 5)
reloaded_codex.reference()
assert_eq(
  sent[#sent].data,
  "src/example.lua:2",
  "full single-line characterwise reference should collapse to a single-line reference"
)

select_visual(reference_buf, "v", 1, 1, 3, 4)
reloaded_codex.reference()
assert_eq(
  sent[#sent].data,
  "src/example.lua:1-3",
  "full multi-line characterwise reference should collapse to linewise form"
)

select_visual(reference_buf, "V", 3, 1, 3, 1)
leave_visual()
vim.cmd("'<,'>CodexReference")
assert_eq(sent[#sent].data, "src/example.lua:3", ":CodexReference should normalize a single-line range")

select_visual(outside_buf, "V", 1, 1, 1, 1)
reloaded_codex.reference()
assert_eq(sent[#sent].data, "../shared/out.lua:1", "references outside the Codex cwd should retain ../ segments")

leave_visual()
vim.api.nvim_set_current_buf(reference_buf)
local reference_second = reloaded_codex.new()
channels[reference_second.buf] = 202
select_visual(reference_buf, "v", 1, 2, 1, 5)
local active_result = reloaded_codex.reference()
assert_eq(active_result, reference_second, "reference should return the active session when several exist")
assert_eq(sent[#sent].channel, 202, "reference should send to the active session when several exist")
assert_eq(sent[#sent].data, "src/example.lua:1:2-1:5", "reference should send exactly the formatted text")
assert_eq(reference_second.shown, 1, "reference should show the active session")
assert_eq(reference_second.focused, 1, "reference should focus the active session")
assert_eq(#calls, 2, "reference should not create a terminal when several sessions exist")

leave_visual()
reset_fake_snacks()
reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = reference_project })
select_visual(reference_buf, "V", 1, 1, 1, 1)
local sends_before_missing = #sent
assert_eq(reloaded_codex.reference(), nil, "reference should fail when no matching session exists")
assert_eq(#calls, 0, "reference should never create a missing session")
assert_eq(#sent, sends_before_missing, "reference should not send when no matching session exists")
assert_contains(
  notifications[#notifications].message,
  "no active Codex session",
  "missing session should produce a plugin error notification"
)

leave_visual()
vim.cmd.runtime("plugin/codex.lua")
reloaded_codex.setup({ cwd = reference_project })
vim.api.nvim_set_current_buf(reference_buf)
local error_terminal = reloaded_codex.toggle()
channels[error_terminal.buf] = 303

select_visual(unnamed_buf, "V", 1, 1, 1, 1)
assert_eq(reloaded_codex.reference(), nil, "reference should reject unnamed buffers")
assert_contains(notifications[#notifications].message, "named buffer", "unnamed buffers should produce a plugin error")

select_visual(reference_buf, blockwise, 1, 1, 2, 2)
assert_eq(reloaded_codex.reference(), nil, "reference should reject blockwise selections")
assert_contains(notifications[#notifications].message, "blockwise", "blockwise selection should produce a plugin error")

select_visual(incompatible_buf, "V", 1, 1, 1, 1)
assert_eq(reloaded_codex.reference(), nil, "reference should reject paths on incompatible roots")
assert_contains(
  notifications[#notifications].message,
  "incompatible filesystem roots",
  "incompatible roots should produce a plugin error"
)

channels[error_terminal.buf] = nil
select_visual(reference_buf, "V", 1, 1, 1, 1)
local sends_before_invalid_channel = #sent
assert_eq(reloaded_codex.reference(), nil, "reference should reject an invalid terminal channel")
assert_eq(#sent, sends_before_invalid_channel, "invalid terminal channel should not receive reference text")
assert_contains(notifications[#notifications].message, "valid channel", "invalid channel should produce a plugin error")

leave_visual()
vim.api.nvim_set_current_buf(reference_buf)
vim.cmd("CodexReference")
assert_contains(
  notifications[#notifications].message,
  "must be called from Visual mode",
  "non-visual command use should produce a plugin error"
)

vim.fn.setpos("'<", { 0, 0, 0, 0 })
vim.fn.setpos("'>", { 0, 0, 0, 0 })
assert_eq(
  reloaded_codex.reference({ _command = { range = 2, line1 = 0, line2 = 0 } }),
  nil,
  "reference should reject missing visual marks"
)
assert_contains(notifications[#notifications].message, "missing or invalid", "invalid marks should produce a plugin error")

leave_visual()
vim.notify = original_notify
vim.api.nvim_get_option_value = original_get_option_value
vim.api.nvim_chan_send = original_chan_send

local fake_snacks = package.loaded.snacks
local original_jobstart = vim.fn.jobstart
local original_termopen = vim.fn.termopen
local unrelated_launch_opts
local unchanged_jobstart = function(_, opts)
  unrelated_launch_opts = opts
  return 41
end
local launched
local unchanged_termopen = function(cmd, opts)
  launched = { cmd = cmd, opts = opts }
  return 42
end
vim.fn.jobstart = unchanged_jobstart
vim.fn.termopen = unchanged_termopen

local original_stdout_calls = {}
local terminal_stdout
local unrelated_opts
local notification_terminal
local reuse_notification_terminal = false
package.loaded.snacks = {
  terminal = {
    toggle = function(cmd, opts)
      unrelated_opts = {
        on_stdout = function() end,
      }
      vim.fn.jobstart({ "unrelated" }, unrelated_opts)

      if reuse_notification_terminal and vim.api.nvim_buf_is_valid(notification_terminal.buf) then
        return notification_terminal
      end

      notification_terminal = {
        buf = vim.api.nvim_create_buf(false, true),
      }
      vim.api.nvim_buf_call(notification_terminal.buf, function()
        terminal_stdout = function(job_id, data, event)
          original_stdout_calls[#original_stdout_calls + 1] = {
            job_id = job_id,
            data = data,
            event = event,
          }
        end
        vim.fn.termopen(cmd, {
          cwd = opts.cwd,
          on_stdout = terminal_stdout,
        })
      end)
      return notification_terminal
    end,
    list = function()
      return notification_terminal and { notification_terminal } or {}
    end,
  },
}

local function notification_autocmds(buf)
  return vim.api.nvim_get_autocmds({
    event = "TermRequest",
    group = "codex.nvim.termrequest",
    buffer = buf,
  })
end

local function termrequest(buf, data)
  local autocmds = notification_autocmds(buf)
  assert_eq(#autocmds, 1, "notification-enabled terminals should have one TermRequest handler")
  return autocmds[1].callback({ buf = buf, data = data })
end

local function exec_termrequest(buf, sequence)
  assert_eq(#notification_autocmds(buf), 1, "notification-enabled terminals should have one TermRequest handler")
  return vim.api.nvim_exec_autocmds("TermRequest", {
    buffer = buf,
    data = { sequence = sequence, cursor = { 1, 0 } },
  })
end

local legacy_notification_events = 0
local notification_group = vim.api.nvim_create_augroup("codex.nvim.test.notifications", { clear = true })
vim.api.nvim_create_autocmd("User", {
  group = notification_group,
  pattern = "CodexNotification",
  callback = function()
    legacy_notification_events = legacy_notification_events + 1
  end,
})

reloaded_codex.deactivate()
reloaded_codex.setup({
  args = { "--unobserved-test", "--config", OSC9_CONFIG },
  cwd = dir_a,
  count = 6,
})
local unobserved_terminal = reloaded_codex.toggle()
assert_eq(
  launched.opts.on_stdout,
  terminal_stdout,
  "launches without on_notification should retain their original stdout callback"
)
assert_eq(#notification_autocmds(unobserved_terminal.buf), 0, "unobserved terminals should not attach TermRequest handlers")
launched.opts.on_stdout(42, { "before\7after\27]9;ignored message\7" }, "stdout")
assert_eq(#original_stdout_calls, 1, "unobserved output should still reach the original stdout callback")
assert_eq(legacy_notification_events, 0, "unobserved notifications should not emit legacy User events")

local notification_calls = {}
original_stdout_calls = {}
reloaded_codex.deactivate()
reloaded_codex.setup({
  args = { "--notification-test", "--config", OSC9_CONFIG },
  cwd = dir_a,
  count = 6,
  on_notification = function(data)
    if data.message == "callback failure" then
      error("simulated notification callback failure")
    end
    notification_calls[#notification_calls + 1] = vim.deepcopy(data)
  end,
})
local observed_terminal = reloaded_codex.toggle()

assert_eq(observed_terminal, notification_terminal, "notification launch should return the Snacks terminal")
assert_eq(vim.fn.jobstart, unchanged_jobstart, "notification setup should leave jobstart unchanged")
assert_eq(vim.fn.termopen, unchanged_termopen, "notification setup should leave termopen unchanged")
assert_eq(unrelated_launch_opts, unrelated_opts, "unrelated commands should retain their original launch options")
assert_list(
  launched.cmd,
  { "codex", "--notification-test", "--config", OSC9_CONFIG },
  "custom notification args should explicitly include the OSC 9 configuration"
)
assert_eq(#notification_autocmds(observed_terminal.buf), 1, "notification terminals should attach one handler")

launched.opts.on_stdout(42, { "plain text\7\27]9;stdout message\7" }, "stdout")
assert_eq(#notification_calls, 0, "BEL and OSC bytes on stdout should not invoke the callback")
assert_eq(#original_stdout_calls, 1, "the original stdout callback should receive terminal output unchanged")
assert_eq(original_stdout_calls[1].job_id, 42, "the original stdout callback should receive its job id")
assert_eq(original_stdout_calls[1].event, "stdout", "the original stdout callback should receive its event name")

exec_termrequest(observed_terminal.buf, "\27]9;direct message")
assert_eq(#notification_calls, 1, "table-shaped direct OSC 9 requests should invoke once")
assert_eq(notification_calls[1].method, "osc9", "direct OSC 9 should report its method")
assert_eq(notification_calls[1].message, "direct message", "direct OSC 9 should decode its message")

termrequest(observed_terminal.buf, "\27]9;legacy message\7")
assert_eq(#notification_calls, 2, "string-shaped direct OSC 9 requests should invoke once")
assert_eq(notification_calls[2].method, "osc9", "legacy OSC 9 should report its method")
assert_eq(notification_calls[2].message, "legacy message", "legacy OSC 9 should preserve its complete payload")

for _, request in ipairs({
  "\7",
  "\27]0;title",
  "\27Ptmux;\27\27]9;tmux message\7\27\\",
  "\27_ignore this\27\\",
}) do
  termrequest(observed_terminal.buf, { sequence = request })
end
termrequest(observed_terminal.buf, {})
assert_eq(#notification_calls, 2, "BEL and unrelated OSC, DCS, and APC requests should be ignored")

for _, data in ipairs(notification_calls) do
  assert_eq(data.buf, notification_terminal.buf, "notifications should identify their terminal buffer")
  assert_eq(data.cwd, resolved_a, "notifications should identify their session cwd")
  assert_eq(data.count, 6, "notifications should identify their Snacks session count")
end
assert_eq(legacy_notification_events, 0, "notification callbacks should not emit legacy User events")

reuse_notification_terminal = true
local duplicate_terminal = reloaded_codex.toggle()
reuse_notification_terminal = false
assert_eq(duplicate_terminal, observed_terminal, "duplicate launches should reuse the simulated terminal")
assert_eq(#notification_autocmds(observed_terminal.buf), 1, "duplicate attachment should retain one TermRequest handler")

local callback_ok, callback_err = pcall(termrequest, observed_terminal.buf, { sequence = "\27]9;callback failure" })
assert_eq(callback_ok, false, "notification callback errors should propagate synchronously")
assert_contains(tostring(callback_err), "simulated notification callback failure", "callback errors should be preserved")

local invalid_ok, invalid_err = pcall(reloaded_codex.setup, { on_notification = "notify" })
assert_eq(invalid_ok, false, "setup should reject a non-function on_notification")
assert_contains(tostring(invalid_err), "on_notification must be a function", "invalid on_notification errors should be clear")

local per_call_notifications = {}
reloaded_codex.deactivate()
reloaded_codex.setup({
  args = { "--per-call-notification-test", "--config", OSC9_CONFIG },
  cwd = dir_b,
  count = 7,
})
local per_call_terminal = reloaded_codex.toggle({
  on_notification = function(data)
    per_call_notifications[#per_call_notifications + 1] = vim.deepcopy(data)
  end,
})
termrequest(per_call_terminal.buf, { sequence = "\27]9;per-call message" })
assert_eq(#per_call_notifications, 1, "per-call on_notification should be merged into launch options")
assert_eq(per_call_notifications[1].message, "per-call message", "per-call callbacks should receive OSC payloads")
assert_eq(per_call_notifications[1].buf, per_call_terminal.buf, "per-call callbacks should receive the source buffer")
assert_eq(per_call_notifications[1].cwd, resolved_b, "per-call callbacks should receive the resolved cwd")
assert_eq(per_call_notifications[1].count, 7, "per-call callbacks should receive the session count")
assert_eq(legacy_notification_events, 0, "per-call callbacks should not emit legacy User events")

local failing_jobstart = function()
  return 51
end
local failed_command
local failing_termopen = function()
  failed_command = true
  error("simulated termopen failure")
end
vim.fn.jobstart = failing_jobstart
vim.fn.termopen = failing_termopen
package.loaded.snacks = {
  terminal = {
    toggle = function(cmd, opts)
      return vim.fn.termopen(cmd, { cwd = opts.cwd })
    end,
    list = function()
      return {}
    end,
  },
}

reloaded_codex.deactivate()
reloaded_codex.setup({ cwd = dir_b, on_notification = function() end })
local launch_ok, launch_err = pcall(reloaded_codex.toggle)
assert_eq(launch_ok, false, "terminal creation failures should propagate")
assert_contains(tostring(launch_err), "simulated termopen failure", "terminal creation should preserve the launch error")
assert_eq(failed_command, true, "terminal launch failures should reach the terminal backend")
assert_eq(vim.fn.jobstart, failing_jobstart, "failed notification launches should leave jobstart unchanged")
assert_eq(vim.fn.termopen, failing_termopen, "failed notification launches should leave termopen unchanged")

vim.fn.jobstart = original_jobstart
vim.fn.termopen = original_termopen
package.loaded.snacks = fake_snacks
vim.api.nvim_del_augroup_by_id(notification_group)
reloaded_codex.deactivate()
vim.api.nvim_set_current_buf(normal_buf)
vim.api.nvim_buf_delete(unobserved_terminal.buf, { force = true })
vim.api.nvim_buf_delete(observed_terminal.buf, { force = true })
vim.api.nvim_buf_delete(per_call_terminal.buf, { force = true })

vim.api.nvim_buf_delete(reference_buf, { force = true })
vim.api.nvim_buf_delete(outside_buf, { force = true })
vim.api.nvim_buf_delete(unnamed_buf, { force = true })
vim.api.nvim_buf_delete(incompatible_buf, { force = true })
vim.fn.delete(reference_root, "rf")
vim.fn.delete(changed_cwd, "rf")
vim.fn.delete(dir_a, "rf")
vim.fn.delete(dir_b, "rf")
vim.api.nvim_buf_delete(normal_buf, { force = true })
vim.env.PATH = old_path
vim.fn.delete(tmp, "rf")

print("codex.nvim smoke tests passed")
