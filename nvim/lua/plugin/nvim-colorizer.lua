return {
  "NvChad/nvim-colorizer.lua",
  event = "BufReadPre",
  opts = {
    user_default_options = {
      RGB = true,        -- #RGB 形式
      RRGGBB = true,     -- #RRGGBB 形式
      names = false,     -- "red" などの色名（falseでパフォーマンス向上）
      RRGGBBAA = true,   -- #RRGGBBAA 形式
      rgb_fn = true,     -- CSS rgb() / rgba()
      hsl_fn = true,     -- CSS hsl() / hsla()
      mode = "background",  -- "background" or "foreground"
    },
  },
}

