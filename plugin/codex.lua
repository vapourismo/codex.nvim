if vim.g.loaded_codex == 1 then
  return
end

vim.g.loaded_codex = 1

vim.api.nvim_create_user_command("CodexToggle", function()
  require("codex").toggle()
end, {
  desc = "Toggle Codex CLI in a Snacks terminal",
  force = true,
})

vim.api.nvim_create_user_command("CodexNew", function()
  require("codex").new()
end, {
  desc = "Open a new Codex CLI session",
  force = true,
})

vim.api.nvim_create_user_command("CodexClose", function()
  require("codex").close()
end, {
  desc = "Close the current Codex CLI session",
  force = true,
})

vim.api.nvim_create_user_command("CodexPrevious", function()
  require("codex").previous()
end, {
  desc = "Show the previous Codex CLI session",
  force = true,
})

vim.api.nvim_create_user_command("CodexNext", function()
  require("codex").next()
end, {
  desc = "Show the next Codex CLI session",
  force = true,
})
