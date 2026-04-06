return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    lazy = false,
    config = function()
      vim.schedule(function()
        local ts = require("nvim-treesitter")
        if ts.install then
          ts.install({
            "lua",
            "vim",
            "vimdoc",
            "javascript",
            "typescript",
            "tsx",
            "json",
            "html",
            "css",
            "python",
            "go",
            "rust",
            "markdown",
            "markdown_inline",
            "bash",
            "yaml",
            "toml",
          })
        end
      end)

      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          if vim.api.nvim_buf_line_count(args.buf) > 50000 then
            return
          end
          if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = {
          lookahead = true,
        },
        move = {
          set_jumps = true,
        },
      })

      local ts_select = require("nvim-treesitter-textobjects.select")
      local ts_move = require("nvim-treesitter-textobjects.move")

      local select_maps = {
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner",
        ["ab"] = "@block.outer",
        ["ib"] = "@block.inner",
        ["ai"] = "@conditional.outer",
        ["ii"] = "@conditional.inner",
        ["al"] = "@loop.outer",
        ["il"] = "@loop.inner",
      }
      for key, query in pairs(select_maps) do
        vim.keymap.set({ "x", "o" }, key, function()
          ts_select.select_textobject(query, "textobjects")
        end)
      end

      local move_maps = {
        ["]f"] = { ts_move.goto_next_start, "@function.outer" },
        ["]c"] = { ts_move.goto_next_start, "@class.outer" },
        ["]F"] = { ts_move.goto_next_end, "@function.outer" },
        ["]C"] = { ts_move.goto_next_end, "@class.outer" },
        ["[f"] = { ts_move.goto_previous_start, "@function.outer" },
        ["[c"] = { ts_move.goto_previous_start, "@class.outer" },
        ["[F"] = { ts_move.goto_previous_end, "@function.outer" },
        ["[C"] = { ts_move.goto_previous_end, "@class.outer" },
      }
      for key, mapping in pairs(move_maps) do
        vim.keymap.set({ "n", "x", "o" }, key, function()
          mapping[1](mapping[2], "textobjects")
        end)
      end
    end,
  },
}
