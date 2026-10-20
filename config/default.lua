-- ============================================================
-- duckwm — the default configuration
--
-- Installed as /etc/duckwm/config.lua: what duckwm runs when you have no
-- config of your own, or when yours fails to load. So it needs nothing
-- but duckwm and a shell: no launcher, bar, theme or fonts. A terminal is
-- the first of $TERMINAL and a few common ones that's installed, and
-- Super+R runs any command through duckwm's own prompt.
--
-- Every part is set up on its own, so one that fails (an API that changed,
-- say) doesn't take the rest down: Super+F1 shows the keys, and what failed.
-- To make it yours, copy it to ~/.config/duckwm/config.lua.
-- ============================================================

local X11 = wm.PLATFORM == wm.PLATFORM_X11
local M, S, C, A = wm.MOD_SUPER, wm.MOD_SHIFT, wm.MOD_CTRL, wm.MOD_ALT

-- ------------------------------------------------------------
-- Robustness
-- ------------------------------------------------------------
local problems = {}

local function report(what, err)
	local msg = what .. ": " .. tostring(err)
	problems[#problems + 1] = msg
	io.stderr:write("duckwm default config: " .. msg .. "\n")
end

-- Run one part of the setup; a failure is reported, not fatal.
local function section(name, f)
	local ok, err = pcall(f)
	if not ok then
		report(name, err)
	end
end

-- Text in the input bar, if this duckwm has wm.message; stderr otherwise.
local function say(text, ms)
	if type(wm.message) ~= "function" or not pcall(wm.message, text, ms) then
		io.stderr:write("duckwm: " .. text .. "\n")
	end
end

-- For use while running (keys, rules, layouts): say it on screen too.
local function complain(what, err)
	report(what, err)
	say(what .. " failed (Super+F1 for details)", 4000)
end

-- A key action that can't take duckwm's state down with it.
local function safe(name, f)
	return function()
		local ok, err = pcall(f)
		if not ok then
			complain(name, err)
		end
	end
end

local function bind(mods, key, name, f)
	if type(f) ~= "function" then
		return report("binding " .. name, "no such function")
	end
	local ok, err = pcall(wm.bind, mods, key, safe(name, f))
	if not ok then
		report("binding " .. name, err)
	end
end

local function focus(id)
	if id then
		pcall(wm.focus, id)
	end
end

local function set(list)
	local t = {}
	for _, v in ipairs(list) do
		t[v] = true
	end
	return t
end

local function contains(list, x)
	for _, v in ipairs(list) do
		if v == x then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------
-- Programs
-- ------------------------------------------------------------
local function sh(cmd)
	wm.spawn({ "sh", "-c", cmd })
end

-- $TERMINAL, then the first of these that's installed (foot is Wayland-only).
local TERMINALS = X11 and "kitty alacritty wezterm xterm urxvt st" or "foot kitty alacritty wezterm xterm"

local function terminal()
	sh(
		'for t in "$TERMINAL" '
			.. TERMINALS
			.. "; do "
			.. '[ -n "$t" ] && command -v "$t" >/dev/null 2>&1 && exec "$t"; done'
	)
end

local function run_prompt()
	wm.read_line("run: ", function(cmd)
		if cmd:match("%S") then
			sh(cmd)
		end
	end)
end

local function lua_prompt()
	wm.read_line("lua: ", function(src)
		local _, out = wm.eval(src)
		out = tostring(out or ""):gsub("\n+$", ""):gsub("\n", "  ")
		if out ~= "" then
			say(out, 4000)
		end
	end)
end

local HELP = "Super: Return terminal · R run · Shift+Q close · F float · F11 fullscreen · "
	.. "hjkl/arrows focus (+Shift swap, +Ctrl resize) · 1-9 workspace (+Shift send) · "
	.. ", . monitor (+Shift send) · Shift+N layout · Shift+R reload · Shift+E quit"

local function help()
	local text = HELP
	if #problems > 0 then
		text = #problems .. " problem(s): " .. table.concat(problems, " | ") .. "  —  " .. HELP
	end
	say(text, 10000)
end

-- ------------------------------------------------------------
-- The essentials first: whatever fails below, these keys work.
-- ------------------------------------------------------------
bind(M, "Return", "terminal", terminal)
bind(M, "r", "run prompt", run_prompt)
bind(M | S, "q", "close", wm.kill_client)
bind(M | S, "r", "reload", wm.reload_config)
bind(M | S, "e", "quit", wm.quit) -- on river this ends the whole session
bind(M, "F1", "help", help)

-- ------------------------------------------------------------
-- Behaviour
-- ------------------------------------------------------------
section("behaviour", function()
	wm.set_border_width(2)
	wm.set_gaps(0, 0, 0, 0)
	wm.set_workspace_switch_mode("previous")
	wm.set_click_to_focus(true)
end)

section("pointer", function()
	wm.set_resize_modifier(A)
	wm.set_float_modifier(A)
	wm.set_pan_modifier(A)
	wm.set_pan_button(wm.BUTTON_MIDDLE)
end)

section("animation", function()
	wm.set_animation(100, "ease_in_out")
end)

section("prompt keys", function()
	wm.set_prompt_keys("emacs") -- or "vi"
end)

section("environment", function()
	if not X11 then
		-- Toolkits default to X11 in places; point them at Wayland, with X11 fallback.
		wm.setenv("XDG_CURRENT_DESKTOP", "duckwm")
		wm.setenv("XDG_SESSION_TYPE", "wayland")
		wm.setenv("MOZ_ENABLE_WAYLAND", "1")
		wm.setenv("QT_QPA_PLATFORM", "wayland;xcb")
		wm.setenv("SDL_VIDEODRIVER", "wayland,x11")
		wm.setenv("ELECTRON_OZONE_PLATFORM_HINT", "auto")
	end
end)

-- ------------------------------------------------------------
-- Windows
-- ------------------------------------------------------------
section("window keys", function()
	bind(M, "f", "float", wm.toggle_floating)
	bind(M, "F11", "fullscreen", wm.toggle_fullscreen)
	bind(M | C, "p", "lua prompt", lua_prompt)

	local MOVES = { left = { "h", "Left" }, right = { "l", "Right" }, up = { "k", "Up" }, down = { "j", "Down" } }
	for dir, keys in pairs(MOVES) do
		for _, k in ipairs(keys) do
			bind(M, k, "focus " .. dir, wm["focus_" .. dir])
			bind(M | S, k, "swap " .. dir, wm["exchange_" .. dir])
			bind(M | C, k, "resize " .. dir, function()
				wm.resize_focused_edge(dir, 20)
			end)
		end
	end
end)

-- Scratchpad: Super+S makes the focused window the scratchpad, then shows
-- and hides it; Super+Shift+Escape puts it back in the tiling. A window
-- of class "scratchpad" becomes it by itself.
section("scratchpad", function()
	local pad = nil

	local function alive()
		if pad ~= nil and wm.get_node_type(pad) == nil then
			pad = nil
		end
		return pad ~= nil
	end

	bind(M, "s", "scratchpad", function()
		if not alive() then
			pad = wm.get_focused()
			if not pad then
				return
			end
		end
		wm.scratchpad_toggle(pad)
	end)

	bind(M | S, "Escape", "release scratchpad", function()
		if not alive() then
			return
		end
		wm.scratchpad_show(pad) -- onto this workspace, focused
		wm.toggle_floating() -- it floats: toggling drops it into the tiling
		pad = nil
	end)

	wm.add_rule(function(event, id)
		if event ~= "prop" or id == pad then
			return
		end
		local ok, class = pcall(wm.get_window_class, id)
		if ok and class == "scratchpad" then
			wm.scratchpad_hide(id)
			pad = id
		end
	end)
end)

-- Glue: Super+G on one floating window, then another: they stick side by side.
section("glue", function()
	local anchor = nil
	bind(M, "g", "glue", function()
		local f = wm.get_focused()
		if not f then
			return
		end
		if not anchor then
			anchor = f
			return
		end
		local a = anchor
		anchor = nil
		if f == a or wm.get_node_type(a) == nil then
			return
		end
		wm.float_right_of(f, a)
		wm.float_left_of(a, f)
		wm.float_equal_height(f, a)
		wm.float_equal_height(a, f)
		wm.align_top(f, a)
		wm.align_top(a, f)
	end)
end)

-- ------------------------------------------------------------
-- Workspaces and monitors
-- ------------------------------------------------------------
section("workspaces", function()
	for i = 1, 9 do
		local key = tostring(i)
		bind(M, key, "workspace " .. key, function()
			wm.switch_to_workspace(i)
		end)
		bind(M | S, key, "send and follow to " .. key, function()
			local id = wm.get_focused()
			if id then
				wm.send_to_workspace(id, i)
				wm.switch_to_workspace(i)
			end
		end)
		bind(A, key, "send to " .. key, function()
			local id = wm.get_focused()
			if id then
				wm.send_to_workspace(id, i)
			end
		end)
	end

	-- Nested workspaces
	bind(M, "w", "new nested workspace", function()
		wm.create_nested_workspace()
	end)
	bind(M, "e", "enter nested", wm.enter_nested)
	bind(M, "Escape", "leave nested", wm.leave_nested)
end)

section("monitors", function()
	for key, dir in pairs({ comma = "left", period = "right" }) do
		bind(M, key, "monitor " .. dir, function()
			wm.focus_output(dir)
		end)
		bind(M | S, key, "send to monitor " .. dir, function()
			local id = wm.get_focused()
			if id then
				wm.send_to_output(id, dir)
			end
		end)
	end
end)

-- Zoom: Super+minus out, Super+equal in, Super+0 the whole canvas and back.
section("zoom", function()
	bind(M, "minus", "zoom out", function()
		wm.set_zoom(math.max(0.25, wm.get_zoom() - 0.25))
	end)
	bind(M, "equal", "zoom in", function()
		wm.set_zoom(math.min(1, wm.get_zoom() + 0.25))
	end)
	bind(M, "0", "zoom toggle", function()
		wm.set_zoom(wm.get_zoom() < 1 and 1 or 0)
	end)
end)

-- ============================================================
-- Layouts. An arranger gets a snapshot s of its workspace and returns the
-- whole layout and the state to keep; duckwm stores the state per
-- workspace. Window constraints are relative to the work area.
-- ============================================================
local L = {}

function L.key(k)
	return { key = k }
end

function L.fixed(x, y, w, h)
	return {
		{ type = "fixed_x", value = x },
		{ type = "fixed_y", value = y },
		{ type = "fixed_width", value = math.max(0, w) },
		{ type = "fixed_height", value = math.max(0, h) },
	}
end

function L.at(id, x, y, w, h)
	return { id = id, constraints = L.fixed(x, y, w, h) }
end

function L.cell_abs(container, x, y, w, h)
	return { type = "grid_cell_abs", x = x, y = y, w = math.max(0, w), h = math.max(0, h), container = container }
end

function L.split(container, axis, children, ratios)
	if not ratios then
		ratios = {}
		for i = 1, #children do
			ratios[i] = 1 / #children
		end
	end
	return { type = "split", container = container, axis = axis, ratios = ratios, children = children }
end

-- The tiled windows, without the one being unmapped.
function L.windows(s)
	local out = {}
	for _, w in ipairs(s.windows or {}) do
		if not (s.event == "unmap" and w.id == s.id) then
			out[#out + 1] = w.id
		end
	end
	return out
end

function L.geometry(s, id)
	for _, w in ipairs(s.windows or {}) do
		if w.id == id then
			return w.geometry
		end
	end
end

function L.area(s, id)
	local g = L.geometry(s, id)
	return g and g.width * g.height or 0
end

-- The state as stored, or a fresh default if it's missing or not a table.
function L.state(s, default)
	return type(s.state) == "table" and s.state or default
end

-- Keyed container k's split ratios as duckwm has them: resizes end up here.
function L.ratios_of(s, k)
	for _, n in ipairs((s.layout or {}).nodes or {}) do
		if type(n.id) == "table" and n.id.key == k then
			for _, c in ipairs(n.constraints or {}) do
				if c.type == "split" then
					return c.ratios
				end
			end
		end
	end
end

-- Nested rows ("h") and columns ("v"). A branch of one child without an
-- explicit key is just that child. opts: ratios, key.
function L.branch(axis, kids, opts)
	opts = opts or {}
	if #kids == 0 then
		return nil
	end
	if #kids == 1 and opts.key == nil then
		return kids[1]
	end
	local ratios = opts.ratios
	if ratios and #ratios ~= #kids then
		ratios = nil
	end
	return { axis = axis, kids = kids, ratios = ratios, key = opts.key }
end

-- A tree as nodes: keyed containers holding splits. Keys are depth-first
-- from 0 unless given; a container's ratios as duckwm has them win over the
-- tree's while it has the same number of children.
function L.compile(s, t)
	local wa = s.work_area
	if t == nil then
		return {}
	end
	if type(t) ~= "table" then
		return { L.at(t, 0, 0, wa.width, wa.height) }
	end
	local branches, taken = {}, {}
	local function walk(b)
		branches[#branches + 1] = b
		if b.key then
			taken[b.key] = true
		end
		for _, c in ipairs(b.kids) do
			if type(c) == "table" then
				walk(c)
			end
		end
	end
	walk(t)
	local auto = 0
	for _, b in ipairs(branches) do
		if b.key then
			b.k = b.key
		else
			while taken[auto] do
				auto = auto + 1
			end
			b.k, auto = auto, auto + 1
		end
	end
	local nodes = {}
	for _, b in ipairs(branches) do
		local stored = L.ratios_of(s, b.k)
		local ratios = (stored and #stored == #b.kids) and stored or b.ratios
		local kids = {}
		for i, c in ipairs(b.kids) do
			kids[i] = type(c) == "table" and L.key(c.k) or c
		end
		local cons = b == t and L.fixed(0, 0, wa.width, wa.height) or {}
		cons[#cons + 1] = L.split(L.key(b.k), b.axis, kids, ratios)
		nodes[#nodes + 1] = { id = L.key(b.k), constraints = cons }
		for _, c in ipairs(b.kids) do
			if type(c) ~= "table" then
				nodes[#nodes + 1] = { id = c, constraints = {} }
			end
		end
	end
	return nodes
end

-- The reply: the whole layout and the state to keep; a new window gets focus.
function L.done(s, nodes, state)
	if s.event == "map" then
		focus(s.id)
	end
	return { nodes = nodes }, state
end

-- ------------------------------------------------------------
-- Split direction, per window: where the next window goes in scroller2d
-- and manual ("h": to the right, "v": below), shown on the focused border.
-- ------------------------------------------------------------
local DIRS = {}

local function dir_of(w)
	return DIRS[w] or "h"
end

local function indicate(windows, focused)
	for _, w in ipairs(windows) do
		if w ~= focused then
			pcall(wm.clear_node_indicator, w)
		end
	end
	if focused and contains(windows, focused) then
		pcall(wm.set_node_indicator, focused, dir_of(focused) == "h" and "right" or "bottom")
	end
end

-- ------------------------------------------------------------
-- Grid: as square as fits, filled row by row. No state, nothing to go
-- wrong: also what any other layout falls back to if it fails.
-- ------------------------------------------------------------
local function grid(s)
	local ws = L.windows(s)
	if #ws == 0 then
		return L.done(s, {})
	end
	local cols = math.ceil(math.sqrt(#ws))
	local rows = math.ceil(#ws / cols)
	local W, H = s.work_area.width, s.work_area.height
	local nodes = {}
	for i, w in ipairs(ws) do
		local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
		local x0, x1 = math.floor(c * W / cols), math.floor((c + 1) * W / cols)
		local y0, y1 = math.floor(r * H / rows), math.floor((r + 1) * H / rows)
		nodes[i] = L.at(w, x0, y0, x1 - x0, y1 - y0)
	end
	return L.done(s, nodes)
end

-- Fair: columns of near-equal windows; two side by side, then as square as possible.
local function fair(s)
	local ws = L.windows(s)
	local rows = #ws == 2 and 1 or math.max(1, math.ceil(math.sqrt(#ws)))
	local columns = {}
	for i = 1, #ws, rows do
		local col = {}
		for j = i, math.min(#ws, i + rows - 1) do
			col[#col + 1] = ws[j]
		end
		columns[#columns + 1] = L.branch("v", col)
	end
	return L.done(s, L.compile(s, L.branch("h", columns)))
end

-- Dwindle: each new window splits the focused one, alternating direction,
-- on the side of the cursor. A tree is a window, or { k, axis, a, b }.
local function dw_leaves(t, out)
	out = out or {}
	if t == nil then
		return out
	end
	if type(t) ~= "table" then
		out[#out + 1] = t
		return out
	end
	dw_leaves(t.a, out)
	dw_leaves(t.b, out)
	return out
end

local function dw_remove(t, w)
	if type(t) ~= "table" then
		if t == w then
			return nil
		end
		return t
	end
	local a, b = dw_remove(t.a, w), dw_remove(t.b, w)
	if a == nil then
		return b
	end
	if b == nil then
		return a
	end
	return { k = t.k, axis = t.axis, a = a, b = b }
end

local function dw_replace(t, target, new)
	if type(t) ~= "table" then
		return t == target and new or t
	end
	return { k = t.k, axis = t.axis, a = dw_replace(t.a, target, new), b = dw_replace(t.b, target, new) }
end

local function dw_build(t)
	if type(t) ~= "table" then
		return t
	end
	return L.branch(t.axis, { dw_build(t.a), dw_build(t.b) }, { key = t.k })
end

local function dwindle(s)
	local st = L.state(s, { h = true, key = 1 })
	if type(st.key) ~= "number" then
		st.key = 1
	end
	local present = set(L.windows(s))
	for _, w in ipairs(dw_leaves(st.tree)) do
		if not present[w] then
			st.tree = dw_remove(st.tree, w)
		end
	end
	local have = set(dw_leaves(st.tree))
	for _, w in ipairs(L.windows(s)) do
		if not have[w] then
			if st.tree == nil then
				st.tree = w
			else
				local ls = dw_leaves(st.tree)
				local target = ls[1]
				for _, x in ipairs(ls) do
					if L.area(s, x) > L.area(s, target) then
						target = x
					end
				end
				if s.prev_id and contains(ls, s.prev_id) then
					local g = L.geometry(s, s.prev_id)
					if not g or (g.width >= 20 and g.height >= 20) then
						target = s.prev_id
					end
				end
				local first = ((st.h and s.cursor_dx or s.cursor_dy) or 0) < 0
				local split = {
					k = st.key,
					axis = st.h and "h" or "v",
					a = first and w or target,
					b = first and target or w,
				}
				st.tree = dw_replace(st.tree, target, split)
				st.h, st.key = not st.h, st.key + 1
			end
			have[w] = true
		end
	end
	return L.done(s, L.compile(s, dw_build(st.tree)), st)
end

-- Scroller2D: rows of windows on a canvas wider than the screen, panned to
-- the focused one. A window opens right of the focused one, pushing along
-- only the windows after it in that row; or, with the focused window's
-- direction "v" (Super+T), below it.
-- State: { rows = { { h = height, cells = { {window, x, width}, ... } }, ... } }.
local function scroller2d(s)
	local W, H = s.work_area.width, s.work_area.height
	local st = L.state(s, {})
	local present = set(L.windows(s))
	if s.event == "unmap" then
		DIRS[s.id] = nil
	end

	-- What's still open, each row closing the gap a closed window leaves.
	local rows, gone = {}, nil
	for _, r in ipairs(type(st.rows) == "table" and st.rows or {}) do
		if type(r) == "table" and type(r.cells) == "table" then
			local cells, shift = {}, 0
			for _, c in ipairs(r.cells) do
				if type(c) == "table" and present[c[1]] then
					cells[#cells + 1] = { c[1], c[2] - shift, c[3] }
				elseif type(c) == "table" then
					shift = shift + (c[3] or 0)
					if c[1] == s.id then
						gone = { cells = cells, before = #cells }
					end
				end
			end
			if #cells > 0 then
				rows[#rows + 1] = { h = r.h or H, cells = cells }
			end
		end
	end

	local function find(win)
		for ri, r in ipairs(rows) do
			for ci, c in ipairs(r.cells) do
				if c[1] == win then
					return ri, ci
				end
			end
		end
	end
	-- Move the cells of row r that start at or after x along by d.
	local function push(r, x, d)
		for _, c in ipairs(r.cells) do
			if c[2] >= x then
				c[2] = c[2] + d
			end
		end
	end
	local function free(r, x0, x1)
		for _, c in ipairs(r.cells) do
			if c[2] < x1 and c[2] + c[3] > x0 then
				return false
			end
		end
		return true
	end
	local function sort(r)
		table.sort(r.cells, function(a, b)
			return a[2] < b[2]
		end)
	end

	for _, win in ipairs(L.windows(s)) do
		if not find(win) then
			if #rows == 0 then
				rows[1] = { h = H, cells = { { win, 0, W } } }
			else
				local ri, ci = find(s.prev_id)
				if not ri then
					ri = #rows
					ci = #rows[ri].cells
				end
				local p = rows[ri].cells[ci]
				if dir_of(p[1]) == "h" then -- right of the parent, its row pushed along
					local x = p[2] + p[3]
					push(rows[ri], x, W)
					table.insert(rows[ri].cells, { win, x, W })
					sort(rows[ri])
				else -- under the parent, as wide as it
					local below = rows[ri + 1]
					if below and free(below, p[2], p[2] + p[3]) then
						table.insert(below.cells, { win, p[2], p[3] })
						sort(below)
					else
						table.insert(rows, ri + 1, { h = H, cells = { { win, p[2], p[3] } } })
					end
				end
			end
		end
	end

	if #rows == 0 then
		wm.set_virtual_size(W, H)
		wm.set_pan(0, 0)
		return L.done(s, {}, false)
	end

	if s.event == "resize" then -- keep the sizes the user dragged to
		for _, r in ipairs(rows) do
			local h = 0
			for _, c in ipairs(r.cells) do
				local g = L.geometry(s, c[1])
				if g then
					local w = math.max(100, g.width)
					push(r, c[2] + c[3], w - c[3])
					c[3] = w
					h = math.max(h, g.height)
				end
			end
			if h > 0 then
				r.h = math.max(100, h)
			end
		end
	end

	local nodes, ids, rect, y, vw = {}, {}, {}, 0, W
	for _, r in ipairs(rows) do
		for _, c in ipairs(r.cells) do
			ids[#ids + 1] = c[1]
			rect[c[1]] = { c[2], y, c[3], r.h }
			nodes[#nodes + 1] = { id = c[1], constraints = { L.cell_abs(L.key(0), c[2], y, c[3], r.h) } }
			vw = math.max(vw, c[2] + c[3])
		end
		y = y + r.h
	end
	local vh = math.max(y, H)
	nodes[#nodes + 1] = { id = L.key(0), constraints = L.fixed(0, 0, vw, vh) }
	wm.set_virtual_size(vw, vh)

	-- Pan just enough to have win on screen.
	local function reveal(win)
		local r = rect[win]
		if not r then
			return
		end
		local px, py = wm.get_pan()
		if r[1] < px or r[1] + r[3] > px + W then
			px = r[1]
		end
		if r[2] < py or r[2] + r[4] > py + H then
			py = r[2]
		end
		wm.set_pan(px, py)
	end

	if s.event == "map" or s.event == "focus" then
		reveal(s.id)
		indicate(ids, s.id)
	elseif s.event == "unmap" then
		local t
		if present[s.prev_id] then
			t = s.prev_id
		elseif gone and #gone.cells > 0 then -- its left neighbour, or the one that took its place
			t = gone.cells[math.max(1, gone.before)][1]
		else
			t = rows[1].cells[1][1]
		end
		reveal(t)
		focus(t)
		indicate(ids, t)
	end
	return L.done(s, nodes, { rows = rows })
end

-- Manual: i3-style. A new window joins the focused one's split if that split
-- runs in the focused window's direction (Super+T); otherwise the two get a
-- split of their own. A tree is a window, or { k, axis, kids, ratios }.
local function m_leaves(t, out)
	out = out or {}
	if t == nil then
		return out
	end
	if type(t) ~= "table" then
		out[#out + 1] = t
		return out
	end
	for _, c in ipairs(t.kids) do
		m_leaves(c, out)
	end
	return out
end

local function m_containers(t, out)
	out = out or {}
	if type(t) == "table" then
		out[#out + 1] = t
		for _, c in ipairs(t.kids) do
			m_containers(c, out)
		end
	end
	return out
end

-- The container holding target, and where.
local function m_parent(t, target)
	if type(t) ~= "table" then
		return nil
	end
	for i, c in ipairs(t.kids) do
		if c == target then
			return t, i
		end
		local p, j = m_parent(c, target)
		if p then
			return p, j
		end
	end
end

local function renorm(r)
	local sum, out = 0, {}
	for _, v in ipairs(r) do
		sum = sum + v
	end
	for i, v in ipairs(r) do
		out[i] = sum > 0 and v / sum or 1 / #r
	end
	return out
end

local function m_insert(s, st, win)
	if st.tree == nil then
		st.tree = win
		return
	end
	local ls = m_leaves(st.tree)
	local f = ls[1]
	if s.prev_id and contains(ls, s.prev_id) then
		f = s.prev_id
	else
		for _, x in ipairs(ls) do
			if L.area(s, x) > L.area(s, f) then
				f = x
			end
		end
	end
	local axis = dir_of(f)
	DIRS[win] = axis -- a new window inherits its parent's direction
	local p, i = m_parent(st.tree, f)
	if p and p.axis == axis then -- join f's split, right after it, with f's share
		table.insert(p.kids, i + 1, win)
		table.insert(p.ratios, i + 1, p.ratios[i] or 1 / #p.kids)
		p.ratios = renorm(p.ratios)
		return
	end
	local pair = { k = st.key, axis = axis, kids = { f, win }, ratios = { 0.5, 0.5 } }
	st.key = st.key + 1
	if p then
		p.kids[i] = pair
	else
		st.tree = pair
	end
end

local function m_remove(st, win)
	local p, i = m_parent(st.tree, win)
	if not p then -- the lone root window
		st.tree = nil
		return
	end
	table.remove(p.kids, i)
	table.remove(p.ratios, i)
	p.ratios = renorm(p.ratios)
	if #p.kids == 1 then -- a split of one: its child takes its place
		local gp, j = m_parent(st.tree, p)
		if gp then
			gp.kids[j] = p.kids[1]
		else
			st.tree = p.kids[1]
		end
	end
end

local function m_build(t)
	if type(t) ~= "table" then
		return t
	end
	local kids = {}
	for i, c in ipairs(t.kids) do
		kids[i] = m_build(c)
	end
	return L.branch(t.axis, kids, { key = t.k, ratios = t.ratios })
end

local function manual(s)
	local st = L.state(s, { key = 1 })
	if type(st.key) ~= "number" then
		st.key = 1
	end
	for _, c in ipairs(m_containers(st.tree)) do -- ratios as duckwm has them: resizes stick
		local r = L.ratios_of(s, c.k)
		if r and #r == #c.kids then
			c.ratios = r
		end
	end
	local present = set(L.windows(s))
	for _, w in ipairs(m_leaves(st.tree)) do
		if not present[w] then
			m_remove(st, w)
			DIRS[w] = nil
		end
	end
	local have = set(m_leaves(st.tree))
	for _, w in ipairs(L.windows(s)) do
		if not have[w] then
			m_insert(s, st, w)
		end
	end
	local ids = m_leaves(st.tree)
	if s.event == "map" or s.event == "focus" then
		indicate(ids, s.id)
	elseif s.event == "unmap" and #ids > 0 then
		indicate(ids, contains(ids, s.prev_id) and s.prev_id or nil)
	end
	return L.done(s, L.compile(s, m_build(st.tree)), st)
end

-- ============================================================
-- Arrangers. set_arranger takes a factory; state lives in duckwm, so every
-- workspace shares the one function. A layout that fails is reported and
-- laid out as a grid this time, its state reset so the next call starts over.
-- ============================================================
local function arranger(name, f)
	return function()
		return function(_, _, _, s)
			local ok, layout, state = pcall(f, s)
			if ok then
				return layout, state
			end
			complain("layout " .. name, layout)
			local nodes = grid(s)
			return nodes, false
		end
	end
end

local LAYOUTS = {
	{ "fair", fair },
	{ "grid", grid },
	{ "dwindle", dwindle },
	{ "scroller2d", scroller2d },
	{ "manual", manual },
}

local function use(i)
	wm.set_arranger(arranger(LAYOUTS[i][1], LAYOUTS[i][2]), LAYOUTS[i][1])
	wm.set_arranger_index(i)
	say("layout: " .. LAYOUTS[i][1], 1500)
end

section("layouts", function()
	-- Super+Shift+N: the next layout on this workspace.
	bind(M | S, "n", "next layout", function()
		use((wm.get_arranger_index() or 0) % #LAYOUTS + 1)
	end)
	-- Super+T: where the next window goes (right or below), in scroller2d and manual.
	bind(M, "t", "split direction", function()
		local f = wm.get_focused()
		local name = wm.get_arranger_name()
		if not f or (name ~= "scroller2d" and name ~= "manual") then
			return
		end
		DIRS[f] = dir_of(f) == "h" and "v" or "h"
		indicate({ f }, f)
	end)
	wm.set_default_arranger(arranger("fair", fair), "fair")
end)
