return {
  -- Mason: Language Server installer
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    build = ":MasonUpdate",
    opts = {
      ui = {
        border = "rounded",
        icons = {
          package_installed = "✓",
          package_pending = "➜",
          package_uninstalled = "✗",
        },
      },
    },
  },

  -- Mason-LSPConfig bridge
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = {
      "williamboman/mason.nvim",
    },
    config = function()
      require("mason-lspconfig").setup({
        -- Language Servers to auto-install
        ensure_installed = {
          "lua_ls",           -- Lua
          "solargraph",       -- Ruby
          "gopls",            -- Go
          "clangd",           -- C/C++
          "ts_ls",            -- TypeScript/JavaScript
          "pyright",          -- Python
          "html",             -- HTML
          "cssls",            -- CSS
          "marksman",         -- Markdown
        },
        -- Don't auto-setup (we use vim.lsp.enable instead)
        automatic_installation = true,
      })
    end,
  },
}
