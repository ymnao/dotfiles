-- macOS-specific keymaps
-- Uses CMD modifier key (Command key on Mac keyboards)

local wezterm = require("wezterm")
local act = wezterm.action

local keys = {
	-- Pane management (CMD key)
	{ key = "d", mods = "CMD|SHIFT", action = act({ SplitVertical = { domain = "CurrentPaneDomain" } }) },
	{ key = "d", mods = "CMD", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "W", mods = "CMD|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },

	-- Tab management
	{ key = "t", mods = "CMD", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "(", mods = "CMD|SHIFT", action = act.MoveTabRelative(-1) },
	{ key = ")", mods = "CMD|SHIFT", action = act.MoveTabRelative(1) },

	-- Pane navigation (CMD + hjkl)
	{ key = "h", mods = "CMD", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "CMD", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CMD", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "CMD", action = act.ActivatePaneDirection("Right") },

	-- Pane resizing (CMD + Shift + HJKL)
	{ key = "H", mods = "CMD|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "J", mods = "CMD|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "K", mods = "CMD|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "L", mods = "CMD|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },

	-- Visual effects
	{ key = "b", mods = "CMD|SHIFT", action = act.EmitEvent("toggle-blur") },
	{ key = "f", mods = "CMD|CTRL", action = act.EmitEvent("toggle-maximize") },

	-- Workspace management (CMD key)
	{ key = "n", mods = "CMD|SHIFT", action = act.SwitchWorkspaceRelative(1) },
	{ key = "p", mods = "CMD|SHIFT", action = act.SwitchWorkspaceRelative(-1) },
	{
		key = "S",
		mods = "CMD|SHIFT",
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
		mods = "CMD",
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

return keys
