return {
  "echasnovski/mini.trailspace",
  version = "*",
  event = "BufReadPost",
  keys = {
    { "<leader>tw", "<cmd>lua MiniTrailspace.trim()<cr>", desc = "Trim Whitespace" },
  },
  init = function()
    vim.api.nvim_create_user_command("TrimSpace", function()
      require("mini.trailspace").trim()
    end, {})
  end,
  config = function()
    require("mini.trailspace").setup()
  end,
}
