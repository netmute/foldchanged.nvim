local M = {}

local last = {} -- last[win] = snapshot string
local pending = {} -- pending[win] = true

local onkey_ns
local waiting_z = false

local fold_keys = {
	c = true,
	o = true,
	a = true,
	A = true,
	v = true,
	x = true,
	X = true,
	m = true,
	M = true,
	r = true,
	R = true,
}

local function fold_snapshot_for_win(win)
	return vim.api.nvim_win_call(win, function()
		local buf = vim.api.nvim_win_get_buf(win)
		local n = vim.api.nvim_buf_line_count(buf)

		local prev = 0
		local stack = {}
		local parts = {}

		for l = 1, n do
			local lvl = vim.fn.foldlevel(l)

			if lvl > prev then
				for k = prev + 1, lvl do
					stack[#stack + 1] = { start = l, level = k }
				end
			elseif lvl < prev then
				for _ = prev, lvl + 1, -1 do
					local top = stack[#stack]
					stack[#stack] = nil
					local s, e = top.start, l - 1
					local closed = (vim.fn.foldclosed(s) == s) and 1 or 0
					parts[#parts + 1] = table.concat({ s, e, top.level, closed }, ",")
				end
			end

			prev = lvl
		end

		for _ = prev, 1, -1 do
			local top = stack[#stack]
			stack[#stack] = nil
			local s, e = top.start, n
			local closed = (vim.fn.foldclosed(s) == s) and 1 or 0
			parts[#parts + 1] = table.concat({ s, e, top.level, closed }, ",")
		end

		return table.concat(parts, ";")
	end)
end

local function emit_foldchanged(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	vim.api.nvim_exec_autocmds("User", {
		pattern = "FoldChanged",
		modeline = false,
		data = { win = win, buf = buf },
	})
end

local function check_win(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.api.nvim_get_option_value("buftype", { buf = buf }) ~= "" then
		-- Non-file buffers (e.g. Fzf prompt) should not emit FoldChanged.
		return
	end
	local snap = fold_snapshot_for_win(win)
	if last[win] ~= snap then
		last[win] = snap
		emit_foldchanged(win)
	end
end

local function schedule_check(win)
	if pending[win] then
		return
	end
	pending[win] = true
	vim.schedule(function()
		pending[win] = nil
		if vim.api.nvim_win_is_valid(win) then
			check_win(win)
		end
	end)
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local grp = vim.api.nvim_create_augroup("FoldChangedUserEvent", { clear = true })

	local function hook()
		schedule_check(vim.api.nvim_get_current_win())
	end

	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = grp,
		callback = hook,
	})

	vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "TextChangedI", "InsertLeave" }, {
		group = grp,
		callback = hook,
	})

	vim.api.nvim_create_autocmd("OptionSet", {
		group = grp,
		pattern = {
			"foldenable",
			"foldlevel",
			"foldlevelstart",
			"foldmethod",
			"foldexpr",
			"foldminlines",
			"foldnestmax",
			"foldopen",
			"foldclose",
			"fillchars",
		},
		callback = hook,
	})

	vim.api.nvim_create_autocmd({ "WinClosed" }, {
		group = grp,
		callback = function(ev)
			local win = tonumber(ev.match)
			if win then
				last[win] = nil
				pending[win] = nil
			end
		end,
	})

	onkey_ns = onkey_ns or vim.api.nvim_create_namespace("FoldChangedOnKey")
	vim.on_key(function(key)
		-- catch common fold toggles that don't move the cursor (zc/zo/za/zA/zv/zx/zX/zM/zR/...)
		if key == "z" then
			waiting_z = true
			return
		end
		if waiting_z then
			waiting_z = false
			if fold_keys[key] then
				schedule_check(vim.api.nvim_get_current_win())
			end
			return
		end
	end, onkey_ns)

	hook()
end

return M
