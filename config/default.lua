-- ============================================================
-- duckwm — default configuration
-- ============================================================
-- Modifier keys available:
--   wm.MOD_SUPER  (Windows / Command key)
--   wm.MOD_ALT
--   wm.MOD_SHIFT
--   wm.MOD_CTRL
--
-- Mouse buttons available:
--   wm.BUTTON_LEFT, BUTTON_MIDDLE, BUTTON_RIGHT
--   wm.BUTTON_SCROLL_UP, BUTTON_SCROLL_DOWN
-- ============================================================

local M = wm.MOD_SUPER
local S = wm.MOD_SHIFT
local C = wm.MOD_CTRL
local A = wm.MOD_ALT

-- ------------------------------------------------------------
-- Core behaviour
-- ------------------------------------------------------------
wm.set_gaps(0, 0, 0, 0)
wm.set_resize_modifier(A)
wm.set_float_modifier(A)
wm.set_pan_modifier(A)
wm.set_pan_button(wm.BUTTON_MIDDLE)
wm.set_border_width(2)
wm.set_border_width(2)
wm.set_default_focused_border_color(0x5294e2)
wm.set_default_unfocused_border_color(0x333333)
wm.set_default_urgent_border_color(0xe53935)
wm.set_workspace_switch_mode("previous")

-- ------------------------------------------------------------
-- Terminal
-- Find the first available terminal emulator.
-- ------------------------------------------------------------
local function find_terminal()
    local candidates = {
        {"x-terminal-emulator"},
        {"xdg-terminal"},
        {"xterm"},
        {"rxvt"},
        {"st"},
        {"alacritty"},
        {"kitty"},
        {"wezterm"},
        {"foot"},
    }
    for _, cmd in ipairs(candidates) do
        local handle = io.popen("command -v " .. cmd[1] .. " 2>/dev/null")
        if handle then
            local result = handle:read("*l")
            handle:close()
            if result and result ~= "" then
                return cmd
            end
        end
    end
    return {"xterm"}
end

local TERMINAL = find_terminal()

-- ------------------------------------------------------------
-- Application launcher
-- ------------------------------------------------------------
local function find_launcher()
    local candidates = {"rofi", "dmenu_run", "gmrun"}
    for _, cmd in ipairs(candidates) do
        local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
        if handle then
            local result = handle:read("*l")
            handle:close()
            if result and result ~= "" then
                if cmd == "rofi" then
                    return {"rofi", "-show", "drun"}
                end
                return {cmd}
            end
        end
    end
    return nil
end

local LAUNCHER = find_launcher()

-- ------------------------------------------------------------
-- Scratchpad
-- ------------------------------------------------------------
local scratchpad_id      = nil
local scratchpad_visible = false

local function toggle_scratchpad()
    if scratchpad_id ~= nil then
        if wm.get_node_type(scratchpad_id) == nil then
            scratchpad_id    = nil
            scratchpad_visible = false
        end
    end

    if scratchpad_id == nil then
        local id = wm.get_focused()
        if not id then return end
        local info = wm.get_node_info(id)
        if not info then return end
        scratchpad_id    = id
        scratchpad_visible = true
        if not info.floating then wm.toggle_floating() end
        return
    end

    if scratchpad_visible then
        wm.hide_window(scratchpad_id)
        scratchpad_visible = false
    else
        wm.show_window(scratchpad_id)
        scratchpad_visible = true
    end
end

local function unscratchpad()
    if scratchpad_id and wm.get_node_type(scratchpad_id) then
        if not scratchpad_visible then
            wm.show_window(scratchpad_id)
            scratchpad_visible = true
            wm.toggle_floating()
            scratchpad_id = nil
        else
            wm.toggle_floating()
            scratchpad_id = nil
        end
    end
end

-- ============================================================
-- Window rules
-- ============================================================
-- Rules fire on "pre_map" (before layout), "map" (after layout),
-- and "prop" (when WM_CLASS or title changes — useful for apps
-- that set their class late, like Electron apps).
--
-- Example:
--   wm.add_rule(function(event, id)
--       if event ~= "pre_map" and event ~= "prop" then return end
--       local class = wm.get_window_class(id) or ""
--       if class == "pavucontrol" then wm.set_floating(id, true) end
--   end)

-- ============================================================
-- Keybindings
-- ============================================================

-- Terminal
wm.bind(M, "Return", function() wm.spawn(TERMINAL) end)

-- Launcher
if LAUNCHER then
    wm.bind(M, "d", function() wm.spawn(LAUNCHER) end)
end

-- Window management
wm.bind(M | S, "q",      wm.kill_client)
wm.bind(M,     "f",      wm.toggle_floating)
wm.bind(M,     "F11",    wm.toggle_fullscreen)
wm.bind(M,     "s",      toggle_scratchpad)
wm.bind(M,     "Escape", unscratchpad)

-- Focus
wm.bind(M, "h",     wm.focus_left)
wm.bind(M, "l",     wm.focus_right)
wm.bind(M, "k",     wm.focus_up)
wm.bind(M, "j",     wm.focus_down)
wm.bind(M, "Left",  wm.focus_left)
wm.bind(M, "Right", wm.focus_right)
wm.bind(M, "Up",    wm.focus_up)
wm.bind(M, "Down",  wm.focus_down)

