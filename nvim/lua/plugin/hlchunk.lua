return {
  "shellRaining/hlchunk.nvim",
  event = { "UIEnter" },
  config = function()
    require("hlchunk").setup({
      chunk = {
        enable = false,  -- ブロックハイライトを無効化（スクロール問題の原因）
      },
      indent = {
        enable = true,   -- インデントガイドのみ有効化
        chars = { "│" },
      },
      line_num = {
        enable = false,
      },
      blank = {
        enable = false,
      },
    })
  end,
}

