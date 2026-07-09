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

No default keymap is registered.

## Keymap

Add your own mapping from your Neovim config:

```lua
vim.keymap.set("n", "<leader>cc", function()
  require("codex").toggle()
end, { desc = "Toggle Codex" })
```

## Configuration

The defaults run `codex` from `vim.fn.getcwd()` and reuse one terminal session.

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
- `count`: stable Snacks terminal count. Defaults to `1`.
- `win`: options merged into the Snacks window config.
- `terminal`: options merged into the Snacks terminal config.

Programmatic usage:

```lua
require("codex").toggle({
  cwd = vim.fn.getcwd(),
  args = { "--ask-for-approval", "on-request" },
})
```

`codex.nvim` requires `folke/snacks.nvim` and the `codex` executable to be
available on `$PATH`.
