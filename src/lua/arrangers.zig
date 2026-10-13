const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const util = @import("util.zig");
const config = @import("config.zig");
const Lua = ziglua.Lua;
const Graph = graph_mod.Graph;

// ---- arrangers ----
/// Replace g's arranger with a fresh instance from factory_ref, and
/// re-map every tiled node through it, one at a time.
fn apply_arranger_to_graph(lua: *Lua, g: *Graph, factory_ref: i32) void {
    const wm = util.global_wm;
    const saved_current = wm.current_graph;
    wm.current_graph = g;
    defer wm.current_graph = saved_current;

    config.reload_persistent(lua); // drop state the old arranger's scope may have relied on

    _ = lua.getIndexRaw(ziglua.registry_index, factory_ref);
    lua.protectedCall(.{ .args = 0, .results = 1 }) catch |err| {
        std.debug.print("arranger factory error: {}\n", .{err});
        lua.pop(1);
        return;
    };
    if (lua.typeOf(-1) != .function) {
        lua.pop(1);
        return;
    }
    const arranger_ref = lua.ref(ziglua.registry_index);
    if (g.arranger_ref != 0) lua.unref(ziglua.registry_index, g.arranger_ref);
    g.arranger_ref = arranger_ref;

    g.set(g, "virtual_width", 0);
    g.set(g, "virtual_height", 0);
    g.set(g, "lock_horizontal_resize", false);
    g.set(g, "lock_vertical_resize", false);
    g.set(g, "pan_disabled", false);

    // The tiled windows and workspaces to re-map, in their current order.
    var ids: std.ArrayListUnmanaged(u32) = .empty;
    defer ids.deinit(wm.allocator);
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        switch (node.content) {
            .window, .workspace => {
                if (node.content == .workspace and node.preview_window == null) continue;
                if (wm.get_id_for_node(node)) |id| ids.append(wm.allocator, id) catch {};
            },
            .empty => {},
        }
    }

    // Drop the old arranger's containers (backwards: remove_node shrinks the list).
    var i = g.nodes.items.len;
    while (i > 0) {
        i -= 1;
        const node = g.nodes.items[i];
        if (node.content == .empty) g.remove_node(node);
    }

    // Take the tiled nodes out, then map them back one at a time, so each
    // map callback's get_layout() sees only the windows placed so far.
    for (ids.items) |id| {
        const node = wm.get_node_by_id(id) orelse continue;
        g.detach_node(node);
        g.replace_constraints(node, &.{}) catch {};
    }
    var prev_id: ?u32 = null;
    for (ids.items) |id| {
        const node = wm.get_node_by_id(id) orelse continue;
        g.attach_node(node) catch continue;
        wm.call_arranger(g, "map", id, prev_id);
        prev_id = id;
    }

    wm.resolve(g) catch {};
    wm.rebuild_focus_edges() catch {};
    g.set(g, "pan_x", 0);
    g.set(g, "pan_y", 0);
    if (g == saved_current) wm.flush(g) catch {};
}

/// The arranger name argument at i, if one was given.
fn name_arg(lua: *Lua, i: i32) ?[]const u8 {
    if (lua.typeOf(i) != .string) return null;
    return lua.toString(i) catch null;
}

fn set_name(g: *Graph, name: []const u8) void {
    const wm = util.global_wm;
    const owned = wm.allocator.dupe(u8, name) catch return;
    if (g.arranger_name.len > 0) wm.allocator.free(g.arranger_name);
    g.arranger_name = owned;
}

pub fn l_set_arranger(lua: *Lua) i32 {
    lua.checkType(1, .function);
    const name = name_arg(lua, 2);
    lua.pushValue(1);
    const factory_ref = lua.ref(ziglua.registry_index);
    const g = util.global_wm.current_graph;
    apply_arranger_to_graph(lua, g, factory_ref);
    lua.unref(ziglua.registry_index, factory_ref);
    if (name) |n| set_name(g, n);
    return 0;
}

pub fn l_register_arranger(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "register_arranger: invalid workspace id");
    if (node.content != .workspace) util.luaL_error_str(lua, "register_arranger: node is not a workspace");
    lua.checkType(2, .function);
    const name = name_arg(lua, 3);
    lua.pushValue(2);
    const factory_ref = lua.ref(ziglua.registry_index);
    apply_arranger_to_graph(lua, node.content.workspace, factory_ref);
    lua.unref(ziglua.registry_index, factory_ref);
    if (name) |n| set_name(node.content.workspace, n);
    return 0;
}

pub fn l_set_default_arranger(lua: *Lua) i32 {
    lua.checkType(1, .function);
    lua.pushValue(1);
    const wm = util.global_wm;
    wm.default_arranger_ref = lua.ref(ziglua.registry_index);
    if (name_arg(lua, 2)) |name| {
        const owned = wm.allocator.dupe(u8, name) catch return 0;
        if (wm.default_arranger_name.len > 0) wm.allocator.free(wm.default_arranger_name);
        wm.default_arranger_name = owned;
    }
    return 0;
}

pub fn l_get_arranger_name(lua: *Lua) i32 {
    const name = util.global_wm.current_graph.arranger_name;
    if (name.len == 0) lua.pushNil() else _ = lua.pushString(name);
    return 1;
}

pub fn l_get_arranger_index(lua: *Lua) i32 {
    lua.pushInteger(util.global_wm.current_graph.arranger_index);
    return 1;
}

pub fn l_set_arranger_index(lua: *Lua) i32 {
    const g = util.global_wm.current_graph;
    g.set(g, "arranger_index", @intCast(lua.checkInteger(1)));
    return 0;
}

// ---- rules ----
pub fn l_add_rule(lua: *Lua) i32 {
    lua.checkType(1, .function);
    lua.pushValue(1);
    const ref = lua.ref(ziglua.registry_index);
    const wm = util.global_wm;
    wm.rules.append(wm.allocator, ref) catch {
        lua.unref(ziglua.registry_index, ref);
        util.luaL_error_str(lua, "add_rule: out of memory");
    };
    lua.pushInteger(@intCast(ref));
    return 1;
}

pub fn l_remove_rule(lua: *Lua) i32 {
    const ref: i32 = @intCast(lua.checkInteger(1));
    const wm = util.global_wm;
    for (wm.rules.items, 0..) |r, i| {
        if (r == ref) {
            lua.unref(ziglua.registry_index, ref);
            _ = wm.rules.swapRemove(i);
            break;
        }
    }
    return 0;
}

// ---- transactions ----
pub fn l_transaction(lua: *Lua) i32 {
    lua.checkType(1, .function);
    const wm = util.global_wm;
    const tx = wm.tx_begin();
    lua.pushValue(1);
    lua.protectedCall(.{ .args = 0, .results = 1 }) catch {
        wm.tx_end(tx, false);
        lua.raiseError(); // re-raise the original error, already on the stack
    };
    // Returning false rolls back without being an error.
    const ok = !(lua.typeOf(-1) == .boolean and !lua.toBoolean(-1));
    lua.pop(1);
    wm.tx_end(tx, ok);
    lua.pushBoolean(ok);
    return 1;
}
