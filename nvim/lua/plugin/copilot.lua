return {
  -- GitHub Copilot本体
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup({
        panel = {
          enabled = true,
          auto_refresh = false,
          keymap = {
            jump_prev = "[[",
            jump_next = "]]",
            accept = "<CR>",
            refresh = "gr",
            open = "<M-CR>",  -- Alt+Enter
          },
          layout = {
            position = "bottom",
            ratio = 0.4,
          },
        },
        suggestion = {
          enabled = true,
          auto_trigger = true,
          debounce = 75,
          keymap = {
            accept = "<M-l>",     -- Alt+l で候補を受け入れ
            accept_word = false,
            accept_line = false,
            next = "<M-]>",       -- Alt+] で次の候補
            prev = "<M-[>",       -- Alt+[ で前の候補
            dismiss = "<C-]>",    -- Ctrl+] で候補を消す
          },
        },
        filetypes = {
          yaml = false,
          markdown = false,
          help = false,
          gitcommit = false,
          gitrebase = false,
          hgcommit = false,
          svn = false,
          cvs = false,
          ["."] = false,
        },
        copilot_node_command = "node",
        server_opts_overrides = {},
      })
    end,
  },

  -- Copilot Chat（会話型AI補助）
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
      { "nvim-lua/plenary.nvim" },
    },
    cmd = {
      "CopilotChat",
      "CopilotChatOpen",
      "CopilotChatToggle",
    },
    keys = {
      { "<leader>cc", "<cmd>CopilotChatToggle<cr>", desc = "Copilot Chat Toggle" },
      { "<leader>ce", "<cmd>CopilotChatExplain<cr>", desc = "Copilot Explain", mode = { "n", "v" } },
      { "<leader>ct", "<cmd>CopilotChatTests<cr>", desc = "Copilot Tests", mode = { "n", "v" } },
      { "<leader>cf", "<cmd>CopilotChatFix<cr>", desc = "Copilot Fix", mode = { "n", "v" } },
      { "<leader>co", "<cmd>CopilotChatOptimize<cr>", desc = "Copilot Optimize", mode = { "n", "v" } },
    },
    opts = {
      debug = false,
      window = {
        layout = "vertical",
        width = 0.4,
        height = 0.6,
      },
    },
  },
}
