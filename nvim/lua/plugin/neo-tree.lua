return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "echasnovski/mini.icons",
    "MunifTanjim/nui.nvim",
  },
  cmd = "Neotree",
  keys = {
    { "<leader>e", "<cmd>Neotree focus<cr>", desc = "Focus Neo-tree" },
  },
  config = function()
    require("neo-tree").setup({
      -- デフォルトファイルエクスプローラーとして使用
      default_file_explorer = true,

      -- ファイルシステム設定
      filesystem = {
        filtered_items = {
          visible = true,  -- 隠しファイルをデフォルトで表示
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_by_name = {
            ".DS_Store",
            "thumbs.db",
          },
        },
      },

      -- カラム設定（表示する情報）
      columns = {
        "icon",  -- ファイルタイプアイコン
        -- "permissions",  -- パーミッション（オプション）
        -- "size",         -- ファイルサイズ（オプション）
        -- "mtime",        -- 更新日時（オプション）
      },

      -- バッファ設定
      buf_options = {
        buflisted = false,  -- バッファリストに表示しない
        bufhidden = "hide",
      },

      -- ウィンドウ設定
      win_options = {
        wrap = false,
        signcolumn = "yes:2",  -- Git statusなどのサイン表示用
        cursorcolumn = false,
        foldcolumn = "0",
        spell = false,
        list = false,
        conceallevel = 3,
        concealcursor = "nvic",
      },

      -- 削除設定
      delete_to_trash = true,  -- ゴミ箱に移動（macOS）
      skip_confirm_for_simple_edits = false,  -- 簡単な編集でも確認

      -- ウィンドウ設定とキーマップ
      window = {
        position = "left",
        width = 30,
        mappings = {
          ["g?"] = "show_help",  -- ヘルプ表示
          ["<CR>"] = "open",   -- 開く/ディレクトリに入る
          ["<C-v>"] = "open_vsplit",  -- 垂直分割で開く
          ["<C-x>"] = "open_split",   -- 水平分割で開く
          ["<C-t>"] = "open_tabnew",     -- 新しいタブで開く
          ["<C-p>"] = "toggle_preview",  -- プレビュー
          ["<C-c>"] = "close_window",    -- 閉じる
          ["<C-l>"] = "refresh",  -- リフレッシュ
          ["-"] = "navigate_up",       -- 親ディレクトリへ
          ["."] = "set_root",     -- カレントディレクトリをルートに設定
          ["C"] = "close_node",   -- ノードを閉じる
          ["gs"] = "order_by_name", -- ソート方法変更
        },
      },

      -- キーマップをデフォルトから使う
      use_default_keymaps = true,

      -- フローティングウィンドウ設定
      float = {
        padding = 2,
        max_width = 0,
        max_height = 0,
        border = "rounded",
        win_options = {
          winblend = 0,
        },
      },

      -- プレビューウィンドウ設定
      preview = {
        max_width = 0.9,
        min_width = { 40, 0.4 },
        width = nil,
        max_height = 0.9,
        min_height = { 5, 0.1 },
        height = nil,
        border = "rounded",
      },

      -- プログレス表示
      progress = {
        max_width = 0.9,
        min_width = { 40, 0.4 },
        width = nil,
        max_height = { 10, 0.9 },
        min_height = { 5, 0.1 },
        height = nil,
        border = "rounded",
      },
    })
  end,
}