-- Move (swap)
wm.bind(M | S, "h",     function() wm.exchange_left();  wm.focus_left()  end)
wm.bind(M | S, "l",     function() wm.exchange_right(); wm.focus_right() end)
wm.bind(M | S, "k",     function() wm.exchange_up();    wm.focus_up()    end)
wm.bind(M | S, "j",     function() wm.exchange_down();  wm.focus_down()  end)
wm.bind(M | S, "Left",  function() wm.exchange_left();  wm.focus_left()  end)
wm.bind(M | S, "Right", function() wm.exchange_right(); wm.focus_right() end)
wm.bind(M | S, "Up",    function() wm.exchange_up();    wm.focus_up()    end)
wm.bind(M | S, "Down",  function() wm.exchange_down();  wm.focus_down()  end)

-- Resize
wm.bind(M | C, "h",     function() wm.resize_focused_edge("left",  20) end)
wm.bind(M | C, "l",     function() wm.resize_focused_edge("right", 20) end)
wm.bind(M | C, "k",     function() wm.resize_focused_edge("up",    20) end)
wm.bind(M | C, "j",     function() wm.resize_focused_edge("down",  20) end)
wm.bind(M | C, "Left",  function() wm.resize_focused_edge("left",  20) end)
wm.bind(M | C, "Right", function() wm.resize_focused_edge("right", 20) end)
wm.bind(M | C, "Up",    function() wm.resize_focused_edge("up",    20) end)
wm.bind(M | C, "Down",  function() wm.resize_focused_edge("down",  20) end)

-- Nested workspaces
wm.bind(M,     "w",         function() wm.create_nested_workspace() end)
wm.bind(M,     "y",         wm.enter_nested)
wm.bind(M,     "BackSpace", wm.leave_nested)

-- Workspace switching (Super+1-9)
-- Send window to workspace (Super+Shift+1-9)
-- Send window to workspace silently (Alt+1-9)
for i = 1, 9 do
    local idx = i
    wm.bind(M,     tostring(idx), function() wm.switch_to_workspace(idx) end)
    wm.bind(M | S, tostring(idx), function()
        local id = wm.get_focused()
        if id then
            wm.send_to_workspace(id, idx)
            wm.switch_to_workspace(idx)
        end
    end)
    wm.bind(A, tostring(idx), function()
        local id = wm.get_focused()
        if id then wm.send_to_workspace(id, idx) end
    end)
end

-- duckwm
wm.bind(M | S, "r", wm.reload_config)
wm.bind(M | S, "e", wm.quit)

-- ============================================================
-- Layout implementations
-- ============================================================

