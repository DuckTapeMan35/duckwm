const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const wm_mod = @import("wm");
const WM = wm_mod.WM;
const graph_mod = @import("graph");
const Constraint = graph_mod.Constraint;
const c = @import("c").c;

var global_wm: *WM = undefined;

fn create_workspace_node(lua: *Lua, call_on_map: bool) !u32 {
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
        if (global_wm.on_map_ref != 0) {
            _ = lua.getIndexRaw(ziglua.registry_index, global_wm.on_map_ref);
            lua.pushInteger(@intCast(id));
            // previous focused node ID logic
            if (global_wm.focused) |prev_focused| {
                var in_current = false;
                for (global_wm.current_graph.nodes.items) |n| {
                    if (n == prev_focused) { in_current = true; break; }
                }
                if (in_current) {
                    var focused_id: ?u32 = null;
                    var it = global_wm.node_registry.iterator();
                    while (it.next()) |entry| {
                        if (entry.value_ptr.* == prev_focused) {
                            focused_id = entry.key_ptr.*;
                            break;
                        }
                    }
                    if (focused_id) |fid| lua.pushInteger(@intCast(fid)) else lua.pushNil();
                } else {
                    lua.pushNil();
                }
            } else {
                lua.pushNil();
            }
            lua.protectedCall(.{ .args = 2, .results = 0 }) catch return error.LuaError;
        }
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
    _ = c.XGrabButton(@ptrCast(global_wm.display), c.AnyButton, mod, global_wm.root, 0,
        c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
        c.GrabModeAsync, c.GrabModeAsync, c.None, c.None);
    return 0;
}

