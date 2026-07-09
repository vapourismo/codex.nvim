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
