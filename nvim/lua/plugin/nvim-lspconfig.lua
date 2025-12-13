return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "hrsh7th/cmp-nvim-lsp", -- For completion capabilities
  },
  config = function()
    -- Get completion capabilities from nvim-cmp
    local capabilities = vim.lsp.protocol.make_client_capabilities()

    -- Check if nvim-cmp is available and enhance capabilities
    local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
    if ok then
      capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
    end

    -- Snippet support
    capabilities.textDocument.completion.completionItem.snippetSupport = true

    -- Global LSP configuration for all servers
    vim.lsp.config("*", {
      capabilities = capabilities,
    })

    -- Basic on_attach for keymaps (will be enhanced later)
    local on_attach = function(client, bufnr)
      local opts = { buffer = bufnr, silent = true }

      -- Navigation
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
      vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
      vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
      vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, opts)
      vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)

      -- Information
      vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
      vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
      vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, opts)

      -- Actions
      vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
      vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
      vim.keymap.set("n", "<leader>f", function()
        vim.lsp.buf.format({ async = true })
      end, vim.tbl_extend("force", opts, { desc = "Format" }))

      -- Diagnostics
      vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
      vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
      vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)
      vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, opts)
    end

    -- Attach on_attach to all LSP clients
    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client then
          on_attach(client, args.buf)
        end
      end,
    })

    -- Diagnostic display configuration
    vim.diagnostic.config({
      virtual_text = true,
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = {
        border = "rounded",
        source = "always",
      },
    })

    -- Diagnostic signs
    local signs = {
      Error = " ",
      Warn = " ",
      Hint = " ",
      Info = " ",
    }
    for type, icon in pairs(signs) do
      local hl = "DiagnosticSign" .. type
      vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
    end

    -- Enable Language Servers
    vim.lsp.enable({
      "lua_ls",       -- Lua (for Neovim config)
      "solargraph",   -- Ruby
      "gopls",        -- Go
      "clangd",       -- C/C++
      "ts_ls",        -- TypeScript/JavaScript
      "pyright",      -- Python
      "html",         -- HTML
      "cssls",        -- CSS
      "marksman",     -- Markdown
    })
  end,
}
