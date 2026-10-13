const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const types = @import("types");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const Node = graph_mod.Node;

fn new_empty(lua: *Lua, comptime what: []const u8, fill_screen: bool) i32 {
    const wm = util.global_wm;
    const node = wm.current_graph.add_node(.empty) catch util.luaL_error_str(lua, "failed to create " ++ what);
    if (fill_screen) {
        // A new node: no journal entries needed for its own fields.
        node.width = wm.screen_width;
        node.height = wm.screen_height;
    }
    const id = wm.register_node(null, node) catch util.luaL_error_str(lua, "failed to register " ++ what);
    lua.pushInteger(@intCast(id));
    return 1;
}

pub fn l_create_root_node(lua: *Lua) i32 {
    return new_empty(lua, "root node", true);
}

pub fn l_create_empty_node(lua: *Lua) i32 {
    return new_empty(lua, "empty node", false);
}

pub fn l_create_container(lua: *Lua) i32 {
    return new_empty(lua, "container", false);
}

/// Registry entries are dropped at commit, when the node is actually freed.
fn remove(node: *Node) void {
    if (node.owner_graph) |g| g.remove_node(node);
}

pub fn l_destroy_container(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    if (node.content != .empty) util.luaL_error_str(lua, "destroy_container called on non-container");
    remove(node);
    return 0;
}

pub fn l_remove_node(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    remove(node);
    return 0;
}

pub fn l_reparent(lua: *Lua) i32 {
    const child = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid child node");
    const parent = util.node_arg(lua, 2) orelse util.luaL_error_str(lua, "invalid parent node");
    const g = child.owner_graph orelse util.luaL_error_str(lua, "child is not in a graph");
    var i: usize = 0;
    while (i < child.constraints.items.len) {
        if (child.constraints.items[i] == .grid_cell) g.remove_constraint_at(child, i) else i += 1;
    }
    g.add_constraint(child, .{ .grid_cell = .{
        .col = 0,
        .row = 0,
        .cols = 1,
        .rows = 1,
        .container = parent,
    } }) catch
        util.luaL_error_str(lua, "out of memory");
    return 0;
}

pub fn l_get_container_of(lua: *Lua) i32 {
    const child = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const container = graph_mod.get_container(child) orelse {
        lua.pushNil();
        return 1;
    };
    if (util.global_wm.get_id_for_node(container)) |id| lua.pushInteger(@intCast(id)) else lua.pushNil();
    return 1;
}

pub fn l_set_reparent_strategy(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    // Not journaled: an optional union, too large for a field entry, and only set at layout setup.
    if (lua.isNoneOrNil(2)) {
        node.on_remove = null;
        return 0;
    }
    const strategy = lua.checkString(2);
    node.on_remove = if (std.mem.eql(u8, strategy, "promote"))
        .promote
    else if (std.mem.eql(u8, strategy, "remove"))
        .remove
    else if (std.mem.eql(u8, strategy, "empty"))
        .leave_empty
    else
        util.luaL_error_str(lua, "set_reparent_strategy: unknown strategy, expected 'promote', 'remove', or 'empty'");
    return 0;
}

pub fn l_unregister_node(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return 0;
    _ = util.global_wm.node_registry.remove(id);
    return 0;
}

pub fn l_set_node_empty(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return 0;
    util.global_wm.set_node_empty(id);
    return 0;
}

pub fn l_set_node_window(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse util.luaL_error_str(lua, "invalid node id");
    const win = util.check_node_id(lua, 2) orelse util.luaL_error_str(lua, "invalid window id");
    util.global_wm.set_node_window(id, win) catch util.luaL_error_str(lua, "failed to set node window");
    return 0;
}

pub fn l_move_window_to_node(lua: *Lua) i32 {
    const src = util.check_node_id(lua, 1) orelse util.luaL_error_str(lua, "invalid source node id");
    const dst = util.check_node_id(lua, 2) orelse util.luaL_error_str(lua, "invalid destination node id");
    util.global_wm.move_window_to_node(src, dst) catch util.luaL_error_str(lua, "move_window_to_node failed");
    return 0;
}

// ---- queries ----
fn type_name(node: *const Node) [:0]const u8 {
    return switch (node.content) {
        .window => "window",
        .empty => "empty",
        .workspace => "workspace",
    };
}

fn push_geometry_fields(lua: *Lua, node: *const Node) void {
    lua.pushInteger(node.x);
    lua.setField(-2, "x");
    lua.pushInteger(node.y);
    lua.setField(-2, "y");
    lua.pushInteger(node.width);
    lua.setField(-2, "width");
    lua.pushInteger(node.height);
    lua.setField(-2, "height");
}

pub fn l_get_node_type(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    _ = lua.pushString(type_name(node));
    return 1;
}

pub fn l_get_node_geometry(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    lua.createTable(0, 4);
    push_geometry_fields(lua, node);
    return 1;
}

pub fn l_get_node_info(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    lua.createTable(0, 6);
    push_geometry_fields(lua, node);
    lua.pushBoolean(node.floating);
    lua.setField(-2, "floating");
    _ = lua.pushString(type_name(node));
    lua.setField(-2, "type");
    return 1;
}

pub fn l_get_split_ratios(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    for (node.constraints.items) |con| {
        if (con != .split) continue;
        lua.newTable();
        for (0..con.split.count) |i| {
            lua.pushNumber(con.split.ratios[i]);
            lua.setIndexRaw(-2, @intCast(i + 1));
        }
        return 1;
    }
    lua.pushNil();
    return 1;
}

pub fn l_get_all_windows(lua: *Lua) i32 {
    const wm = util.global_wm;
    lua.newTable();
    var i: i64 = 1;
    for (wm.current_graph.nodes.items) |node| {
        // Real windows and workspace-preview nodes.
        const h: types.WindowHandle = switch (node.content) {
            .window => |w| w,
            .workspace => node.preview_window orelse continue,
            .empty => continue,
        };
        if (wm.window_to_node_id.get(h)) |id| {
            lua.pushInteger(@intCast(id));
            lua.setIndexRaw(-2, i);
            i += 1;
        }
    }
    return 1;
}
