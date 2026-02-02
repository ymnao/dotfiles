-- treesitter用のCコンパイラ (Windows)
vim.env.CC = "gcc"

vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"

vim.opt.cursorline = true
vim.opt.cursorcolumn = false

vim.opt.list = true
vim.opt.listchars = {
  tab = "▸ ",
  trail = "▫",
  nbsp = "␣",
  extends = "❯",
  precedes = "❮",
}

vim.opt.wrap = false

vim.opt.scrolloff = 4
vim.opt.sidescrolloff = 8

vim.opt.virtualedit = "onemore"

vim.opt.smoothscroll = true

vim.opt.splitbelow = true
vim.opt.splitright = true

-- インデント
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.autoindent = true

-- 検索
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- 補完メニュー
vim.opt.pumheight = 10
vim.opt.pumblend = 10

-- クリップボード
vim.opt.clipboard = "unnamedplus"

-- マウス
vim.opt.mouse = "a"

-- バックアップ・スワップ
vim.opt.backup = false
vim.opt.swapfile = false
vim.opt.writebackup = false

-- アンドゥ
vim.opt.undofile = true
vim.opt.undolevels = 10000

-- 分割
vim.opt.splitright = true
vim.opt.splitbelow = true

-- タイムアウト
vim.opt.timeoutlen = 1000
vim.opt.updatetime = 200

-- ターミナルの色
vim.opt.termguicolors = true

-- コマンドライン
vim.opt.cmdheight = 1
vim.opt.showcmd = false

-- 補完
vim.opt.completeopt = "menu,menuone,noselect"

-- ビープ音
vim.opt.errorbells = false
vim.opt.visualbell = true

-- エンコード
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"
vim.opt.fileencodings = "utf-8,cp932,euc-jp,sjis"

vim.opt.hidden = true
vim.opt.autoread = true
vim.opt.confirm = true

vim.opt.laststatus = 3

-- 仮想編集
vim.opt.virtualedit = "block"

-- ファイル末尾
vim.opt.fixendofline = true

