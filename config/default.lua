wm.set_resize_modifier(wm.MOD_ALT)
wm.set_float_modifier(wm.MOD_ALT)

local M = wm.MOD_SUPER
local S = wm.MOD_SHIFT
local C = wm.MOD_CTRL

local LAYOUT = "grid"  -- "dwindle", "grid", or "meridian"

-- ==================================================================
--  Common keybindings
-- ==================================================================

wm.bind(M,     "z",         function() wm.spawn({"xterm"}) end)
wm.bind(M,     "q",         wm.kill_client)
wm.bind(M,     "h",         wm.focus_left)
wm.bind(M,     "l",         wm.focus_right)
wm.bind(M,     "k",         wm.focus_up)
wm.bind(M,     "j",         wm.focus_down)
wm.bind(M | S, "h",         wm.exchange_left)
wm.bind(M | S, "l",         wm.exchange_right)
wm.bind(M | S, "k",         wm.exchange_up)
wm.bind(M | S, "j",         wm.exchange_down)
wm.bind(M | C, "h",         function() wm.resize_focused_edge("left",  20) end)
wm.bind(M | C, "l",         function() wm.resize_focused_edge("right", 20) end)
wm.bind(M | C, "k",         function() wm.resize_focused_edge("up",    20) end)
wm.bind(M | C, "j",         function() wm.resize_focused_edge("down",  20) end)
wm.bind(M | C, "r",         function() wm.resize_focused_corner(10, 10) end)
wm.bind(M,     "f",         wm.toggle_floating)
wm.bind(M,     "y",         wm.enter_nested)
wm.bind(M,     "BackSpace", wm.leave_nested)

wm.bind(M, "w", function()
    wm.create_nested_workspace()
end)

for i = 1, 9 do
    local idx = i
    wm.bind(M | C, tostring(idx), function() wm.switch_to_workspace(idx) end)
end

-- ==================================================================
--  Layout factory functions
-- ==================================================================

local function make_dwindle()
    local par, spl, ch = {}, {}, {}
    local root   = nil
    local anchor = nil

    local function is_win(id) return wm.get_node_type(id) == "window"    end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function get_anchor()
        if not anchor then anchor = wm.create_container() end
        return anchor
    end

    local function rebuild()
        if not root then return end
        local function walk(id, container, col, row, cols, rows)
            wm.clear_constraints(id)
            wm.grid_cell(id, col, row, cols, rows, container)
            if ch[id] then
                local ca, cb = ch[id][1], ch[id][2]
                if spl[id] == "h" then
                    walk(ca, id, 0, 0, 2, 1)
                    walk(cb, id, 1, 0, 2, 1)
                else
                    walk(ca, id, 0, 0, 1, 2)
                    walk(cb, id, 0, 1, 1, 2)
                end
            end
        end
        walk(root, get_anchor(), 0, 0, 1, 1)
    end

    local function do_split(focused, new_id)
        local dx, dy  = wm.get_cursor_relative_to_focused()
        local geo     = wm.get_node_geometry(focused)
        local split_h = (geo.width >= geo.height)
        local as_first = split_h and (dx < 0) or (dy < 0)
        local cont    = wm.create_container()
        local old_par = par[focused]
        spl[cont]    = split_h and "h" or "v"
        ch[cont]     = as_first and { new_id, focused } or { focused, new_id }
        par[cont]    = old_par
        par[focused] = cont
        par[new_id]  = cont
        if old_par then
            local c = ch[old_par]
            if c[1] == focused then c[1] = cont else c[2] = cont end
        else
            root = cont
        end
        rebuild()
    end

    local function do_remove(id)
        local p = par[id]
        if not p then
            root    = nil
            par[id] = nil
            anchor  = nil
            return
        end
        local sibling = (ch[p][1] == id) and ch[p][2] or ch[p][1]
        local gp = par[p]
        par[id] = nil; ch[p] = nil; spl[p] = nil; par[p] = nil
        par[sibling] = gp
        if gp then
            local c = ch[gp]
            if c[1] == p then c[1] = sibling else c[2] = sibling end
        else
            root   = sibling
            anchor = nil
        end
        wm.clear_constraints(id)
        wm.destroy_container(p)
        rebuild()
    end

    return function(event, id, prev_id)
        if not is_win(id) and not is_ws(id) then return end
        if event == "map" then
            if not prev_id then
                root = id; par[id] = nil
                rebuild()
            else
                do_split(prev_id, id)
            end
            wm.focus(id)
        elseif event == "unmap" then
            do_remove(id)
        end
    end
