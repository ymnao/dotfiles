---@type vim.lsp.Config
return {
  settings = {
    Lua = {
      runtime = {
        version = "LuaJIT",  -- Neovim uses LuaJIT
        path = { "?.lua", "?/init.lua" },
      },
      diagnostics = {
        globals = { "vim" },  -- Recognize 'vim' global
      },
      workspace = {
        library = {
          vim.fn.stdpath("config") .. "/lua",
          vim.env.VIMRUNTIME .. "/lua",
          "${3rd}/luv/library",
          "${3rd}/busted/library",
          "${3rd}/luassert/library",
        },
        checkThirdParty = false,  -- Disable third-party checking
      },
      completion = {
        callSnippet = "Replace",
      },
      format = {
        enable = false,  -- Use external formatter if needed
      },
      hint = {
        enable = true,  -- Enable inlay hints
      },
      telemetry = {
        enable = false,
      },
    },
  },
}
