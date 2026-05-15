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

const registrations = [_]Registration{
    .{ .func = ziglua.wrap(l_bind),                              .name = "bind" },
    .{ .func = ziglua.wrap(l_spawn),                             .name = "spawn" },
    .{ .func = ziglua.wrap(l_set_default_arranger),              .name = "set_default_arranger" },
    .{ .func = ziglua.wrap(l_register_arranger),                 .name = "register_arranger" },
    .{ .func = ziglua.wrap(l_focus_left),                        .name = "focus_left" },
    .{ .func = ziglua.wrap(l_focus_right),                       .name = "focus_right" },
    .{ .func = ziglua.wrap(l_focus_up),                          .name = "focus_up" },
    .{ .func = ziglua.wrap(l_focus_down),                        .name = "focus_down" },
    .{ .func = ziglua.wrap(l_focus),                             .name = "focus" },
    .{ .func = ziglua.wrap(l_exchange_left),                     .name = "exchange_left" },
    .{ .func = ziglua.wrap(l_exchange_right),                    .name = "exchange_right" },
    .{ .func = ziglua.wrap(l_exchange_up),                       .name = "exchange_up" },
    .{ .func = ziglua.wrap(l_exchange_down),                     .name = "exchange_down" },
    .{ .func = ziglua.wrap(l_get_focused),                       .name = "get_focused" },
    .{ .func = ziglua.wrap(l_remove_node),                       .name = "remove_node" },
    .{ .func = ziglua.wrap(l_kill_client),                       .name = "kill_client" },
    .{ .func = ziglua.wrap(l_get_node_info),                     .name = "get_node_info" },
    .{ .func = ziglua.wrap(l_resize_edge),                       .name = "resize_edge" },
    .{ .func = ziglua.wrap(l_resize_corner),                     .name = "resize_corner" },
    .{ .func = ziglua.wrap(l_resize_focused_edge),               .name = "resize_focused_edge" },
    .{ .func = ziglua.wrap(l_resize_focused_corner),             .name = "resize_focused_corner" },
    .{ .func = ziglua.wrap(l_create_root_node),                  .name = "create_root_node" },
    .{ .func = ziglua.wrap(l_left_of),                           .name = "left_of" },
    .{ .func = ziglua.wrap(l_right_of),                          .name = "right_of" },
    .{ .func = ziglua.wrap(l_above),                             .name = "above" },
    .{ .func = ziglua.wrap(l_below),                             .name = "below" },
    .{ .func = ziglua.wrap(l_align_left),                        .name = "align_left" },
    .{ .func = ziglua.wrap(l_align_top),                         .name = "align_top" },
    .{ .func = ziglua.wrap(l_align_right),                       .name = "align_right" },
    .{ .func = ziglua.wrap(l_align_bottom),                      .name = "align_bottom" },
    .{ .func = ziglua.wrap(l_equal_width),                       .name = "equal_width" },
    .{ .func = ziglua.wrap(l_equal_height),                      .name = "equal_height" },
    .{ .func = ziglua.wrap(l_fixed_ratio),                       .name = "fixed_ratio" },
    .{ .func = ziglua.wrap(l_fixed_width),                       .name = "fixed_width" },
    .{ .func = ziglua.wrap(l_fixed_height),                      .name = "fixed_height" },
    .{ .func = ziglua.wrap(l_fixed_x),                           .name = "fixed_x" },
    .{ .func = ziglua.wrap(l_fixed_y),                           .name = "fixed_y" },
    .{ .func = ziglua.wrap(l_grid_cell),                         .name = "grid_cell" },
    .{ .func = ziglua.wrap(l_grid_cell_abs),                     .name = "grid_cell_abs" },
    .{ .func = ziglua.wrap(l_get_all_windows),                   .name = "get_all_windows" },
    .{ .func = ziglua.wrap(l_screen_width),                      .name = "screen_width" },
    .{ .func = ziglua.wrap(l_screen_height),                     .name = "screen_height" },
    .{ .func = ziglua.wrap(l_clear_constraints),                 .name = "clear_constraints" },
    .{ .func = ziglua.wrap(l_set_node_empty),                    .name = "set_node_empty" },
    .{ .func = ziglua.wrap(l_set_node_window),                   .name = "set_node_window" },
    .{ .func = ziglua.wrap(l_get_node_type),                     .name = "get_node_type" },
    .{ .func = ziglua.wrap(l_move_window_to_node),               .name = "move_window_to_node" },
    .{ .func = ziglua.wrap(l_set_resize_modifier),               .name = "set_resize_modifier" },
    .{ .func = ziglua.wrap(l_set_float_modifier),                .name = "set_float_modifier" },
    .{ .func = ziglua.wrap(l_toggle_floating),                   .name = "toggle_floating" },
    .{ .func = ziglua.wrap(l_set_node_focused_border_color),     .name = "set_node_focused_border_color" },
    .{ .func = ziglua.wrap(l_set_node_unfocused_border_color),   .name = "set_node_unfocused_border_color" },
    .{ .func = ziglua.wrap(l_set_default_focus_border_color),    .name = "set_default_focus_border_color" },
    .{ .func = ziglua.wrap(l_set_default_unfocused_border_color),.name = "set_default_unfocused_border_color" },
    .{ .func = ziglua.wrap(l_get_node_geometry),                 .name = "get_node_geometry" },
    .{ .func = ziglua.wrap(l_set_border_width),                  .name = "set_border_width" },
    .{ .func = ziglua.wrap(l_create_nested_workspace),           .name = "create_nested_workspace" },
    .{ .func = ziglua.wrap(l_enter_nested),                      .name = "enter_nested" },
    .{ .func = ziglua.wrap(l_leave_nested),                      .name = "leave_nested" },
    .{ .func = ziglua.wrap(l_switch_workspace),                  .name = "switch_workspace" },
    .{ .func = ziglua.wrap(l_get_workspace),                     .name = "get_workspace" },
    .{ .func = ziglua.wrap(l_create_empty_node),                 .name = "create_empty_node" },
    .{ .func = ziglua.wrap(l_get_workspaces_at_level),           .name = "get_workspaces_at_level" },
    .{ .func = ziglua.wrap(l_enter_workspace_by_id),             .name = "enter_workspace_by_id" },
    .{ .func = ziglua.wrap(l_switch_to_workspace),               .name = "switch_to_workspace" },
    .{ .func = ziglua.wrap(l_create_container),                  .name = "create_container" },
    .{ .func = ziglua.wrap(l_destroy_container),                 .name = "destroy_container" },
    .{ .func = ziglua.wrap(l_reparent),                          .name = "reparent" },
    .{ .func = ziglua.wrap(l_get_container_of),                  .name = "get_container_of" },
    .{ .func = ziglua.wrap(l_set_on_remove_promote),             .name = "set_on_remove_promote" },
    .{ .func = ziglua.wrap(l_unregister_node),                   .name = "unregister_node" },
    .{ .func = ziglua.wrap(l_get_cursor_pos),                    .name = "get_cursor_pos" },
    .{ .func = ziglua.wrap(l_get_cursor_relative_to_focused),    .name = "get_cursor_relative_to_focused" },
};