-- ------------------------------------------------------------
-- Dwindle
-- ------------------------------------------------------------
local function make_dwindle()
    local next_split = "h"
    local anchor_id  = nil

    local function find_parent_split(by_id, id)
        local node = by_id[id]
        if not node or not node.parent then return nil, nil end
        local parent = by_id[node.parent]
        if not parent then return nil, nil end
        for _, con in ipairs(parent.constraints) do
            if con.type == "split" then return parent, con end
        end
        return nil, nil
    end

    local function do_split(layout, focused_id, new_id)
        local by_id = layout.by_id
        local focused_node = by_id[focused_id]

        -- If focused node is tiny, fall back to splitting the largest window
        if focused_node and (focused_node.width < 20 or focused_node.height < 20) then
            local best, best_area = nil, 0
            for _, wid in ipairs(layout.windows) do
                if wid ~= new_id then
                    local nd = by_id[wid]
                    if nd then
                        local area = nd.width * nd.height
                        if area > best_area then best, best_area = wid, area end
                    end
                end
            end
            if best then focused_id = best; focused_node = by_id[focused_id] end
        end

        local split_h  = (next_split == "h")
        next_split     = split_h and "v" or "h"
        local dx, dy   = wm.get_cursor_relative_to_focused()
        local as_first = split_h and (dx < 0) or (dy < 0)
        local axis     = split_h and "h" or "v"

        -- Create structural split container node
        local cont_id = wm.create_container()
        local cont = { id=cont_id, type="empty", x=0, y=0, width=0, height=0,
                       constraints={}, parent=nil, parent_idx=nil }
        table.insert(layout.nodes, cont)
        by_id[cont_id] = cont

        local parent, parent_con = find_parent_split(by_id, focused_id)

        if parent then
            for i, cid in ipairs(parent_con.children) do
                if cid == focused_id then
                    parent_con.children[i] = cont_id
                    break
                end
            end
            cont.parent = parent.id
        else
            -- If focused_node was the root window, transfer its grid_cell constraint to the container
            if focused_node then
                for i, con in ipairs(focused_node.constraints) do
                    if con.type == "grid_cell" then
                        table.insert(cont.constraints, con)
                        table.remove(focused_node.constraints, i)
                        break
                    end
                end
            end
        end

        local children = as_first and { new_id, focused_id } or { focused_id, new_id }
        table.insert(cont.constraints, {
            type="split", axis=axis, count=2,
            ratios={0.5, 0.5}, children=children, container=cont_id,
        })

        -- Corrected: Clear child constraints but register their new parent tree relationships
        if focused_node then 
            focused_node.constraints = {} 
            focused_node.parent = cont_id
        end
        local new_node = by_id[new_id]
        if new_node then 
            new_node.constraints = {} 
            new_node.parent = cont_id
        end
    end

    local function do_remove(layout, id)
        local by_id = layout.by_id
        local parent, parent_con = find_parent_split(by_id, id)

        if not parent then
            local nd = by_id[id]
            if nd then nd.constraints = {} end
            anchor_id = nil
            return
        end

        local sibling_id = parent_con.children[1] == id
            and parent_con.children[2] or parent_con.children[1]

        local gp, gp_con = find_parent_split(by_id, parent.id)

        if gp then
            for i, cid in ipairs(gp_con.children) do
                if cid == parent.id then
                    gp_con.children[i] = sibling_id
                    break
                end
            end
            local sibling_node = by_id[sibling_id]
            if sibling_node then sibling_node.parent = gp.id end
        else
            local sibling_node = by_id[sibling_id]
            if sibling_node then
                for _, con in ipairs(parent.constraints) do
                    if con.type == "grid_cell" then
                        table.insert(sibling_node.constraints, con)
                        break
                    end
                end
                sibling_node.parent = nil
            end
        end

        wm.destroy_container(parent.id)
        by_id[parent.id] = nil
        for i = #layout.nodes, 1, -1 do
            if layout.nodes[i].id == parent.id or layout.nodes[i].id == id then
                table.remove(layout.nodes, i)
            end
        end
        for i, wid in ipairs(layout.windows) do
            if wid == id then table.remove(layout.windows, i); break end
        end
    end

    return function(event, id, prev_id)
        if wm.get_node_type(id) ~= "window" and wm.get_node_type(id) ~= "workspace" then return end

        local layout = wm.get_layout()
        local by_id  = layout.by_id
        local _, _, ww, wh = wm.get_work_area() -- Ensure work area is calculated every event execution

        -- Force synchronization of the base anchor bounds on any incoming event changes
        if anchor_id and by_id[anchor_id] then
            by_id[anchor_id].constraints = {
                { type="fixed_x",      value=0  },
                { type="fixed_y",      value=0  },
                { type="fixed_width",  value=ww },
                { type="fixed_height", value=wh },
            }
        end

        if event == "map" then
            local focused_id = prev_id and by_id[prev_id] and prev_id or nil
            if not focused_id then
                local best, best_area = nil, 0
                for _, wid in ipairs(layout.windows) do
                    if wid ~= id then
                        local nd = by_id[wid]
                        if nd then
                            local area = nd.width * nd.height
                            if area > best_area then best, best_area = wid, area end
                        end
                    end
                end
                focused_id = best
            end

            if not focused_id then
                if not anchor_id or not by_id[anchor_id] then
                    anchor_id = wm.create_container()
                    local anchor = {
                        id=anchor_id, type="empty", x=0, y=0, width=0, height=0,
                        parent=nil, parent_idx=nil,
                        constraints={
                            { type="fixed_x",      value=0  },
                            { type="fixed_y",      value=0  },
                            { type="fixed_width",  value=ww },
                            { type="fixed_height", value=wh },
                        },
                    }
                    table.insert(layout.nodes, anchor)
                    by_id[anchor_id] = anchor
                    layout.root = anchor_id
                end
                local win_node = by_id[id]
                if win_node then
                    win_node.constraints = {{
                        type="grid_cell", col=0, row=0, cols=1, rows=1,
                        container=anchor_id,
                    }}
                end
            else
                do_split(layout, focused_id, id)
            end

            wm.set_layout(layout)
            wm.focus(id)

        elseif event == "unmap" then
            do_remove(layout, id)
            wm.set_layout(layout)

        elseif event == "resize" then
            -- Let duckwm know the dynamic geometry updates need to commit to the layout engine
            wm.set_layout(layout)
        end
    end
end

