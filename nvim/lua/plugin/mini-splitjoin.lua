return {
  "echasnovski/mini.splitjoin",
  version = "*",
  event = "VeryLazy",
  opts = {
    mappings = {
      toggle = "<leader>j",
    },
  },
  config = function(_, opts)
    require("mini.splitjoin").setup(opts)
  end,
}