end

-- ------------------------------------------------------------------

local function make_grid()
    local windows      = {}
    local cell_node    = {}
    local container_id = nil
    local cols, rows   = 0, 0

    local function is_win(id) return wm.get_node_type(id) == "window"    end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function hsv_to_rgb(h, s, v)
        local c = v * s
        local x = c * (1 - math.abs((h / 60) % 2 - 1))
        local r, g, b = 0, 0, 0
        if     h < 60  then r, g, b = c, x, 0
        elseif h < 120 then r, g, b = x, c, 0
        elseif h < 180 then r, g, b = 0, c, x
        elseif h < 240 then r, g, b = 0, x, c
        elseif h < 300 then r, g, b = x, 0, c
        else                r, g, b = c, 0, x end
        return (math.floor(r*255) << 16) | (math.floor(g*255) << 8) | math.floor(b*255)
    end

    local function best_grid(n)
        if n <= 1 then return 1, 1 end
        local c = math.ceil(math.sqrt(n))
        return c, math.ceil(n / c)
    end

    local function get_container()
        if not container_id then container_id = wm.create_root_node() end
        return container_id
    end

    local function rebuild()
        local win_set = {}
        for _, v in ipairs(windows) do win_set[v] = true end
        local old_total = cols * rows
        for i = 1, old_total do
            local n = cell_node[i]
            if n and not win_set[n] and wm.get_node_type(n) == "empty" then
                wm.remove_node(n)
            end
        end

        local n = #windows
        if n == 0 then
            cols, rows, cell_node = 0, 0, {}
            container_id = nil  -- reset so next map gets a fresh root node
            return
        end

        local new_cols, new_rows = best_grid(n)
        cols, rows = new_cols, new_rows
        local total = cols * rows
        cell_node = {}

        local cont = get_container()
        for i = 1, total do
            cell_node[i] = (i <= n) and windows[i] or wm.create_empty_node()
            if i <= n then wm.clear_constraints(windows[i]) end
        end
        for i = 1, total do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            wm.grid_cell(cell_node[i], col, row, cols, rows, cont)
        end
    end

    return function(event, id, prev_id)
        if not is_win(id) and not is_ws(id) then return end

        if event == "map" then
            wm.set_node_unfocused_border_color(id, hsv_to_rgb((id * 31) % 360, 1.0, 1.0))
            table.insert(windows, id)
            wm.focus(id)
        elseif event == "unmap" then
            for i, wid in ipairs(windows) do
                if wid == id then table.remove(windows, i); break end
            end
        end
        rebuild()
    end
end

-- ------------------------------------------------------------------

