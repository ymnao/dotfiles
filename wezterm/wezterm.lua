local wezterm = require 'wezterm'

local utils = require("utils")
local keys = require("keymaps")
require("on")

---------------------------------------------------------------
--- Platform detection
---------------------------------------------------------------
local is_windows = wezterm.target_triple:find("windows") ~= nil
local is_macos = wezterm.target_triple:find("darwin") ~= nil
local is_linux = wezterm.target_triple:find("linux") ~= nil

---------------------------------------------------------------
--- local_config
---------------------------------------------------------------
local function load_local_config()
	local ok, re = pcall(require, "local")
	if not ok then
		return {}
	end
	return re.setup()
end
local local_config = load_local_config()

---------------------------------------------------------------
--- Base configuration (common to all platforms)
---------------------------------------------------------------
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

  window_decorations = "RESIZE",

  use_ime = true,
  send_composed_key_when_left_alt_is_pressed = false,
	send_composed_key_when_right_alt_is_pressed = false,
  keys = keys,
  set_environment_variables = {},
	leader = { key = ";", mods = "CTRL" },
  enable_csi_u_key_encoding = true,
	audible_bell = "SystemBeep",

  scrollback_lines = 5000,
  exit_behavior = 'CloseOnCleanExit',

  check_for_updates = true,
  check_for_updates_interval_seconds = 86400
}

---------------------------------------------------------------
--- Platform-specific configuration
---------------------------------------------------------------
if is_windows then
	-- Windows-specific settings
	config.default_prog = {"pwsh.exe", "-NoLogo"}
	config.window_background_opacity = 0.95
	-- Windows doesn't support blur, so use slightly less transparency

	-- Windows font fallback (in case UDEV Gothic isn't installed)
	config.font = wezterm.font_with_fallback({
		"UDEV Gothic 35",
		"JetBrainsMono Nerd Font",
		"Cica",
		"Cascadia Code",
		"Consolas"
	})

elseif is_macos then
	-- macOS-specific settings
	config.default_prog = {"/opt/homebrew/bin/fish"}
	config.window_background_opacity = 0.7
	config.macos_window_background_blur = 20
	config.macos_forward_to_ime_modifier_mask = "SHIFT|CTRL"

	-- macOS-specific unix domain socket
	config.unix_domains = {
		{
			name = "unix",
		},
	}

elseif is_linux then
	-- Linux-specific settings
	config.window_background_opacity = 0.85
	-- Linux uses X11/Wayland compositors for transparency

	-- Try to find fish in common Linux locations
	local fish_paths = {"/usr/bin/fish", "/bin/fish", "/usr/local/bin/fish"}
	for _, fish_path in ipairs(fish_paths) do
		local f = io.open(fish_path, "r")
		if f then
			f:close()
			config.default_prog = {fish_path}
			break
		end
	end
	-- If fish not found, WezTerm will use default shell
end

config = utils.merge_tables(config, require("tab_bar"))
config = utils.merge_tables(config, require("colors.kanagawa_dragon"))

require("zen-mode")

return utils.merge_tables(config, local_config)
