const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const wm_mod = @import("wm");
const WM = wm_mod.WM;
const graph_mod = @import("graph");
const Constraint = graph_mod.Constraint;
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("stdlib.h");
});

var global_wm: *WM = undefined;

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
    global_wm.graph.remove_node(node);
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
    const node = global_wm.graph.add_node(.empty) catch return luaL_error_str(lua, "failed to create root node");
    const w = @as(u32, @intCast(c.XDisplayWidth(@ptrCast(global_wm.display), 0)));
    const h = @as(u32, @intCast(c.XDisplayHeight(@ptrCast(global_wm.display), 0)));
    node.width = w;
    node.height = h;
    node.x = 0;
    node.y = 0;
    lua.pushInteger(global_wm.register_node(0, node) catch return luaL_error_str(lua, "failed to register root node"));
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
    global_wm.graph.add_constraint(a, .{ .left_of = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_right_of(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .right_of = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_above(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .above = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_below(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .below = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_left(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .align_left = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_top(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .align_top = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_right(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .align_right = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_align_bottom(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .align_bottom = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_equal_width(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .equal_width = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_equal_height(lua: *Lua) i32 {
    const a_id = @as(u32, @intCast(lua.checkInteger(1)));
    const b_id = @as(u32, @intCast(lua.checkInteger(2)));
    const a = global_wm.get_node_by_id(a_id) orelse return luaL_error_str(lua, "invalid node a");
    const b = global_wm.get_node_by_id(b_id) orelse return luaL_error_str(lua, "invalid node b");
    global_wm.graph.add_constraint(a, .{ .equal_height = b }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_fixed_ratio(lua: *Lua) i32 {
    const id = @as(u32, @intCast(lua.checkInteger(1)));
    const ratio = lua.checkNumber(2);
    const node = global_wm.get_node_by_id(id) orelse return luaL_error_str(lua, "invalid node");
    global_wm.graph.add_constraint(node, .{ .fixed_ratio = @floatCast(ratio) }) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_grid_cell(lua: *Lua) i32 {
    const id           = @as(u32, @intCast(lua.checkInteger(1)));
    const col          = lua.checkInteger(2);
    const row          = lua.checkInteger(3);
    const cols         = lua.checkInteger(4);
    const rows         = lua.checkInteger(5);
    const container_id = @as(u32, @intCast(lua.checkInteger(6)));
    const node      = global_wm.get_node_by_id(id)           orelse return luaL_error_str(lua, "invalid node");
    const container = global_wm.get_node_by_id(container_id) orelse return luaL_error_str(lua, "invalid container");
    const g = Constraint{ .grid_cell = .{
        .col = @intCast(col),
        .row = @intCast(row),
        .cols = @intCast(cols),
        .rows = @intCast(rows),
        .container = container,
    } };
    global_wm.graph.add_constraint(node, g) catch return luaL_error_str(lua, "out of memory");
    return 0;
}

fn l_set_geometry(lua: *Lua) i32 {
    const id     = @as(u32, @intCast(lua.checkInteger(1)));
    const x      = @as(i32, @intCast(lua.checkInteger(2)));
    const y      = @as(i32, @intCast(lua.checkInteger(3)));
    const width  = @as(u32, @intCast(lua.checkInteger(4)));
    const height = @as(u32, @intCast(lua.checkInteger(5)));
    const node = global_wm.get_node_by_id(id) orelse return luaL_error_str(lua, "invalid node");
    node.x = x;
    node.y = y;
    node.width = width;
    node.height = height;
    return 0;
}

fn l_get_all_windows(lua: *Lua) i32 {
    lua.newTable();
    var i: usize = 0;
    for (global_wm.graph.nodes.items) |node| {
        if (node.content == .window) {
            var it = global_wm.window_to_node_id.iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.* == node.content.window) {
                    lua.pushInteger(@intCast(entry.value_ptr.*));
                    lua.setIndexRaw(-2, @intCast(i + 1));
                    i += 1;
                    break;
                }
            }
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
    lua.pushFunction(ziglua.wrap(l_grid_cell));             lua.setField(-2, "grid_cell");
    lua.pushFunction(ziglua.wrap(l_set_geometry));          lua.setField(-2, "set_geometry");
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
