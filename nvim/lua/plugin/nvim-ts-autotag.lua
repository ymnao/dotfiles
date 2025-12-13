return {
  "windwp/nvim-ts-autotag",
  event = "InsertEnter",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    require("nvim-ts-autotag").setup({
      opts = {
        -- 自動閉じを有効化するファイルタイプ
        enable_close = true,          -- 自動で閉じタグを追加
        enable_rename = true,          -- タグのリネームを同期
        enable_close_on_slash = false, -- /> で自動閉じ（オプション）
      },
    })
  end,
}

