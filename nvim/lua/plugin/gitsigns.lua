return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPost" },

  keys = {
    -- Navigation
    { "]c", "<cmd>Gitsigns next_hunk<cr>", desc = "Next hunk" },
    { "[c", "<cmd>Gitsigns prev_hunk<cr>", desc = "Previous hunk" },

    -- Actions
    { "<leader>hs", "<cmd>Gitsigns stage_hunk<cr>", mode = { "n", "v" }, desc = "Stage hunk" },
    { "<leader>hr", "<cmd>Gitsigns reset_hunk<cr>", mode = { "n", "v" }, desc = "Reset hunk" },
    { "<leader>hS", "<cmd>Gitsigns stage_buffer<cr>", desc = "Stage buffer" },
    { "<leader>hu", "<cmd>Gitsigns undo_stage_hunk<cr>", desc = "Undo stage hunk" },
    { "<leader>hR", "<cmd>Gitsigns reset_buffer<cr>", desc = "Reset buffer" },
    { "<leader>hp", "<cmd>Gitsigns preview_hunk<cr>", desc = "Preview hunk" },
    { "<leader>hb", "<cmd>Gitsigns blame_line<cr>", desc = "Blame line" },
    { "<leader>hd", "<cmd>Gitsigns diffthis<cr>", desc = "Diff this" },
    { "<leader>tb", "<cmd>Gitsigns toggle_current_line_blame<cr>", desc = "Toggle blame" },
    { "<leader>td", "<cmd>Gitsigns toggle_deleted<cr>", desc = "Toggle deleted" },

    -- Text object
    { "ih", ":<C-U>Gitsigns select_hunk<cr>", mode = { "o", "x" }, desc = "Select hunk" },
  },

  opts = {
    signs = {
      add          = { text = "+" },
      change       = { text = "~" },
      delete       = { text = "_" },
      topdelete    = { text = "‾" },
      changedelete = { text = "~_" },
    },
    current_line_blame = true,
  },

  config = true,
}
