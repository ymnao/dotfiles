if vim.env.NVIM_COLORSCHEME == nil then
  vim.env.NVIM_COLORSCHEME = "kanagawa-dragon"
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  print("Installing lazy.nvim...")
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
  print("lazy.nvim installed!")
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugin" },
  },
  defaults = {
    lazy = true,
  },
   install = {
    missing = true,
    colorscheme = { "kanagawa" },
  },
  ui = {
    border = "rounded",
  },
  checker = { enabled = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})

vim.keymap.set("n", "<leader>l", "<cmd>Lazy<cr>", { desc = "Lazy Plugin Manager" })

