return {
	"HiPhish/rainbow-delimiters.nvim",
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
	},
	lazy = false,
	init = function()
		vim.g.rainbow_delimiters = {
			condition = function(bufnr)
				local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
				return ok and parser ~= nil
			end,
		}
	end,
}

