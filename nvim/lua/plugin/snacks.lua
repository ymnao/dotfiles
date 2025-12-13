return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  init = function()
    -- デバッグヘルパー関数
    _G.dd = function(...)
      Snacks.debug.inspect(...)
    end
    _G.bt = function()
      Snacks.debug.backtrace()
    end
    vim.print = _G.dd

    -- ユーザーコマンド
    vim.api.nvim_create_user_command("Bdelete", function()
      Snacks.bufdelete()
    end, { nargs = 0 })
    vim.api.nvim_create_user_command("Bdeleteall", function()
      Snacks.bufdelete.all()
    end, { nargs = 0 })
    vim.api.nvim_create_user_command("Lazygit", function()
      Snacks.lazygit()
    end, { nargs = 0 })
  end,
  keys = {
    -- Picker
    {
      ",<cr>",
      function()
        Snacks.picker.picker_actions()
      end,
      desc = "Picker Actions",
    },
    {
      ",<space>",
      function()
        Snacks.picker.grep()
      end,
      desc = "Grep",
    },
    {
      ",b",
      function()
        Snacks.picker.grep_buffers()
      end,
      desc = "Grep Buffers",
    },
    {
      ",s",
      function()
        Snacks.picker.grep_word()
      end,
      desc = "Grep String",
      mode = { "n", "x" },
    },
    {
      ",P",
      function()
        Snacks.picker.projects()
      end,
      desc = "Projects",
    },
    {
      ",B",
      function()
        Snacks.picker.buffers()
      end,
      desc = "Buffers",
    },
    {
      ",c",
      function()
        Snacks.picker.colorschemes()
      end,
      desc = "Colorscheme",
    },
    {
      ",f",
      function()
        Snacks.picker.files()
      end,
      desc = "Find Files",
    },
    {
      ",g",
      function()
        Snacks.picker.git_branches()
      end,
      desc = "Git Branches",
    },
    {
      ",h",
      function()
        Snacks.picker.help()
      end,
      desc = "Help Pages",
    },
    {
      ",j",
      function()
        Snacks.picker.jumps()
      end,
      desc = "Jumplist",
    },
    {
      ",l",
      function()
        Snacks.picker.lazy()
      end,
      desc = "Lazy",
    },
    {
      ",m",
      function()
        Snacks.picker.marks()
      end,
      desc = "Marks",
    },
    {
      ",p",
      function()
        Snacks.picker.commands()
      end,
      desc = "Commands",
    },
    {
      ",q",
      function()
        Snacks.picker.qflist()
      end,
      desc = "qflist",
    },
    {
      ",r",
      function()
        Snacks.picker.resume()
      end,
      desc = "Resume",
    },
    {
      ",t",
      function()
        Snacks.picker.todo_comments()
      end,
      desc = "TODO",
    },
    {
      ",i",
      function()
        Snacks.picker.icons()
      end,
      desc = "Icons",
    },
    {
      ",d",
      function()
        Snacks.picker.diagnostics_buffer()
      end,
      desc = "Diagnostics (buffer)",
    },
    {
      ",D",
      function()
        Snacks.picker.diagnostics()
      end,
      desc = "Diagnostics (all)",
    },
    {
      "<leader>/",
      function()
        Snacks.picker.lines()
      end,
      desc = "Search in buffer",
    },
    {
      "<leader>gf",
      function()
        Snacks.picker.git_files()
      end,
      desc = "Git files",
    },
    {
      "<leader>gc",
      function()
        Snacks.picker.git_log()
      end,
      desc = "Git commits",
    },
    {
      "<leader>gs",
      function()
        Snacks.picker.git_status()
      end,
      desc = "Git status",
    },
    -- Lazygit
    {
      "<leader>g",
      function()
        Snacks.lazygit()
      end,
      desc = "Lazygit",
    },
    {
      "<leader>gg",
      function()
        Snacks.lazygit()
      end,
      desc = "Lazygit",
    },
    {
      "<leader>gl",
      function()
        Snacks.lazygit.log()
      end,
      desc = "Lazygit Log",
    },
    {
      "<leader>gk",
      function()
        Snacks.lazygit.log_file()
      end,
      desc = "Lazygit Log File",
    },
    -- Dim
    {
      "<leader>dim",
      function()
        if Snacks.dim.enabled then
          Snacks.dim.disable()
        else
          Snacks.dim.enable()
        end
      end,
      desc = "Toggle Dim",
    },
    -- Zen
    {
      "<leader>z",
      function()
        Snacks.zen()
      end,
      desc = "Zen",
    },
  },
  opts = {
    input = {
      enabled = true,
    },
    picker = {
      enabled = true,
      ui_select = true,
      formatters = {
        file = {
          filename_first = true,
          truncate = 400,
        },
      },
      matcher = {
        frecency = true,
        cwd_bonus = true,
      },
      sort_empty = true,
      sources = {
        files = {
          hidden = true,
          ignored = {
            "node_modules/",
            ".git/",
            "dist/",
            "build/",
            "target/",
            "%.lock",
          },
        },
      },
    },
    bigfile = {
      enabled = true,
      size = 1024 * 1024, -- 1MB
    },
    scratch = {
      enabled = true,
    },
    debug = {
      enabled = true,
    },
    lazygit = {
      enabled = true,
      configure = true,
      theme = {
        activeBorderColor = { fg = "Special" },
        inactiveBorderColor = { fg = "Comment" },
      },
    },
    zen = {
      enabled = true,
    },
    notifier = {
      enabled = true,
      timeout = 3000,
    },
    terminal = {
      enabled = true,
    },
    dashboard = {
      enabled = true,
      sections = {
        { section = "header" },
        { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
        { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1 },
        { icon = " ", title = "Keymaps", section = "keys", indent = 2, padding = 1 },
        { section = "startup" },
      },
      autokeys = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
      preset = {
        keys = {
          { icon = "", desc = "New file", key = "e", action = ":enew" },
          { icon = "󰒲", desc = "Lazy", key = "l", action = ":Lazy" },
          { icon = "󰙅", desc = "Explorer", key = "x", action = ":Neotree" },
          { icon = "", desc = "Config", key = "c", action = function() vim.fn.chdir(vim.fn.stdpath("config")) vim.cmd("Neotree") end },
          { icon = "󰈙", desc = "Find Files", key = "f", action = function() Snacks.picker.files() end },
          { icon = "", desc = "Restore Session", key = "s", section = "session" },
          { icon = "󰅚", desc = "Quit", key = "q", action = ":qa" },
        },
        header = [[
  ___     ___    ___   __  __ /\_\    ___ ___
 / _ `\  / __`\ / __`\/\ \/\ \\/\ \  / __` __`\
/\ \/\ \/\  __//\ \_\ \ \ \_/ |\ \ \/\ \/\ \/\ \
 \ \_\ \_\ \____\ \____/\ \___/  \ \_\ \_\ \_\ \_\
  \/_/\/_/\/____/\/___/  \/__/    \/_/\/_/\/_/\/_/ ]],
      },
    },
  },
}
