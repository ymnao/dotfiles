return {
  "nvim-treesitter/nvim-treesitter-context",
  event = "BufReadPost",
  config = function()
    require("treesitter-context").setup({
      enable = true,
      throttle = true,
      max_lines = 0,
      patterns = {
        default = {
          "class",
          "function",
          "method",
          "for",
          "while",
          "if",
          "switch",
          "case",
        },
      },
      on_attach = function(bufnr)
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
        return ok and parser ~= nil
      end,
    })
  end,
}