fn create_workspace_node(_: *Lua, call_on_map: bool) !u32 {
    const sub = global_wm.allocator.create(graph_mod.Graph) catch return error.OutOfMemory;
    sub.* = graph_mod.Graph.init(global_wm.allocator);

    const pw = c.XCreateSimpleWindow(
        global_wm.display, global_wm.root,
        0, 0, 200, 150, 0, 0, 0x4488ff
    );
    var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
    wa.override_redirect = 1;
    _ = c.XChangeWindowAttributes(global_wm.display, pw, c.CWOverrideRedirect, &wa);

    const node = global_wm.current_graph.add_node(.{ .workspace = sub }) catch return error.OutOfMemory;
    sub.parent_node = node;
    node.preview_window = pw;
    node.floating = false;

    global_wm.frame(pw, node) catch return error.OutOfMemory;
    _ = c.XMapWindow(global_wm.display, pw);
    _ = c.XSelectInput(global_wm.display, pw, c.ButtonPressMask | c.ButtonReleaseMask);

    const id = global_wm.register_node(pw, node) catch return error.OutOfMemory;

    if (call_on_map) {
        // Resolve prev focused id in the current graph
        var prev_id: ?u32 = null;
        if (global_wm.focused) |prev_focused| {
            var in_current = false;
            for (global_wm.current_graph.nodes.items) |n| {
                if (n == prev_focused) { in_current = true; break; }
            }
            if (in_current) {
                var it = global_wm.node_registry.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == prev_focused) { prev_id = entry.key_ptr.*; break; }
                }
            }
        }
        global_wm.call_arranger(global_wm.current_graph, "map", id, prev_id);
    }

    global_wm.resolve(global_wm.current_graph) catch return error.OutOfMemory;
    global_wm.rebuild_focus_edges() catch {};
    global_wm.flush(global_wm.current_graph) catch {};

    return id;
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
    const id: u32 = @intCast(lua.toInteger(1) catch return 0);
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
    return 0;
}

