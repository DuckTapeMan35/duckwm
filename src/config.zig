const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const wm_mod = @import("wm");
const WM = wm_mod.WM;
const graph_mod = @import("graph");
const Constraint = graph_mod.Constraint;
const c = @import("c").c;
const api = @import("api");

var global_wm: *WM = undefined;

const Registration = struct {
    func: ziglua.CFn,
    name: [:0]const u8,
};

fn check_node_id(lua: *Lua, stack_pos: i32) ?u32 {
    const n = lua.toInteger(stack_pos) catch return null;
    if (n <= 0) return null;
    return @intCast(n);
}

fn check_u32(lua: *Lua, stack_pos: i32) ?u32 {
    const n = lua.toInteger(stack_pos) catch return null;
    if (n < 0) return null;
    return @intCast(n);
}

fn check_color(lua: *Lua, stack_pos: i32) ?u32 {
    const n = lua.toInteger(stack_pos) catch return null;
    if (n < 0 or n > 0xFFFFFFFF) return null;
    return @intCast(n);
}

fn repaint_node(wm: *WM, node: *graph_mod.Node) void {
    const win = switch (node.content) {
        .window    => |w| w,
        .workspace => node.preview_window orelse return,
        .empty     => return,
    };
    if (wm.frames.get(win)) |frame| {
        wm.draw_frame_borders(frame, node);
        _ = c.XFlush(wm.display);
    }
}

fn repaint_all_nodes(wm: *WM) void {
    for (wm.current_graph.nodes.items) |node| {
        repaint_node(wm, node);
    }
    _ = c.XFlush(wm.display);
}

fn print_graph_to_buf(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, g: *graph_mod.Graph, depth: u32) void {
    var ind = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer ind.deinit(allocator);
    for (0..depth) |_| ind.appendSlice(allocator, "  ") catch {};

    buf.print(allocator, "{s}Graph [level={}, number={}]\n\n", .{
        ind.items, g.id.level, g.id.number,
    }) catch {};

    for (g.nodes.items) |node| {
        const type_str: []const u8 = switch (node.content) {
            .window    => "window",
            .empty     => "empty",
            .workspace => "workspace",
        };
        const id = global_wm.get_id_for_node(node) orelse 0;
        buf.print(allocator, "{s}  [{d}] {s} x={} y={} w={} h={} floating={}\n", .{
            ind.items, id, type_str,
            node.x, node.y, node.width, node.height, node.floating,
        }) catch {};
    }

    buf.print(allocator, "{s}\n", .{ind.items}) catch {};

    for (g.nodes.items) |node| {
        const from_id = global_wm.get_id_for_node(node) orelse 0;
        for (node.constraints.items) |con| {
            switch (con) {
                .left_of, .right_of, .above, .below,
                .align_left, .align_top, .align_right, .align_bottom,
                .equal_width, .equal_height => {
                    const other: *graph_mod.Node = switch (con) {
                        .left_of      => |o| o,
                        .right_of     => |o| o,
                        .above        => |o| o,
                        .below        => |o| o,
                        .align_left   => |o| o,
                        .align_top    => |o| o,
                        .align_right  => |o| o,
                        .align_bottom => |o| o,
                        .equal_width  => |o| o,
                        .equal_height => |o| o,
                        else => unreachable,
                    };
                    const to_id = global_wm.get_id_for_node(other) orelse 0;
                    const name: []const u8 = switch (con) {
                        .left_of      => "left_of",
                        .right_of     => "right_of",
                        .above        => "above",
                        .below        => "below",
                        .align_left   => "align_left",
                        .align_top    => "align_top",
                        .align_right  => "align_right",
                        .align_bottom => "align_bottom",
                        .equal_width  => "equal_width",
                        .equal_height => "equal_height",
                        else => unreachable,
                    };
                    buf.print(allocator, "{s}  [{d}] --{s}--> [{d}]\n", .{
                        ind.items, from_id, name, to_id,
                    }) catch {};
                },
                .grid_cell => |gc| {
                    const cont_id = global_wm.get_id_for_node(gc.container) orelse 0;
                    buf.print(allocator, "{s}  [{d}] --grid_cell(col={},row={},cols={},rows={})--> [{d}]\n", .{
                        ind.items, from_id, gc.col, gc.row, gc.cols, gc.rows, cont_id,
                    }) catch {};
                },
                .grid_cell_abs => |gc| {
                    const cont_id = global_wm.get_id_for_node(gc.container) orelse 0;
                    buf.print(allocator, "{s}  [{d}] --grid_cell_abs(x={},y={},w={},h={})--> [{d}]\n", .{
                        ind.items, from_id, gc.x, gc.y, gc.w, gc.h, cont_id,
                    }) catch {};
                },
                .split => |s| {
                    const cont_id = global_wm.get_id_for_node(s.container) orelse 0;
                    buf.print(allocator, "{s}  [{d}] --split({s},count={}", .{
                        ind.items, from_id,
                        if (s.axis == .horizontal) "h" else "v",
                        s.count,
                    }) catch {};
                    for (0..s.count) |i| {
                        buf.print(allocator, ",r={d:.3}", .{s.ratios[i]}) catch {};
                    }
                    buf.print(allocator, ")--> [{d}]\n", .{cont_id}) catch {};
                },
                .fixed_width  => |w| buf.print(allocator, "{s}  [{d}] fixed_width={}\n",      .{ ind.items, from_id, w }) catch {},
                .fixed_height => |h| buf.print(allocator, "{s}  [{d}] fixed_height={}\n",     .{ ind.items, from_id, h }) catch {},
                .fixed_x      => |x| buf.print(allocator, "{s}  [{d}] fixed_x={}\n",          .{ ind.items, from_id, x }) catch {},
                .fixed_y      => |y| buf.print(allocator, "{s}  [{d}] fixed_y={}\n",          .{ ind.items, from_id, y }) catch {},
                .fixed_ratio  => |r| buf.print(allocator, "{s}  [{d}] fixed_ratio={d:.3}\n",  .{ ind.items, from_id, r }) catch {},
            }
        }
    }

    buf.print(allocator, "{s}\n", .{ind.items}) catch {};

    for (g.nodes.items) |node| {
        if (node.content == .workspace) {
            print_graph_to_buf(buf, allocator, node.content.workspace, depth + 1);
        }
    }
}


fn apply_other(lua: *Lua, g: *graph_mod.Graph, node: *graph_mod.Node, comptime tag: std.meta.Tag(graph_mod.Constraint)) void {
    _ = lua.getField(-1, "other");
    const other_id: u32 = @intCast(lua.toInteger(-1) catch 0);
    lua.pop(1);
    const other = global_wm.get_node_by_id(other_id) orelse return;
    g.add_constraint(node, switch (tag) {
        .left_of     => .{ .left_of     = other },
        .right_of    => .{ .right_of    = other },
        .above       => .{ .above       = other },
        .below       => .{ .below       = other },
        .align_left  => .{ .align_left  = other },
        .align_top   => .{ .align_top   = other },
        .align_right => .{ .align_right = other },
        .align_bottom=> .{ .align_bottom= other },
        .equal_width => .{ .equal_width = other },
        .equal_height=> .{ .equal_height= other },
        else => return,
    }) catch {};
}

fn clear_all_node_colors(g: *graph_mod.Graph) void {
    for (g.nodes.items) |node| {
        node.border_color_focused   = null;
        node.border_color_unfocused = null;
        node.border_color_top       = null;
        node.border_color_bottom    = null;
        node.border_color_left      = null;
        node.border_color_right     = null;
        if (node.content == .workspace) {
            clear_all_node_colors(node.content.workspace);
        }
    }
}

fn reload_persistent(lua: *Lua) void {
    const user_path = resolve_user_path(global_wm) orelse return;
    defer global_wm.allocator.free(user_path);
    const path_z = std.mem.concatWithSentinel(global_wm.allocator, u8, &[_][]const u8{user_path}, 0) catch return;
    defer global_wm.allocator.free(path_z);

    clear_all_node_colors(global_wm.current_graph);

    // Free lua refs for existing lua keybinds
    var kb_it = global_wm.keybinds.iterator();
    while (kb_it.next()) |entry| {
        switch (entry.value_ptr.*) {
            .lua => |ref| if (global_wm.lua) |l| l.unref(ziglua.registry_index, ref),
            else => {},
        }
    }
    global_wm.ungrab_keys();
    global_wm.keybinds.clearRetainingCapacity();

    // Clear rules to avoid duplicates
    for (global_wm.rules.items) |ref| {
        if (global_wm.lua) |l| l.unref(ziglua.registry_index, ref);
    }
    global_wm.rules.clearRetainingCapacity();

    lua.doFile(path_z) catch {
        lua.pop(1);
    };
}

fn apply_arranger_to_graph(lua: *Lua, g: *graph_mod.Graph, factory_ref: i32) void {
    const saved_current = global_wm.current_graph;
    global_wm.current_graph = g;
    defer global_wm.current_graph = saved_current;
    _ = lua.getIndexRaw(ziglua.registry_index, factory_ref);
    lua.protectedCall(.{ .args = 0, .results = 1 }) catch |err| {
        std.debug.print("arranger factory error: {}\n", .{err});
        return;
    };
    if (lua.typeOf(-1) != .function) {
        lua.pop(1);
        return;
    }
    const arranger_ref = lua.ref(ziglua.registry_index);

    if (g.arranger_ref != 0) {
        lua.unref(ziglua.registry_index, g.arranger_ref);
    }
    g.arranger_ref = arranger_ref;

    g.virtual_width = 0;
    g.virtual_height = 0;
    g.lock_horizontal_resize = false;
    g.lock_vertical_resize = false;
    g.pan_disabled = false;

    // Collect window/workspace node pointers to remap
    var ids: std.ArrayListUnmanaged(u32) = .{ .items = &.{}, .capacity = 0 };
    defer ids.deinit(global_wm.allocator);
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        switch (node.content) {
            .window, .workspace => {
                if (node.content == .workspace and node.preview_window == null) continue;
                if (global_wm.get_id_for_node(node)) |id| {
                    ids.append(global_wm.allocator, id) catch {};
                }
            },
            else => {},
        }
    }

    // Remove all empty nodes (structural containers from previous arranger)
    var i: usize = 0;
    while (i < g.nodes.items.len) {
        const node = g.nodes.items[i];
        if (node.content == .empty) {
            var it = global_wm.node_registry.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* == node) {
                    _ = global_wm.node_registry.remove(entry.key_ptr.*);
                    break;
                }
            }
            node.deinit(global_wm.allocator);
            global_wm.allocator.destroy(node);
            _ = g.nodes.swapRemove(i);
        } else {
            i += 1;
        }
    }

    // Remove all window/workspace nodes from graph temporarily so that
    // get_layout() inside each map callback only sees windows mapped so far.
    // This prevents arrangers from treating all windows as already-placed
    // when deciding how to insert the first few.
    for (ids.items) |id| {
        const node = global_wm.node_registry.get(id) orelse continue;
        for (g.nodes.items, 0..) |n, idx| {
            if (n == node) {
                _ = g.nodes.swapRemove(idx);
                break;
            }
        }
    }

    // Re-add and map one at a time so each map callback sees a clean
    // incrementally-built graph
    var prev_id: ?u32 = null;
    for (ids.items) |id| {
        const node = global_wm.node_registry.get(id) orelse continue;
        node.constraints.clearRetainingCapacity();
        g.nodes.append(global_wm.allocator, node) catch {};
        global_wm.call_arranger(g, "map", id, prev_id);
        prev_id = id;
    }

    global_wm.resolve(g) catch {};
    global_wm.rebuild_focus_edges() catch {};
    g.pan_x = 0;
    g.pan_y = 0;
    if (g == saved_current) {
        global_wm.flush(g) catch {};
    }

    reload_persistent(lua);
}

fn apply_gaps_to_graph(g: *graph_mod.Graph, ih: u32, iv: u32, oh: u32, ov: u32) void {
    g.gap_inner_h = ih;
    g.gap_inner_v = iv;
    g.gap_outer_h = oh;
    g.gap_outer_v = ov;
    for (g.nodes.items) |node| {
        if (node.content == .workspace) {
            apply_gaps_to_graph(node.content.workspace, ih, iv, oh, ov);
        }
    }
}

