wm.set_resize_modifier(wm.MOD_ALT)

local function make_arranger()
    local windows = {}
    local par     = {}
    local spl     = {}
    local ch      = {}
    local root    = nil
    local anchor  = nil

    local function is_win(id) return wm.get_node_type(id) == "window"   end
    local function is_ws(id)  return wm.get_node_type(id) == "workspace" end

    local function get_anchor()
        if not anchor then anchor = wm.create_container() end
        return anchor
    end

    local function rebuild()
        if not root then return end
        local a = get_anchor()
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
        walk(root, a, 0, 0, 1, 1)
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
          anchor  = nil  -- no windows left, reset anchor too
          return
      end
      local sibling = (ch[p][1] == id) and ch[p][2] or ch[p][1]
      local gp      = par[p]
      par[id]    = nil
      ch[p]      = nil
      spl[p]     = nil
      par[p]     = nil
      par[sibling] = gp
      if gp then
          local c = ch[gp]
          if c[1] == p then c[1] = sibling else c[2] = sibling end
      else
          root    = sibling
          anchor  = nil  -- root changed to a bare window, anchor no longer valid
      end
      wm.clear_constraints(id)
      wm.destroy_container(p)
      rebuild()
  end

    return function(event, id, prev_id)
        if event == "map" then
            if not is_win(id) and not is_ws(id) then return end
            table.insert(windows, id)
            if not prev_id then
                root    = id
                par[id] = nil
                rebuild()
            else
                do_split(prev_id, id)
            end
            wm.focus(id)
        elseif event == "unmap" then
            if not is_win(id) and not is_ws(id) then return end
            for i, w in ipairs(windows) do
                if w == id then table.remove(windows, i); break end
            end
            do_remove(id)
        end
    end
end

wm.set_default_arranger(make_arranger)

local mod = wm.MOD_SUPER

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

for i = 1, 9 do
    wm.bind(mod | wm.MOD_CTRL, tostring(i), function()
        wm.switch_to_workspace(i)
    end)
end

wm.bind(mod, "w", function()
    wm.create_nested_workspace()
end)

wm.bind(mod, "y", function()
    wm.enter_nested()
end)

wm.bind(mod, "Escape", function()
    wm.leave_nested()
end)
