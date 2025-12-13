return {
  -- Treesitter本体
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",  -- インストール時にパーサーを更新
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      -- テキストオブジェクト拡張（オプション）
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      require("nvim-treesitter.configs").setup({
        -- インストールする言語パーサー
        ensure_installed = {
          "lua",        -- Neovim設定用
          "vim",        -- Vimscript
          "vimdoc",     -- Vimヘルプ
          "javascript", -- JavaScript
          "typescript", -- TypeScript
          "tsx",        -- TypeScript JSX
          "json",       -- JSON
          "html",       -- HTML
          "css",        -- CSS
          "python",     -- Python
          "go",         -- Go
          "rust",       -- Rust
          "markdown",   -- Markdown
          "markdown_inline",  -- Markdown内のコード
          "bash",       -- Bash
          "yaml",       -- YAML
          "toml",       -- TOML
          -- 使用する言語を追加
        },

        -- パーサーの自動インストール（新しいファイルタイプを開いたとき）
        auto_install = true,

        -- ハイライト設定
        highlight = {
          enable = true,  -- Treesitterハイライトを有効化

          -- 従来のVim正規表現ハイライトを無効化（パフォーマンス向上）
          additional_vim_regex_highlighting = false,

          -- 大きいファイルで無効化（パフォーマンス対策）
          disable = function(lang, bufnr)
            return vim.api.nvim_buf_line_count(bufnr) > 50000
          end,
        },

        -- インデント設定
        indent = {
          enable = true,  -- Treesitterベースのインデント
          -- 一部の言語では問題があるため無効化することも
          -- disable = { "python", "yaml" },
        },

        -- インクリメンタル選択（オプション）
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "<C-space>",    -- 選択開始
            node_incremental = "<C-space>",  -- ノード拡大
            scope_incremental = "<C-s>",     -- スコープ拡大
            node_decremental = "<C-backspace>",  -- ノード縮小
          },
        },

        -- テキストオブジェクト（オプション）
        textobjects = {
          select = {
            enable = true,
            lookahead = true,  -- 次のテキストオブジェクトに自動ジャンプ
            keymaps = {
              -- 関数
              ["af"] = "@function.outer",  -- 関数全体（aで囲む）
              ["if"] = "@function.inner",  -- 関数の中身

              -- クラス
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",

              -- ブロック
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",

              -- 条件文
              ["ai"] = "@conditional.outer",
              ["ii"] = "@conditional.inner",

              -- ループ
              ["al"] = "@loop.outer",
              ["il"] = "@loop.inner",
            },
          },
          move = {
            enable = true,
            set_jumps = true,  -- ジャンプリストに追加
            goto_next_start = {
              ["]f"] = "@function.outer",  -- 次の関数へ
              ["]c"] = "@class.outer",     -- 次のクラスへ
            },
            goto_next_end = {
              ["]F"] = "@function.outer",
              ["]C"] = "@class.outer",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",  -- 前の関数へ
              ["[c"] = "@class.outer",     -- 前のクラスへ
            },
            goto_previous_end = {
              ["[F"] = "@function.outer",
              ["[C"] = "@class.outer",
            },
          },
        },
      })
    end,
  },
}