const registrations = [_]Registration{
    .{ .func = ziglua.wrap(l_set_preview_colors_workspace),       .name = "set_preview_colors_workspace" },
    .{ .func = ziglua.wrap(l_bind),                               .name = "bind" },
    .{ .func = ziglua.wrap(l_spawn),                              .name = "spawn" },
    .{ .func = ziglua.wrap(l_setenv),                             .name = "setenv" },
    .{ .func = ziglua.wrap(l_exec_once),                          .name = "exec_once" },
    .{ .func = ziglua.wrap(l_set_arranger),                       .name = "set_arranger" },
    .{ .func = ziglua.wrap(l_set_default_arranger),               .name = "set_default_arranger" },
    .{ .func = ziglua.wrap(l_register_arranger),                  .name = "register_arranger" },
    .{ .func = ziglua.wrap(l_focus_left),                         .name = "focus_left" },
    .{ .func = ziglua.wrap(l_focus_right),                        .name = "focus_right" },
    .{ .func = ziglua.wrap(l_focus_up),                           .name = "focus_up" },
    .{ .func = ziglua.wrap(l_focus_down),                         .name = "focus_down" },
    .{ .func = ziglua.wrap(l_focus),                              .name = "focus" },
    .{ .func = ziglua.wrap(l_exchange_left),                      .name = "exchange_left" },
    .{ .func = ziglua.wrap(l_exchange_right),                     .name = "exchange_right" },
    .{ .func = ziglua.wrap(l_exchange_up),                        .name = "exchange_up" },
    .{ .func = ziglua.wrap(l_exchange_down),                      .name = "exchange_down" },
    .{ .func = ziglua.wrap(l_get_focused),                        .name = "get_focused" },
    .{ .func = ziglua.wrap(l_remove_node),                        .name = "remove_node" },
    .{ .func = ziglua.wrap(l_kill_client),                        .name = "kill_client" },
    .{ .func = ziglua.wrap(l_get_node_info),                      .name = "get_node_info" },
    .{ .func = ziglua.wrap(l_resize_edge),                        .name = "resize_edge" },
    .{ .func = ziglua.wrap(l_resize_corner),                      .name = "resize_corner" },
    .{ .func = ziglua.wrap(l_resize_focused_edge),                .name = "resize_focused_edge" },
    .{ .func = ziglua.wrap(l_resize_focused_corner),              .name = "resize_focused_corner" },
    .{ .func = ziglua.wrap(l_create_root_node),                   .name = "create_root_node" },
    .{ .func = ziglua.wrap(l_left_of),                            .name = "left_of" },
    .{ .func = ziglua.wrap(l_right_of),                           .name = "right_of" },
    .{ .func = ziglua.wrap(l_above),                              .name = "above" },
    .{ .func = ziglua.wrap(l_below),                              .name = "below" },
    .{ .func = ziglua.wrap(l_align_left),                         .name = "align_left" },
    .{ .func = ziglua.wrap(l_align_top),                          .name = "align_top" },
    .{ .func = ziglua.wrap(l_align_right),                        .name = "align_right" },
    .{ .func = ziglua.wrap(l_align_bottom),                       .name = "align_bottom" },
    .{ .func = ziglua.wrap(l_equal_width),                        .name = "equal_width" },
    .{ .func = ziglua.wrap(l_equal_height),                       .name = "equal_height" },
    .{ .func = ziglua.wrap(l_fixed_ratio),                        .name = "fixed_ratio" },
    .{ .func = ziglua.wrap(l_fixed_width),                        .name = "fixed_width" },
    .{ .func = ziglua.wrap(l_fixed_height),                       .name = "fixed_height" },
    .{ .func = ziglua.wrap(l_fixed_x),                            .name = "fixed_x" },
    .{ .func = ziglua.wrap(l_fixed_y),                            .name = "fixed_y" },
    .{ .func = ziglua.wrap(l_grid_cell),                          .name = "grid_cell" },
    .{ .func = ziglua.wrap(l_grid_cell_abs),                      .name = "grid_cell_abs" },
    .{ .func = ziglua.wrap(l_split),                              .name = "split" },
    .{ .func = ziglua.wrap(l_get_all_windows),                    .name = "get_all_windows" },
    .{ .func = ziglua.wrap(l_screen_width),                       .name = "screen_width" },
    .{ .func = ziglua.wrap(l_screen_height),                      .name = "screen_height" },
    .{ .func = ziglua.wrap(l_clear_constraints),                  .name = "clear_constraints" },
    .{ .func = ziglua.wrap(l_set_node_empty),                     .name = "set_node_empty" },
    .{ .func = ziglua.wrap(l_set_node_window),                    .name = "set_node_window" },
    .{ .func = ziglua.wrap(l_get_node_type),                      .name = "get_node_type" },
    .{ .func = ziglua.wrap(l_move_window_to_node),                .name = "move_window_to_node" },
    .{ .func = ziglua.wrap(l_set_resize_modifier),                .name = "set_resize_modifier" },
    .{ .func = ziglua.wrap(l_set_float_modifier),                 .name = "set_float_modifier" },
    .{ .func = ziglua.wrap(l_toggle_floating),                    .name = "toggle_floating" },
    .{ .func = ziglua.wrap(l_set_node_focused_border_color),      .name = "set_node_focused_border_color" },
    .{ .func = ziglua.wrap(l_set_node_unfocused_border_color),    .name = "set_node_unfocused_border_color" },
    .{ .func = ziglua.wrap(l_set_default_focused_border_color),   .name = "set_default_focused_border_color" },
    .{ .func = ziglua.wrap(l_set_default_unfocused_border_color), .name = "set_default_unfocused_border_color" },
    .{ .func = ziglua.wrap(l_set_preview_colors),                 .name = "set_preview_colors" },
    .{ .func = ziglua.wrap(l_get_node_geometry),                  .name = "get_node_geometry" },
    .{ .func = ziglua.wrap(l_set_border_width),                   .name = "set_border_width" },
    .{ .func = ziglua.wrap(l_create_nested_workspace),            .name = "create_nested_workspace" },
    .{ .func = ziglua.wrap(l_enter_nested),                       .name = "enter_nested" },
    .{ .func = ziglua.wrap(l_leave_nested),                       .name = "leave_nested" },
    .{ .func = ziglua.wrap(l_enter_nested_by_id),                 .name = "enter_nested_by_id" },
    .{ .func = ziglua.wrap(l_get_workspace),                      .name = "get_workspace" },
    .{ .func = ziglua.wrap(l_create_empty_node),                  .name = "create_empty_node" },
    .{ .func = ziglua.wrap(l_get_workspaces_at_level),            .name = "get_workspaces_at_level" },
    .{ .func = ziglua.wrap(l_enter_workspace_by_id),              .name = "enter_workspace_by_id" },
    .{ .func = ziglua.wrap(l_switch_to_workspace),                .name = "switch_to_workspace" },
    .{ .func = ziglua.wrap(l_send_to_workspace),                  .name = "send_to_workspace" },
    .{ .func = ziglua.wrap(l_create_container),                   .name = "create_container" },
    .{ .func = ziglua.wrap(l_destroy_container),                  .name = "destroy_container" },
    .{ .func = ziglua.wrap(l_reparent),                           .name = "reparent" },
    .{ .func = ziglua.wrap(l_get_container_of),                   .name = "get_container_of" },
    .{ .func = ziglua.wrap(l_set_reparent_strategy),              .name = "set_reparent_strategy" },
    .{ .func = ziglua.wrap(l_unregister_node),                    .name = "unregister_node" },
    .{ .func = ziglua.wrap(l_get_cursor_pos),                     .name = "get_cursor_pos" },
    .{ .func = ziglua.wrap(l_get_cursor_relative_to_focused),     .name = "get_cursor_relative_to_focused" },
    .{ .func = ziglua.wrap(l_warp_cursor),                        .name = "warp_cursor" },
    .{ .func = ziglua.wrap(l_warp_cursor_to_node),                .name = "warp_cursor_to_node" },
    .{ .func = ziglua.wrap(l_get_mouse_node),                     .name = "get_mouse_node" },
    .{ .func = ziglua.wrap(l_set_focus_follows_mouse),            .name = "set_focus_follows_mouse" },
    .{ .func = ziglua.wrap(l_set_float_move_button),              .name = "set_float_move_button" },
    .{ .func = ziglua.wrap(l_set_float_resize_button),            .name = "set_float_resize_button" },
    .{ .func = ziglua.wrap(l_set_gaps),                           .name = "set_gaps" },
    .{ .func = ziglua.wrap(l_set_gaps_workspace),                 .name = "set_gaps_workspace" },
    .{ .func = ziglua.wrap(l_quit),                               .name = "quit" },
    .{ .func = ziglua.wrap(l_get_window_class),                   .name = "get_window_class" },
    .{ .func = ziglua.wrap(l_get_window_name),                    .name = "get_window_name" },
    .{ .func = ziglua.wrap(l_set_floating),                       .name = "set_floating" },
    .{ .func = ziglua.wrap(l_set_fullscreen),                     .name = "set_fullscreen" },
    .{ .func = ziglua.wrap(l_toggle_fullscreen),                  .name = "toggle_fullscreen" },
    .{ .func = ziglua.wrap(l_reload_config),                      .name = "reload_config" },
    .{ .func = ziglua.wrap(l_reload_visuals),                     .name = "reload_visuals" },
    .{ .func = ziglua.wrap(l_get_window_pid),                     .name = "get_window_pid" },
    .{ .func = ziglua.wrap(l_get_urgent),                         .name = "get_urgent" },
    .{ .func = ziglua.wrap(l_set_urgent),                         .name = "set_urgent" },
    .{ .func = ziglua.wrap(l_set_default_urgent_border_color),    .name = "set_default_urgent_border_color" },
    .{ .func = ziglua.wrap(l_set_click_to_focus),                 .name = "set_click_to_focus" },
    .{ .func = ziglua.wrap(l_hide_window),                        .name = "hide_window" },
    .{ .func = ziglua.wrap(l_show_window),                        .name = "show_window" },
    .{ .func = ziglua.wrap(l_set_pan),                            .name = "set_pan" },
    .{ .func = ziglua.wrap(l_get_pan),                            .name = "get_pan" },
    .{ .func = ziglua.wrap(l_pan_by),                             .name = "pan_by" },
    .{ .func = ziglua.wrap(l_set_virtual_size),                   .name = "set_virtual_size" },
    .{ .func = ziglua.wrap(l_get_work_area),                      .name = "get_work_area" },
    .{ .func = ziglua.wrap(l_set_lock_horizontal_resize),         .name = "set_lock_horizontal_resize" },
    .{ .func = ziglua.wrap(l_set_lock_vertical_resize),           .name = "set_lock_vertical_resize" },
    .{ .func = ziglua.wrap(l_remove_constraint),                  .name = "remove_constraint" },
    .{ .func = ziglua.wrap(l_set_pan_modifier),                   .name = "set_pan_modifier" },
    .{ .func = ziglua.wrap(l_set_pan_button),                     .name = "set_pan_button" },
    .{ .func = ziglua.wrap(l_get_arranger_index),                 .name = "get_arranger_index" },
    .{ .func = ziglua.wrap(l_set_arranger_index),                 .name = "set_arranger_index" },
    .{ .func = ziglua.wrap(l_get_current_workspace),              .name = "get_current_workspace" },
    .{ .func = ziglua.wrap(l_set_workspace_switch_mode),          .name = "set_workspace_switch_mode" },
    .{ .func = ziglua.wrap(l_get_arranger_name),                  .name = "get_arranger_name" },
    .{ .func = ziglua.wrap(l_set_pan_disabled),                   .name = "set_pan_disabled" },
    .{ .func = ziglua.wrap(l_set_cursor_theme),                   .name = "set_cursor_theme" },
    .{ .func = ziglua.wrap(l_get_current_level),                  .name = "get_current_level" },
    .{ .func = ziglua.wrap(l_get_node_level),                     .name = "get_node_level" },
    .{ .func = ziglua.wrap(l_add_rule),                           .name = "add_rule" },
    .{ .func = ziglua.wrap(l_remove_rule),                        .name = "remove_rule" },
    .{ .func = ziglua.wrap(l_print_graph),                        .name = "print_graph" },
    .{ .func = ziglua.wrap(l_get_workspace_positions),            .name = "get_workspace_positions" },
    .{ .func = ziglua.wrap(l_get_current_workspace_position),     .name = "get_current_workspace_position" },
    .{ .func = ziglua.wrap(l_get_split_ratios),                   .name = "get_split_ratios" },
    .{ .func = ziglua.wrap(l_get_layout),                         .name = "get_layout" },
    .{ .func = ziglua.wrap(l_set_layout),                         .name = "set_layout" },
    .{ .func = ziglua.wrap(l_set_node_border_side_color),         .name = "set_node_border_side_color" },
    .{ .func = ziglua.wrap(l_clear_node_border_side_colors),      .name = "clear_node_border_side_colors" },
    .{ .func = ziglua.wrap(l_set_border_side_colors_focused_only),.name = "set_border_side_colors_focused_only" },
    .{ .func = ziglua.wrap(l_get_node_border_side_colors),        .name = "get_node_border_side_colors" },
    .{ .func = ziglua.wrap(l_float_left_of),                      .name = "float_left_of"  },
    .{ .func = ziglua.wrap(l_float_right_of),                     .name = "float_right_of" },
    .{ .func = ziglua.wrap(l_float_above),                        .name = "float_above"    },
    .{ .func = ziglua.wrap(l_float_below),                        .name = "float_below"    },
    .{ .func = ziglua.wrap(l_float_equal_width),                  .name = "float_equal_width"       },
    .{ .func = ziglua.wrap(l_float_equal_height),                 .name = "float_equal_height"      },
    .{ .func = ziglua.wrap(l_float_align_left),                   .name = "float_align_left"        },
    .{ .func = ziglua.wrap(l_float_align_top),                    .name = "float_align_top"         },
    .{ .func = ziglua.wrap(l_float_align_right),                  .name = "float_align_right"       },
    .{ .func = ziglua.wrap(l_float_align_bottom),                 .name = "float_align_bottom"      },
    .{ .func = ziglua.wrap(l_float_clear_constraints),            .name = "float_clear_constraints" },
    .{ .func = ziglua.wrap(l_clear_node_focused_border_color),    .name = "clear_node_focused_border_color"   },
    .{ .func = ziglua.wrap(l_clear_node_unfocused_border_color),  .name = "clear_node_unfocused_border_color" },
    .{ .func = ziglua.wrap(l_register_swallow),                   .name = "register_swallow"   },
    .{ .func = ziglua.wrap(l_unregister_swallow),                 .name = "unregister_swallow" },
    .{ .func = ziglua.wrap(l_reload_persistent),                  .name = "reload_persistent" },
    .{ .func = ziglua.wrap(l_get_workspace_states),               .name = "get_workspace_states" },
};

fn l_get_workspace_states(lua: *Lua) i32 {
    const parent_graph: *graph_mod.Graph = if (global_wm.current_graph.parent_node) |pn|
        pn.owner_graph orelse &global_wm.graph
    else
        &global_wm.graph;

    var all: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0 };
    defer all.deinit(global_wm.allocator);
    for (parent_graph.nodes.items) |node| {
        if (node.content == .workspace)
            all.append(global_wm.allocator, node) catch return 0;
    }
    std.sort.heap(*graph_mod.Node, all.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    lua.newTable();
    for (all.items, 0..) |node, i| {
        const sub = node.content.workspace;
        const is_current = (sub == global_wm.current_graph);
        var has_content = false;
        for (sub.nodes.items) |n| {
            switch (n.content) {
                .window, .workspace => { has_content = true; break; },
                else => {},
            }
        }
        const state: [:0]const u8 = if (is_current) "focused"
            else if (has_content) "active"
            else "inactive";

        lua.newTable();
        lua.pushInteger(@intCast(i + 1));
        lua.setField(-2, "position");
        _ = lua.pushString(state);
        lua.setField(-2, "state");
        lua.setIndexRaw(-2, @intCast(i + 1));
    }
    return 1;
}

fn l_reload_persistent(lua: *Lua) i32 {
    reload_persistent(lua);
    return 0;
}

fn l_register_swallow(lua: *Lua) i32 {
    const class = lua.checkString(1);
    const owned = global_wm.allocator.dupe(u8, class) catch
        return luaL_error_str(lua, "register_swallow: out of memory");
    global_wm.swallow_classes.put(global_wm.allocator, owned, {}) catch
        return luaL_error_str(lua, "register_swallow: out of memory");
    return 0;
}

fn l_unregister_swallow(lua: *Lua) i32 {
    const class = lua.checkString(1);
    const idx = global_wm.swallow_classes.getIndex(class) orelse return 0;
    const key = global_wm.swallow_classes.keys()[idx];
    global_wm.swallow_classes.swapRemoveAt(idx);
    global_wm.allocator.free(key);
    return 0;
}