fn l_set_float_modifier(lua: *Lua) i32 {
    const mod: c_uint = @intCast(lua.checkInteger(1));
    if (global_wm.float_move_modifier) |old|
        _ = c.XUngrabButton(@ptrCast(global_wm.display), c.AnyButton, old, global_wm.root);
    global_wm.float_move_modifier = mod;
    _ = c.XGrabButton(@ptrCast(global_wm.display), c.AnyButton, mod, global_wm.root, 0,
        c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
        c.GrabModeAsync, c.GrabModeAsync, c.None, c.None);
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

fn l_on_map(lua: *Lua) i32 {
    lua.checkType(1, .function);
    lua.pushValue(1);
    const ref = lua.ref(ziglua.registry_index);
    global_wm.on_map_ref = ref;
    return 0;
}

fn l_on_unmap(lua: *Lua) i32 {
    lua.checkType(1, .function);
    lua.pushValue(1);
    const ref = lua.ref(ziglua.registry_index);
    global_wm.on_unmap_ref = ref;
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

    lua.pushFunction(ziglua.wrap(l_bind));                  lua.setField(-2, "bind");
    lua.pushFunction(ziglua.wrap(l_spawn));                 lua.setField(-2, "spawn");
    lua.pushFunction(ziglua.wrap(l_focus_left));            lua.setField(-2, "focus_left");
    lua.pushFunction(ziglua.wrap(l_focus_right));           lua.setField(-2, "focus_right");
    lua.pushFunction(ziglua.wrap(l_focus_up));              lua.setField(-2, "focus_up");
    lua.pushFunction(ziglua.wrap(l_focus_down));            lua.setField(-2, "focus_down");
    lua.pushFunction(ziglua.wrap(l_focus));                 lua.setField(-2, "focus");
    lua.pushFunction(ziglua.wrap(l_exchange_left));         lua.setField(-2, "exchange_left");
    lua.pushFunction(ziglua.wrap(l_exchange_right));        lua.setField(-2, "exchange_right");
    lua.pushFunction(ziglua.wrap(l_exchange_up));           lua.setField(-2, "exchange_up");
    lua.pushFunction(ziglua.wrap(l_exchange_down));         lua.setField(-2, "exchange_down");
    lua.pushFunction(ziglua.wrap(l_on_map));                lua.setField(-2, "on_map");
    lua.pushFunction(ziglua.wrap(l_on_unmap));              lua.setField(-2, "on_unmap");
    lua.pushFunction(ziglua.wrap(l_get_focused));           lua.setField(-2, "get_focused");
    lua.pushFunction(ziglua.wrap(l_remove_node));           lua.setField(-2, "remove_node");
    lua.pushFunction(ziglua.wrap(l_kill_client));           lua.setField(-2, "kill_client");
    lua.pushFunction(ziglua.wrap(l_get_node_info));         lua.setField(-2, "get_node_info");
    lua.pushFunction(ziglua.wrap(l_resize_edge));           lua.setField(-2, "resize_edge");
    lua.pushFunction(ziglua.wrap(l_resize_corner));         lua.setField(-2, "resize_corner");
    lua.pushFunction(ziglua.wrap(l_resize_focused_edge));   lua.setField(-2, "resize_focused_edge");
    lua.pushFunction(ziglua.wrap(l_resize_focused_corner)); lua.setField(-2, "resize_focused_corner");
    lua.pushFunction(ziglua.wrap(l_create_root_node));      lua.setField(-2, "create_root_node");
    lua.pushFunction(ziglua.wrap(l_left_of));               lua.setField(-2, "left_of");
    lua.pushFunction(ziglua.wrap(l_right_of));              lua.setField(-2, "right_of");
    lua.pushFunction(ziglua.wrap(l_above));                 lua.setField(-2, "above");
    lua.pushFunction(ziglua.wrap(l_below));                 lua.setField(-2, "below");
    lua.pushFunction(ziglua.wrap(l_align_left));            lua.setField(-2, "align_left");
    lua.pushFunction(ziglua.wrap(l_align_top));             lua.setField(-2, "align_top");
    lua.pushFunction(ziglua.wrap(l_align_right));           lua.setField(-2, "align_right");
    lua.pushFunction(ziglua.wrap(l_align_bottom));          lua.setField(-2, "align_bottom");
    lua.pushFunction(ziglua.wrap(l_equal_width));           lua.setField(-2, "equal_width");
    lua.pushFunction(ziglua.wrap(l_equal_height));          lua.setField(-2, "equal_height");
    lua.pushFunction(ziglua.wrap(l_fixed_ratio));           lua.setField(-2, "fixed_ratio");
    lua.pushFunction(ziglua.wrap(l_fixed_width));           lua.setField(-2, "fixed_width");
    lua.pushFunction(ziglua.wrap(l_fixed_height));          lua.setField(-2, "fixed_height");
    lua.pushFunction(ziglua.wrap(l_grid_cell));             lua.setField(-2, "grid_cell");
    lua.pushFunction(ziglua.wrap(l_get_all_windows));       lua.setField(-2, "get_all_windows");
    lua.pushFunction(ziglua.wrap(l_screen_width));          lua.setField(-2, "screen_width");
    lua.pushFunction(ziglua.wrap(l_screen_height));         lua.setField(-2, "screen_height");
    lua.pushFunction(ziglua.wrap(l_clear_constraints));     lua.setField(-2, "clear_constraints");
    lua.pushFunction(ziglua.wrap(l_set_node_empty));        lua.setField(-2, "set_node_empty");
    lua.pushFunction(ziglua.wrap(l_set_node_window));       lua.setField(-2, "set_node_window");
    lua.pushFunction(ziglua.wrap(l_get_node_type));         lua.setField(-2, "get_node_type");
    lua.pushFunction(ziglua.wrap(l_move_window_to_node));   lua.setField(-2, "move_window_to_node");
    lua.pushFunction(ziglua.wrap(l_set_resize_modifier));   lua.setField(-2, "set_resize_modifier");
    lua.pushFunction(ziglua.wrap(l_set_float_modifier));    lua.setField(-2, "set_float_modifier");
    lua.pushFunction(ziglua.wrap(l_toggle_floating));       lua.setField(-2, "toggle_floating");
    lua.pushFunction(ziglua.wrap(l_set_node_focused_border_color));   lua.setField(-2, "set_node_focused_border_color");
    lua.pushFunction(ziglua.wrap(l_set_node_unfocused_border_color)); lua.setField(-2, "set_node_unfocused_border_color");
    lua.pushFunction(ziglua.wrap(l_set_default_focus_border_color));   lua.setField(-2, "set_default_focus_border_color");
    lua.pushFunction(ziglua.wrap(l_set_default_unfocused_border_color)); lua.setField(-2, "set_default_unfocused_border_color");
    lua.pushFunction(ziglua.wrap(l_get_node_geometry));       lua.setField(-2, "get_node_geometry");
    lua.pushFunction(ziglua.wrap(l_set_border_width));        lua.setField(-2, "set_border_width");
    lua.pushFunction(ziglua.wrap(l_create_nested_workspace)); lua.setField(-2, "create_nested_workspace");
    lua.pushFunction(ziglua.wrap(l_enter_nested));           lua.setField(-2, "enter_nested");
    lua.pushFunction(ziglua.wrap(l_leave_nested));           lua.setField(-2, "leave_nested");
    lua.pushFunction(ziglua.wrap(l_switch_workspace));       lua.setField(-2, "switch_workspace");
    lua.pushFunction(ziglua.wrap(l_get_workspace));        lua.setField(-2, "get_workspace");
    lua.pushFunction(ziglua.wrap(l_create_empty_node)); lua.setField(-2, "create_empty_node");
    lua.pushFunction(ziglua.wrap(l_get_workspaces_at_level)); lua.setField(-2, "get_workspaces_at_level");
    lua.pushFunction(ziglua.wrap(l_enter_workspace_by_id));   lua.setField(-2, "enter_workspace_by_id");
    lua.pushFunction(ziglua.wrap(l_switch_to_workspace));   lua.setField(-2, "switch_to_workspace");
    lua.pushFunction(ziglua.wrap(l_create_container));  lua.setField(-2, "create_container");
    lua.pushFunction(ziglua.wrap(l_destroy_container)); lua.setField(-2, "destroy_container");
    lua.pushFunction(ziglua.wrap(l_reparent));          lua.setField(-2, "reparent");
    lua.pushFunction(ziglua.wrap(l_get_container_of));  lua.setField(-2, "get_container_of");
    lua.pushFunction(ziglua.wrap(l_set_on_remove_promote)); lua.setField(-2, "set_on_remove_promote");
    lua.pushFunction(ziglua.wrap(l_unregister_node)); lua.setField(-2, "unregister_node");
    lua.pushFunction(ziglua.wrap(l_get_cursor_pos));                  lua.setField(-2, "get_cursor_pos");
    lua.pushFunction(ziglua.wrap(l_get_cursor_relative_to_focused));  lua.setField(-2, "get_cursor_relative_to_focused");

    lua.setGlobal("wm");

    const home_ptr = c.getenv("HOME") orelse return error.NoHome;
    const home: []const u8 = std.mem.span(home_ptr);
    if (home.len == 0) return error.NoHome;
    const path = try std.fmt.allocPrint(wm.allocator, "{s}/.config/duckwm/config.lua", .{home});
    defer wm.allocator.free(path);
    const path_z = try std.mem.concatWithSentinel(wm.allocator, u8, &[_][]const u8{path}, 0);
    defer wm.allocator.free(path_z);

    try lua.doFile(path_z);
}
