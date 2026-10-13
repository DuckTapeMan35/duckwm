const std = @import("std");
const ziglua = @import("ziglua");
const wm_mod = @import("wm");
const graph_mod = @import("graph");
const types = @import("types");
const Lua = ziglua.Lua;
const WM = wm_mod.WM;

/// The WM the Lua API operates on. Set once in config.load.
pub var global_wm: *WM = undefined;

const Node = graph_mod.Node;

pub const Registration = struct {
    func: ziglua.CFn,
    name: [:0]const u8,
};

/// Raise "<prefix><detail>" as a Lua error. detail may be runtime-known.
pub fn raise_with(lua: *Lua, comptime prefix: []const u8, detail: []const u8) noreturn {
    _ = lua.pushString(prefix);
    _ = lua.pushString(detail);
    lua.concat(2);
    lua.raiseError();
}

pub fn luaL_error_str(lua: *Lua, msg: []const u8) noreturn {
    _ = lua.pushString(msg);
    lua.raiseError();
}

pub fn check_mods(lua: *Lua, idx: i32) types.Mods {
    const m = lua.checkInteger(idx);
    if (m < 0 or m > std.math.maxInt(types.Mods)) return luaL_error_str(lua, "invalid modifier mask");
    return @intCast(m);
}

pub fn check_button(lua: *Lua, idx: i32) types.Button {
    const b = lua.checkInteger(idx);
    if (b < 1 or b > 255) return luaL_error_str(lua, "invalid button");
    return @intCast(b);
}

pub fn check_node_id(lua: *Lua, stack_pos: i32) ?u32 {
    const n = lua.toInteger(stack_pos) catch return null;
    if (n <= 0) return null;
    return @intCast(n);
}

pub fn check_u32(lua: *Lua, stack_pos: i32) ?u32 {
    const n = lua.toInteger(stack_pos) catch return null;
    if (n < 0) return null;
    return @intCast(n);
}

pub fn check_color(lua: *Lua, stack_pos: i32) ?u32 {
    const n = lua.toInteger(stack_pos) catch return null;
    if (n < 0 or n > 0xFFFFFFFF) return null;
    return @intCast(n);
}

pub fn repaint_node(wm: *WM, node: *graph_mod.Node) void {
    wm.paint_borders(node, null);
}

pub fn repaint_all_nodes(wm: *WM) void {
    for (wm.current_graph.nodes.items) |node| {
        repaint_node(wm, node);
    }
}

pub fn opt_str(lua: *Lua, i: i32) []const u8 {
    return if (lua.isNoneOrNil(i)) "" else lua.checkString(i);
}

/// The node whose id is at stack index i, if any.
pub fn node_arg(lua: *Lua, i: i32) ?*Node {
    const id = check_node_id(lua, i) orelse return null;
    return global_wm.get_node_by_id(id);
}
