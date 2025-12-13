return {
  "echasnovski/mini.surround",
  version = "*",
  event = "VeryLazy",
  opts = {
    n_lines = 100,
    mappings = {
      add = "sa",
      delete = "sd",
      find = "sf",
      find_left = "sF",
      highlight = "",
      replace = "sr",
      update_n_lines = "sn",
      suffix_last = "l",
      suffix_next = "n",
    },
  },
  config = function(_, opts)
    require("mini.surround").setup(opts)
  end,
}
