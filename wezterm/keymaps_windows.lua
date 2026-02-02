-- Windows-specific keymaps
-- Uses CTRL and ALT modifier keys (Windows standard)
-- Design: CTRL+Shift+C/V for copy/paste (terminal standard), ALT for pane navigation

local wezterm = require("wezterm")
local act = wezterm.action

local keys = {
	-- Copy/Paste (terminal standard: Ctrl+Shift+C/V)
	-- Note: Ctrl+C sends SIGINT to terminal apps, so we use Ctrl+Shift+C for copy
	{ key = "c", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard") },
	{ key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },

	-- Pane management (CTRL key)
	{ key = "d", mods = "CTRL|SHIFT", action = act({ SplitVertical = { domain = "CurrentPaneDomain" } }) },
	{ key = "d", mods = "CTRL", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "w", mods = "CTRL", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "W", mods = "CTRL|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },

	-- Tab management (CTRL key)
	{ key = "t", mods = "CTRL", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "(", mods = "CTRL|SHIFT", action = act.MoveTabRelative(-1) },
	{ key = ")", mods = "CTRL|SHIFT", action = act.MoveTabRelative(1) },

	-- Tab navigation (browser-style)
	{ key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
	{ key = "Tab", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "PageUp", mods = "CTRL", action = act.ActivateTabRelative(-1) },
	{ key = "PageDown", mods = "CTRL", action = act.ActivateTabRelative(1) },

	-- Pane navigation (ALT + hjkl) - ALT to avoid conflict with terminal control chars
	{ key = "h", mods = "ALT", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "ALT", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "ALT", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "ALT", action = act.ActivatePaneDirection("Right") },

	-- Pane resizing (ALT + Shift + HJKL)
	{ key = "H", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "J", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "K", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "L", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },

	-- Visual effects (CTRL key)
	{ key = "b", mods = "CTRL|SHIFT", action = act.EmitEvent("toggle-blur") },
	{ key = "f", mods = "CTRL|ALT", action = act.EmitEvent("toggle-maximize") },

	-- Workspace management (CTRL key)
	{ key = "n", mods = "CTRL|SHIFT", action = act.SwitchWorkspaceRelative(1) },
	{ key = "p", mods = "CTRL|SHIFT", action = act.SwitchWorkspaceRelative(-1) },
	{
		key = "S",
		mods = "CTRL|SHIFT",
		action = act.PromptInputLine({
			description = "(wezterm) Create new workspace:",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					window:perform_action(
						act.SwitchToWorkspace({
							name = line,
						}),
						pane
					)
				end
			end),
		}),
	},
	{
		key = "s",
		mods = "CTRL",
		action = wezterm.action_callback(function(win, pane)
			local workspaces = {}
			for i, name in ipairs(wezterm.mux.get_workspace_names()) do
				table.insert(workspaces, {
					id = name,
					label = string.format("%d. %s", i, name),
				})
			end
			win:perform_action(
				act.InputSelector({
					action = wezterm.action_callback(function(_, _, id, label)
						if not id and not label then
							wezterm.log_info("Workspace selection canceled")
						else
							win:perform_action(act.SwitchToWorkspace({ name = id }), pane)
						end
					end),
					title = "Select workspace",
					choices = workspaces,
					fuzzy = true,
				}),
				pane
			)
		end),
	},
}

-- Tab activation by number (CTRL+1~9)
for i = 1, 9 do
	table.insert(keys, {
		key = tostring(i),
		mods = "CTRL",
		action = act.ActivateTab(i - 1),
	})
end

return keys
