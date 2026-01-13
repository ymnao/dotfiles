-- Close all special windows when quitting
vim.api.nvim_create_autocmd('QuitPre', {
  callback = function()
    local current_win = vim.api.nvim_get_current_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= current_win then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == '' then
          return
        end
      end
    end
    vim.cmd.only({ bang = true })
  end,
  desc = 'Close all special buffers when quitting',
})
