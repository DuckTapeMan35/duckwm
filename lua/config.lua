----------- dwindle start ------------
-- local next_dir = {}
--
-- -- First window: no focused, solver gives it full screen by default – nothing to do.
-- wm.on_map(function(id, focused)
--     if not focused then return end
--
--     local info = wm.get_node_info(focused)
--     local dir = next_dir[focused] or "right"
--
--     -- Clear old constraints before applying new layout
--     wm.clear_constraints(focused)
--     wm.clear_constraints(id)
--
--     if dir == "right" then
--         local half_w = math.floor(info.width / 2)
--         wm.set_geometry(focused, info.x, info.y, half_w, info.height)
--         wm.set_geometry(id,      info.x + half_w, info.y, info.width - half_w, info.height)
--         wm.right_of(id, focused)
--         next_dir[focused] = "below"
--         next_dir[id]      = "below"
--     else
--         local half_h = math.floor(info.height / 2)
--         wm.set_geometry(focused, info.x, info.y,         info.width, half_h)
--         wm.set_geometry(id,      info.x, info.y + half_h, info.width, info.height - half_h)
--         wm.below(id, focused)
--         next_dir[focused] = "right"
--         next_dir[id]      = "right"
--     end
--     wm.focus(id)
-- end)
--
-- -- Re-tile all remaining windows, excluding the one being removed.
-- local function reflow(all_ids, exclude_id)
--     -- Build a clean list without the dying window
--     local ids = {}
--     for _, wid in ipairs(all_ids) do
--         if wid ~= exclude_id then table.insert(ids, wid) end
--     end
--     if #ids == 0 then return end
--
--     local scr_w = wm.screen_width()
--     local scr_h = wm.screen_height()
--     local first = ids[1]
--
--     -- First window gets full screen
--     wm.set_geometry(first, 0, 0, scr_w, scr_h)
--
--     for i = 2, #ids do
--         local focused = ids[i-1]
--         local id = ids[i]
--
--         -- Clear existing constraints on these two
--         wm.clear_constraints(focused)
--         wm.clear_constraints(id)
--
--         local dir = next_dir[focused] or "right"
--         local info = wm.get_node_info(focused)
--
--         if dir == "right" then
--             local half_w = math.floor(info.width / 2)
--             wm.set_geometry(focused, info.x, info.y, half_w, info.height)
--             wm.set_geometry(id,      info.x + half_w, info.y, info.width - half_w, info.height)
--             wm.right_of(id, focused)
--             next_dir[focused] = "below"
--             next_dir[id]      = "below"
--         else
--             local half_h = math.floor(info.height / 2)
--             wm.set_geometry(focused, info.x, info.y,         info.width, half_h)
--             wm.set_geometry(id,      info.x, info.y + half_h, info.width, info.height - half_h)
--             wm.below(id, focused)
--             next_dir[focused] = "right"
--             next_dir[id]      = "right"
--         end
--     end
-- end
--
-- wm.on_unmap(function(id)
--     next_dir[id] = nil
--     local all = wm.get_all_windows()
--     if all then reflow(all, id) end
-- end)
--
-- -- Keybindings remain the same
-- local mod = wm.MOD_SUPER
-- wm.bind(mod, "z", function() wm.spawn({"xterm"}) end)
-- wm.bind(mod, "h", wm.focus_left)
-- wm.bind(mod, "l", wm.focus_right)
-- wm.bind(mod, "k", wm.focus_up)
-- wm.bind(mod, "j", wm.focus_down)
-- wm.bind(mod, "q", wm.kill_client)
-- wm.bind(mod | wm.MOD_SHIFT, "h", wm.exchange_left)
-- wm.bind(mod | wm.MOD_SHIFT, "l", wm.exchange_right)
-- wm.bind(mod | wm.MOD_SHIFT, "k", wm.exchange_up)
-- wm.bind(mod | wm.MOD_SHIFT, "j", wm.exchange_down)
-- wm.bind(mod, "v", function()
--     local f = wm.get_focused()
--     if f then next_dir[f] = "right" end
-- end)
-- wm.bind(mod, "b", function()
--     local f = wm.get_focused()
--     if f then next_dir[f] = "below" end
-- end)
-- wm.bind(mod | wm.MOD_CTRL, "h", function() wm.resize_focused_edge("left",  20) end)
-- wm.bind(mod | wm.MOD_CTRL, "l", function() wm.resize_focused_edge("right", 20) end)
-- wm.bind(mod | wm.MOD_CTRL, "k", function() wm.resize_focused_edge("up",    20) end)
-- wm.bind(mod | wm.MOD_CTRL, "j", function() wm.resize_focused_edge("down",  20) end)
-- wm.bind(mod | wm.MOD_CTRL, "r", function() wm.resize_focused_corner(10, 10) end)

