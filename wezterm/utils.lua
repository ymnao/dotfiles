local wezterm = require("wezterm")

local M = {}

-- 1〜9 のキーでタブ番号ジャンプするエントリを keys に追加して返す。
-- ActivateTab は 0 始まりなので i - 1 を渡す。
-- merge_lists ではなく table.insert で足すのは、merge_lists が pairs() 走査で
-- 配列順序を保証しないため。
function M.add_tab_number_keys(keys, mods)
	for i = 1, 9 do
		table.insert(keys, {
			key = tostring(i),
			mods = mods,
			action = wezterm.action.ActivateTab(i - 1),
		})
	end
	return keys
end

function M.basename(s)
	return string.gsub(s, "(.*[/\\])(.*)", "%2")
end

function M.merge_tables(t1, t2)
	for k, v in pairs(t2) do
		if (type(v) == "table") and (type(t1[k] or false) == "table") then
			M.merge_tables(t1[k], t2[k])
		else
			t1[k] = v
		end
	end
	return t1
end

function M.merge_lists(t1, t2)
	local result = {}
	for _, v in pairs(t1) do
		table.insert(result, v)
	end
	for _, v in pairs(t2) do
		table.insert(result, v)
	end
	return result
end

function M.exists(tab, element)
	for _, v in pairs(tab) do
		if v == element then
			return true
		elseif type(v) == "table" then
			return M.exists(v, element)
		end
	end
	return false
end

function M.convert_home_dir(path)
	local cwd = path
	local home = os.getenv("HOME")
	cwd = cwd:gsub("^" .. home .. "/", "~/")
	return cwd
end

return M
