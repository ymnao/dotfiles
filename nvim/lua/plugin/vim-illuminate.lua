return {
  "RRethy/vim-illuminate",
  event = "BufReadPost",
  opts = {
    delay = 500,
    large_file_cutoff = 2000,
    large_file_overrides = {
      providers = { "lsp" },
    },
  },
  config = function(_, opts)
    require("illuminate").configure(opts)
  end,
}
