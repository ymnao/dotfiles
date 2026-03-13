return {
  'keaising/im-select.nvim',
  cond = vim.fn.executable('macism') == 1,
  event = 'InsertEnter',
  opts = {
    default_im_select = 'com.apple.keylayout.ABC',
    set_default_events = { 'InsertLeave' },
    set_previous_events = {},
  },
}