----------- dwindle end ------------

----------- grid start -------------
local windows = {}          -- ordered list of window IDs
local cell_node = {}        -- cell_index → node ID (window or empty)
local container_id = nil    -- root node that fills the screen
local cols = 0
local rows = 0

-- pick the smallest square‑ish grid that fits n windows
local function best_grid(n)
    if n <= 1 then return 1, 1 end
    local c = math.ceil(math.sqrt(n))
    local r = math.ceil(n / c)
    return c, r
end

-- rebuild the whole grid with new_cols × new_rows cells
-- all windows are placed in order, remaining cells become empty nodes
local function expand_grid(new_cols, new_rows)
    local old_cols, old_rows = cols, rows
    local old_cell_node = cell_node

    cols, rows = new_cols, new_rows
    local total = cols * rows

    -- assign each cell: window (if within windows list) or new empty node
    cell_node = {}
    for i = 1, total do
        if i <= #windows then
            local wid = windows[i]
            cell_node[i] = wid
            wm.clear_constraints(wid)
        else
            local empty = wm.create_root_node() -- creates an empty node
            cell_node[i] = empty
        end
    end

    -- apply grid constraints to every node (window or empty)
    for i = 1, total do
        local node = cell_node[i]
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        wm.grid_cell(node, col, row, cols, rows, container_id)
    end

    -- delete old empty nodes that are no longer part of the grid
    if old_cols > 0 and old_rows > 0 then
        local old_total = old_cols * old_rows
        for i = 1, old_total do
            local old_node = old_cell_node[i]
            if old_node and wm.get_node_type(old_node) == "empty" then
                local still_used = false
                for j = 1, total do
                    if cell_node[j] == old_node then
                        still_used = true
                        break
                    end
                end
                if not still_used then
                    wm.remove_node(old_node)
                end
            end
        end
    end
end

-- ensure screen‑filling root container exists
local function ensure_container()
    if not container_id then
        container_id = wm.create_root_node()
    end
end

-- if necessary, enlarge the grid to accommodate all windows
local function reflow_if_needed()
    local n = #windows
    if n == 0 then return end
    if cols == 0 or n > cols * rows then
        local new_cols, new_rows = best_grid(n)
        expand_grid(new_cols, new_rows)
    end
end

-- place a new window into the first empty cell (no grid expansion)
local function place_window(wid)
    for i = 1, cols * rows do
        local node = cell_node[i]
        if wm.get_node_type(node) == "empty" then
            -- replace empty placeholder with the real window node
            wm.remove_node(node)        -- delete the empty node
            cell_node[i] = wid
            wm.clear_constraints(wid)
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            wm.grid_cell(wid, col, row, cols, rows, container_id)
            return
        end
    end
    error("No empty cell – should not happen (reflow_if_needed was called)")
end

-- CALLBACKS

wm.on_map(function(id, focused)
    ensure_container()
    table.insert(windows, id)

    if #windows <= cols * rows then
        place_window(id)
    else
        reflow_if_needed()   -- expands and reassigns all windows (including the new one)
    end

    wm.focus(id)
end)

wm.on_unmap(function(id)
    -- remove from ordered list
    for i, wid in ipairs(windows) do
        if wid == id then
            table.remove(windows, i)
            break
        end
    end
    -- clear from cell map (if present)
    for i, node in pairs(cell_node) do
        if node == id then
            cell_node[i] = nil
            break
        end
    end

    -- rebuild grid with remaining windows (this will create empty nodes for gaps)
    local n = #windows
    if n == 0 then
        cols, rows = 0, 0
        cell_node = {}
    else
        local new_cols, new_rows = best_grid(n)
        expand_grid(new_cols, new_rows)
    end
end)