local function make_meridian()
    local SW = wm.screen_width()
    local SH = wm.screen_height()
    local E_W_pct = 0.27
    local W_W_pct = 0.22
    local N_H_pct = 0.20
    local S_H_pct = 0.23
    local windows = {}

    local function is_win(id) return wm.get_node_type(id) == "window"    end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function place(id, x, y, w, h)
        wm.clear_constraints(id)
        wm.fixed_x(id, x);     wm.fixed_y(id, y)
        wm.fixed_width(id, w); wm.fixed_height(id, h)
    end

    local function relayout()
        local n = #windows
        if n == 0 then return end
        local east, south, west, north = {}, {}, {}, {}
        for i = 2, n do
            local cycle = (i - 2) % 4
            if     cycle == 0 then table.insert(east,  i)
            elseif cycle == 1 then table.insert(south, i)
            elseif cycle == 2 then table.insert(west,  i)
            else                    table.insert(north, i) end
        end
        local ww = (#west  > 0) and math.floor(SW * W_W_pct) or 0
        local ew = (#east  > 0) and math.floor(SW * E_W_pct) or 0
        local nh = (#north > 0) and math.floor(SH * N_H_pct) or 0
        local sh = (#south > 0) and math.floor(SH * S_H_pct) or 0
        local mw = SW - ww - ew
        local mh = SH - nh - sh
        place(windows[1], ww, nh, mw, mh)
        for j, idx in ipairs(east) do
            local slot_h = math.floor(mh / #east)
            local y = nh + (j-1)*slot_h
            local h = (j == #east) and (mh - (j-1)*slot_h) or slot_h
            place(windows[idx], ww+mw, y, ew, h)
        end
        for j, idx in ipairs(south) do
            local slot_w = math.floor(SW / #south)
            local x = (j-1)*slot_w
            local w = (j == #south) and (SW - (j-1)*slot_w) or slot_w
            place(windows[idx], x, nh+mh, w, sh)
        end
        for j, idx in ipairs(west) do
            local slot_h = math.floor(mh / #west)
            local y = nh + (j-1)*slot_h
            local h = (j == #west) and (mh - (j-1)*slot_h) or slot_h
            place(windows[idx], 0, y, ww, h)
        end
        for j, idx in ipairs(north) do
            local slot_w = math.floor(SW / #north)
            local x = (j-1)*slot_w
            local w = (j == #north) and (SW - (j-1)*slot_w) or slot_w
            place(windows[idx], x, 0, w, nh)
        end
    end

    local function remove_from_list(id)
        for i, wid in ipairs(windows) do
            if wid == id then table.remove(windows, i); return end
        end
    end

    local function promote_focused()
        local fid = wm.get_focused()
        if not fid then return end
        for i, id in ipairs(windows) do
            if id == fid and i > 1 then
                windows[i] = windows[1]; windows[1] = fid
                relayout(); return
            end
        end
    end

    local function rotate_forward()
        if #windows < 2 then return end
        table.insert(windows, table.remove(windows, 1)); relayout()
    end

    local function rotate_back()
        if #windows < 2 then return end
        table.insert(windows, 1, table.remove(windows)); relayout()
    end

    local function resize_strip(axis, delta)
        if axis == "h" then
            W_W_pct = math.max(0.05, math.min(0.45, W_W_pct + delta))
            E_W_pct = math.max(0.05, math.min(0.45, E_W_pct + delta))
        elseif axis == "k" then
            N_H_pct = math.max(0.05, math.min(0.45, N_H_pct + delta))
            S_H_pct = math.max(0.05, math.min(0.45, S_H_pct + delta))
        end
        relayout()
    end

    wm.bind(M | wm.MOD_ALT, "h", function() resize_strip("h", -0.02) end)
    wm.bind(M | wm.MOD_ALT, "l", function() resize_strip("h",  0.02) end)
    wm.bind(M | wm.MOD_ALT, "k", function() resize_strip("k", -0.02) end)
    wm.bind(M | wm.MOD_ALT, "j", function() resize_strip("k",  0.02) end)
    wm.bind(M,     "Return", promote_focused)
    wm.bind(M,     "Tab",    rotate_forward)
    wm.bind(M | S, "Tab",    rotate_back)

    return function(event, id, prev_id)
        if not is_win(id) and not is_ws(id) then return end
        if event == "map" then
            table.insert(windows, id)
            wm.focus(id)
        elseif event == "unmap" then
            remove_from_list(id)
        end
        relayout()
    end
end

-- ==================================================================
--  Layout registry and default arranger factory
-- ==================================================================

local makers = {
    dwindle  = make_dwindle,
    grid     = make_grid,
    meridian = make_meridian,
}

wm.set_default_arranger(function()
    local maker = makers[LAYOUT] or make_dwindle
    return maker()
end)
