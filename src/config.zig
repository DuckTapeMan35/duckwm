const std = @import("std");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const wm_mod = @import("wm");
const WM = wm_mod.WM;
const graph_mod = @import("graph");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("stdlib.h");
});

var global_wm: *WM = undefined;

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
    const len = lua.rawLen(1);
    var args = global_wm.allocator.alloc([]const u8, len) catch {
        _ = lua.pushString("wm.spawn: out of memory");
        return lua.raiseError();
    };
    defer global_wm.allocator.free(args);
    for (0..len) |i| {
        _ = lua.rawGetIndex(1, @intCast(i + 1));
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
        _ = lua.pushString("resize failed (no neighbour or size limit)");
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

fn l_add_edge(lua: *Lua) i32 {
    const a_id: u32 = @intCast(lua.checkInteger(1));
    const b_id: u32 = @intCast(lua.checkInteger(2));
    const dir = lua.checkString(3);
    const weight: f32 = @floatCast(lua.checkNumber(4));

    const a = global_wm.get_node_by_id(a_id) orelse {
        _ = lua.pushString("wm.add_edge: invalid node id for a");
        return lua.raiseError();
    };
    const b = global_wm.get_node_by_id(b_id) orelse {
        _ = lua.pushString("wm.add_edge: invalid node id for b");
        return lua.raiseError();
    };

    if (std.mem.eql(u8, dir, "right")) {
        a.right = b;
        b.left = a;
        a.split_h = .{ .weighted = weight };
    } else if (std.mem.eql(u8, dir, "left")) {
        b.right = a;
        a.left = b;
        b.split_h = .{ .weighted = weight };
    } else if (std.mem.eql(u8, dir, "down")) {
        a.down = b;
        b.up = a;
        a.split_v = .{ .weighted = weight };
    } else if (std.mem.eql(u8, dir, "up")) {
        b.down = a;
        a.up = b;
        b.split_v = .{ .weighted = weight };
    } else {
        _ = lua.pushString("wm.add_edge: direction must be 'left', 'right', 'up', or 'down'");
        return lua.raiseError();
    }

    return 0;
}

fn l_insert_right(lua: *Lua) i32 {
    const anchor_id: u32 = @intCast(lua.checkInteger(1));
    const new_id: u32 = @intCast(lua.checkInteger(2));

    const anchor = global_wm.get_node_by_id(anchor_id) orelse {
        _ = lua.pushString("wm.insert_right: invalid anchor id");
        return lua.raiseError();
    };
    const new = global_wm.get_node_by_id(new_id) orelse {
        _ = lua.pushString("wm.insert_right: invalid new id");
        return lua.raiseError();
    };

    const old_right = anchor.right; // B (may be null)
    anchor.right = new;
    anchor.split_h = .{ .weighted = 0.5 };
    new.left = anchor;
    new.right = old_right;
    if (old_right) |b| b.left = new;

    return 0;
}

fn l_insert_left(lua: *Lua) i32 {
    const anchor_id: u32 = @intCast(lua.checkInteger(1));
    const new_id: u32 = @intCast(lua.checkInteger(2));

    const anchor = global_wm.get_node_by_id(anchor_id) orelse {
        _ = lua.pushString("wm.insert_left: invalid anchor id");
        return lua.raiseError();
    };
    const new = global_wm.get_node_by_id(new_id) orelse {
        _ = lua.pushString("wm.insert_left: invalid new id");
        return lua.raiseError();
    };

    const old_left = anchor.left; // B (may be null)
    anchor.left = new;
    new.right = anchor;
    new.left = old_left;
    new.split_h = .{ .weighted = 0.5 };
    if (old_left) |b| b.right = new;

    return 0;
}

fn l_insert_below(lua: *Lua) i32 {
    const anchor_id: u32 = @intCast(lua.checkInteger(1));
    const new_id: u32 = @intCast(lua.checkInteger(2));

    const anchor = global_wm.get_node_by_id(anchor_id) orelse {
        _ = lua.pushString("wm.insert_below: invalid anchor id");
        return lua.raiseError();
    };
    const new = global_wm.get_node_by_id(new_id) orelse {
        _ = lua.pushString("wm.insert_below: invalid new id");
        return lua.raiseError();
    };

    const old_down = anchor.down;
    anchor.down = new;
    anchor.split_v = .{ .weighted = 0.5 };
    new.up = anchor;
    new.down = old_down;
    if (old_down) |b| b.up = new;

    return 0;
}

fn l_insert_above(lua: *Lua) i32 {
    const anchor_id: u32 = @intCast(lua.checkInteger(1));
    const new_id: u32 = @intCast(lua.checkInteger(2));

    const anchor = global_wm.get_node_by_id(anchor_id) orelse {
        _ = lua.pushString("wm.insert_above: invalid anchor id");
        return lua.raiseError();
    };
    const new = global_wm.get_node_by_id(new_id) orelse {
        _ = lua.pushString("wm.insert_above: invalid new id");
        return lua.raiseError();
    };

    const old_up = anchor.up;
    anchor.up = new;
    new.down = anchor;
    new.up = old_up;
    new.split_v = .{ .weighted = 0.5 };
    if (old_up) |b| b.down = new;

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
    lua.pushInteger(node.x); lua.setField(-2, "x");
    lua.pushInteger(node.y); lua.setField(-2, "y");
    lua.pushInteger(node.width); lua.setField(-2, "width");
    lua.pushInteger(node.height); lua.setField(-2, "height");
    if (node.split_h) |split_h| {
        switch (split_h) {
            .equal => {
                lua.pushNumber(0.5); lua.setField(-2, "split_h");
            },
            .weighted => |w| {
                lua.pushNumber(w); lua.setField(-2, "split_h");
            },
        }
    } else {
        lua.pushNil(); lua.setField(-2, "split_h");
    }
    if (node.split_v) |split_v| {
        switch (split_v) {
            .equal => {
                lua.pushNumber(0.5); lua.setField(-2, "split_v");
            },
            .weighted => |w| {
                lua.pushNumber(w); lua.setField(-2, "split_v");
            },
        }
    } else {
        lua.pushNil(); lua.setField(-2, "split_v");
    }
    return 1;
}

fn print_layout(lua: *Lua) i32 {
    _ = lua;
    global_wm.print_layout();
    return 0;
}

pub fn load(wm: *WM) !void {
    global_wm = wm;

    var lua = try Lua.init(wm.allocator);
    wm.lua = lua;

    lua.openLibs();

    lua.newTable();

    // modifier constants
    lua.pushInteger(c.Mod4Mask);   lua.setField(-2, "MOD_SUPER");
    lua.pushInteger(c.Mod1Mask);   lua.setField(-2, "MOD_ALT");
    lua.pushInteger(c.ShiftMask);  lua.setField(-2, "MOD_SHIFT");
    lua.pushInteger(c.ControlMask);lua.setField(-2, "MOD_CTRL");

    // functions
    lua.pushFunction(ziglua.wrap(l_bind));                 lua.setField(-2, "bind");
    lua.pushFunction(ziglua.wrap(l_spawn));                lua.setField(-2, "spawn");
    lua.pushFunction(ziglua.wrap(l_focus_left));           lua.setField(-2, "focus_left");
    lua.pushFunction(ziglua.wrap(l_focus_right));          lua.setField(-2, "focus_right");
    lua.pushFunction(ziglua.wrap(l_focus_up));             lua.setField(-2, "focus_up");
    lua.pushFunction(ziglua.wrap(l_focus_down));           lua.setField(-2, "focus_down");
    lua.pushFunction(ziglua.wrap(l_focus));                lua.setField(-2, "focus");
    lua.pushFunction(ziglua.wrap(l_exchange_left));        lua.setField(-2, "exchange_left");
    lua.pushFunction(ziglua.wrap(l_exchange_right));       lua.setField(-2, "exchange_right");
    lua.pushFunction(ziglua.wrap(l_exchange_up));          lua.setField(-2, "exchange_up");
    lua.pushFunction(ziglua.wrap(l_exchange_down));        lua.setField(-2, "exchange_down");
    lua.pushFunction(ziglua.wrap(l_on_map));               lua.setField(-2, "on_map");
    lua.pushFunction(ziglua.wrap(l_on_unmap));             lua.setField(-2, "on_unmap");
    lua.pushFunction(ziglua.wrap(l_get_focused));          lua.setField(-2, "get_focused");
    lua.pushFunction(ziglua.wrap(l_add_edge));             lua.setField(-2, "add_edge");
    lua.pushFunction(ziglua.wrap(l_remove_node));          lua.setField(-2, "remove_node");
    lua.pushFunction(ziglua.wrap(l_insert_right));         lua.setField(-2, "insert_right");
    lua.pushFunction(ziglua.wrap(l_insert_below));         lua.setField(-2, "insert_below");
    lua.pushFunction(ziglua.wrap(l_insert_left));          lua.setField(-2, "insert_left");
    lua.pushFunction(ziglua.wrap(l_insert_above));         lua.setField(-2, "insert_above");
    lua.pushFunction(ziglua.wrap(l_kill_client));          lua.setField(-2, "kill_client");
    lua.pushFunction(ziglua.wrap(l_get_node_info));        lua.setField(-2, "get_node_info");
    lua.pushFunction(ziglua.wrap(l_resize_edge));          lua.setField(-2, "resize_edge");
    lua.pushFunction(ziglua.wrap(l_resize_corner));        lua.setField(-2, "resize_corner");
    lua.pushFunction(ziglua.wrap(l_resize_focused_edge));  lua.setField(-2, "resize_focused_edge");
    lua.pushFunction(ziglua.wrap(l_resize_focused_corner));lua.setField(-2, "resize_focused_corner");
    lua.pushFunction(ziglua.wrap(print_layout));           lua.setField(-2, "print_layout");

    lua.setGlobal("wm");

    const home_ptr = c.getenv("HOME") orelse return error.NoHome;
    const home: []const u8 = std.mem.span(home_ptr);
    if (home.len == 0) {
        return error.NoHome;
    }
    const path = try std.fmt.allocPrint(wm.allocator, "{s}/.config/duckwm/config.lua", .{home});
    defer wm.allocator.free(path);
    const path_z = try std.mem.concatWithSentinel(wm.allocator, u8, &[_][]const u8{path}, 0);
    defer wm.allocator.free(path_z);

    try lua.doFile(path_z);
}