fn l_register_arranger(lua: *Lua) i32 {
    const workspace_id: u32 = @intCast(lua.checkInteger(1));
    lua.checkType(2, .function);
    const node = global_wm.get_node_by_id(workspace_id) orelse {
        _ = lua.pushString("register_arranger: invalid workspace id");
        return lua.raiseError();
    };
    if (node.content != .workspace) {
        _ = lua.pushString("register_arranger: node is not a workspace");
        return lua.raiseError();
    }
    lua.pushValue(2);
    node.content.workspace.arranger_ref = lua.ref(ziglua.registry_index);
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
    const id: u32 = @intCast(lua.checkInteger(1));
    const dir_str = lua.checkString(2);
    const delta: i32 = @intCast(lua.checkInteger(3));
    const node = global_wm.get_node_by_id(id) orelse {
        _ = lua.pushString("invalid node id");
        return lua.raiseError();
    };
    const dir: graph_mod.Direction = if (std.mem.eql(u8, dir_str, "left")) .Left
        else if (std.mem.eql(u8, dir_str, "right")) .Right
        else if (std.mem.eql(u8, dir_str, "up")) .Up
        else if (std.mem.eql(u8, dir_str, "down")) .Down
        else {
            _ = lua.pushString("direction must be left/right/up/down");
            return lua.raiseError();
        };
    global_wm.resize_edge(node, dir, delta) catch {
        _ = lua.pushString("resize failed (size limit)");
        return lua.raiseError();
    };
    return 0;
}