-- KEYBINDINGS (unchanged)

local mod = wm.MOD_SUPER

wm.set_resize_modifier(wm.MOD_ALT)
wm.set_float_modifier(wm.MOD_ALT)
wm.bind(wm.MOD_SUPER, "f", function()
    wm.toggle_floating()
end)

wm.bind(mod, "z", function() wm.spawn({"xterm"}) end)
wm.bind(mod, "h", wm.focus_left)
wm.bind(mod, "l", wm.focus_right)
wm.bind(mod, "k", wm.focus_up)
wm.bind(mod, "j", wm.focus_down)
wm.bind(mod, "q", wm.kill_client)

wm.bind(mod | wm.MOD_SHIFT, "h", wm.exchange_left)
wm.bind(mod | wm.MOD_SHIFT, "l", wm.exchange_right)
wm.bind(mod | wm.MOD_SHIFT, "k", wm.exchange_up)
wm.bind(mod | wm.MOD_SHIFT, "j", wm.exchange_down)

wm.bind(mod | wm.MOD_CTRL, "h", function() wm.resize_focused_edge("left",  20) end)
wm.bind(mod | wm.MOD_CTRL, "l", function() wm.resize_focused_edge("right", 20) end)
wm.bind(mod | wm.MOD_CTRL, "k", function() wm.resize_focused_edge("up",    20) end)
wm.bind(mod | wm.MOD_CTRL, "j", function() wm.resize_focused_edge("down",  20) end)
wm.bind(mod | wm.MOD_CTRL, "r", function() wm.resize_focused_corner(10, 10) end)
-------------- grid end -------------

-------------- meridian start -------------
-- ╔══════════════════════════════════════════════════════════════╗
-- ║                  "MERIDIAN" LAYOUT                           ║
-- ╠══════════════════════════════════════════════════════════════╣
-- ║                                                              ║
-- ║  WHY THIS IS IMPOSSIBLE IN A BSP/TREE/STACK WM:              ║
-- ║                                                              ║
-- ║  In every BSP window manager, each split produces exactly    ║
-- ║  one dividing line. Every window therefore has exactly ONE   ║
-- ║  "split partner" — its sibling in the tree.                  ║
-- ║                                                              ║
-- ║  In Meridian, the MAIN window is simultaneously bounded      ║
-- ║  from ALL FOUR cardinal directions. Its top edge is          ║
-- ║  determined by NORTH, its right by EAST, its bottom by       ║
-- ║  SOUTH, and its left by WEST — all at once. This is a        ║
-- ║  star-topology constraint graph with no tree equivalent.     ║
-- ║                                                              ║
-- ║  Furthermore, EAST and WEST are bounded by NORTH and SOUTH   ║
-- ║  as well — creating a ring of inter-dependencies across      ║
-- ║  what would have to be separate BSP subtrees.                ║
-- ║                                                              ║
-- ║  Diagram (5 windows):                                        ║
-- ║                                                              ║
-- ║  ┌─────────────────────────────────┐                         ║
-- ║  │            NORTH [5]            │  ← full screen width    ║
-- ║  ├────────┬──────────────────┬─────┤                         ║
-- ║  │        │                  │     │                         ║
-- ║  │WEST [4]│    MAIN   [1]    │[2]  │ EAST                    ║
-- ║  │        │                  │     │                         ║
-- ║  ├────────┴──────────────────┴─────┤                         ║
-- ║  │            SOUTH [3]            │  ← full screen width    ║
-- ║  └─────────────────────────────────┘                         ║
-- ║                                                              ║
-- ║  EAST/WEST span only the center strip (between N and S).     ║
-- ║  NORTH/SOUTH span the full screen width.                     ║
-- ║  MAIN is the gap remaining after all four claim their space. ║
-- ║                                                              ║
-- ║  Overflow (≥ 6 windows): extras subdivide their strip.       ║
-- ║  [6] subdivides EAST, [7] subdivides SOUTH, [8] WEST, …      ║
-- ║                                                              ║
-- ║  Space reclamation: when any satellite closes, MAIN          ║
-- ║  immediately expands to fill that cardinal direction.        ║
-- ╚══════════════════════════════════════════════════════════════╝
 
