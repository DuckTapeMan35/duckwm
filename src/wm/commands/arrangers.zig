const std = @import("std");
const graph_mod = @import("graph");
const core = @import("../core.zig");
const command = @import("../command.zig");
const util = @import("util.zig");
const types = @import("types");
const WM = core.WM;
const Graph = graph_mod.Graph;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

/// Give g a fresh arranger from factory, then map every tiled node through it
/// again, one at a time, as if each window had just appeared.
fn apply(wm: *WM, g: *Graph, factory: types.Callback) !void {
    const saved_current = wm.current_graph;
    wm.current_graph = g;
    defer wm.current_graph = saved_current;

    // The old arranger's binds and indicators go with it.
    wm.drop_owned_binds(g);
    for (g.nodes.items) |node| {
        wm.journal.set(node, "indicator_side", null);
        wm.journal.set(node, "border_color_top", null);
        wm.journal.set(node, "border_color_bottom", null);
        wm.journal.set(node, "border_color_left", null);
        wm.journal.set(node, "border_color_right", null);
    }

    const arranger = try wm.instantiate_callback(factory, g);

    if (g.arranger) |old| wm.release_callback(old);
    g.arranger = arranger;
    try g.replace_bytes(&g.arranger_state, "");

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
            .window, .workspace, .group => {
                if (node.content == .workspace and node.preview_window == null) continue;
                if (wm.get_id_for_node(node)) |id| try ids.append(wm.allocator, id);
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
    // map callback's get_layout sees only the windows placed so far.
    for (ids.items) |id| {
        const node = wm.get_node_by_id(id) orelse continue;
        g.detach_node(node);
        try g.replace_constraints(node, &.{});
    }
    var prev_id: ?u32 = null;
    for (ids.items) |id| {
        const node = wm.get_node_by_id(id) orelse continue;
        try g.attach_node(node);
        wm.call_arranger(g, .map, id, prev_id);
        prev_id = id;
    }

    try wm.resolve(g);
    try wm.rebuild_focus_edges();
    g.set(g, "pan_x", 0);
    g.set(g, "pan_y", 0);
    if (g == saved_current) try wm.flush(g);
}

fn set_name(wm: *WM, g: *Graph, name: []const u8) !void {
    const owned = try wm.allocator.dupe(u8, name);
    if (g.arranger_name.len > 0) wm.allocator.free(g.arranger_name);
    g.arranger_name = owned;
}

pub fn set_arranger(wm: *WM, args: Args(.set_arranger), _: Allocator) !Value {
    const factory = try util.callback(wm, args.factory);
    const g = wm.current_graph;
    try apply(wm, g, factory);
    wm.release_callback(factory); // only needed to make the arranger
    if (args.name) |n| try set_name(wm, g, n);
    return .nil;
}

pub fn register_arranger(wm: *WM, args: Args(.register_arranger), _: Allocator) !Value {
    const node = try util.node(wm, args.id);
    const g = node.inner() orelse return error.NotAWorkspace;
    const factory = try util.callback(wm, args.factory);
    try apply(wm, g, factory);
    wm.release_callback(factory);
    if (args.name) |n| try set_name(wm, g, n);
    return .nil;
}

pub fn set_default_arranger(wm: *WM, args: Args(.set_default_arranger), _: Allocator) !Value {
    const factory = try util.callback(wm, args.factory);
    if (args.name) |n| {
        const owned = try wm.allocator.dupe(u8, n);
        if (wm.default_arranger_name.len > 0) wm.allocator.free(wm.default_arranger_name);
        wm.default_arranger_name = owned;
    }
    if (wm.default_arranger) |old| wm.release_callback(old);
    wm.default_arranger = factory; // kept: called for every new workspace
    return .nil;
}

pub fn get_arranger_name(wm: *WM, _: Args(.get_arranger_name), arena: Allocator) !Value {
    const name = wm.current_graph.arranger_name;
    return if (name.len == 0) .nil else .{ .str = try arena.dupe(u8, name) };
}

pub fn get_arranger_index(wm: *WM, _: Args(.get_arranger_index), _: Allocator) !Value {
    return .{ .integer = wm.current_graph.arranger_index };
}

pub fn set_arranger_index(wm: *WM, args: Args(.set_arranger_index), _: Allocator) !Value {
    const g = wm.current_graph;
    g.set(g, "arranger_index", args.index);
    return .nil;
}
