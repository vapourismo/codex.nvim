# codex.nvim

Minimal Neovim integration for running the Codex CLI in a right-side
[Snacks terminal](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md).

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "vapourismo/codex.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
}
```

Then run:

```vim
:CodexToggle
```

Additional session commands are available:

```vim
:CodexNew
:CodexClose
:CodexPrevious
:CodexNext
```

Use `:CodexReference` from Visual mode to insert the selected file range into
the active Codex prompt. It supports characterwise and linewise selections and
does not submit the prompt.

## Keymap

No global keymap is registered. Codex terminal buffers get terminal-local
Snacks window keys for session management:

- `<D-n>`: create a new Codex session for the current directory.
- `<D-w>`: close the current Codex session.
- `<D-{>`: switch to the previous Codex session for the current directory.
- `<D-}>`: switch to the next Codex session for the current directory.

You can also add your own global mapping from your Neovim config:

```lua
vim.keymap.set("n", "<leader>cc", function()
  require("codex").toggle()
end, { desc = "Toggle Codex" })

vim.keymap.set("x", "<leader>cr", ":CodexReference<CR>", {
  desc = "Reference selection in Codex",
})
```

## Configuration

The defaults run `codex` from `vim.fn.getcwd()`. Each resolved directory keeps
its own active Codex session list.

```lua
{
  "vapourismo/codex.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  opts = {
    args = { "--model", "gpt-5" },
    cwd = function()
      return vim.fn.getcwd()
    end,
    keys = {
      close = "<D-w>",
      new = "<D-n>",
      previous = "<D-{>",
      next = "<D-}>",
    },
    win = {
      width = 0.35,
    },
  },
}
```

You can also call setup directly:

```lua
require("codex").setup({
  command = "codex",
  args = {},
  cwd = function()
    return vim.fn.getcwd()
  end,
  count = 1,
  on_notification = function(data)
    vim.notify(data.message or "Codex needs attention", vim.log.levels.INFO, {
      title = ("Codex session %d"):format(data.count),
    })
  end,
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
  },
  terminal = {},
})
```

Supported options:

- `command`: executable name or path. Defaults to `"codex"`.
- `args`: command arguments. Defaults to `{}`.
- `cwd`: working directory string or function returning a string. Defaults to `vim.fn.getcwd()`.
- `count`: first Snacks terminal count for each directory. Defaults to `1`.
- `on_notification`: optional callback for OSC 9 and BEL notifications. Defaults to `nil`.
- `keys`: terminal-local session keys. Set an entry to `false` to disable it.
- `win`: options merged into the Snacks window config. `win.wo.winbar` is reserved and managed by `codex.nvim`.
- `terminal`: options merged into the Snacks terminal config.

When more than one session exists for the current directory, Codex terminal
windows show a managed winbar with numbered session boxes. The visible terminal
is highlighted, and session labels are displayed as `1`, `2`, `3`, ... in the
current session order.

Programmatic usage:

```lua
require("codex").toggle({
  cwd = vim.fn.getcwd(),
  args = { "--ask-for-approval", "on-request" },
})

require("codex").new()
require("codex").close()
require("codex").previous()
require("codex").next()
require("codex").reference() -- call from characterwise or linewise Visual mode
```

## Notifications

With the standard Snacks terminal backend, `codex.nvim` can call an
`on_notification` callback for every OSC 9 notification or standalone BEL byte
written by Codex. The notification bytes are only observed, so terminal rendering
and native bell behavior are unchanged. When the callback is unset, notifications
are ignored.

The callback's `data` table contains:

- `method`: `"osc9"` or `"bel"`.
- `message`: the OSC 9 payload; absent for BEL notifications.
- `buf`: the source terminal buffer.
- `cwd`: the session working directory.
- `count`: the Snacks session identifier.

For example, configure it during setup:

```lua
require("codex").setup({
  on_notification = function(data)
    vim.notify(data.message or "Codex needs attention", vim.log.levels.INFO, {
      title = ("Codex session %d"):format(data.count),
    })
  end,
})
```

A custom `terminal.override` owns its process and must provide its own
notification integration.

`codex.nvim` requires `folke/snacks.nvim` and the `codex` executable to be
available on `$PATH`.