fn l_resize_corner(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const delta_x: i32 = @intCast(lua.checkInteger(2));
    const delta_y: i32 = @intCast(lua.checkInteger(3));
    const node = global_wm.get_node_by_id(id) orelse {
        _ = lua.pushString("invalid node id");
        return lua.raiseError();
    };
    global_wm.resize_corner(node, delta_x, delta_y) catch {
        _ = lua.pushString("resize corner failed");
        return lua.raiseError();
    };
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
    const id: u32 = @intCast(lua.checkInteger(1));
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
    const id: u32 = @intCast(lua.checkInteger(1));
    const node = global_wm.get_node_by_id(id) orelse {
        _ = lua.pushString("wm.get_node_info: invalid node id");
        return lua.raiseError();
    };
    lua.newTable();
    lua.pushInteger(node.x);      lua.setField(-2, "x");
    lua.pushInteger(node.y);      lua.setField(-2, "y");
    lua.pushInteger(node.width);  lua.setField(-2, "width");
    lua.pushInteger(node.height); lua.setField(-2, "height");
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
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .left_of = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_right_of(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .right_of = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_above(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .above = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_below(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .below = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_left(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .align_left = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_top(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .align_top = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_right(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .align_right = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_bottom(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .align_bottom = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_equal_width(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .equal_width = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_equal_height(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.current_graph.add_constraint(a, .{ .equal_height = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_fixed_ratio(lua: *Lua) i32 {
    const id = @as(u32, @intCast(lua.checkInteger(1)));
    const ratio = lua.checkNumber(2);
    const node = global_wm.get_node_by_id(id) orelse return luaL_error_str(lua, "invalid node");
    global_wm.current_graph.add_constraint(node, .{ .fixed_ratio = @floatCast(ratio) }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_fixed_width(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const w:  u32 = @intCast(lua.checkInteger(2));
    const node = global_wm.get_node_by_id(id) orelse return 0;
    global_wm.current_graph.add_constraint(node, .{ .fixed_width = w }) catch {};
    return 0;
}

fn l_fixed_height(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const h:  u32 = @intCast(lua.checkInteger(2));
    const node = global_wm.get_node_by_id(id) orelse return 0;
    global_wm.current_graph.add_constraint(node, .{ .fixed_height = h }) catch {};
    return 0;
}

fn l_fixed_x(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const x: i32  = @intCast(lua.checkInteger(2));
    const node = global_wm.get_node_by_id(id) orelse return 0;
    global_wm.current_graph.add_constraint(node, .{ .fixed_x = x }) catch {};
    return 0;
}

fn l_fixed_y(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const y: i32  = @intCast(lua.checkInteger(2));
    const node = global_wm.get_node_by_id(id) orelse return 0;
    global_wm.current_graph.add_constraint(node, .{ .fixed_y = y }) catch {};
    return 0;
}

fn l_grid_cell(lua: *Lua) i32 {
    const id           = @as(u32, @intCast(lua.checkInteger(1)));
    const col          = lua.checkInteger(2);
    const row          = lua.checkInteger(3);
    const cols         = lua.checkInteger(4);
    const rows         = lua.checkInteger(5);
    const container_id = @as(u32, @intCast(lua.checkInteger(6)));
    // Validate grid parameters
    if (cols <= 0 or rows <= 0) {
        _ = lua.pushString("grid_cell: cols and rows must be positive");
        return lua.raiseError();
    }
    if (col < 0 or row < 0 or col >= cols or row >= rows) {
        _ = lua.pushString("grid_cell: cell (col,row) out of range");
        return lua.raiseError();
    }
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
    const id           = @as(u32, @intCast(lua.checkInteger(1)));
    const x            = @as(i32, @intCast(lua.checkInteger(2)));
    const y            = @as(i32, @intCast(lua.checkInteger(3)));
    const w            = @as(u32, @intCast(lua.checkInteger(4)));
    const h            = @as(u32, @intCast(lua.checkInteger(5)));
    const container_id = @as(u32, @intCast(lua.checkInteger(6)));
    const node      = global_wm.get_node_by_id(id)           orelse return luaL_error_str(lua, "invalid node");
    const container = global_wm.get_node_by_id(container_id) orelse return luaL_error_str(lua, "invalid container");
    global_wm.current_graph.add_constraint(node, .{ .grid_cell_abs = .{
        .x = x, .y = y, .w = w, .h = h, .container = container,
    }}) catch return luaL_error_str(lua, "out of memory");
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
    const id: u32 = @intCast(lua.checkInteger(1));
    const node = global_wm.get_node_by_id(id) orelse return 0;
    // Containers are .empty content — no X window to clean up
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
    const child_id = @as(u32, @intCast(lua.checkInteger(1)));
    const parent_id = @as(u32, @intCast(lua.checkInteger(2)));

    const child = global_wm.get_node_by_id(child_id) orelse
        return luaL_error_str(lua, "invalid child node");
    const parent = global_wm.get_node_by_id(parent_id) orelse
        return luaL_error_str(lua, "invalid parent node");

    // Remove any existing grid_cell constraint from the child
    var i: usize = 0;
    while (i < child.constraints.items.len) {
        if (child.constraints.items[i] == .grid_cell) {
            _ = child.constraints.swapRemove(i);
        } else {
            i += 1;
        }
    }

    // Add a new constraint that makes the child fill the entire parent
    const g = Constraint{ .grid_cell = .{
        .col = 0,
        .row = 0,
        .cols = 1,
        .rows = 1,
        .container = parent,
    } };
    global_wm.current_graph.add_constraint(child, g) catch
        return luaL_error_str(lua, "out of memory");

    return 0;
}

fn l_get_container_of(lua: *Lua) i32 {
    const child_id = @as(u32, @intCast(lua.checkInteger(1)));
    const child = global_wm.get_node_by_id(child_id) orelse
        return luaL_error_str(lua, "invalid node");
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
    const id = @as(u32, @intCast(lua.checkInteger(1)));
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
    const id: u32 = @intCast(lua.checkInteger(1));
    const node = global_wm.get_node_by_id(id) orelse return 0;
    node.constraints.clearRetainingCapacity();
    return 0;
}

fn l_set_node_empty(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    global_wm.set_node_empty(id);
    return 0;
}

fn l_set_node_window(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const win: c.Window = @intCast(lua.checkInteger(2));
    global_wm.set_node_window(id, win) catch {
        _ = lua.pushString("failed to set node window");
        return lua.raiseError();
    };
    return 0;
}

fn l_get_node_type(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
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
    const src_id: u32 = @intCast(lua.checkInteger(1));
    const dst_id: u32 = @intCast(lua.checkInteger(2));
    global_wm.move_window_to_node(src_id, dst_id) catch {
        _ = lua.pushString("move_window_to_node failed");
        return lua.raiseError();
    };
    return 0;
}

fn l_toggle_floating(lua: *Lua) i32 {
    global_wm.toggle_floating() catch {
        _ = lua.pushString("failed to toggle floating");
        return lua.raiseError();
    };
    return 0;
}

fn l_set_node_focused_border_color(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const color: u32 = @intCast(lua.checkInteger(2));
    if (global_wm.get_node_by_id(id)) |node| {
        node.border_color_focused = color;
        return 0;
    }
    _ = lua.pushString("invalid node id");
    return lua.raiseError();
}

fn l_set_node_unfocused_border_color(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const color: u32 = @intCast(lua.checkInteger(2));
    if (global_wm.get_node_by_id(id)) |node| {
        node.border_color_unfocused = color;
        return 0;
    }
    _ = lua.pushString("invalid node id");
    return lua.raiseError();
}

fn l_set_default_focus_border_color(lua: *Lua) i32 {
    const color: u32 = @intCast(lua.checkInteger(1));
    global_wm.default_border_color_focused = color;
    return 0;
}

fn l_set_default_unfocused_border_color(lua: *Lua) i32 {
    const color: u32 = @intCast(lua.checkInteger(1));
    global_wm.default_border_color_unfocused = color;
    return 0;
}

fn l_set_border_width(lua: *Lua) i32 {
    const width: i32 = @intCast(lua.checkInteger(1));
    global_wm.border_width = width;
    return 0;
}

fn l_create_nested_workspace(lua: *Lua) i32 {
    const id = create_workspace_node(lua, true) catch return luaL_error_str(lua, "create failed");
    lua.pushInteger(@intCast(id));
    return 1;
}

fn l_get_workspace(lua: *Lua) i32 {
    const index: usize = @intCast(lua.checkInteger(1));
    var workspaces: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0};
    defer workspaces.deinit(global_wm.allocator);

    for (global_wm.current_graph.nodes.items) |node| {
        if (node.content == .workspace) {
            workspaces.append(global_wm.allocator, node) catch {
                _ = lua.pushString("wm.get_workspace: out of memory");
                return lua.raiseError();
            };
        }
    }

    // Sort by node ID (creation order)
    std.sort.heap(*graph_mod.Node, workspaces.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    if (index < 1 or index > workspaces.items.len) {
        lua.pushNil();
    } else {
        const node = workspaces.items[index - 1];
        const id = global_wm.get_id_for_node(node) orelse {
            lua.pushNil();
            return 1;
        };
        lua.pushInteger(@intCast(id));
    }
    return 1;
}

fn l_get_workspaces_at_level(lua: *Lua) i32 {
    // Determine the graph that contains the workspace nodes we can switch to.
    // If we are inside a nested workspace, use its parent graph;
    // otherwise use the current (top‑level) graph itself.
    const parent_graph: *graph_mod.Graph = if (global_wm.current_graph.parent_node) |pn|
        pn.owner_graph orelse global_wm.current_graph
    else
        global_wm.current_graph;

    // Collect workspace nodes in that graph
    var list: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0};
    defer list.deinit(global_wm.allocator);

    for (parent_graph.nodes.items) |node| {
        if (node.content == .workspace) {
            list.append(global_wm.allocator, node) catch {
                _ = lua.pushString("out of memory");
                return lua.raiseError();
            };
        }
    }

    // Sort by node ID (creation order)
    std.sort.heap(*graph_mod.Node, list.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    lua.newTable();
    for (list.items, 0..) |node, i| {
        if (global_wm.get_id_for_node(node)) |nid| {
            lua.pushInteger(@intCast(nid));
            lua.setIndexRaw(-2, @intCast(i + 1));
        }
    }
    return 1;
}

fn l_switch_to_workspace(lua: *Lua) i32 {
    const index: usize = @intCast(lua.checkInteger(1));
    if (index < 1) return 0;

    // If we are inside a nested workspace, go back to its parent first.
    if (global_wm.current_graph.parent_node != null) {
        global_wm.leave_workspace() catch {
            _ = lua.pushString("failed to leave workspace");
            return lua.raiseError();
        };
    }

    const graph = global_wm.current_graph;

    // Collect existing workspace nodes, sorted by creation ID.
    var list: std.ArrayListUnmanaged(*graph_mod.Node) = .{ .items = &.{}, .capacity = 0 };
    defer list.deinit(global_wm.allocator);
    for (graph.nodes.items) |node| {
        if (node.content == .workspace) {
            list.append(global_wm.allocator, node) catch {
                _ = lua.pushString("out of memory");
                return lua.raiseError();
            };
        }
    }
    std.sort.heap(*graph_mod.Node, list.items, {}, struct {
        fn lt(_: void, a: *graph_mod.Node, b: *graph_mod.Node) bool {
            const id_a = global_wm.get_id_for_node(a) orelse return false;
            const id_b = global_wm.get_id_for_node(b) orelse return false;
            return id_a < id_b;
        }
    }.lt);

    // If the workspace already exists, switch to it.
    if (index <= list.items.len) {
        const target = list.items[index - 1];
        global_wm.enter_workspace(target) catch {
            _ = lua.pushString("enter_workspace failed");
            return lua.raiseError();
        };
        return 0;
    }

    // Create missing workspace nodes up to the requested index.
    var last_id: u32 = 0;
    const needed = index - list.items.len;
    for (0..needed) |_| {
        const new_id = create_workspace_node(lua, true) catch {
            _ = lua.pushString("failed to create workspace");
            return lua.raiseError();
        };
        last_id = new_id;
    }

    // Enter the newly created workspace.
    const target_node = global_wm.get_node_by_id(last_id) orelse {
        _ = lua.pushString("internal error: newly created workspace not found");
        return lua.raiseError();
    };
    global_wm.enter_workspace(target_node) catch {
        _ = lua.pushString("enter_workspace failed");
        return lua.raiseError();
    };
    return 0;
}

fn l_enter_workspace_by_id(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const node = global_wm.get_node_by_id(id) orelse {
        _ = lua.pushString("invalid workspace id");
        return lua.raiseError();
    };
    if (node.content != .workspace) {
        _ = lua.pushString("node is not a workspace");
        return lua.raiseError();
    }
    global_wm.enter_workspace(node) catch {
        _ = lua.pushString("enter_workspace failed");
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

fn l_switch_workspace(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const node = global_wm.get_node_by_id(id) orelse return luaL_error_str(lua, "invalid node");
    if (node.content != .workspace) return luaL_error_str(lua, "not a workspace");
    global_wm.enter_workspace(node) catch return luaL_error_str(lua, "enter failed");
    return 0;
}

fn l_set_on_remove_promote(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    const node = global_wm.get_node_by_id(id) orelse {
        std.debug.print("set_on_remove_promote: id {} NOT FOUND\n", .{id});
        return 0;
    };
    node.on_remove = .promote;
    std.debug.print("set_on_remove_promote: id {} set OK, content={s}\n", .{id, @tagName(node.content)});
    return 0;
}

fn l_unregister_node(lua: *Lua) i32 {
    const id: u32 = @intCast(lua.checkInteger(1));
    _ = global_wm.node_registry.remove(id);
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

fn luaL_error_str(lua: *Lua, msg: []const u8) noreturn {
    _ = lua.pushString(msg);
    lua.raiseError();
}

pub fn load(wm: *WM) !void {
    global_wm = wm;

    var lua = try Lua.init(wm.allocator);
    wm.lua = lua;

    lua.openLibs();
    lua.newTable();

    lua.pushInteger(c.Mod4Mask);    lua.setField(-2, "MOD_SUPER");
    lua.pushInteger(c.Mod1Mask);    lua.setField(-2, "MOD_ALT");
    lua.pushInteger(c.ShiftMask);   lua.setField(-2, "MOD_SHIFT");
    lua.pushInteger(c.ControlMask); lua.setField(-2, "MOD_CTRL");

    comptime {
        @setEvalBranchQuota(100000);
        for (api.entries) |entry| {
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

    for (registrations) |reg| {
        lua.pushFunction(reg.func);
        lua.setField(-2, reg.name);
    }

    lua.setGlobal("wm");

    const user_path: ?[]const u8 = blk: {
        if (c.getenv("XDG_CONFIG_HOME")) |xdg| {
            const base: []const u8 = std.mem.span(xdg);
            if (base.len > 0) {
                break :blk std.fmt.allocPrint(wm.allocator, "{s}/duckwm/config.lua", .{base}) catch null;
            }
        }
        if (c.getenv("HOME")) |home_ptr| {
            const home: []const u8 = std.mem.span(home_ptr);
            if (home.len > 0) {
                break :blk std.fmt.allocPrint(wm.allocator, "{s}/.config/duckwm/config.lua", .{home}) catch null;
            }
        }
        break :blk null;
    };
    defer if (user_path) |p| wm.allocator.free(p);

    // pending_error is transferred to wm.post_load_error on failure;
    // if not transferred it is freed by this defer.
    var pending_error: ?[]u8 = null;
    defer if (pending_error) |msg| wm.allocator.free(msg);

    const paths_to_try = [_]?[]const u8{ user_path, "/etc/duckwm/config.lua" };
    for (paths_to_try) |maybe_path| {
        const path = maybe_path orelse continue;
        const path_z = std.mem.concatWithSentinel(wm.allocator, u8, &[_][]const u8{path}, 0) catch continue;
        defer wm.allocator.free(path_z);

        lua.doFile(path_z) catch |err| {
            // Copy the error message out of Lua's memory before we potentially reset the VM
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

            // Tear down the broken VM and start fresh
            lua.deinit();
            lua = try Lua.init(wm.allocator);
            wm.lua = lua;
            lua.openLibs();
            lua.newTable();
            lua.pushInteger(c.Mod4Mask);    lua.setField(-2, "MOD_SUPER");
            lua.pushInteger(c.Mod1Mask);    lua.setField(-2, "MOD_ALT");
            lua.pushInteger(c.ShiftMask);   lua.setField(-2, "MOD_SHIFT");
            lua.pushInteger(c.ControlMask); lua.setField(-2, "MOD_CTRL");
            for (registrations) |reg| {
                lua.pushFunction(reg.func);
                lua.setField(-2, reg.name);
            }
            lua.setGlobal("wm");

            wm.ungrab_keys();
            wm.keybinds.clearRetainingCapacity();
            wm.default_arranger_ref = 0;
            wm.reset_arranger_refs(&wm.graph);

            if (is_missing) continue;

            if (pending_error == null) {
                pending_error = std.fmt.allocPrint(wm.allocator, "{s}", .{owned_msg orelse @errorName(err)}) catch null;
            }
            continue;
        };
        // Loaded successfully — transfer any pending error to wm for deferred notification
        if (pending_error) |msg| {
            wm.post_load_error = msg;
            pending_error = null; // prevent defer from freeing it
        }
        return;
    }

    // No config loaded at all
    wm.post_load_error = pending_error
        orelse std.fmt.allocPrint(wm.allocator, "no config found at $XDG_CONFIG_HOME/duckwm/config.lua or /etc/duckwm/config.lua", .{}) catch null;
    pending_error = null;
}
