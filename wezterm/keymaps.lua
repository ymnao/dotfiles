-- Platform-aware keymap loader
-- Loads common keymaps and platform-specific keymaps based on OS

local wezterm = require("wezterm")

-- Detect platform
local is_windows = wezterm.target_triple:find("windows") ~= nil
local is_macos = wezterm.target_triple:find("darwin") ~= nil
local is_linux = wezterm.target_triple:find("linux") ~= nil

-- Load common keymaps
local common_keys = require("keymaps_common")

-- Load platform-specific keymaps
local platform_keys = {}
if is_windows then
	wezterm.log_info("Loading Windows keymaps")
	platform_keys = require("keymaps_windows")
elseif is_macos then
	wezterm.log_info("Loading macOS keymaps")
	platform_keys = require("keymaps_macos")
elseif is_linux then
	wezterm.log_info("Loading Linux keymaps (reusing macOS keymaps)")
	-- Note: Linux uses Super/Meta key instead of CMD.
	-- WezTerm maps "CMD" modifier to Super on Linux, so macOS keymaps work.
	-- If shortcuts don't work, verify your system's Super key configuration.
	platform_keys = require("keymaps_macos")
else
	wezterm.log_warn("Unknown platform, using macOS keymaps as fallback")
	platform_keys = require("keymaps_macos")
end

-- Merge common and platform-specific keymaps
local keys = {}

-- Add common keys first
for _, key in ipairs(common_keys) do
	table.insert(keys, key)
end

-- Add platform-specific keys
for _, key in ipairs(platform_keys) do
	table.insert(keys, key)
end

return keys