-- local SW = wm.screen_width()
-- local SH = wm.screen_height()
--  
-- -- ── Satellite strip dimensions (tweak to taste) ──────────────────────────────
-- local E_W = math.floor(SW * 0.27)  -- east strip width
-- local W_W = math.floor(SW * 0.22)  -- west strip width
-- local N_H = math.floor(SH * 0.20)  -- north strip height
-- local S_H = math.floor(SH * 0.23)  -- south strip height
--  
-- -- ── Window registry ───────────────────────────────────────────────────────────
-- -- Slot assignment: 1=MAIN, 2=E, 3=S, 4=W, 5=N, 6=E2, 7=S2, 8=W2, 9=N2, …
-- -- Each group of four windows after the first fills a satellite (in E/S/W/N order).
-- -- Within a satellite, windows are distributed evenly along the strip.
-- local windows = {}  -- list of node IDs in slot order; [1] = MAIN
--  
-- -- ── Layout engine ─────────────────────────────────────────────────────────────
--  
-- local function compute_geoms(n)
--     local has_e = n >= 2
--     local has_s = n >= 3
--     local has_w = n >= 4
--     local has_n = n >= 5
--  
--     -- MAIN window shrinks as each satellite appears (the star in action)
--     local mx = has_w and W_W or 0
--     local my = has_n and N_H or 0
--     local mw = SW - mx - (has_e and E_W or 0)
--     local mh = SH - my - (has_s and S_H or 0)
--  
--     local geoms = {}
--     geoms[1] = { mx, my, mw, mh }
--  
--     -- Distribute slots among the four satellites (cycle: E, S, W, N)
--     local east_slots, south_slots, west_slots, north_slots = {}, {}, {}, {}
--     for i = 2, n do
--         local cycle = (i - 2) % 4
--         if     cycle == 0 then table.insert(east_slots,  i)
--         elseif cycle == 1 then table.insert(south_slots, i)
--         elseif cycle == 2 then table.insert(west_slots,  i)
--         else                    table.insert(north_slots, i)
--         end
--     end
--  
--     -- EAST strip — subdivided vertically, bounded by north/south strips
--     if has_e then
--         local count   = #east_slots
--         local strip_h = mh  -- exactly the center strip, flush with N and S
--         local slot_h  = math.floor(strip_h / count)
--         for j, idx in ipairs(east_slots) do
--             local wy = my + (j - 1) * slot_h
--             local wh = (j == count) and (strip_h - (j - 1) * slot_h) or slot_h
--             geoms[idx] = { SW - E_W, wy, E_W, wh }
--         end
--     end
--  
--     -- SOUTH strip — subdivided horizontally, spans full screen width
--     if has_s then
--         local count  = #south_slots
--         local slot_w = math.floor(SW / count)
--         for j, idx in ipairs(south_slots) do
--             local wx = (j - 1) * slot_w
--             local ww = (j == count) and (SW - (j - 1) * slot_w) or slot_w
--             geoms[idx] = { wx, SH - S_H, ww, S_H }
--         end
--     end
--  
--     -- WEST strip — subdivided vertically, bounded by north/south strips
--     if has_w then
--         local count   = #west_slots
--         local strip_h = mh
--         local slot_h  = math.floor(strip_h / count)
--         for j, idx in ipairs(west_slots) do
--             local wy = my + (j - 1) * slot_h
--             local wh = (j == count) and (strip_h - (j - 1) * slot_h) or slot_h
--             geoms[idx] = { 0, wy, W_W, wh }
--         end
--     end
--  
--     -- NORTH strip — subdivided horizontally, spans full screen width
--     if has_n then
--         local count  = #north_slots
--         local slot_w = math.floor(SW / count)
--         for j, idx in ipairs(north_slots) do
--             local wx = (j - 1) * slot_w
--             local ww = (j == count) and (SW - (j - 1) * slot_w) or slot_w
--             geoms[idx] = { wx, 0, ww, N_H }
--         end
--     end
--  
--     return geoms
-- end
--  
-- local function relayout()
--     local n = #windows
--     if n == 0 then return end
--     local geoms = compute_geoms(n)
--     for i, id in ipairs(windows) do
--         local g = geoms[i]
--         if g then
--             -- Clear constraints so the iterative solver leaves this geometry alone.
--             -- The star relationship is enforced by our geometry computation, not by
--             -- the constraint propagator — this is what makes it structurally non-BSP.
--             wm.clear_constraints(id)
--             wm.set_geometry(id, g[1], g[2], math.max(g[3], 20), math.max(g[4], 20))
--         end
--     end
-- end
--  
-- -- ── Hooks ─────────────────────────────────────────────────────────────────────
--  
-- wm.on_map(function(id, _)
--     table.insert(windows, id)
--     relayout()
-- end)
--  
-- wm.on_unmap(function(id)
--     -- Space reclamation: remove from slots, re-pack, relayout.
--     -- MAIN window will expand to fill any vacated cardinal direction.
--     for i, wid in ipairs(windows) do
--         if wid == id then
--             table.remove(windows, i)
--             break
--         end
--     end
--     relayout()
-- end)
--  
-- -- ── Helpers ───────────────────────────────────────────────────────────────────
--  
-- -- Swap focused window into the MAIN slot by exchanging node IDs in the slot
-- -- table, then redrawing. This lets any window become the main pane instantly.
-- local function promote_focused()
--     local fid = wm.get_focused()
--     if not fid then return end
--     for i, id in ipairs(windows) do
--         if id == fid and i > 1 then
--             windows[i] = windows[1]
--             windows[1] = fid
--             relayout()
--             return
--         end
--     end
-- end
--  
-- -- Rotate: demote MAIN to the back of the queue, promoting the next satellite.
-- local function rotate_forward()
--     if #windows < 2 then return end
--     local demoted = table.remove(windows, 1)
--     table.insert(windows, demoted)
--     relayout()
-- end
--  
-- local function rotate_back()
--     if #windows < 2 then return end
--     local promoted = table.remove(windows)
--     table.insert(windows, 1, promoted)
--     relayout()
-- end
--  
-- -- ── Keybindings ───────────────────────────────────────────────────────────────
-- local M = wm.MOD_SUPER
-- local S = wm.MOD_SHIFT
-- local A = wm.MOD_ALT
--  
-- -- Focus movement (uses the WM's spatial focus graph)
-- wm.bind(M,   "h", function() wm.focus_left()  end)
-- wm.bind(M,   "l", function() wm.focus_right() end)
-- wm.bind(M,   "k", function() wm.focus_up()    end)
-- wm.bind(M,   "j", function() wm.focus_down()  end)
--  
-- -- Visual swapping (exchange window contents between slots)
-- wm.bind(M|S, "h", function() wm.exchange_left()  end)
-- wm.bind(M|S, "l", function() wm.exchange_right() end)
-- wm.bind(M|S, "k", function() wm.exchange_up()    end)
-- wm.bind(M|S, "j", function() wm.exchange_down()  end)
--  
-- -- Meridian-specific slot operations
-- wm.bind(M,   "Return", function() promote_focused()  end)  -- focused → MAIN
-- wm.bind(M,   "Tab",    function() rotate_forward()   end)  -- cycle MAIN forward
-- wm.bind(M|S, "Tab",    function() rotate_back()      end)  -- cycle MAIN back
--  
-- -- Applications
-- wm.bind(M,   "z",   function() wm.spawn({ "xterm" })         end)
-- wm.bind(M, "q",   function() wm.kill_client()                  end)
--  
-- -- Dynamic satellite sizing (adjust strip widths / heights live)
-- -- These change the module-level variables; next map/unmap will use new sizes.
-- wm.bind(M|A, "h", function()
--     W_W = math.max(40, W_W - 20); relayout()
-- end)
-- wm.bind(M|A, "l", function()
--     W_W = math.min(SW // 2, W_W + 20); relayout()
-- end)
-- wm.bind(M|A, "k", function()
--     N_H = math.max(40, N_H - 20); relayout()
-- end)
-- wm.bind(M|A, "j", function()
--     N_H = math.min(SH // 2, N_H + 20); relayout()
-- end)
--
-------------- meridian end -------------
