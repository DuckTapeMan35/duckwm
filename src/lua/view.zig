const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const util = @import("util.zig");
const std = @import("std");
const Lua = ziglua.Lua;

// ---- screen ----
pub fn l_screen_width(lua: *Lua) i32 {
    lua.pushInteger(@intCast(util.global_wm.screen_width));
    return 1;
}

pub fn l_screen_height(lua: *Lua) i32 {
    lua.pushInteger(@intCast(util.global_wm.screen_height));
    return 1;
}

pub fn l_get_work_area(lua: *Lua) i32 {
    const work = util.global_wm.get_work_area();
    lua.pushInteger(work.x);
    lua.pushInteger(work.y);
    lua.pushInteger(work.width);
    lua.pushInteger(work.height);
    return 4;
}

// ---- pan and virtual size (current workspace) ----

fn current() *graph_mod.Graph {
    return util.global_wm.current_graph;
}

pub fn l_set_pan(lua: *Lua) i32 {
    const g = current();
    g.set(g, "pan_x", @intCast(lua.checkInteger(1)));
    g.set(g, "pan_y", @intCast(lua.checkInteger(2)));
    util.global_wm.flush(g) catch {};
    return 0;
}

pub fn l_pan_by(lua: *Lua) i32 {
    const g = current();
    g.set(g, "pan_x", g.pan_x + @as(i32, @intCast(lua.checkInteger(1))));
    g.set(g, "pan_y", g.pan_y + @as(i32, @intCast(lua.checkInteger(2))));
    util.global_wm.flush(g) catch {};
    return 0;
}

pub fn l_get_pan(lua: *Lua) i32 {
    lua.pushInteger(current().pan_x);
    lua.pushInteger(current().pan_y);
    return 2;
}

pub fn l_set_virtual_size(lua: *Lua) i32 {
    const g = current();
    g.set(g, "virtual_width", @intCast(lua.checkInteger(1)));
    g.set(g, "virtual_height", @intCast(lua.checkInteger(2)));
    return 0;
}

pub fn l_set_pan_disabled(lua: *Lua) i32 {
    const g = current();
    g.set(g, "pan_disabled", lua.toBoolean(1));
    return 0;
}

pub fn l_set_lock_horizontal_resize(lua: *Lua) i32 {
    const g = current();
    g.set(g, "lock_horizontal_resize", lua.toBoolean(1));
    return 0;
}

pub fn l_set_lock_vertical_resize(lua: *Lua) i32 {
    const g = current();
    g.set(g, "lock_vertical_resize", lua.toBoolean(1));
    return 0;
}

// ---- resizing ----
pub fn l_resize_edge(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return util.luaL_error_str(lua, "invalid node id");
    const dir_str = lua.checkString(2);
    const delta: i32 = @intCast(lua.checkInteger(3));
    const node = util.global_wm.get_node_by_id(id) orelse return util.luaL_error_str(lua, "invalid node id");
    const dir: graph_mod.Direction = if (std.mem.eql(u8, dir_str, "left")) .Left else if (std.mem.eql(u8, dir_str, "right")) .Right else if (std.mem.eql(u8, dir_str, "up")) .Up else if (std.mem.eql(u8, dir_str, "down")) .Down else return util.luaL_error_str(lua, "direction must be left/right/up/down");
    util.global_wm.resize_edge(node, dir, delta) catch
        return util.luaL_error_str(lua, "resize failed (size limit)");
    return 0;
}

pub fn l_resize_corner(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return util.luaL_error_str(lua, "invalid node id");
    const delta_x: i32 = @intCast(lua.checkInteger(2));
    const delta_y: i32 = @intCast(lua.checkInteger(3));
    const node = util.global_wm.get_node_by_id(id) orelse return util.luaL_error_str(lua, "invalid node id");
    util.global_wm.resize_corner(node, delta_x, delta_y) catch
        return util.luaL_error_str(lua, "resize corner failed");
    return 0;
}

pub fn l_resize_focused_edge(lua: *Lua) i32 {
    const dir_str = lua.checkString(1);
    const delta: i32 = @intCast(lua.checkInteger(2));
    const node = util.global_wm.focused orelse return 0;
    const dir: graph_mod.Direction = if (std.mem.eql(u8, dir_str, "left")) .Left else if (std.mem.eql(u8, dir_str, "right")) .Right else if (std.mem.eql(u8, dir_str, "up")) .Up else if (std.mem.eql(u8, dir_str, "down")) .Down else {
        _ = lua.pushString("direction must be left/right/up/down");
        return lua.raiseError();
    };
    util.global_wm.resize_edge(node, dir, delta) catch {
        _ = lua.pushString("resize edge failed");
        return lua.raiseError();
    };
    return 0;
}

pub fn l_resize_focused_corner(lua: *Lua) i32 {
    const delta_x: i32 = @intCast(lua.checkInteger(1));
    const delta_y: i32 = @intCast(lua.checkInteger(2));
    const node = util.global_wm.focused orelse return 0;
    util.global_wm.resize_corner(node, delta_x, delta_y) catch {
        _ = lua.pushString("resize corner failed");
        return lua.raiseError();
    };
    return 0;
}