fn l_float_left_of(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    a.x = b.x - @as(i32, @intCast(a.width));
    a.y = b.y;
    global_wm.current_graph.add_constraint(a, .{ .left_of = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_right_of(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    a.x = b.x + @as(i32, @intCast(b.width));
    a.y = b.y;
    global_wm.current_graph.add_constraint(a, .{ .right_of = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_above(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    a.x = b.x;
    a.y = b.y - @as(i32, @intCast(a.height));
    global_wm.current_graph.add_constraint(a, .{ .above = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_below(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    a.x = b.x;
    a.y = b.y + @as(i32, @intCast(b.height));
    global_wm.current_graph.add_constraint(a, .{ .below = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_equal_width(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    global_wm.current_graph.add_constraint(a, .{ .equal_width = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_equal_height(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    global_wm.current_graph.add_constraint(a, .{ .equal_height = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_align_left(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    global_wm.current_graph.add_constraint(a, .{ .align_left = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_align_top(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    global_wm.current_graph.add_constraint(a, .{ .align_top = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_align_right(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    a.constraints.clearRetainingCapacity();
    global_wm.current_graph.add_constraint(a, .{ .align_right = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_align_bottom(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    if (!a.floating) return luaL_error_str(lua, "node is not floating");
    a.constraints.clearRetainingCapacity();
    global_wm.current_graph.add_constraint(a, .{ .align_bottom = b }) catch {};
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_float_clear_constraints(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const node = global_wm.get_node_by_id(id) orelse return 0;
    if (!node.floating) return luaL_error_str(lua, "node is not floating");
    node.constraints.clearRetainingCapacity();
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_get_node_border_side_colors(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushNil();
        return 1;
    };
    lua.newTable();
    if (node.border_color_top) |color| { lua.pushInteger(@intCast(color)); lua.setField(-2, "top"); }
    if (node.border_color_bottom) |color| { lua.pushInteger(@intCast(color)); lua.setField(-2, "bottom"); }
    if (node.border_color_left) |color| { lua.pushInteger(@intCast(color)); lua.setField(-2, "left"); }
    if (node.border_color_right) |color| { lua.pushInteger(@intCast(color)); lua.setField(-2, "right"); }
    return 1;
}

fn l_set_node_border_side_color(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const side       = lua.checkString(2);
    const color = check_color(lua, 3) orelse return luaL_error_str(lua, "invalid color");
    const node = global_wm.get_node_by_id(id) orelse return 0;
    if (std.mem.eql(u8, side, "top"))         node.border_color_top    = color
    else if (std.mem.eql(u8, side, "bottom")) node.border_color_bottom = color
    else if (std.mem.eql(u8, side, "left"))   node.border_color_left   = color
    else if (std.mem.eql(u8, side, "right"))  node.border_color_right  = color;
    repaint_node(global_wm, node);
    return 0;
}

fn l_clear_node_border_side_colors(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const node = global_wm.get_node_by_id(id) orelse return 0;
    node.border_color_top    = null;
    node.border_color_bottom = null;
    node.border_color_left   = null;
    node.border_color_right  = null;
    repaint_node(global_wm, node);
    return 0;
}

fn l_set_border_side_colors_focused_only(lua: *Lua) i32 {
    global_wm.border_side_colors_focused_only = lua.toBoolean(1);
    return 0;
}

fn l_set_layout(lua: *Lua) i32 {
    lua.checkType(1, .table);
    const g = global_wm.current_graph;

    // get nodes array
    _ = lua.getField(1, "nodes");
    if (lua.typeOf(-1) != .table) {
        lua.pop(1);
        return luaL_error_str(lua, "set_layout: expected table with 'nodes' array");
    }
    const n_nodes: usize = @intCast(lua.lenRaw(-1));

    // first pass: clear all constraints for nodes in the layout
    for (0..n_nodes) |i| {
        _ = lua.getIndexRaw(-1, @intCast(i + 1));
        _ = lua.getField(-1, "id");
        const id: u32 = @intCast(lua.toInteger(-1) catch 0);
        lua.pop(1);
        if (id != 0) {
            if (global_wm.get_node_by_id(id)) |node| {
                node.constraints.clearRetainingCapacity();
            }
        }
        lua.pop(1);
    }

    // second pass: apply constraints
    for (0..n_nodes) |i| {
        _ = lua.getIndexRaw(-1, @intCast(i + 1));

        _ = lua.getField(-1, "id");
        const id: u32 = @intCast(lua.toInteger(-1) catch 0);
        lua.pop(1);

        const node = global_wm.get_node_by_id(id) orelse {
            lua.pop(1);
            continue;
        };

        _ = lua.getField(-1, "constraints");
        if (lua.typeOf(-1) == .table) {
            const n_cons: usize = @intCast(lua.lenRaw(-1));
            for (0..n_cons) |ci| {
                _ = lua.getIndexRaw(-1, @intCast(ci + 1));

                _ = lua.getField(-1, "type");
                const con_type = lua.toString(-1) catch {
                    lua.pop(2);
                    continue;
                };
                lua.pop(1);

                if (std.mem.eql(u8, con_type, "fixed_x")) {
                    _ = lua.getField(-1, "value");
                    const v: i32 = @intCast(lua.toInteger(-1) catch 0);
                    lua.pop(1);
                    g.add_constraint(node, .{ .fixed_x = v }) catch {};
                } else if (std.mem.eql(u8, con_type, "fixed_y")) {
                    _ = lua.getField(-1, "value");
                    const v: i32 = @intCast(lua.toInteger(-1) catch 0);
                    lua.pop(1);
                    g.add_constraint(node, .{ .fixed_y = v }) catch {};
                } else if (std.mem.eql(u8, con_type, "fixed_width")) {
                    _ = lua.getField(-1, "value");
                    const v: u32 = @intCast(lua.toInteger(-1) catch 0);
                    lua.pop(1);
                    g.add_constraint(node, .{ .fixed_width = v }) catch {};
                } else if (std.mem.eql(u8, con_type, "fixed_height")) {
                    _ = lua.getField(-1, "value");
                    const v: u32 = @intCast(lua.toInteger(-1) catch 0);
                    lua.pop(1);
                    g.add_constraint(node, .{ .fixed_height = v }) catch {};
                } else if (std.mem.eql(u8, con_type, "fixed_ratio")) {
                    _ = lua.getField(-1, "value");
                    const v: f32 = @floatCast(lua.toNumber(-1) catch 0);
                    lua.pop(1);
                    g.add_constraint(node, .{ .fixed_ratio = v }) catch {};
                } else if (std.mem.eql(u8, con_type, "grid_cell")) {
                    _ = lua.getField(-1, "col");  const col:  u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "row");  const row:  u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "cols"); const cols: u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "rows"); const rows: u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "container");
                    const cont_id: u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    const cont = global_wm.get_node_by_id(cont_id) orelse { lua.pop(1); continue; };
                    g.add_constraint(node, .{ .grid_cell = .{
                        .col = col, .row = row, .cols = cols, .rows = rows, .container = cont,
                    }}) catch {};
                } else if (std.mem.eql(u8, con_type, "grid_cell_abs")) {
                    _ = lua.getField(-1, "x"); const x: i32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "y"); const y: i32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "w"); const w: u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "h"); const h: u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "container");
                    const cont_id: u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    const cont = global_wm.get_node_by_id(cont_id) orelse { lua.pop(1); continue; };
                    g.add_constraint(node, .{ .grid_cell_abs = .{
                        .x = x, .y = y, .w = w, .h = h, .container = cont,
                    }}) catch {};
                } else if (std.mem.eql(u8, con_type, "split")) {
                    _ = lua.getField(-1, "axis");
                    const axis_str = lua.toString(-1) catch "h"; lua.pop(1);
                    const axis: graph_mod.SplitAxis = if (std.mem.eql(u8, axis_str, "h")) .horizontal else .vertical;
                    _ = lua.getField(-1, "count");
                    const count: u8 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    _ = lua.getField(-1, "container");
                    const cont_id: u32 = @intCast(lua.toInteger(-1) catch 0); lua.pop(1);
                    const cont = global_wm.get_node_by_id(cont_id) orelse { lua.pop(1); continue; };

                    var con = graph_mod.Constraint{ .split = .{
                        .container = cont,
                        .axis      = axis,
                        .count     = count,
                        .ratios    = undefined,
                        .children  = undefined,
                    }};

                    _ = lua.getField(-1, "ratios");
                    for (0..count) |ri| {
                        _ = lua.getIndexRaw(-1, @intCast(ri + 1));
                        con.split.ratios[ri] = @floatCast(lua.toNumber(-1) catch 0.5);
                        lua.pop(1);
                    }
                    lua.pop(1);

                    _ = lua.getField(-1, "children");
                    for (0..count) |ci2| {
                        _ = lua.getIndexRaw(-1, @intCast(ci2 + 1));
                        const child_id: u32 = @intCast(lua.toInteger(-1) catch 0);
                        lua.pop(1);
                        con.split.children[ci2] = global_wm.get_node_by_id(child_id) orelse {
                            lua.pop(2);
                            return luaL_error_str(lua, "set_layout: invalid child id in split");
                        };
                    }
                    lua.pop(1);

                    g.add_constraint(node, con) catch {};
                } else if (std.mem.eql(u8, con_type, "left_of"))     { apply_other(lua, g, node, .left_of);     }
                  else if (std.mem.eql(u8, con_type, "right_of"))    { apply_other(lua, g, node, .right_of);    }
                  else if (std.mem.eql(u8, con_type, "above"))       { apply_other(lua, g, node, .above);       }
                  else if (std.mem.eql(u8, con_type, "below"))       { apply_other(lua, g, node, .below);       }
                  else if (std.mem.eql(u8, con_type, "align_left"))  { apply_other(lua, g, node, .align_left);  }
                  else if (std.mem.eql(u8, con_type, "align_top"))   { apply_other(lua, g, node, .align_top);   }
                  else if (std.mem.eql(u8, con_type, "align_right")) { apply_other(lua, g, node, .align_right); }
                  else if (std.mem.eql(u8, con_type, "align_bottom")){ apply_other(lua, g, node, .align_bottom);}
                  else if (std.mem.eql(u8, con_type, "equal_width")) { apply_other(lua, g, node, .equal_width); }
                  else if (std.mem.eql(u8, con_type, "equal_height")){ apply_other(lua, g, node, .equal_height);}

                lua.pop(1); // constraint table
            }
        }
        lua.pop(1); // constraints
        lua.pop(1); // node table
    }

    lua.pop(1); // nodes array
    return 0;
}

fn l_get_layout(lua: *Lua) i32 {
    const g = global_wm.current_graph;

    lua.checkStack(20) catch {};

    var parent_map = std.AutoHashMapUnmanaged(*graph_mod.Node, *graph_mod.Node){};
    defer parent_map.deinit(global_wm.allocator);
    var parent_idx_map = std.AutoHashMapUnmanaged(*graph_mod.Node, u8){};
    defer parent_idx_map.deinit(global_wm.allocator);

    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content == .workspace and node.preview_window == null) continue;
        for (node.constraints.items) |con| {
            if (con == .split) {
                for (0..con.split.count) |i| {
                    parent_map.put(global_wm.allocator, con.split.children[i], node) catch {};
                    parent_idx_map.put(global_wm.allocator, con.split.children[i], @intCast(i + 1)) catch {};
                }
            }
        }
    }

    lua.newTable();
    lua.newTable();

    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content == .workspace and node.preview_window == null) continue;
        const id = global_wm.get_id_for_node(node) orelse continue;

        lua.checkStack(30) catch {};

        lua.newTable();

        lua.pushInteger(@intCast(id));
        lua.setField(-2, "id");

        _ = switch (node.content) {
            .window    => lua.pushString("window"),
            .empty     => lua.pushString("empty"),
            .workspace => lua.pushString("workspace"),
        };
        lua.setField(-2, "type");

        lua.pushInteger(node.x);      lua.setField(-2, "x");
        lua.pushInteger(node.y);      lua.setField(-2, "y");
        lua.pushInteger(node.width);  lua.setField(-2, "width");
        lua.pushInteger(node.height); lua.setField(-2, "height");

        if (parent_map.get(node)) |pn| {
            if (global_wm.get_id_for_node(pn)) |pid| {
                lua.pushInteger(@intCast(pid));
                lua.setField(-2, "parent");
                lua.pushInteger(@intCast(parent_idx_map.get(node) orelse 1));
                lua.setField(-2, "parent_idx");
            } else {
                lua.pushNil(); lua.setField(-2, "parent");
                lua.pushNil(); lua.setField(-2, "parent_idx");
            }
        } else {
            lua.pushNil(); lua.setField(-2, "parent");
            lua.pushNil(); lua.setField(-2, "parent_idx");
        }

        lua.newTable();
        for (node.constraints.items, 0..) |con, ci| {
            lua.checkStack(20) catch {};
            lua.newTable();
            switch (con) {
                .fixed_x      => |v| { _ = lua.pushString("fixed_x");      lua.setField(-2, "type"); lua.pushInteger(v); lua.setField(-2, "value"); },
                .fixed_y      => |v| { _ = lua.pushString("fixed_y");      lua.setField(-2, "type"); lua.pushInteger(v); lua.setField(-2, "value"); },
                .fixed_width  => |v| { _ = lua.pushString("fixed_width");  lua.setField(-2, "type"); lua.pushInteger(v); lua.setField(-2, "value"); },
                .fixed_height => |v| { _ = lua.pushString("fixed_height"); lua.setField(-2, "type"); lua.pushInteger(v); lua.setField(-2, "value"); },
                .fixed_ratio  => |v| { _ = lua.pushString("fixed_ratio");  lua.setField(-2, "type"); lua.pushNumber(v);  lua.setField(-2, "value"); },
                .grid_cell => |gc| {
                    _ = lua.pushString("grid_cell"); lua.setField(-2, "type");
                    lua.pushInteger(@intCast(gc.col));  lua.setField(-2, "col");
                    lua.pushInteger(@intCast(gc.row));  lua.setField(-2, "row");
                    lua.pushInteger(@intCast(gc.cols)); lua.setField(-2, "cols");
                    lua.pushInteger(@intCast(gc.rows)); lua.setField(-2, "rows");
                    lua.pushInteger(@intCast(global_wm.get_id_for_node(gc.container) orelse 0));
                    lua.setField(-2, "container");
                },
                .grid_cell_abs => |gc| {
                    _ = lua.pushString("grid_cell_abs"); lua.setField(-2, "type");
                    lua.pushInteger(gc.x); lua.setField(-2, "x");
                    lua.pushInteger(gc.y); lua.setField(-2, "y");
                    lua.pushInteger(gc.w); lua.setField(-2, "w");
                    lua.pushInteger(gc.h); lua.setField(-2, "h");
                    lua.pushInteger(@intCast(global_wm.get_id_for_node(gc.container) orelse 0));
                    lua.setField(-2, "container");
                },
                .split => |s| {
                    _ = lua.pushString("split"); lua.setField(-2, "type");
                    _ = lua.pushString(if (s.axis == .horizontal) "h" else "v");
                    lua.setField(-2, "axis");
                    lua.pushInteger(@intCast(s.count)); lua.setField(-2, "count");
                    lua.pushInteger(@intCast(global_wm.get_id_for_node(s.container) orelse 0));
                    lua.setField(-2, "container");
                    lua.newTable();
                    for (0..s.count) |ri| {
                        lua.pushNumber(s.ratios[ri]);
                        lua.setIndexRaw(-2, @intCast(ri + 1));
                    }
                    lua.setField(-2, "ratios");
                    lua.newTable();
                    for (0..s.count) |ci2| {
                        lua.pushInteger(@intCast(global_wm.get_id_for_node(s.children[ci2]) orelse 0));
                        lua.setIndexRaw(-2, @intCast(ci2 + 1));
                    }
                    lua.setField(-2, "children");
                },
                .left_of      => |o| { _ = lua.pushString("left_of");      lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .right_of     => |o| { _ = lua.pushString("right_of");     lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .above        => |o| { _ = lua.pushString("above");        lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .below        => |o| { _ = lua.pushString("below");        lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .align_left   => |o| { _ = lua.pushString("align_left");   lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .align_top    => |o| { _ = lua.pushString("align_top");    lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .align_right  => |o| { _ = lua.pushString("align_right");  lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .align_bottom => |o| { _ = lua.pushString("align_bottom"); lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .equal_width  => |o| { _ = lua.pushString("equal_width");  lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
                .equal_height => |o| { _ = lua.pushString("equal_height"); lua.setField(-2, "type"); lua.pushInteger(@intCast(global_wm.get_id_for_node(o) orelse 0)); lua.setField(-2, "other"); },
            }
            lua.setIndexRaw(-2, @intCast(ci + 1));
        }
        lua.setField(-2, "constraints");

        lua.pushValue(-1);
        lua.setIndexRaw(-3, @intCast(id));
        lua.pop(1);
    }

    // nodes array
    lua.newTable();
    var ni: usize = 0;
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content == .workspace and node.preview_window == null) continue;
        const id = global_wm.get_id_for_node(node) orelse continue;
        lua.pushInteger(@intCast(id));
        _ = lua.getTable(-3);
        if (lua.typeOf(-1) == .nil) {
            lua.pop(1);
            continue;
        }
        lua.setIndexRaw(-2, @intCast(ni + 1));
        ni += 1;
    }
    lua.setField(-3, "nodes");

    lua.setField(-2, "by_id");

    // windows array
    lua.newTable();
    var wi: usize = 0;
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content == .workspace and node.preview_window == null) continue;
        switch (node.content) {
            .window, .workspace => {
                if (global_wm.get_id_for_node(node)) |id| {
                    lua.pushInteger(@intCast(id));
                    lua.setIndexRaw(-2, @intCast(wi + 1));
                    wi += 1;
                }
            },
            else => {},
        }
    }
    lua.setField(-2, "windows");

    if (global_wm.focused) |f| {
        if (global_wm.get_id_for_node(f)) |fid| {
            lua.pushInteger(@intCast(fid));
        } else {
            lua.pushNil();
        }
    } else {
        lua.pushNil();
    }
    lua.setField(-2, "focused");

    // root
    var root_id: u32 = 0;
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content != .empty) continue;
        if (parent_map.get(node) == null) {
            if (global_wm.get_id_for_node(node)) |id| {
                root_id = id;
                break;
            }
        }
    }
    if (root_id != 0) {
        lua.pushInteger(@intCast(root_id));
    } else {
        lua.pushNil();
    }
    lua.setField(-2, "root");

    return 1;
}

fn l_get_split_ratios(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushNil();
        return 1;
    };
    for (node.constraints.items) |con| {
        if (con == .split) {
            lua.newTable();
            for (0..con.split.count) |i| {
                lua.pushNumber(con.split.ratios[i]);
                lua.setIndexRaw(-2, @intCast(i + 1));
            }
            return 1;
        }
    }
    lua.pushNil();
    return 1;
}

fn l_get_workspace_positions(lua: *Lua) i32 {
    const parent_graph: *graph_mod.Graph = if (global_wm.current_graph.parent_node) |pn|
        pn.owner_graph orelse &global_wm.graph
    else
        &global_wm.graph;

    // Full list sorted by creation ID
    var all: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0 };
    defer all.deinit(global_wm.allocator);
    for (parent_graph.nodes.items) |node| {
        if (node.content == .workspace)
            all.append(global_wm.allocator, node) catch return 0;
    }
    std.sort.heap(*graph_mod.Node, all.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    // Return positional indices (1-based) for occupied or current workspaces
    lua.newTable();
    var out_idx: i64 = 1;
    for (all.items, 0..) |node, i| {
        const sub = node.content.workspace;
        const is_current = (sub == global_wm.current_graph);
        var has_content = false;
        for (sub.nodes.items) |n| {
            switch (n.content) {
                .window, .workspace => { has_content = true; break; },
                else => {},
            }
        }
        if (is_current or has_content) {
            lua.pushInteger(@intCast(i + 1)); // actual position in full list
            lua.setIndexRaw(-2, out_idx);
            out_idx += 1;
        }
    }
    return 1;
}

fn l_get_current_workspace_position(lua: *Lua) i32 {
    const parent_graph: *graph_mod.Graph = if (global_wm.current_graph.parent_node) |pn|
        pn.owner_graph orelse &global_wm.graph
    else
        &global_wm.graph;

    var all: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0 };
    defer all.deinit(global_wm.allocator);
    for (parent_graph.nodes.items) |node| {
        if (node.content == .workspace)
            all.append(global_wm.allocator, node) catch return 0;
    }
    std.sort.heap(*graph_mod.Node, all.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    for (all.items, 0..) |node, i| {
        if (node.content.workspace == global_wm.current_graph) {
            lua.pushInteger(@intCast(i + 1));
            return 1;
        }
    }
    lua.pushNil();
    return 1;
}

fn l_print_graph(lua: *Lua) i32 {
    var buf = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer buf.deinit(global_wm.allocator);
    print_graph_to_buf(&buf, global_wm.allocator, global_wm.current_graph, 0);
    _ = lua.pushString(buf.items);
    return 1;
}

fn l_add_rule(lua: *Lua) i32 {
    lua.checkType(1, .function);
    lua.pushValue(1);
    const ref = lua.ref(ziglua.registry_index);
    global_wm.rules.append(global_wm.allocator, ref) catch
        return luaL_error_str(lua, "out of memory");
    lua.pushInteger(@intCast(ref));
    return 1;
}

fn l_remove_rule(lua: *Lua) i32 {
    const ref: i32 = @intCast(lua.checkInteger(1));
    const lua_vm = global_wm.lua orelse return 0;
    for (global_wm.rules.items, 0..) |r, i| {
        if (r == ref) {
            lua_vm.unref(ziglua.registry_index, ref);
            _ = global_wm.rules.swapRemove(i);
            break;
        }
    }
    return 0;
}

fn l_get_current_level(lua: *Lua) i32 {
    lua.pushInteger(@intCast(global_wm.current_graph.id.level));
    return 1;
}

fn l_get_node_level(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushNil();
        return 1;
    };
    const g = node.owner_graph orelse {
        lua.pushNil();
        return 1;
    };
    lua.pushInteger(@intCast(g.id.level));
    return 1;
}

fn l_set_preview_colors(lua: *Lua) i32 {
    const bg     = check_color(lua, 1) orelse return luaL_error_str(lua, "invalid bg color");
    const win_bg = check_color(lua, 2) orelse return luaL_error_str(lua, "invalid win_bg color");
    const border = check_color(lua, 3) orelse return luaL_error_str(lua, "invalid border color");
    const text   = check_color(lua, 4) orelse return luaL_error_str(lua, "invalid text color");
    global_wm.set_preview_colors(bg, win_bg, border, text);
    for (global_wm.current_graph.nodes.items) |node| {
        if (node.content == .workspace and !node.hidden) {
            global_wm.repaint_preview(node);
        }
    }
    _ = c.XFlush(global_wm.display);
    return 0;
}

fn l_set_preview_colors_workspace(lua: *Lua) i32 {
    const id     = check_node_id(lua, 1) orelse return 0;
    const bg     = check_color(lua, 2) orelse return luaL_error_str(lua, "invalid bg color");
    const win_bg = check_color(lua, 3) orelse return luaL_error_str(lua, "invalid win_bg color");
    const border = check_color(lua, 4) orelse return luaL_error_str(lua, "invalid border color");
    const text   = check_color(lua, 5) orelse return luaL_error_str(lua, "invalid text color");
    const node = global_wm.get_node_by_id(id) orelse return 0;
    if (node.content != .workspace) return 0;
    const sub = node.content.workspace;
    sub.preview_bg     = bg;
    sub.preview_win_bg = win_bg;
    sub.preview_border = border;
    sub.preview_text   = text;
    global_wm.repaint_preview(node);
    _ = c.XFlush(global_wm.display);
    return 0;
}

fn l_set_pan_disabled(lua: *Lua) i32 {
    global_wm.current_graph.pan_disabled = lua.toBoolean(1);
    return 0;
}

fn l_set_workspace_switch_mode(lua: *Lua) i32 {
    const mode = lua.checkString(1);
    if (std.mem.eql(u8, mode, "previous")) {
        global_wm.workspace_switch_mode = .previous;
    } else {
        global_wm.workspace_switch_mode = .none;
    }
    return 0;
}

fn l_get_arranger_index(lua: *Lua) i32 {
    lua.pushInteger(global_wm.current_graph.arranger_index);
    return 1;
}

fn l_set_arranger_index(lua: *Lua) i32 {
    global_wm.current_graph.arranger_index = @intCast(lua.checkInteger(1));
    return 0;
}

fn l_set_pan_modifier(lua: *Lua) i32 {
    const mod: c_uint = @intCast(lua.checkInteger(1));
    global_wm.pan_modifier = mod;
    const locks = [_]c_uint{ 0, c.LockMask, c.Mod2Mask, c.LockMask | c.Mod2Mask };
    for (locks) |lock| {
        _ = c.XGrabButton(@ptrCast(global_wm.display), global_wm.pan_button, mod | lock,
            global_wm.root, 1,
            c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
            c.GrabModeAsync, c.GrabModeAsync, c.None, c.None);
    }
    return 0;
}

fn l_set_pan_button(lua: *Lua) i32 {
    global_wm.pan_button = @intCast(lua.checkInteger(1));
    return 0;
}

fn l_remove_constraint(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const type_str = lua.checkString(2);
    const node = global_wm.get_node_by_id(id) orelse return 0;
    var i: usize = 0;
    while (i < node.constraints.items.len) {
        const con = node.constraints.items[i];
        const matches = blk: {
            if (std.mem.eql(u8, type_str, "fixed_x"))      break :blk con == .fixed_x;
            if (std.mem.eql(u8, type_str, "fixed_y"))      break :blk con == .fixed_y;
            if (std.mem.eql(u8, type_str, "fixed_width"))  break :blk con == .fixed_width;
            if (std.mem.eql(u8, type_str, "fixed_height")) break :blk con == .fixed_height;
            if (std.mem.eql(u8, type_str, "left_of"))      break :blk con == .left_of;
            if (std.mem.eql(u8, type_str, "right_of"))     break :blk con == .right_of;
            if (std.mem.eql(u8, type_str, "above"))        break :blk con == .above;
            if (std.mem.eql(u8, type_str, "below"))        break :blk con == .below;
            if (std.mem.eql(u8, type_str, "grid_cell"))    break :blk con == .grid_cell;
            if (std.mem.eql(u8, type_str, "split"))        break :blk con == .split;
            if (std.mem.eql(u8, type_str, "align_left"))   break :blk con == .align_left;
            if (std.mem.eql(u8, type_str, "align_right"))  break :blk con == .align_right;
            if (std.mem.eql(u8, type_str, "align_top"))    break :blk con == .align_top;
            if (std.mem.eql(u8, type_str, "align_bottom")) break :blk con == .align_bottom;
            if (std.mem.eql(u8, type_str, "equal_width"))  break :blk con == .equal_width;
            if (std.mem.eql(u8, type_str, "equal_height")) break :blk con == .equal_height;
            break :blk false;
        };
        if (matches) {
            _ = node.constraints.swapRemove(i);
        } else {
            i += 1;
        }
    }
    return 0;
}

fn l_set_lock_horizontal_resize(lua: *Lua) i32 {
    global_wm.current_graph.lock_horizontal_resize = lua.toBoolean(1);
    return 0;
}

fn l_set_lock_vertical_resize(lua: *Lua) i32 {
    global_wm.current_graph.lock_vertical_resize = lua.toBoolean(1);
    return 0;
}

fn l_get_work_area(lua: *Lua) i32 {
    const work = global_wm.get_work_area();
    lua.pushInteger(work.x);
    lua.pushInteger(work.y);
    lua.pushInteger(work.width);
    lua.pushInteger(work.height);
    return 4;
}

fn l_set_pan(lua: *Lua) i32 {
    global_wm.current_graph.pan_x = @intCast(lua.checkInteger(1));
    global_wm.current_graph.pan_y = @intCast(lua.checkInteger(2));
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_get_pan(lua: *Lua) i32 {
    lua.pushInteger(global_wm.current_graph.pan_x);
    lua.pushInteger(global_wm.current_graph.pan_y);
    return 2;
}

fn l_pan_by(lua: *Lua) i32 {
    global_wm.current_graph.pan_x += @intCast(lua.checkInteger(1));
    global_wm.current_graph.pan_y += @intCast(lua.checkInteger(2));
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_set_virtual_size(lua: *Lua) i32 {
    const w: u32 = @intCast(lua.checkInteger(1));
    const h: u32 = @intCast(lua.checkInteger(2));
    global_wm.current_graph.virtual_width  = w;
    global_wm.current_graph.virtual_height = h;
    return 0;
}

fn l_hide_window(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const node = global_wm.get_node_by_id(id) orelse return 0;
    node.hidden = true;
    switch (node.content) {
        .window => |win| {
            if (global_wm.frames.get(win)) |frame| {
                _ = c.XUnmapWindow(global_wm.display, frame);
                _ = c.XFlush(global_wm.display);
            }
        },
        .workspace => {
            if (node.preview_window) |pw| {
                if (global_wm.frames.get(pw)) |frame| {
                    _ = c.XUnmapWindow(global_wm.display, frame);
                    _ = c.XFlush(global_wm.display);
                }
            }
        },
        else => {},
    }
    return 0;
}

fn l_show_window(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const node = global_wm.get_node_by_id(id) orelse return 0;
    node.hidden = false;
    switch (node.content) {
        .window => |win| {
            if (global_wm.frames.get(win)) |frame| {
                _ = c.XMapWindow(global_wm.display, frame);
                _ = c.XMapWindow(global_wm.display, win);
                _ = c.XRaiseWindow(global_wm.display, frame);
                _ = c.XFlush(global_wm.display);
                global_wm.focus(node);
            }
        },
        .workspace => {
            if (node.preview_window) |pw| {
                if (global_wm.frames.get(pw)) |frame| {
                    _ = c.XMapWindow(global_wm.display, frame);
                    _ = c.XMapWindow(global_wm.display, pw);
                    _ = c.XRaiseWindow(global_wm.display, frame);
                    global_wm.repaint_preview(node);
                    _ = c.XFlush(global_wm.display);
                    global_wm.focus(node);
                }
            }
        },
        else => {},
    }
    return 0;
}

fn l_set_click_to_focus(lua: *Lua) i32 {
    global_wm.click_to_focus = lua.toBoolean(1);
    if (global_wm.click_to_focus) {
        // Grab button 1 on all existing frames so clicks reach on_button_press
        var it = global_wm.frames.valueIterator();
        while (it.next()) |frame| {
            _ = c.XGrabButton(global_wm.display, 1, c.AnyModifier, frame.*, 0,
                c.ButtonPressMask | c.ButtonReleaseMask,
                c.GrabModeSync, c.GrabModeAsync, c.None, c.None);
        }
    } else {
        var it = global_wm.frames.valueIterator();
        while (it.next()) |frame| {
            _ = c.XUngrabButton(global_wm.display, 1, c.AnyModifier, frame.*);
        }
    }
    return 0;
}

fn l_get_urgent(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(node.urgent);
    return 1;
}

fn l_set_urgent(lua: *Lua) i32 {
    const id  = check_node_id(lua, 1) orelse return 0;
    const val = lua.toBoolean(2);
    const node = global_wm.get_node_by_id(id) orelse return 0;
    node.urgent = val;
    return 0;
}

fn l_get_window_class(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushNil();
        return 1;
    };
    const win = switch (node.content) {
        .window => |w| w,
        else => {
            lua.pushNil();
            return 1;
        },
    };
    var hint: c.XClassHint = std.mem.zeroes(c.XClassHint);
    if (c.XGetClassHint(global_wm.display, win, &hint) == 0) {
        lua.pushNil();
        return 1;
    }
    defer {
        if (hint.res_name)  |n| _ = c.XFree(n);
        if (hint.res_class) |cl| _ = c.XFree(cl);
    }
    _ = lua.pushString(if (hint.res_class) |cl| std.mem.span(cl) else "");
    return 1;
}

fn l_get_window_name(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushNil();
        return 1;
    };
    const win = switch (node.content) {
        .window => |w| w,
        else => {
            lua.pushNil();
            return 1;
        },
    };
    var name: [*c]u8 = null;
    if (c.XFetchName(global_wm.display, win, &name) == 0 or name == null) {
        lua.pushNil();
        return 1;
    }
    defer _ = c.XFree(name);
    _ = lua.pushString(std.mem.span(name));
    return 1;
}

fn l_quit(lua: *Lua) i32 {
    _ = lua;
    std.process.exit(0);
}

fn l_set_gaps(lua: *Lua) i32 {
    const inner_h = check_u32(lua, 1) orelse return luaL_error_str(lua, "invalid inner_h");
    const inner_v = check_u32(lua, 2) orelse return luaL_error_str(lua, "invalid inner_v");
    const outer_h = check_u32(lua, 3) orelse return luaL_error_str(lua, "invalid outer_h");
    const outer_v = check_u32(lua, 4) orelse return luaL_error_str(lua, "invalid outer_v");
    global_wm.default_gap_inner_h = inner_h;
    global_wm.default_gap_inner_v = inner_v;
    global_wm.default_gap_outer_h = outer_h;
    global_wm.default_gap_outer_v = outer_v;
    apply_gaps_to_graph(&global_wm.graph, inner_h, inner_v, outer_h, outer_v);
    apply_gaps_to_graph(global_wm.current_graph, inner_h, inner_v, outer_h, outer_v);
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_set_gaps_workspace(lua: *Lua) i32 {
    const id      = check_node_id(lua, 1) orelse return 0;
    const inner_h = check_u32(lua, 2) orelse return luaL_error_str(lua, "invalid inner_h");
    const inner_v = check_u32(lua, 3) orelse return luaL_error_str(lua, "invalid inner_v");
    const outer_h = check_u32(lua, 4) orelse return luaL_error_str(lua, "invalid outer_h");
    const outer_v = check_u32(lua, 5) orelse return luaL_error_str(lua, "invalid outer_v");
    const node = global_wm.get_node_by_id(id) orelse return 0;
    if (node.content != .workspace) return 0;
    node.content.workspace.gap_inner_h = inner_h;
    node.content.workspace.gap_inner_v = inner_v;
    node.content.workspace.gap_outer_h = outer_h;
    node.content.workspace.gap_outer_v = outer_v;
    if (node.content.workspace == global_wm.current_graph) {
        global_wm.resolve(global_wm.current_graph) catch {};
        global_wm.flush(global_wm.current_graph) catch {};
    }
    return 0;
}

fn l_set_resize_modifier(lua: *Lua) i32 {
    const mod: c_uint = @intCast(lua.checkInteger(1));
    if (global_wm.resize_modifier) |old|
        _ = c.XUngrabButton(@ptrCast(global_wm.display), c.AnyButton, old, global_wm.root);
    global_wm.resize_modifier = mod;
    const locks = [_]c_uint{ 0, c.LockMask, c.Mod2Mask, c.LockMask | c.Mod2Mask };
    for (locks) |lock| {
        _ = c.XGrabButton(@ptrCast(global_wm.display), c.AnyButton, mod | lock, global_wm.root, 0,
            c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
            c.GrabModeAsync, c.GrabModeAsync, c.None, c.None);
    }
    return 0;
}

fn l_set_float_modifier(lua: *Lua) i32 {
    const mod: c_uint = @intCast(lua.checkInteger(1));
    if (global_wm.float_move_modifier) |old|
        _ = c.XUngrabButton(@ptrCast(global_wm.display), c.AnyButton, old, global_wm.root);
    global_wm.float_move_modifier = mod;
    const locks = [_]c_uint{ 0, c.LockMask, c.Mod2Mask, c.LockMask | c.Mod2Mask };
    for (locks) |lock| {
        _ = c.XGrabButton(@ptrCast(global_wm.display), c.AnyButton, mod | lock, global_wm.root, 0,
            c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
            c.GrabModeAsync, c.GrabModeAsync, c.None, c.None);
    }
    return 0;
}

fn l_set_float_move_button(lua: *Lua) i32 {
    global_wm.float_move_button = @intCast(lua.checkInteger(1));
    return 0;
}

fn l_set_float_resize_button(lua: *Lua) i32 {
    global_wm.float_resize_button = @intCast(lua.checkInteger(1));
    return 0;
}

fn l_bind(lua: *Lua) i32 {
    const mod: c_uint = @intCast(lua.checkInteger(1));
    const key = lua.checkString(2);
    lua.checkType(3, .function);
    lua.pushValue(3);
    const ref = lua.ref(ziglua.registry_index);
    const keysym = c.XStringToKeysym(key.ptr);
    if (keysym == c.NoSymbol) {
        _ = lua.pushString("wm.bind: unknown keysym");
        return lua.raiseError();
    }
    global_wm.bind_lua(mod, keysym, ref) catch {
        _ = lua.pushString("wm.bind: failed to bind key");
        return lua.raiseError();
    };
    return 0;
}

fn l_setenv(lua: *Lua) i32 {
    const key = lua.checkString(1);
    const val = lua.checkString(2);
    _ = c.setenv(key.ptr, val.ptr, 1);
    return 0;
}

fn l_spawn(lua: *Lua) i32 {
    lua.checkType(1, .table);
    const len = lua.lenRaw(1);
    var args = global_wm.allocator.alloc([]const u8, len) catch {
        _ = lua.pushString("wm.spawn: out of memory");
        return lua.raiseError();
    };
    defer global_wm.allocator.free(args);
    for (0..len) |i| {
        _ = lua.getIndexRaw(1, @intCast(i + 1));
        args[i] = lua.toString(-1) catch {
            _ = lua.pushString("wm.spawn: expected string in argv table");
            return lua.raiseError();
        };
        lua.pop(1);
    }
    global_wm.spawn(args) catch {
        _ = lua.pushString("wm.spawn: failed to spawn process");
        return lua.raiseError();
    };
    return 0;
}

fn l_focus_left(lua: *Lua) i32 {
    _ = lua;
    global_wm.focus_left() catch {};
    return 0;
}

fn l_focus_right(lua: *Lua) i32 {
    _ = lua;
    global_wm.focus_right() catch {};
    return 0;
}

fn l_focus_up(lua: *Lua) i32 {
    _ = lua;
    global_wm.focus_up() catch {};
    return 0;
}

fn l_focus_down(lua: *Lua) i32 {
    _ = lua;
    global_wm.focus_down() catch {};
    return 0;
}

fn l_focus(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    if (global_wm.get_node_by_id(id)) |node| global_wm.focus(node);
    return 0;
}

fn l_exchange_left(lua: *Lua) i32 {
    _ = lua;
    global_wm.exchange_left() catch {};
    return 0;
}

fn l_exchange_right(lua: *Lua) i32 {
    _ = lua;
    global_wm.exchange_right() catch {};
    return 0;
}

fn l_exchange_up(lua: *Lua) i32 {
    _ = lua;
    global_wm.exchange_up() catch {};
    return 0;
}

fn l_exchange_down(lua: *Lua) i32 {
    _ = lua;
    global_wm.exchange_down() catch {};
    return 0;
}

fn l_set_default_arranger(lua: *Lua) i32 {
    lua.checkType(1, .function);
    lua.pushValue(1);
    global_wm.default_arranger_ref = lua.ref(ziglua.registry_index);
    if (lua.typeOf(2) == .string) {
        const name = lua.toString(2) catch return 0;
        const owned = global_wm.allocator.dupe(u8, name) catch return 0;
        if (global_wm.default_arranger_name.len > 0)
            global_wm.allocator.free(global_wm.default_arranger_name);
        global_wm.default_arranger_name = owned;
    }
    return 0;
}

fn l_register_arranger(lua: *Lua) i32 {
    const workspace_id = check_node_id(lua, 1) orelse
        return luaL_error_str(lua, "invalid workspace id");
    lua.checkType(2, .function);
    const name: ?[]const u8 = if (lua.typeOf(3) == .string)
        lua.toString(3) catch null
    else
        null;
    const node = global_wm.get_node_by_id(workspace_id) orelse
        return luaL_error_str(lua, "register_arranger: invalid workspace id");
    if (node.content != .workspace)
        return luaL_error_str(lua, "register_arranger: node is not a workspace");
    lua.pushValue(2);
    const factory_ref = lua.ref(ziglua.registry_index);
    apply_arranger_to_graph(lua, node.content.workspace, factory_ref);
    lua.unref(ziglua.registry_index, factory_ref);
    if (name) |n| {
        const owned = global_wm.allocator.dupe(u8, n) catch return 0;
        if (node.content.workspace.arranger_name.len > 0)
            global_wm.allocator.free(node.content.workspace.arranger_name);
        node.content.workspace.arranger_name = owned;
    }
    return 0;
}

fn l_get_arranger_name(lua: *Lua) i32 {
    const name = global_wm.current_graph.arranger_name;
    if (name.len == 0) {
        lua.pushNil();
        return 1;
    }
    _ = lua.pushString(name);
    return 1;
}

fn l_set_arranger(lua: *Lua) i32 {
    lua.checkType(1, .function);
    const name: ?[]const u8 = if (lua.typeOf(2) == .string)
        lua.toString(2) catch null
    else
        null;

    lua.pushValue(1);
    const factory_ref = lua.ref(ziglua.registry_index);
    apply_arranger_to_graph(lua, global_wm.current_graph, factory_ref);
    lua.unref(ziglua.registry_index, factory_ref);

    if (name) |n| {
        const owned = global_wm.allocator.dupe(u8, n) catch return 0;
        if (global_wm.current_graph.arranger_name.len > 0)
            global_wm.allocator.free(global_wm.current_graph.arranger_name);
        global_wm.current_graph.arranger_name = owned;
    }
    return 0;
}

fn l_get_focused(lua: *Lua) i32 {
    if (global_wm.focused) |node| {
        var it = global_wm.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == node) {
                lua.pushInteger(@intCast(entry.key_ptr.*));
                return 1;
            }
        }
    }
    lua.pushNil();
    return 1;
}

fn l_resize_edge(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const dir_str = lua.checkString(2);
    const delta: i32 = @intCast(lua.checkInteger(3));
    const node = global_wm.get_node_by_id(id) orelse return luaL_error_str(lua, "invalid node id");
    const dir: graph_mod.Direction = if (std.mem.eql(u8, dir_str, "left")) .Left
        else if (std.mem.eql(u8, dir_str, "right")) .Right
        else if (std.mem.eql(u8, dir_str, "up")) .Up
        else if (std.mem.eql(u8, dir_str, "down")) .Down
        else return luaL_error_str(lua, "direction must be left/right/up/down");
    global_wm.resize_edge(node, dir, delta) catch
        return luaL_error_str(lua, "resize failed (size limit)");
    return 0;
}

fn l_resize_corner(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const delta_x: i32 = @intCast(lua.checkInteger(2));
    const delta_y: i32 = @intCast(lua.checkInteger(3));
    const node = global_wm.get_node_by_id(id) orelse return luaL_error_str(lua, "invalid node id");
    global_wm.resize_corner(node, delta_x, delta_y) catch
        return luaL_error_str(lua, "resize corner failed");
    return 0;
}

fn l_resize_focused_edge(lua: *Lua) i32 {
    const dir_str = lua.checkString(1);
    const delta: i32 = @intCast(lua.checkInteger(2));
    const node = global_wm.focused orelse return 0;
    const dir: graph_mod.Direction = if (std.mem.eql(u8, dir_str, "left")) .Left
        else if (std.mem.eql(u8, dir_str, "right")) .Right
        else if (std.mem.eql(u8, dir_str, "up")) .Up
        else if (std.mem.eql(u8, dir_str, "down")) .Down
        else {
            _ = lua.pushString("direction must be left/right/up/down");
            return lua.raiseError();
        };
    global_wm.resize_edge(node, dir, delta) catch {
        _ = lua.pushString("resize edge failed");
        return lua.raiseError();
    };
    return 0;
}

fn l_resize_focused_corner(lua: *Lua) i32 {
    const delta_x: i32 = @intCast(lua.checkInteger(1));
    const delta_y: i32 = @intCast(lua.checkInteger(2));
    const node = global_wm.focused orelse return 0;
    global_wm.resize_corner(node, delta_x, delta_y) catch {
        _ = lua.pushString("resize corner failed");
        return lua.raiseError();
    };
    return 0;
}

fn l_remove_node(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const node = global_wm.get_node_by_id(id) orelse return 0;
    switch (node.content) {
        .window => |win| _ = global_wm.window_to_node_id.remove(win),
        else => {},
    }
    _ = global_wm.node_registry.remove(id);
    if (node.owner_graph) |graph| {
        graph.remove_node(node);
    }
    return 0;
}

fn l_kill_client(lua: *Lua) i32 {
    _ = lua;
    global_wm.kill_client() catch {};
    return 0;
}

fn l_get_node_info(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushNil();
        return 1;
    };
    lua.newTable();
    lua.pushInteger(node.x);       lua.setField(-2, "x");
    lua.pushInteger(node.y);       lua.setField(-2, "y");
    lua.pushInteger(node.width);   lua.setField(-2, "width");
    lua.pushInteger(node.height);  lua.setField(-2, "height");
    lua.pushBoolean(node.floating); lua.setField(-2, "floating");
    _ = switch (node.content) {
        .window    => lua.pushString("window"),
        .empty     => lua.pushString("empty"),
        .workspace => lua.pushString("workspace"),
    };
    lua.setField(-2, "type");
    return 1;
}

fn l_create_root_node(lua: *Lua) i32 {
    const node = global_wm.current_graph.add_node(.empty) catch
        return luaL_error_str(lua, "failed to create root node");
    const w = @as(u32, @intCast(c.XDisplayWidth(@ptrCast(global_wm.display), 0)));
    const h = @as(u32, @intCast(c.XDisplayHeight(@ptrCast(global_wm.display), 0)));
    node.width = w;
    node.height = h;
    node.x = 0;
    node.y = 0;
    // Root container is not a real window, so pass null.
    const id = global_wm.register_node(null, node) catch
        return luaL_error_str(lua, "failed to register root node");
    lua.pushInteger(@intCast(id));
    return 1;
}

fn l_create_empty_node(lua: *Lua) i32 {
     const node = global_wm.current_graph.add_node(.empty) catch
        return luaL_error_str(lua, "failed to create empty node");
    // Empty nodes have no window; just register them.
    const id = global_wm.register_node(null, node) catch
        return luaL_error_str(lua, "failed to register empty node");
    lua.pushInteger(@intCast(id));
    return 1;
}

fn add_constraint(_: *Lua, comptime constr: Constraint) i32 {
    _ = constr;
    return 0;
}

fn l_left_of(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .left_of = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_right_of(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .right_of = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_above(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .above = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_below(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .below = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_left(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .align_left = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_top(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .align_top = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_right(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .align_right = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_bottom(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .align_bottom = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_equal_width(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .equal_width = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_equal_height(lua: *Lua) i32 {
    const a_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node a");
    const b_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid node b");
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .equal_height = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_fixed_ratio(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node");
    const ratio = lua.checkNumber(2);
    if (ratio <= 0.0) return luaL_error_str(lua, "ratio must be positive");
    const node = global_wm.get_node_by_id(id) orelse return luaL_error_str(lua, "invalid node");
    global_wm.current_graph.add_constraint(node, .{ .fixed_ratio = @floatCast(ratio) }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_fixed_width(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const w  = check_u32(lua, 2) orelse return luaL_error_str(lua, "width must be non-negative");
    const node = global_wm.get_node_by_id(id) orelse return 0;
    global_wm.current_graph.add_constraint(node, .{ .fixed_width = w }) catch {};
    return 0;
}


fn l_fixed_height(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const h  = check_u32(lua, 2) orelse return luaL_error_str(lua, "height must be non-negative");
    const node = global_wm.get_node_by_id(id) orelse return 0;
    global_wm.current_graph.add_constraint(node, .{ .fixed_height = h }) catch {};
    return 0;
}

fn l_fixed_x(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const x: i32 = @intCast(lua.checkInteger(2));
    const node = global_wm.get_node_by_id(id) orelse return 0;
    global_wm.current_graph.add_constraint(node, .{ .fixed_x = x }) catch {};
    return 0;
}

fn l_fixed_y(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const y: i32 = @intCast(lua.checkInteger(2));
    const node = global_wm.get_node_by_id(id) orelse return 0;
    global_wm.current_graph.add_constraint(node, .{ .fixed_y = y }) catch {};
    return 0;
}

fn l_grid_cell(lua: *Lua) i32 {
    const id           = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node");
    const col          = lua.checkInteger(2);
    const row          = lua.checkInteger(3);
    const cols         = lua.checkInteger(4);
    const rows         = lua.checkInteger(5);
    const container_id = check_node_id(lua, 6) orelse return luaL_error_str(lua, "invalid container");
    if (cols <= 0 or rows <= 0) return luaL_error_str(lua, "grid_cell: cols and rows must be positive");
    if (col < 0 or row < 0 or col >= cols or row >= rows) return luaL_error_str(lua, "grid_cell: cell (col,row) out of range");
    const node      = global_wm.get_node_by_id(id)           orelse return luaL_error_str(lua, "invalid node");
    const container = global_wm.get_node_by_id(container_id) orelse return luaL_error_str(lua, "invalid container");
    const g = Constraint{ .grid_cell = .{
        .col = @intCast(col),
        .row = @intCast(row),
        .cols = @intCast(cols),
        .rows = @intCast(rows),
        .container = container,
    } };
    global_wm.current_graph.add_constraint(node, g) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_grid_cell_abs(lua: *Lua) i32 {
    const id           = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node");
    const x            = @as(i32, @intCast(lua.checkInteger(2)));
    const y            = @as(i32, @intCast(lua.checkInteger(3)));
    const w            = check_u32(lua, 4) orelse return luaL_error_str(lua, "width must be non-negative");
    const h            = check_u32(lua, 5) orelse return luaL_error_str(lua, "height must be non-negative");
    const container_id = check_node_id(lua, 6) orelse return luaL_error_str(lua, "invalid container");
    const node      = global_wm.get_node_by_id(id)           orelse return luaL_error_str(lua, "invalid node");
    const container = global_wm.get_node_by_id(container_id) orelse return luaL_error_str(lua, "invalid container");
    global_wm.current_graph.add_constraint(node, .{ .grid_cell_abs = .{
        .x = x, .y = y, .w = w, .h = h, .container = container,
    }}) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_split(lua: *Lua) i32 {
    const container_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid container");
    const axis_str     = lua.checkString(2);
    lua.checkType(3, .table);
    lua.checkType(4, .table);

    const container = global_wm.get_node_by_id(container_id)
        orelse return luaL_error_str(lua, "invalid container");
    const axis: graph_mod.SplitAxis = if (std.mem.eql(u8, axis_str, "h"))
        .horizontal else .vertical;

    const count: u8 = @intCast(lua.lenRaw(3));
    if (count == 0 or count > 16)
        return luaL_error_str(lua, "split: need 1-16 children");

    const ratios_len = lua.lenRaw(3);
    const children_len = lua.lenRaw(4);
    if (ratios_len != children_len)
        return luaL_error_str(lua, "split: ratios and children must have the same length");

    var con: graph_mod.Constraint = .{ .split = .{
        .container = container,
        .axis      = axis,
        .count     = count,
        .ratios    = undefined,
        .children  = undefined,
    }};

    for (0..count) |i| {
        _ = lua.getIndexRaw(3, @intCast(i + 1));
        const ratio = lua.toNumber(-1) catch {
            lua.pop(1);
            return luaL_error_str(lua, "split: ratios must be numbers");
        };
        if (ratio <= 0.0) {
            lua.pop(1);
            return luaL_error_str(lua, "split: ratios must be positive");
        }
        con.split.ratios[i] = @floatCast(ratio);
        lua.pop(1);

        _ = lua.getIndexRaw(4, @intCast(i + 1));
        const child_id = check_node_id(lua, -1) orelse {
            lua.pop(1);
            return luaL_error_str(lua, "split: invalid child id");
        };
        lua.pop(1);
        con.split.children[i] = global_wm.get_node_by_id(child_id)
            orelse return luaL_error_str(lua, "split: invalid child id");
    }

    global_wm.current_graph.add_constraint(container, con)
        catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_create_container(lua: *Lua) i32 {
    const node = global_wm.current_graph.add_node(.empty) catch
        return luaL_error_str(lua, "failed to create container");
    const id = global_wm.register_node(null, node) catch
        return luaL_error_str(lua, "failed to register container");
    lua.pushInteger(@intCast(id));
    return 1;
}

fn l_destroy_container(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const node = global_wm.get_node_by_id(id) orelse return 0;
    switch (node.content) {
        .empty => {},
        else => return luaL_error_str(lua, "destroy_container called on non-container"),
    }
    _ = global_wm.node_registry.remove(id);
    if (node.owner_graph) |graph| {
        graph.remove_node(node);
    }
    return 0;
}

fn l_reparent(lua: *Lua) i32 {
    const child_id  = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid child node");
    const parent_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid parent node");
    const child  = global_wm.get_node_by_id(child_id)  orelse return luaL_error_str(lua, "invalid child node");
    const parent = global_wm.get_node_by_id(parent_id) orelse return luaL_error_str(lua, "invalid parent node");
    var i: usize = 0;
    while (i < child.constraints.items.len) {
        if (child.constraints.items[i] == .grid_cell) {
            _ = child.constraints.swapRemove(i);
        } else {
            i += 1;
        }
    }
    const g = Constraint{ .grid_cell = .{
        .col = 0, .row = 0, .cols = 1, .rows = 1, .container = parent,
    } };
    global_wm.current_graph.add_constraint(child, g) catch
        return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_get_container_of(lua: *Lua) i32 {
    const child_id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const child = global_wm.get_node_by_id(child_id) orelse {
        lua.pushNil();
        return 1;
    };
    if (graph_mod.get_container(child)) |container| {
        if (global_wm.get_id_for_node(container)) |id| {
            lua.pushInteger(@intCast(id));
            return 1;
        }
    }
    lua.pushNil();
    return 1;
}

fn l_get_node_geometry(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushNil();
        return 1;
    };
    lua.createTable(0, 4);
    lua.pushInteger(node.x);      lua.setField(-2, "x");
    lua.pushInteger(node.y);      lua.setField(-2, "y");
    lua.pushInteger(node.width);  lua.setField(-2, "width");
    lua.pushInteger(node.height); lua.setField(-2, "height");
    return 1;
}

fn l_get_all_windows(lua: *Lua) i32 {
    lua.newTable();
    var i: usize = 0;
    for (global_wm.current_graph.nodes.items) |node| {
        // Include real windows AND workspace-preview nodes.
        const lookup_win: c.Window = switch (node.content) {
            .window    => |w| w,
            .workspace => node.preview_window orelse continue,
            .empty     => continue,
        };
        if (global_wm.window_to_node_id.get(lookup_win)) |nid| {
            lua.pushInteger(@intCast(nid));
            lua.setIndexRaw(-2, @intCast(i + 1));
            i += 1;
        }
    }
    return 1;
}

fn l_screen_width(lua: *Lua) i32 {
    lua.pushInteger(@intCast(global_wm.screen_width));
    return 1;
}

fn l_screen_height(lua: *Lua) i32 {
    lua.pushInteger(@intCast(global_wm.screen_height));
    return 1;
}

fn l_clear_constraints(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const node = global_wm.get_node_by_id(id) orelse return 0;
    node.constraints.clearRetainingCapacity();
    return 0;
}


fn l_set_node_empty(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    global_wm.set_node_empty(id);
    return 0;
}

fn l_set_node_window(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const win = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid window id");
    global_wm.set_node_window(id, win) catch
        return luaL_error_str(lua, "failed to set node window");
    return 0;
}

fn l_get_node_type(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    if (global_wm.node_registry.get(id)) |node| {
        _ = switch (node.content) {
            .window    => lua.pushString("window"),
            .empty     => lua.pushString("empty"),
            .workspace => lua.pushString("workspace"),
        };
        return 1;
    }
    lua.pushNil();
    return 1;
}

fn l_move_window_to_node(lua: *Lua) i32 {
    const src_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid source node id");
    const dst_id = check_node_id(lua, 2) orelse return luaL_error_str(lua, "invalid destination node id");
    global_wm.move_window_to_node(src_id, dst_id) catch
        return luaL_error_str(lua, "move_window_to_node failed");
    return 0;
}

fn l_toggle_floating(lua: *Lua) i32 {
    global_wm.toggle_floating() catch {
        _ = lua.pushString("failed to toggle floating");
        return lua.raiseError();
    };
    return 0;
}

fn l_toggle_fullscreen(lua: *Lua) i32 {
    _ = lua;
    global_wm.toggle_fullscreen() catch {};
    return 0;
}

fn l_set_fullscreen(lua: *Lua) i32 {
    const id  = check_node_id(lua, 1) orelse return 0;
    const val = lua.toBoolean(2);
    const node = global_wm.get_node_by_id(id) orelse return 0;
    if (node.content != .window) return 0;
    const already = (global_wm.fullscreen_node == node);
    if (val == already) return 0;
    global_wm.focused = node;
    global_wm.toggle_fullscreen() catch {};
    return 0;
}

fn l_set_floating(lua: *Lua) i32 {
    const id  = check_node_id(lua, 1) orelse return 0;
    const val = lua.toBoolean(2);
    const node = global_wm.get_node_by_id(id) orelse return 0;
    if (node.content != .window) return 0;
    if (node.floating == val) return 0;
    node.constraints.clearRetainingCapacity();
    if (val) {
        global_wm.call_arranger(global_wm.current_graph, "unmap", id, null);
        node.floating = true;
        global_wm.center_node(node);
    } else {
        node.floating = false;
        var prev_id: ?u32 = null;
        if (global_wm.focused) |f| {
            if (f != node) {
                var it = global_wm.node_registry.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == f) { prev_id = entry.key_ptr.*; break; }
                }
            }
        }
        global_wm.call_arranger(global_wm.current_graph, "map", id, prev_id);
    }
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_set_node_focused_border_color(lua: *Lua) i32 {
    const id    = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const color = check_color(lua, 2)   orelse return luaL_error_str(lua, "invalid color");
    if (global_wm.get_node_by_id(id)) |node| {
        node.border_color_focused = color;
        if (global_wm.focused == node) repaint_node(global_wm, node);
        return 0;
    }
    return luaL_error_str(lua, "invalid node id");
}

fn l_set_node_unfocused_border_color(lua: *Lua) i32 {
    const id    = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const color = check_color(lua, 2)   orelse return luaL_error_str(lua, "invalid color");
    if (global_wm.get_node_by_id(id)) |node| {
        node.border_color_unfocused = color;
        if (global_wm.focused != node) repaint_node(global_wm, node);
        return 0;
    }
    return luaL_error_str(lua, "invalid node id");
}

fn l_clear_node_focused_border_color(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    if (global_wm.get_node_by_id(id)) |node| {
        node.border_color_focused = null;
        if (global_wm.focused == node) repaint_node(global_wm, node);
        return 0;
    }
    return luaL_error_str(lua, "invalid node id");
}

fn l_clear_node_unfocused_border_color(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    if (global_wm.get_node_by_id(id)) |node| {
        node.border_color_unfocused = null;
        if (global_wm.focused != node) repaint_node(global_wm, node);
        return 0;
    }
    return luaL_error_str(lua, "invalid node id");
}

fn l_set_default_focused_border_color(lua: *Lua) i32 {
    const color = check_color(lua, 1) orelse return luaL_error_str(lua, "invalid color");
    global_wm.default_border_color_focused = color;
    repaint_all_nodes(global_wm);
    return 0;
}

fn l_set_default_unfocused_border_color(lua: *Lua) i32 {
    const color = check_color(lua, 1) orelse return luaL_error_str(lua, "invalid color");
    global_wm.default_border_color_unfocused = color;
    repaint_all_nodes(global_wm);
    return 0;
}

fn l_set_default_urgent_border_color(lua: *Lua) i32 {
    const color = check_color(lua, 1) orelse return luaL_error_str(lua, "invalid color");
    global_wm.default_border_color_urgent = color;
    repaint_all_nodes(global_wm);
    return 0;
}

fn l_set_border_width(lua: *Lua) i32 {
    const width = check_u32(lua, 1) orelse return luaL_error_str(lua, "border width must be non-negative");
    global_wm.border_width = @intCast(width);
    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    return 0;
}

fn l_create_nested_workspace(lua: *Lua) i32 {
    const node = global_wm.create_workspace_node_with_preview(global_wm.current_graph) catch
        return luaL_error_str(lua, "create failed");
    const id = global_wm.register_node(node.preview_window, node) catch
        return luaL_error_str(lua, "register failed");

    var prev_id: ?u32 = null;
    if (global_wm.focused) |prev_focused| {
        for (global_wm.current_graph.nodes.items) |n| {
            if (n == prev_focused) {
                var it = global_wm.node_registry.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == prev_focused) { prev_id = entry.key_ptr.*; break; }
                }
                break;
            }
        }
    }
    global_wm.call_arranger(global_wm.current_graph, "map", id, prev_id);

    const sub = node.content.workspace;
    sub.gap_inner_h = global_wm.default_gap_inner_h;
    sub.gap_inner_v = global_wm.default_gap_inner_v;
    sub.gap_outer_h = global_wm.default_gap_outer_h;
    sub.gap_outer_v = global_wm.default_gap_outer_v;

    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.rebuild_focus_edges() catch {};
    node.hidden = false;
    global_wm.flush(global_wm.current_graph) catch {};
    if (global_wm.focused) |f| global_wm.focus(f);
    lua.pushInteger(@intCast(id));
    return 1;
}

fn l_get_workspace(lua: *Lua) i32 {
    const index = lua.checkInteger(1);
    if (index < 1) {
        lua.pushNil();
        return 1;
    }
    var workspaces: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0 };
    defer workspaces.deinit(global_wm.allocator);

    for (global_wm.current_graph.nodes.items) |node| {
        if (node.content == .workspace) {
            workspaces.append(global_wm.allocator, node) catch
                return luaL_error_str(lua, "wm.get_workspace: out of memory");
        }
    }

    std.sort.heap(*graph_mod.Node, workspaces.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    const idx: usize = @intCast(index);
    if (idx > workspaces.items.len) {
        lua.pushNil();
        return 1;
    }
    const node = workspaces.items[idx - 1];
    const id = global_wm.get_id_for_node(node) orelse {
        lua.pushNil();
        return 1;
    };
    lua.pushInteger(@intCast(id));
    return 1;
}

fn l_get_workspaces_at_level(lua: *Lua) i32 {
    const current_level = global_wm.current_graph.id.level;

    // Collect workspace nodes whose subgraph is at the current level
    var list: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0 };
    defer list.deinit(global_wm.allocator);

    // Walk the parent graph's nodes (same as before)
    const parent_graph: *graph_mod.Graph = if (global_wm.current_graph.parent_node) |pn|
        pn.owner_graph orelse global_wm.current_graph
    else
        global_wm.current_graph;

    for (parent_graph.nodes.items) |node| {
        if (node.content != .workspace) continue;
        const sub = node.content.workspace;
        if (sub.id.level != current_level) continue;

        const is_current = (sub == global_wm.current_graph);
        if (is_current) {
            list.append(global_wm.allocator, node) catch {
                _ = lua.pushString("out of memory");
                return lua.raiseError();
            };
            continue;
        }

        var has_content = false;
        for (sub.nodes.items) |sub_node| {
            switch (sub_node.content) {
                .window, .workspace => { has_content = true; break; },
                else => {},
            }
        }
        if (!has_content) continue;

        list.append(global_wm.allocator, node) catch {
            _ = lua.pushString("out of memory");
            return lua.raiseError();
        };
    }

    // Sort by number within the level
    std.sort.heap(*graph_mod.Node, list.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const sub_a = a.content.workspace;
            const sub_b = b.content.workspace;
            return sub_a.id.number < sub_b.id.number;
        }
    }.lt);

    // Push table of {level, number} pairs
    lua.newTable();
    for (list.items, 0..) |node, i| {
        const sub = node.content.workspace;
        lua.pushInteger(@intCast(sub.id.number + 1));
        lua.setIndexRaw(-2, @intCast(i + 1));
    }
    return 1;
}

fn l_get_current_workspace(lua: *Lua) i32 {
    lua.pushInteger(@intCast(global_wm.current_graph.id.number + 1));
    return 1;
}


fn l_switch_to_workspace(lua: *Lua) i32 {
    const index = lua.checkInteger(1);
    if (index < 1) return luaL_error_str(lua, "workspace index must be >= 1");
    const idx: usize = @intCast(index);

    const saved_graph = global_wm.current_graph;

    const parent_graph: *graph_mod.Graph = if (global_wm.current_graph.parent_node) |pn|
        pn.owner_graph orelse &global_wm.graph
    else
        &global_wm.graph;

    var list: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0 };
    defer list.deinit(global_wm.allocator);
    for (parent_graph.nodes.items) |node| {
        if (node.content == .workspace)
            list.append(global_wm.allocator, node) catch return luaL_error_str(lua, "out of memory");
    }
    std.sort.heap(*graph_mod.Node, list.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    if (idx <= list.items.len) {
        const target = list.items[idx - 1];
        if (target.content.workspace == saved_graph) {
            if (global_wm.workspace_switch_mode == .previous) {
                if (global_wm.previous_graph) |prev| {
                    for (list.items) |n| {
                        if (n.content.workspace == prev) {
                            global_wm.previous_graph = saved_graph;
                            global_wm.enter_workspace(n) catch {};
                            return 0;
                        }
                    }
                }
            }
            return 0;
        }
        global_wm.previous_graph = saved_graph;
        global_wm.enter_workspace(target) catch return luaL_error_str(lua, "enter_workspace failed");
        return 0;
    }

    // Create missing workspaces
    const saved_current = global_wm.current_graph;
    global_wm.current_graph = parent_graph;
    var last_id: u32 = 0;
    const needed = idx - list.items.len;
    for (0..needed) |_| {
        const sub = global_wm.create_workspace_graph(parent_graph.id.level + 1) catch
            return luaL_error_str(lua, "failed to create workspace");
        const node = parent_graph.add_node(.{ .workspace = sub }) catch
            return luaL_error_str(lua, "failed to add node");
        sub.parent_node = node;
        node.preview_window = null;
        node.floating = false;
        last_id = global_wm.register_node(null, node) catch
            return luaL_error_str(lua, "failed to register workspace");
    }
    global_wm.current_graph = saved_current;

    const target_node = global_wm.get_node_by_id(last_id) orelse
        return luaL_error_str(lua, "internal error");
    global_wm.previous_graph = saved_graph;
    global_wm.enter_workspace(target_node) catch return luaL_error_str(lua, "enter_workspace failed");
    return 0;
}

fn l_enter_workspace_by_id(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid workspace id");
    const node = global_wm.get_node_by_id(id) orelse
        return luaL_error_str(lua, "invalid workspace id");
    if (node.content != .workspace)
        return luaL_error_str(lua, "node is not a workspace");
    const saved_graph = global_wm.current_graph;
    if (node.content.workspace == saved_graph) {
        if (global_wm.workspace_switch_mode == .previous) {
            if (global_wm.previous_graph) |prev| {
                for (global_wm.current_graph.nodes.items) |n| {
                    if (n.content == .workspace and n.content.workspace == prev) {
                        global_wm.previous_graph = saved_graph;
                        global_wm.enter_workspace(n) catch {};
                        return 0;
                    }
                }
            }
        }
        return 0;
    }
    global_wm.previous_graph = saved_graph;
    global_wm.enter_workspace(node) catch
        return luaL_error_str(lua, "enter_workspace failed");
    return 0;
}

fn l_exec_once(lua: *Lua) i32 {
    if (global_wm.startup_done) return 0;
    lua.checkType(1, .table);
    const len = lua.lenRaw(1);
    var args = global_wm.allocator.alloc([]const u8, len) catch {
        _ = lua.pushString("wm.exec_once: out of memory");
        return lua.raiseError();
    };
    defer global_wm.allocator.free(args);
    for (0..len) |i| {
        _ = lua.getIndexRaw(1, @intCast(i + 1));
        args[i] = lua.toString(-1) catch {
            _ = lua.pushString("wm.exec_once: expected string in argv table");
            return lua.raiseError();
        };
        lua.pop(1);
    }
    global_wm.spawn(args) catch {
        _ = lua.pushString("wm.exec_once: failed to spawn process");
        return lua.raiseError();
    };
    return 0;
}

fn l_enter_nested(lua: *Lua) i32 {
    _ = lua;
    if (global_wm.focused) |node| {
        if (node.content == .workspace) {
            global_wm.enter_workspace(node) catch return luaL_error_str(global_wm.lua.?, "enter failed");
        }
    }
    return 0;
}

fn l_leave_nested(lua: *Lua) i32 {
    _ = lua;
    global_wm.leave_workspace() catch return luaL_error_str(global_wm.lua.?, "leave failed");
    return 0;
}

fn l_enter_nested_by_id(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node");
    const node = global_wm.get_node_by_id(id) orelse return luaL_error_str(lua, "invalid node");
    if (node.content != .workspace) return luaL_error_str(lua, "not a workspace");
    global_wm.enter_workspace(node) catch return luaL_error_str(lua, "enter failed");
    return 0;
}

fn l_send_to_workspace(lua: *Lua) i32 {
    const node_id = check_node_id(lua, 1) orelse return luaL_error_str(lua, "invalid node id");
    const index: usize = @intCast(lua.checkInteger(2));
    if (index < 1) return luaL_error_str(lua, "workspace index must be >= 1");

    const parent_graph: *graph_mod.Graph = if (global_wm.current_graph.parent_node) |pn|
        pn.owner_graph orelse &global_wm.graph
    else
        &global_wm.graph;

    var list: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0 };
    defer list.deinit(global_wm.allocator);
    for (parent_graph.nodes.items) |node| {
        if (node.content == .workspace)
            list.append(global_wm.allocator, node) catch return luaL_error_str(lua, "out of memory");
    }
    std.sort.heap(*graph_mod.Node, list.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    if (index > list.items.len) {
        const needed = index - list.items.len;
        const saved_current = global_wm.current_graph;
        global_wm.current_graph = parent_graph;
        for (0..needed) |_| {
            const sub = global_wm.create_workspace_graph(parent_graph.id.level + 1) catch
                return luaL_error_str(lua, "out of memory");
            const node = parent_graph.add_node(.{ .workspace = sub }) catch
                return luaL_error_str(lua, "out of memory");
            sub.parent_node = node;
            node.preview_window = null;
            node.floating = false;
            _ = global_wm.register_node(null, node) catch
                return luaL_error_str(lua, "out of memory");
        }
        global_wm.current_graph = saved_current;

        list.clearRetainingCapacity();
        for (parent_graph.nodes.items) |node| {
            if (node.content == .workspace)
                list.append(global_wm.allocator, node) catch return luaL_error_str(lua, "out of memory");
        }
        std.sort.heap(*graph_mod.Node, list.items, {}, struct {
            fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
                const id_a = global_wm.get_id_for_node(a) orelse return false;
                const id_b = global_wm.get_id_for_node(b) orelse return false;
                return id_a < id_b;
            }
        }.lt);
    }

    const target_ws_node = list.items[index - 1];
    const target_graph = target_ws_node.content.workspace;
    global_wm.send_to_workspace(node_id, target_graph) catch |err|
        return luaL_error_str(lua, @errorName(err));
    return 0;
}

fn l_set_reparent_strategy(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const node = global_wm.get_node_by_id(id) orelse return 0;
    if (lua.typeOf(2) == .nil or lua.typeOf(2) == .none) {
        node.on_remove = null;
        return 0;
    }
    const strategy = lua.checkString(2);
    if (std.mem.eql(u8, strategy, "promote")) {
        node.on_remove = .promote;
    } else if (std.mem.eql(u8, strategy, "remove")) {
        node.on_remove = .remove;
    } else if (std.mem.eql(u8, strategy, "empty")) {
        node.on_remove = .leave_empty;
    } else {
        return luaL_error_str(lua, "set_reparent_strategy: unknown strategy, expected 'promote', 'remove', or 'empty'");
    }
    return 0;
}

fn l_unregister_node(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    _ = global_wm.node_registry.remove(id);
    return 0;
}

fn l_get_mouse_node(lua: *Lua) i32 {
    var root_return: c.Window = undefined;
    var child_return: c.Window = undefined;
    var root_x: c_int = 0;
    var root_y: c_int = 0;
    var win_x: c_int = 0;
    var win_y: c_int = 0;
    var mask: c_uint = 0;
    _ = c.XQueryPointer(
        global_wm.display,
        global_wm.root,
        &root_return,
        &child_return,
        &root_x,
        &root_y,
        &win_x,
        &win_y,
        &mask,
    );

    var best: ?*graph_mod.Node = null;
    for (global_wm.current_graph.nodes.items) |node| {
        if (node.width == 0 or node.height == 0) continue;
        const nx = node.x;
        const ny = node.y;
        const nw = @as(i32, @intCast(node.width));
        const nh = @as(i32, @intCast(node.height));
        if (root_x >= nx and root_x < nx + nw and
            root_y >= ny and root_y < ny + nh)
        {
            // Prefer the smallest node (most specific hit)
            if (best) |b| {
                if (nw * nh < @as(i32, @intCast(b.width)) * @as(i32, @intCast(b.height))) {
                    best = node;
                }
            } else {
                best = node;
            }
        }
    }

    if (best) |node| {
        if (global_wm.get_id_for_node(node)) |id| {
            lua.pushInteger(@intCast(id));
            return 1;
        }
    }
    lua.pushNil();
    return 1;
}

fn l_warp_cursor(lua: *Lua) i32 {
    const x: i32 = @intCast(lua.checkInteger(1));
    const y: i32 = @intCast(lua.checkInteger(2));
    _ = c.XWarpPointer(global_wm.display, c.None, global_wm.root, 0, 0, 0, 0, x, y);
    return 0;
}

fn l_warp_cursor_to_node(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse return 0;
    const node = global_wm.get_node_by_id(id) orelse return 0;
    const cx = node.x + @divTrunc(@as(i32, @intCast(node.width)), 2);
    const cy = node.y + @divTrunc(@as(i32, @intCast(node.height)), 2);
    _ = c.XWarpPointer(global_wm.display, c.None, global_wm.root, 0, 0, 0, 0, cx, cy);
    return 0;
}

fn l_get_cursor_pos(lua: *Lua) i32 {
    var root_return: c.Window = undefined;
    var child_return: c.Window = undefined;
    var root_x: c_int = 0;
    var root_y: c_int = 0;
    var win_x: c_int = 0;
    var win_y: c_int = 0;
    var mask: c_uint = 0;
    _ = c.XQueryPointer(
        global_wm.display,
        global_wm.root,
        &root_return,
        &child_return,
        &root_x,
        &root_y,
        &win_x,
        &win_y,
        &mask,
    );
    lua.pushInteger(root_x);
    lua.pushInteger(root_y);
    return 2;
}

fn l_get_cursor_relative_to_focused(lua: *Lua) i32 {
    var root_return: c.Window = undefined;
    var child_return: c.Window = undefined;
    var root_x: c_int = 0;
    var root_y: c_int = 0;
    var win_x: c_int = 0;
    var win_y: c_int = 0;
    var mask: c_uint = 0;
    _ = c.XQueryPointer(
        global_wm.display,
        global_wm.root,
        &root_return,
        &child_return,
        &root_x,
        &root_y,
        &win_x,
        &win_y,
        &mask,
    );

    const focused = global_wm.focused orelse {
        lua.pushInteger(0);
        lua.pushInteger(0);
        return 2;
    };

    const cx = focused.x + @divTrunc(@as(i32, @intCast(focused.width)), 2);
    const cy = focused.y + @divTrunc(@as(i32, @intCast(focused.height)), 2);

    lua.pushInteger(root_x - cx);
    lua.pushInteger(root_y - cy);
    return 2;
}

fn l_set_focus_follows_mouse(lua: *Lua) i32 {
    global_wm.focus_follows_mouse = lua.toBoolean(1);
    return 0;
}

fn l_reload_config(lua: *Lua) i32 {
    _ = lua;
    global_wm.pending_reload = true;
    return 0;
}

fn l_reload_visuals(lua: *Lua) i32 {
    const user_path = resolve_user_path(global_wm) orelse return 0;
    defer global_wm.allocator.free(user_path);
    const path_z = std.mem.concatWithSentinel(global_wm.allocator, u8, &[_][]const u8{user_path}, 0) catch return 0;
    defer global_wm.allocator.free(path_z);

    clear_all_node_colors(global_wm.current_graph);

    lua.pushFunction(ziglua.wrap(struct {
        fn noop(_: *Lua) i32 { return 0; }
    }.noop));
    const noop_ref = lua.ref(ziglua.registry_index);
    defer lua.unref(ziglua.registry_index, noop_ref);

    _ = lua.getGlobal("wm");
    for (registrations) |reg| {
        const is_visual =
            std.mem.eql(u8,    reg.name, "set_default_focused_border_color")
            or std.mem.eql(u8, reg.name, "set_default_unfocused_border_color")
            or std.mem.eql(u8, reg.name, "set_default_urgent_border_color")
            or std.mem.eql(u8, reg.name, "set_border_width")
            or std.mem.eql(u8, reg.name, "set_gaps")
            or std.mem.eql(u8, reg.name, "set_gaps_workspace")
            or std.mem.eql(u8, reg.name, "set_preview_colors")
            or std.mem.eql(u8, reg.name, "set_preview_colors_workspace")
            or std.mem.eql(u8, reg.name, "set_node_focused_border_color")
            or std.mem.eql(u8, reg.name, "set_node_unfocused_border_color")
            or std.mem.eql(u8, reg.name, "set_node_border_side_color")
            or std.mem.eql(u8, reg.name, "clear_node_focused_border_color")
            or std.mem.eql(u8, reg.name, "clear_node_unfocused_border_color")
            or std.mem.eql(u8, reg.name, "clear_node_border_side_colors")
            or std.mem.eql(u8, reg.name, "set_border_side_colors_focused_only")
            or std.mem.eql(u8, reg.name, "set_cursor_theme");
        if (!is_visual) {
            _ = lua.getIndexRaw(ziglua.registry_index, noop_ref);
            lua.setField(-2, reg.name);
        }
    }
    lua.pop(1);

    const restore = struct {
        fn run(l: *Lua) void {
            _ = l.getGlobal("wm");
            for (registrations) |reg| {
                l.pushFunction(reg.func);
                l.setField(-2, reg.name);
            }
            l.pop(1);
        }
    };

    lua.doFile(path_z) catch {
        lua.pop(1);
        restore.run(lua);
        return 0;
    };
    restore.run(lua);

    for (global_wm.current_graph.nodes.items) |node| {
        const win = switch (node.content) {
            .window    => |w| w,
            .workspace => node.preview_window orelse continue,
            .empty     => continue,
        };
        if (global_wm.frames.get(win)) |win_frame| {
            _ = c.XClearWindow(global_wm.display, win_frame);
            global_wm.draw_frame_borders(win_frame, node);
        }
    }

    global_wm.resolve(global_wm.current_graph) catch {};
    global_wm.flush(global_wm.current_graph) catch {};
    _ = c.XFlush(global_wm.display);
    return 0;
}

fn l_set_cursor_theme(lua: *Lua) i32 {
    const theme = lua.checkString(1);
    const size: c_int = @intCast(lua.checkInteger(2));

    _ = c.setenv("XCURSOR_THEME", theme.ptr, 1);
    var size_buf: [16]u8 = undefined;
    const size_str = std.fmt.bufPrintZ(&size_buf, "{}", .{size}) catch return 0;
    _ = c.setenv("XCURSOR_SIZE", size_str.ptr, 1);

    var buf: [256]u8 = undefined;
    const prop = std.fmt.bufPrint(&buf, "Xcursor.theme: {s}\nXcursor.size: {}", .{theme, size}) catch return 0;
    const xa_string = c.XInternAtom(global_wm.display, "STRING", 0);
    const resource_manager = c.XInternAtom(global_wm.display, "RESOURCE_MANAGER", 0);
    _ = c.XChangeProperty(global_wm.display, global_wm.root,
        resource_manager, xa_string, 8, c.PropModeReplace,
        prop.ptr, @intCast(prop.len));

    // create and set cursor on root and all frames
    const cursor = c.XcursorLibraryLoadCursor(global_wm.display, "left_ptr");
    if (cursor != 0) {
        _ = c.XDefineCursor(global_wm.display, global_wm.root, cursor);
        var it = global_wm.frames.valueIterator();
        while (it.next()) |frame| {
            _ = c.XDefineCursor(global_wm.display, frame.*, cursor);
        }
        _ = c.XFreeCursor(global_wm.display, cursor);
    }

    _ = c.XFlush(global_wm.display);
    return 0;
}

fn l_get_window_pid(lua: *Lua) i32 {
    const id = check_node_id(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const node = global_wm.get_node_by_id(id) orelse {
        lua.pushNil();
        return 1;
    };
    const win = switch (node.content) {
        .window => |w| w,
        else => {
            lua.pushNil();
            return 1;
        },
    };
    const net_wm_pid = c.XInternAtom(global_wm.display, "_NET_WM_PID", 0);
    var actual_type: c.Atom = undefined;
    var actual_format: c_int = undefined;
    var nitems: c_ulong = undefined;
    var bytes_after: c_ulong = undefined;
    var prop: [*c]u8 = null;
    const result = c.XGetWindowProperty(
        global_wm.display, win, net_wm_pid,
        0, 1, 0, c.AnyPropertyType,
        &actual_type, &actual_format, &nitems, &bytes_after, &prop,
    );
    if (result != c.Success or prop == null or nitems == 0) {
        if (prop != null) _ = c.XFree(prop);
        lua.pushNil();
        return 1;
    }
    defer _ = c.XFree(prop);
    const pid: c_ulong = @as(*c_ulong, @ptrCast(@alignCast(prop))).*;
    lua.pushInteger(@intCast(pid));
    return 1;
}

fn luaL_error_str(lua: *Lua, msg: []const u8) noreturn {
    _ = lua.pushString(msg);
    lua.raiseError();
}

fn setup_lua(wm: *WM, lua: *Lua) void {
    lua.openLibs();
    lua.newTable();
    lua.pushInteger(c.Mod4Mask);    lua.setField(-2, "MOD_SUPER");
    lua.pushInteger(c.Mod1Mask);    lua.setField(-2, "MOD_ALT");
    lua.pushInteger(c.ShiftMask);   lua.setField(-2, "MOD_SHIFT");
    lua.pushInteger(c.ControlMask); lua.setField(-2, "MOD_CTRL");
    lua.pushInteger(c.Mod2Mask);    lua.setField(-2, "MOD_MOD2");
    lua.pushInteger(c.Mod3Mask);    lua.setField(-2, "MOD_MOD3");
    lua.pushInteger(c.Mod5Mask);    lua.setField(-2, "MOD_MOD5");
    lua.pushInteger(c.Button1);     lua.setField(-2, "BUTTON_LEFT");
    lua.pushInteger(c.Button2);     lua.setField(-2, "BUTTON_MIDDLE");
    lua.pushInteger(c.Button3);     lua.setField(-2, "BUTTON_RIGHT");
    lua.pushInteger(c.Button4);     lua.setField(-2, "BUTTON_SCROLL_UP");
    lua.pushInteger(c.Button5);     lua.setField(-2, "BUTTON_SCROLL_DOWN");
    for (registrations) |reg| {
        lua.pushFunction(reg.func);
        lua.setField(-2, reg.name);
    }
    lua.setGlobal("wm");
    _ = wm;
}

fn reset_vm(wm: *WM) !*Lua {
    if (wm.lua) |old| {
        for (wm.rules.items) |ref| {
            old.unref(ziglua.registry_index, ref);
        }
        wm.rules.clearRetainingCapacity();
        old.deinit();
    }
    const lua = try Lua.init(wm.allocator);
    wm.lua = lua;
    setup_lua(wm, lua);
    wm.ungrab_keys();
    wm.keybinds.clearRetainingCapacity();
    wm.default_arranger_ref = 0;
    wm.reset_arranger_refs(&wm.graph);
    return lua;
}

fn resolve_user_path(wm: *WM) ?[]const u8 {
    if (c.getenv("XDG_CONFIG_HOME")) |xdg| {
        const base: []const u8 = std.mem.span(xdg);
        if (base.len > 0)
            return std.fmt.allocPrint(wm.allocator, "{s}/duckwm/config.lua", .{base}) catch null;
    }
    if (c.getenv("HOME")) |home_ptr| {
        const home: []const u8 = std.mem.span(home_ptr);
        if (home.len > 0)
            return std.fmt.allocPrint(wm.allocator, "{s}/.config/duckwm/config.lua", .{home}) catch null;
    }
    return null;
}

fn watch_config(wm: *WM, path: []const u8) void {
    const dir = std.fs.path.dirname(path) orelse {
        std.debug.print("watch_config: could not get dirname of '{s}'\n", .{path});
        return;
    };
    std.debug.print("watch_config: watching dir '{s}'\n", .{dir});
    const dir_z = std.mem.concatWithSentinel(wm.allocator, u8, &[_][]const u8{dir}, 0) catch return;
    defer wm.allocator.free(dir_z);
    wm.watch_config_dir(dir_z);
}

pub fn reload(wm: *WM) void {
    const user_path = resolve_user_path(wm) orelse {
        std.debug.print("duckwm: no user config path found for reload\n", .{});
        return;
    };
    defer wm.allocator.free(user_path);
    const path_z = std.mem.concatWithSentinel(wm.allocator, u8, &[_][]const u8{user_path}, 0) catch return;
    defer wm.allocator.free(path_z);

    // Syntax check only — compile without executing
    const old_lua = wm.lua orelse return;
    std.debug.print("reload: attempting to load '{s}'\n", .{path_z});
    var load_err: ?anyerror = null;
    for (0..5) |_| {
        old_lua.loadFile(path_z, .text) catch |err| {
            load_err = err;
            _ = c.usleep(10_000);
            continue;
        };
        load_err = null;
        break;
    }
    if (load_err) |err| {
        const lua_msg = old_lua.toString(-1) catch null;
        const msg = lua_msg orelse @errorName(err);
        const owned = wm.allocator.dupe(u8, msg) catch null;
        old_lua.pop(1);
        if (owned) |m| {
            wm_mod.notify_error(wm, m);
            wm.allocator.free(m);
        }
        return;
    }
    old_lua.pop(1);

    // Syntax clean — full reset and execute
    var lua = reset_vm(wm) catch {
        std.debug.print("reload: failed to init Lua VM\n", .{});
        return;
    };
    lua.doFile(path_z) catch |err| {
        const lua_msg_raw = lua.toString(-1) catch null;
        const owned_msg: ?[]u8 = if (lua_msg_raw) |msg|
            wm.allocator.dupe(u8, msg) catch null
        else
            null;
        lua.pop(1);
        wm_mod.notify_error(wm, owned_msg orelse @errorName(err));
        if (owned_msg) |m| wm.allocator.free(m);
        // Fall through to default
        lua = reset_vm(wm) catch return;
        lua.doFile("/etc/duckwm/config.lua") catch |err2| {
            std.debug.print("default config also failed: {}\n", .{err2});
            lua.pop(1);
        };
        return;
    };
    remap_all_graphs(wm, &wm.graph);
    std.debug.print("config reloaded successfully\n", .{});
}

fn remap_all_graphs(wm: *WM, g: *graph_mod.Graph) void {
    if (g.arranger_ref == 0 and wm.default_arranger_ref == 0) return;

    const saved_graph = wm.current_graph;
    wm.current_graph = g;  // <-- add this
    defer wm.current_graph = saved_graph;

    var ids: std.ArrayListUnmanaged(u32) = .{ .items = &.{}, .capacity = 0 };
    defer ids.deinit(wm.allocator);
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        switch (node.content) {
            .window, .workspace => {
                if (node.content == .workspace and node.preview_window == null) continue;
                if (wm.get_id_for_node(node)) |id| {
                    ids.append(wm.allocator, id) catch {};
                }
            },
            else => {},
        }
    }
    for (g.nodes.items) |node| {
        if (!node.floating) node.constraints.clearRetainingCapacity();
    }
    var prev_id: ?u32 = null;
    for (ids.items) |id| {
        if (wm.get_node_by_id(id)) |node| {
            if (node.content == .workspace and node.content.workspace == saved_graph) {
                prev_id = id;
                continue;
            }
        }
        wm.call_arranger(g, "map", id, prev_id);
        prev_id = id;
    }
    wm.resolve(g) catch {};
    wm.rebuild_focus_edges() catch {};
    // Only flush if this is a visible graph
    if (g == saved_graph) {
        wm.flush(g) catch {};
    }

    for (g.nodes.items) |node| {
        if (node.content == .workspace) {
            remap_all_graphs(wm, node.content.workspace);
        }
    }
}

pub fn load(wm: *WM) !void {
    std.debug.print("load: starting\n", .{});
    global_wm = wm;

    var lua = try Lua.init(wm.allocator);
    wm.lua = lua;
    setup_lua(wm, lua);

    comptime {
        @setEvalBranchQuota(100000);
        for (api.entries) |entry| {
            if (std.mem.eql(u8, entry.category, "Guides")) continue;
            var found = false;
            for (registrations) |reg| {
                if (std.mem.eql(u8, entry.name, reg.name)) { found = true; break; }
            }
            if (!found) @compileError("api.entries has '" ++ entry.name ++ "' but it is not registered");
        }
        for (registrations) |reg| {
            var found = false;
            for (api.entries) |entry| {
                if (std.mem.eql(u8, entry.name, reg.name)) { found = true; break; }
            }
            if (!found) @compileError("registration '" ++ reg.name ++ "' has no entry in api.entries");
        }
    }

    const user_path = resolve_user_path(wm);
    defer if (user_path) |p| wm.allocator.free(p);

    var pending_error: ?[]u8 = null;
    defer if (pending_error) |msg| wm.allocator.free(msg);

    const paths_to_try = [_]?[]const u8{ user_path, "/etc/duckwm/config.lua" };
    for (paths_to_try) |maybe_path| {
        const path = maybe_path orelse {
            std.debug.print("load: skipping null path\n", .{});
            continue;
        };
        std.debug.print("load: trying path '{s}'\n", .{path});
        const path_z = std.mem.concatWithSentinel(wm.allocator, u8, &[_][]const u8{path}, 0) catch continue;
        defer wm.allocator.free(path_z);

        lua.doFile(path_z) catch |err| {
            std.debug.print("load: doFile failed: {}\n", .{err});
            const lua_msg_raw = lua.toString(-1) catch null;
            const owned_msg: ?[]u8 = if (lua_msg_raw) |msg|
                wm.allocator.dupe(u8, msg) catch null
            else
                null;
            defer if (owned_msg) |m| wm.allocator.free(m);

            const is_missing = if (owned_msg) |msg|
                std.mem.indexOf(u8, msg, "No such file") != null or
                std.mem.indexOf(u8, msg, "cannot open") != null
            else
                err == error.FileNotFound;

            lua.pop(1);
            lua = reset_vm(wm) catch continue;

            if (is_missing) continue;

            if (pending_error == null)
                pending_error = std.fmt.allocPrint(wm.allocator, "{s}", .{owned_msg orelse @errorName(err)}) catch null;
            continue;
        };
         std.debug.print("load: doFile succeeded for '{s}'\n", .{path});

        // Loaded successfully
        if (pending_error) |msg| {
            wm.post_load_error = msg;
            pending_error = null;
        }
        // Watch user config dir for live reload (only if we loaded the user config)
        std.debug.print("load: successful path='{s}' user_path='{s}'\n", .{
            path,
            user_path orelse "(null)",
        });
        if (user_path != null and std.mem.eql(u8, path, user_path.?)) {
            watch_config(wm, path);
        } else {
            std.debug.print("load: skipping watch (loaded system config)\n", .{});
        }

        wm.reload_fn = reload;
        remap_all_graphs(wm, &wm.graph);
        return;
    }

    wm.post_load_error = pending_error
        orelse std.fmt.allocPrint(wm.allocator, "no config found at $XDG_CONFIG_HOME/duckwm/config.lua or /etc/duckwm/config.lua", .{}) catch null;
    pending_error = null;
}
