local wezterm = require 'wezterm'

local utils = require("utils")
local keys = require("keymaps")
require("on")

---------------------------------------------------------------
--- load local_config
---------------------------------------------------------------
-- Write settings you don't want to make public, such as ssh_domains
local function load_local_config()
	local ok, re = pcall(require, "local")
	if not ok then
		return {}
	end
	return re.setup()
end
local local_config = load_local_config()

local config = {
  font = wezterm.font_with_fallback({"UDEV Gothic 35", "JetBrainsMono Nerd Font", "Cica"}),
  font_size = 13.0,
  force_reverse_video_cursor = true,
	adjust_window_size_when_changing_font_size = false,

	window_padding = {
    left = 10,
    right = 10,
    top = 5,
    bottom = 5,
  },

  window_background_opacity = 0.7,
  macos_window_background_blur = 20,
  window_decorations = "RESIZE",
  
  use_ime = true,
  send_composed_key_when_left_alt_is_pressed = false,
	send_composed_key_when_right_alt_is_pressed = false,
  keys = keys,
  set_environment_variables = {},
	leader = { key = ";", mods = "CTRL" },
  enable_csi_u_key_encoding = true,
  unix_domains = {
    {
      name = "unix",
		},
	},
	macos_forward_to_ime_modifier_mask = "SHIFT|CTRL",
	audible_bell = "SystemBeep",
  
  scrollback_lines = 5000,
  exit_behavior = 'CloseOnCleanExit',

  check_for_updates = true,
  check_for_updates_interval_seconds = 86400
}

config = utils.merge_tables(config, require("tab_bar"))
config = utils.merge_tables(config, require("colors.kanagawa_dragon"))

require("zen-mode")

return utils.merge_tables(config, local_config)
