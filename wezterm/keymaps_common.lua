-- Common keymaps (platform-independent)
-- These keymaps work the same across all platforms

local wezterm = require("wezterm")
local act = wezterm.action

local keys = {
	-- Leader key operations
	{ key = "a", mods = "LEADER|CTRL", action = act({ SendString = "\x01" }) },
	{ key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "z", mods = "LEADER", action = act.TogglePaneZoomState },
	{ key = "Space", mods = "LEADER", action = act.QuickSelect },

	-- Workspace management (LEADER key)
	{
		key = "s",
		mods = "LEADER",
		action = act.PromptInputLine({
			description = "(wezterm) Set workspace title:",
			action = wezterm.action_callback(function(win, pane, line)
				if line then
					wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
				end
			end),
		}),
	},

	-- Shift+Enter sends ESC+Enter (useful for some TUI apps)
	{ key = "Enter", mods = "SHIFT", action = wezterm.action({ SendString = "\x1b\r" }) },
}

-- Tab activation with LEADER key (1-9)
for i = 1, 9 do
	table.insert(keys, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i - 1),
	})
end

return keys
