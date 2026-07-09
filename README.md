# codex.nvim

Minimal Neovim integration for running the Codex CLI in a right-side
[Snacks terminal](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md).

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-name/codex.nvim",
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
```

## Configuration

The defaults run `codex` from `vim.fn.getcwd()`. Each resolved directory keeps
its own active Codex session list.

```lua
{
  "your-name/codex.nvim",
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
- `keys`: terminal-local session keys. Set an entry to `false` to disable it.
- `win`: options merged into the Snacks window config. `win.wo.winbar` is reserved and managed by `codex.nvim`.
- `terminal`: options merged into the Snacks terminal config.

Codex terminal windows show a managed winbar with numbered session boxes for the
current directory. The visible terminal is highlighted, and session labels are
displayed as `1`, `2`, `3`, ... in the current session order.

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
```

`codex.nvim` requires `folke/snacks.nvim` and the `codex` executable to be
available on `$PATH`.