-- ------------------------------------------------------------
-- Grid
-- ------------------------------------------------------------
local function make_grid()
    local function best_grid(n)
        if n <= 1 then return 1, 1 end
        local c = math.ceil(math.sqrt(n))
        return c, math.ceil(n / c)
    end

    return function(event, id, prev_id)
        if wm.get_node_type(id) ~= "window" and wm.get_node_type(id) ~= "workspace" then return end

        local layout = wm.get_layout()
        local by_id  = layout.by_id

        local windows = {}
        for _, wid in ipairs(layout.windows) do
            if event ~= "unmap" or wid ~= id then
                table.insert(windows, wid)
            end
        end

        for _, nd in ipairs(layout.nodes) do nd.constraints = {} end

        if #windows == 0 then
            wm.set_layout(layout)
            return
        end

        local root = by_id[layout.root]
        if not root then
            local root_id = wm.create_root_node()
            root = { id=root_id, type="empty", x=0, y=0, width=0, height=0,
                     constraints={}, parent=nil, parent_idx=nil }
            table.insert(layout.nodes, root)
            by_id[root_id] = root
            layout.root = root_id
        end

        local _, _, ww, wh = wm.get_work_area()
        root.constraints = {
            { type="fixed_x",      value=0  },
            { type="fixed_y",      value=0  },
            { type="fixed_width",  value=ww },
            { type="fixed_height", value=wh },
        }

        local cols, rows = best_grid(#windows)
        for i, wid in ipairs(windows) do
            local nd = by_id[wid]
            if nd then
                nd.constraints = {{
                    type="grid_cell",
                    col  = (i-1) % cols,
                    row  = math.floor((i-1) / cols),
                    cols = cols, rows = rows,
                    container = root.id,
                }}
            end
        end

        wm.set_layout(layout)
        if event == "map" then wm.focus(id) end
    end
end

-- ------------------------------------------------------------
-- Fair
-- ------------------------------------------------------------
local function make_fair()
    local function grid_params(n)
        if n == 2 then return 1, 2 end
        local rows = math.ceil(math.sqrt(n))
        return rows, math.ceil(n / rows)
    end

    return function(event, id, prev_id)
        if wm.get_node_type(id) ~= "window" and wm.get_node_type(id) ~= "workspace" then return end

        local layout = wm.get_layout()
        local by_id  = layout.by_id

        local windows = {}
        for _, wid in ipairs(layout.windows) do
            if event ~= "unmap" or wid ~= id then
                table.insert(windows, wid)
            end
        end

        if #windows == 0 then
            for _, nd in ipairs(layout.nodes) do nd.constraints = {} end
            wm.set_layout(layout)
            return
        end

        local n = #windows
        local rows, cols = grid_params(n)

        local root = by_id[layout.root]

        local col_conts  = {}
        local col_ratios = {}
        local row_ratios = {}

        if root then
            for _, con in ipairs(root.constraints) do
                if con.type == "split" and con.axis == "h" then
                    col_ratios = con.ratios
                    for _, cid in ipairs(con.children) do
                        if by_id[cid] then table.insert(col_conts, by_id[cid]) end
                    end
                    break
                end
            end
            if #col_conts == 0 then
                for _, nd in ipairs(layout.nodes) do
                    if nd.type == "empty" and nd.id ~= root.id then
                        for _, con in ipairs(nd.constraints) do
                            if con.type == "grid_cell" and con.container == root.id then
                                table.insert(col_conts, nd); break
                            end
                        end
                    end
                end
            end
        end

        for c, cc in ipairs(col_conts) do
            for _, con in ipairs(cc.constraints) do
                if con.type == "split" and con.axis == "v" then
                    row_ratios[c] = con.ratios; break
                end
            end
        end

        if not root then
            local root_id = wm.create_root_node()
            root = { id=root_id, type="empty", x=0, y=0, width=0, height=0, constraints={} }
            table.insert(layout.nodes, root)
            by_id[root_id] = root
            layout.root = root_id
        end

        while #col_conts < cols do
            local cid = wm.create_container()
            local nc = { id=cid, type="empty", x=0, y=0, width=0, height=0, constraints={} }
            table.insert(layout.nodes, nc)
            by_id[cid] = nc
            table.insert(col_conts, nc)
        end
        while #col_conts > cols do
            local excess = table.remove(col_conts)
            wm.destroy_container(excess.id)
            by_id[excess.id] = nil
            for i = #layout.nodes, 1, -1 do
                if layout.nodes[i].id == excess.id then
                    table.remove(layout.nodes, i); break
                end
            end
        end

        for _, nd in ipairs(layout.nodes) do nd.constraints = {} end

        local _, _, ww, wh = wm.get_work_area()
        root.constraints = {
            { type="fixed_x",      value=0  },
            { type="fixed_y",      value=0  },
            { type="fixed_width",  value=ww },
            { type="fixed_height", value=wh },
        }

        if cols == 1 then
            col_conts[1].constraints = {{
                type="grid_cell", col=0, row=0, cols=1, rows=1, container=root.id
            }}
        else
            local cr, cr_sum = {}, 0
            for c = 1, cols do
                cr[c] = (#col_ratios == cols and col_ratios[c]) or 1.0
                cr_sum = cr_sum + cr[c]
            end
            for c = 1, cols do cr[c] = cr[c] / cr_sum end
            local children = {}
            for c = 1, cols do table.insert(children, col_conts[c].id) end
            root.constraints[#root.constraints+1] = {
                type="split", axis="h", count=cols,
                ratios=cr, children=children, container=root.id,
            }
        end

        local col_wins = {}
        for c = 1, cols do col_wins[c] = {} end
        for k, wid in ipairs(windows) do
            local col = math.floor((k-1) / rows) + 1
            table.insert(col_wins[col], wid)
        end

        for c = 1, cols do
            local wins = col_wins[c]
            local nw   = #wins
            local rr   = row_ratios[c] or {}
            if nw == 1 then
                by_id[wins[1]].constraints = {{
                    type="grid_cell", col=0, row=0,
                    cols=1, rows=1, container=col_conts[c].id
                }}
            elseif nw > 1 then
                local hr, hr_sum = {}, 0
                for r = 1, nw do
                    hr[r] = (#rr == nw and rr[r]) or 1.0
                    hr_sum = hr_sum + hr[r]
                end
                for r = 1, nw do hr[r] = hr[r] / hr_sum end
                local children = {}
                for _, wid in ipairs(wins) do
                    table.insert(children, wid)
                    by_id[wid].constraints = {}
                end
                col_conts[c].constraints = {{
                    type="split", axis="v", count=nw,
                    ratios=hr, children=children,
                    container=col_conts[c].id,
                }}
            end
        end

        wm.set_layout(layout)
        if event == "map" then wm.focus(id) end
    end
end

-- ------------------------------------------------------------
-- Meridian
-- ------------------------------------------------------------
local function make_meridian()
    local SW = wm.screen_width()
    local SH = wm.screen_height()

    local function fresh_state()
        return { E_W_pct=0.15, W_W_pct=0.15, N_H_pct=0.15, S_H_pct=0.15, windows={} }
    end
    local state = fresh_state()

    local function is_win(id) return wm.get_node_type(id) == "window" end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function place(id, x, y, w, h)
        wm.clear_constraints(id)
        wm.fixed_x(id, x); wm.fixed_y(id, y)
        wm.fixed_width(id, w); wm.fixed_height(id, h)
    end

    local function get_strips(n)
        local east, south, west, north = {}, {}, {}, {}
        for i = 2, n do
            local cycle = (i-2) % 4
            if     cycle == 0 then table.insert(east,  i)
            elseif cycle == 1 then table.insert(south, i)
            elseif cycle == 2 then table.insert(west,  i)
            else                    table.insert(north, i) end
        end
        return east, south, west, north
    end

    local function sync_from_graph()
        if #state.windows == 0 then return end
        local geo = wm.get_node_geometry(state.windows[1])
        if not geo then return end
        local _, wy, _, _ = wm.get_work_area()
        local avail_h = SH - wy
        local rel_y = geo.y - wy
        local east, south, west, north = get_strips(#state.windows)

        if #west  > 0 then state.W_W_pct = math.max(0.05, math.min(0.40, geo.x / SW)) end
        if #east  > 0 then state.E_W_pct = math.max(0.05, math.min(0.40, (SW - geo.x - geo.width) / SW)) end
        if #north > 0 then state.N_H_pct = math.max(0.05, math.min(0.40, rel_y / avail_h)) end
        if #south > 0 then state.S_H_pct = math.max(0.05, math.min(0.40, (avail_h - rel_y - geo.height) / avail_h)) end

        if #west > 0 and #east > 0 and state.W_W_pct + state.E_W_pct > 0.85 then
            local scale = 0.85 / (state.W_W_pct + state.E_W_pct)
            state.W_W_pct = state.W_W_pct * scale
            state.E_W_pct = state.E_W_pct * scale
        end
        if #north > 0 and #south > 0 and state.N_H_pct + state.S_H_pct > 0.85 then
            local scale = 0.85 / (state.N_H_pct + state.S_H_pct)
            state.N_H_pct = state.N_H_pct * scale
            state.S_H_pct = state.S_H_pct * scale
        end
    end

    local function relayout()
        local n = #state.windows
        if n == 0 then return end
        local _, wy, _, _ = wm.get_work_area()
        local avail_h = SH - wy
        local east, south, west, north = get_strips(n)
        local ww = (#west  > 0) and math.floor(SW * state.W_W_pct) or 0
        local ew = (#east  > 0) and math.floor(SW * state.E_W_pct) or 0
        local nh = (#north > 0) and math.floor(avail_h * state.N_H_pct) or 0
        local sh = (#south > 0) and math.floor(avail_h * state.S_H_pct) or 0
        local mw = SW - ww - ew
        local mh = avail_h - nh - sh
        place(state.windows[1], ww, nh, mw, mh)
        for j, idx in ipairs(east) do
            local sh2 = math.floor(mh / #east)
            local y   = nh + (j-1)*sh2
            local h   = (j == #east) and (mh - (j-1)*sh2) or sh2
            place(state.windows[idx], ww+mw, y, ew, h)
        end
        for j, idx in ipairs(south) do
            local sw2 = math.floor(SW / #south)
            local x   = (j-1)*sw2
            local w   = (j == #south) and (SW - (j-1)*sw2) or sw2
            place(state.windows[idx], x, nh+mh, w, sh)
        end
        for j, idx in ipairs(west) do
            local sh2 = math.floor(mh / #west)
            local y   = nh + (j-1)*sh2
            local h   = (j == #west) and (mh - (j-1)*sh2) or sh2
            place(state.windows[idx], 0, y, ww, h)
        end
        for j, idx in ipairs(north) do
            local sw2 = math.floor(SW / #north)
            local x   = (j-1)*sw2
            local w   = (j == #north) and (SW - (j-1)*sw2) or sw2
            place(state.windows[idx], x, 0, w, nh)
        end
    end

    wm.bind(M, "p", function()
        local fid = wm.get_focused()
        if not fid then return end
        for i, id in ipairs(state.windows) do
            if id == fid and i > 1 then
                state.windows[i] = state.windows[1]
                state.windows[1] = fid
                relayout(); return
            end
        end
    end)
    wm.bind(M,     "Tab", function()
        if #state.windows < 2 then return end
        table.insert(state.windows, table.remove(state.windows, 1))
        relayout()
    end)
    wm.bind(M | S, "Tab", function()
        if #state.windows < 2 then return end
        table.insert(state.windows, 1, table.remove(state.windows))
        relayout()
    end)

    return function(event, id, prev_id)
        if not is_win(id) and not is_ws(id) then return end
        if event == "map" then
            if #state.windows > 0 then sync_from_graph() end
            table.insert(state.windows, id); wm.focus(id); relayout()
        elseif event == "unmap" then
            sync_from_graph()
            for i, wid in ipairs(state.windows) do
                if wid == id then table.remove(state.windows, i); break end
            end
            if #state.windows == 0 then state = fresh_state() else relayout() end
        end
    end
end

-- ------------------------------------------------------------
-- Scroller
-- ------------------------------------------------------------
local function make_scroller()
    local windows   = {}
    local cols      = 1
    local col_ws    = {}
    local container = nil

    local function is_win(id) return wm.get_node_type(id) == "window" end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function get_container()
        if not container then container = wm.create_empty_node() end
        return container
    end

    local function find_window(id)
        for _, w in ipairs(windows) do if w.id == id then return w end end
        return nil
    end

    local function find_window_idx(id)
        for i, w in ipairs(windows) do if w.id == id then return i end end
        return nil
    end

    local function default_col_w()
        local _, _, ww, _ = wm.get_work_area()
        return ww
    end

    local function sync_from_graph()
        if #windows == 0 then return end
        for c = 1, cols do
            for _, win in ipairs(windows) do
                if win.col == c then
                    local geo = wm.get_node_geometry(win.id)
                    if geo and geo.width > 0 then
                        col_ws[c] = math.max(100, geo.width)
                    end
                    break
                end
            end
        end
    end

    local function total_width()
        local total = 0
        for c = 1, cols do
            total = total + (col_ws[c] or default_col_w())
        end
        return total
    end

    local function col_offset(c)
        local x = 0
        for i = 1, c - 1 do
            x = x + (col_ws[i] or default_col_w())
        end
        return x
    end

    local function relayout()
        if #windows == 0 then return end
        local _, _, ww, wh = wm.get_work_area()
        local total = total_width()
        if total < ww then col_ws[1] = ww; total = ww end
        wm.set_virtual_size(total, wh)
        local cont = get_container()
        wm.clear_constraints(cont)
        wm.fixed_width(cont, total)
        wm.fixed_height(cont, wh)
        local offsets = {}
        local x = 0
        for c = 1, cols do
            offsets[c] = x
            x = x + (col_ws[c] or ww)
        end
        for _, win in ipairs(windows) do
            local cw = col_ws[win.col] or ww
            wm.clear_constraints(win.id)
            wm.grid_cell_abs(win.id, offsets[win.col], 0, cw, wh, cont)
        end
    end

    return function(event, id, prev_id)
        if not is_win(id) and not is_ws(id) then return end
        if event == "map" then
            sync_from_graph()
            local new_col
            if #windows == 0 then
                table.insert(windows, { id = id, col = 1 })
                col_ws[1] = col_ws[1] or default_col_w()
                cols = 1; new_col = 1
            else
                local parent_idx = #windows
                local parent = find_window(prev_id)
                if parent then
                    parent_idx = find_window_idx(prev_id)
                else
                    parent = windows[#windows]
                end
                new_col = parent.col + 1
                if new_col > cols then
                    cols = new_col
                    col_ws[new_col] = default_col_w()
                else
                    for c = cols, new_col, -1 do col_ws[c + 1] = col_ws[c] end
                    col_ws[new_col] = default_col_w()
                    for _, w in ipairs(windows) do
                        if w.col >= new_col then w.col = w.col + 1 end
                    end
                    cols = cols + 1
                end
                table.insert(windows, parent_idx + 1, { id = id, col = new_col })
            end
            relayout()
            wm.set_pan(col_offset(new_col), 0)
            wm.focus(id)
        elseif event == "unmap" then
            sync_from_graph()
            local removed_col = nil
            for i, w in ipairs(windows) do
                if w.id == id then removed_col = w.col; table.remove(windows, i); break end
            end
            if #windows == 0 then
                if container then wm.destroy_container(container); container = nil end
                wm.set_virtual_size(wm.screen_width(), wm.screen_height())
                wm.set_pan(0, 0)
                cols = 1; col_ws = {}
            else
                local col_empty = true
                for _, w in ipairs(windows) do
                    if w.col == removed_col then col_empty = false; break end
                end
                if col_empty and removed_col then
                    for c = removed_col, cols - 1 do col_ws[c] = col_ws[c + 1] end
                    col_ws[cols] = nil
                    for _, w in ipairs(windows) do
                        if w.col > removed_col then w.col = w.col - 1 end
                    end
                    cols = cols - 1
                end
                relayout()
                if prev_id and find_window(prev_id) then
                    wm.focus(prev_id)
                elseif #windows > 0 then
                    wm.focus(windows[#windows].id)
                end
            end
        end
    end
end

-- ------------------------------------------------------------
-- Scroller2D
-- ------------------------------------------------------------
local function make_scroller2d()
    local windows   = {}
    local cols      = 1
    local rows      = 1
    local container = nil

    local function is_win(id) return wm.get_node_type(id) == "window" end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function get_container()
        if not container then container = wm.create_empty_node() end
        return container
    end

    local function find_window(id)
        for _, w in ipairs(windows) do if w.id == id then return w end end
        return nil
    end

    local function find_window_idx(id)
        for i, w in ipairs(windows) do if w.id == id then return i end end
        return nil
    end

    local function relayout()
        if #windows == 0 then return end
        local _, _, ww, wh = wm.get_work_area()
        local vw, vh = ww * cols, wh * rows
        wm.set_virtual_size(vw, vh)
        local cont = get_container()
        wm.clear_constraints(cont)
        wm.fixed_width(cont, vw); wm.fixed_height(cont, vh)
        for _, win in ipairs(windows) do
            wm.clear_constraints(win.id)
            wm.grid_cell(win.id, win.col-1, win.row-1, cols, rows, cont)
        end
    end

    wm.bind(M, "t", function()
        local focused = wm.get_focused()
        if not focused then return end
        local w = find_window(focused)
        if not w then return end
        w.dir = (w.dir == "right") and "down" or "right"
    end)

    return function(event, id, prev_id)
        if not is_win(id) and not is_ws(id) then return end
        if event == "map" then
            if #windows == 0 then
                table.insert(windows, {id=id, col=1, row=1, dir="right"})
                cols = 1; rows = 1
            else
                local parent_idx = #windows
                local parent = find_window(prev_id)
                if parent then parent_idx = find_window_idx(prev_id)
                else parent = windows[#windows] end
                local new_col = parent.col
                local new_row = parent.row
                if parent.dir == "right" then
                    new_col = parent.col + 1
                    if new_col > cols then cols = new_col
                    else
                        for _, w in ipairs(windows) do
                            if w.col >= new_col then w.col = w.col + 1 end
                        end
                        cols = cols + 1
                    end
                else
                    new_row = parent.row + 1
                    if new_row > rows then rows = new_row
                    else
                        for _, w in ipairs(windows) do
                            if w.row >= new_row then w.row = w.row + 1 end
                        end
                        rows = rows + 1
                    end
                end
                table.insert(windows, parent_idx + 1, {id=id, col=new_col, row=new_row, dir="right"})
            end
            relayout(); wm.focus(id)
        elseif event == "unmap" then
            for i, w in ipairs(windows) do
                if w.id == id then table.remove(windows, i); break end
            end
            if #windows == 0 then
                if container then wm.destroy_container(container); container = nil end
                wm.set_virtual_size(wm.screen_width(), wm.screen_height())
                wm.set_pan(0, 0)
                cols = 1; rows = 1
            else
                cols = 1; rows = 1
                for _, w in ipairs(windows) do
                    if w.col > cols then cols = w.col end
                    if w.row > rows then rows = w.row end
                end
                relayout()
            end
        elseif event == "resize" then
            local _, _, ww, wh = wm.get_work_area()
            local max_col_w = ww
            local max_row_h = wh
            for _, win in ipairs(windows) do
                local geo = wm.get_node_geometry(win.id)
                if geo then
                    max_col_w = math.max(max_col_w, geo.width)
                    max_row_h = math.max(max_row_h, geo.height)
                end
            end
            local vw = math.ceil(max_col_w / cols) * cols
            local vh = math.ceil(max_row_h / rows) * rows
            wm.set_virtual_size(vw, vh)
            local cont = get_container()
            wm.remove_constraint(cont, "fixed_width")
            wm.remove_constraint(cont, "fixed_height")
            wm.fixed_width(cont, vw)
            wm.fixed_height(cont, vh)
        end
    end
end

-- ------------------------------------------------------------
-- Fibonacci
-- ------------------------------------------------------------
local function make_fibonacci()
    local PHI   = (1 + math.sqrt(5)) / 2
    local RATIO = 1 / PHI
    local REST  = 1 - RATIO

    local windows    = {}
    local containers = {}
    local anchor     = nil

    local function is_win(id) return wm.get_node_type(id) == "window" end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function get_anchor()
        if not anchor then anchor = wm.create_container() end
        return anchor
    end

    local function reset()
        for _, c in ipairs(containers) do wm.destroy_container(c) end
        containers = {}; windows = {}; anchor = nil
    end

    local steps = {
        { axis = "h", ratios = {RATIO, REST}, win_idx = 1 },
        { axis = "v", ratios = {RATIO, REST}, win_idx = 1 },
        { axis = "h", ratios = {REST, RATIO}, win_idx = 2 },
        { axis = "v", ratios = {REST, RATIO}, win_idx = 2 },
    }

    local function default_ratio(step_idx)
        local s = steps[step_idx]
        return { s.ratios[1], s.ratios[2] }
    end

    local function next_step(step_idx)
        return (step_idx % 4) + 1
    end

    local function find_idx(id)
        for i, w in ipairs(windows) do
            if w.id == id then return i end
        end
        return nil
    end

    local function rebuild(extra_ratios)
        local n = #windows
        if n == 0 then return end
        local saved = extra_ratios or {}
        for i, cont in ipairs(containers) do
            if not saved[i] then
                local r = wm.get_split_ratios(cont)
                if r then saved[i] = { r[1], r[2] } end
            end
        end
        for _, c in ipairs(containers) do wm.clear_constraints(c) end
        for _, w in ipairs(windows) do wm.clear_constraints(w.id) end
        if n == 1 then
            wm.grid_cell(windows[1].id, 0, 0, 1, 1, get_anchor())
            return
        end
        while #containers < n - 1 do
            table.insert(containers, wm.create_container())
        end
        while #containers > n - 1 do
            wm.destroy_container(table.remove(containers))
            saved[#containers + 1] = nil
        end
        wm.grid_cell(containers[1], 0, 0, 1, 1, get_anchor())
        for i = 1, n - 1 do
            local step    = steps[windows[i].step]
            local cur_win = windows[i].id
            local rest    = (i < n - 1) and containers[i + 1] or windows[n].id
            local r       = saved[i] or default_ratio(windows[i].step)
            local children = step.win_idx == 1 and { cur_win, rest } or { rest, cur_win }
            wm.split(containers[i], step.axis, { r[1], r[2] }, children)
        end
    end

    return function(event, id, prev_id)
        if not is_win(id) and not is_ws(id) then return end
        if event == "map" then
            local insert_at = #windows + 1
            local step_idx  = 1
            if prev_id then
                local idx = find_idx(prev_id)
                if idx then
                    insert_at = idx + 1
                    step_idx  = next_step(windows[idx].step)
                end
            elseif #windows > 0 then
                step_idx = next_step(windows[#windows].step)
            end
            table.insert(windows, insert_at, { id = id, step = step_idx })
            for i = insert_at + 1, #windows do
                windows[i].step = next_step(windows[i - 1].step)
            end
            rebuild(); wm.focus(id)
        elseif event == "unmap" then
            local saved = {}
            for i, cont in ipairs(containers) do
                local r = wm.get_split_ratios(cont)
                if r then saved[i] = { r[1], r[2] } end
            end
            local idx = find_idx(id)
            if idx then
                table.remove(windows, idx)
                for i = idx, #windows do
                    windows[i].step = i == 1 and 1 or next_step(windows[i-1].step)
                end
                for i = idx, #windows do saved[i] = saved[i + 1] end
                saved[#windows + 1] = nil
            end
            if #windows == 0 then reset() else rebuild(saved) end
        end
    end
end

-- ------------------------------------------------------------
-- Zoom
-- ------------------------------------------------------------
local function make_zoom()
    local windows    = {}
    local current    = 1
    local STRIP_H    = 80
    local main_cont  = nil
    local strip_cont = nil

    local function is_win(id) return wm.get_node_type(id) == "window" end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function find_idx(id)
        for i, wid in ipairs(windows) do if wid == id then return i end end
        return nil
    end

    local function get_strip_cont()
        if not strip_cont then strip_cont = wm.create_container() end
        return strip_cont
    end

    local function relayout()
        local n = #windows
        if n == 0 then return end
        local _, wy, _, _ = wm.get_work_area()
        local sw = wm.screen_width()
        local sh = wm.screen_height()
        local available_h = sh - wy

        if n == 1 then
            wm.clear_constraints(windows[1])
            wm.fixed_x(windows[1], 0); wm.fixed_y(windows[1], 0)
            wm.fixed_width(windows[1], sw); wm.fixed_height(windows[1], available_h)
            wm.show_window(windows[1])
            return
        end

        local main_h = available_h - STRIP_H
        wm.clear_constraints(windows[current])
        wm.fixed_x(windows[current], 0); wm.fixed_y(windows[current], 0)
        wm.fixed_width(windows[current], sw); wm.fixed_height(windows[current], main_h)
        wm.show_window(windows[current])

        local sc = get_strip_cont()
        local saved = {}
        if strip_cont then
            local r = wm.get_split_ratios(strip_cont)
            if r then saved = r end
        end
        wm.clear_constraints(sc)
        wm.fixed_x(sc, 0); wm.fixed_y(sc, main_h)
        wm.fixed_width(sc, sw); wm.fixed_height(sc, STRIP_H)

        local strip_wins = {}
        for i, id in ipairs(windows) do
            if i ~= current then table.insert(strip_wins, id) end
        end
        for _, id in ipairs(strip_wins) do wm.clear_constraints(id) end

        if #strip_wins == 1 then
            wm.grid_cell(strip_wins[1], 0, 0, 1, 1, sc)
        else
            local ratios = {}
            for i = 1, #strip_wins do
                ratios[i] = saved[i] or (1.0 / #strip_wins)
            end
            wm.split(sc, "h", ratios, strip_wins)
        end
        for _, id in ipairs(strip_wins) do wm.show_window(id) end
    end

    local function reset()
        if main_cont  then wm.destroy_container(main_cont);  main_cont  = nil end
        if strip_cont then wm.destroy_container(strip_cont); strip_cont = nil end
        windows = {}; current = 1
    end

    wm.bind(M, "Tab", function()
        if #windows < 2 then return end
        current = (current % #windows) + 1
        relayout()
        if windows[current] then wm.focus(windows[current]) end
    end)

    wm.bind(M | S, "Tab", function()
        if #windows < 2 then return end
        current = ((current - 2) % #windows) + 1
        relayout()
        if windows[current] then wm.focus(windows[current]) end
    end)

    return function(event, id, prev_id)
        if not is_win(id) and not is_ws(id) then return end
        if event == "map" then
            local insert_at = #windows + 1
            if prev_id then
                local idx = find_idx(prev_id)
                if idx then insert_at = idx + 1 end
            end
            table.insert(windows, insert_at, id)
            current = insert_at
            relayout(); wm.focus(id)
        elseif event == "unmap" then
            local idx = find_idx(id)
            if idx then
                table.remove(windows, idx)
                if #windows == 0 then
                    reset()
                else
                    if current > idx then current = current - 1 end
                    current = math.min(current, #windows)
                    relayout()
                    if windows[current] then wm.focus(windows[current]) end
                end
            end
        end
    end
end

-- ============================================================
-- Layout registry and cycling
-- ============================================================
local layouts = {
    make_dwindle, make_grid, make_fair,
    make_meridian,
    make_scroller, make_scroller2d,
    make_fibonacci, make_zoom,
}
local layout_names = {
    "dwindle", "grid", "fair",
    "meridian",
    "scroller", "scroller2d",
    "fibonacci", "zoom",
}

wm.bind(M | S, "n", function()
    local idx = (wm.get_arranger_index() % #layouts) + 1
    wm.set_arranger(layouts[idx], layout_names[idx])
    wm.set_arranger_index(idx)
end)

-- ============================================================
-- Arranger bootstrap
-- ============================================================
local DEFAULT_LAYOUT = "dwindle"

wm.set_default_arranger(function()
    for i, name in ipairs(layout_names) do
        if name == DEFAULT_LAYOUT then
            return layouts[i]()
        end
    end
    return make_dwindle()
end, DEFAULT_LAYOUT)
