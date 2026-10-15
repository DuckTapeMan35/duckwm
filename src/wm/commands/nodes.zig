const std = @import("std");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("../core.zig");
const command = @import("../command.zig");
const util = @import("util.zig");
const WM = core.WM;
const Node = graph_mod.Node;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

// ---- creation and removal ----
fn new_empty(wm: *WM, fill_screen: bool) !Value {
    const n = try wm.current_graph.add_node(.empty);
    if (fill_screen) {
        // A new node: no journal entries needed for its own fields.
        n.width = wm.screen_width;
        n.height = wm.screen_height;
    }
    return .{ .integer = try wm.register_node(null, n) };
}

pub fn create_root_node(wm: *WM, _: void, _: Allocator) !Value {
    return new_empty(wm, true);
}

pub fn create_empty_node(wm: *WM, _: void, _: Allocator) !Value {
    return new_empty(wm, false);
}

pub fn create_container(wm: *WM, _: void, _: Allocator) !Value {
    return new_empty(wm, false);
}

pub fn destroy_container(wm: *WM, args: Args(.destroy_container), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    if (n.content != .empty) return error.NotAContainer;
    if (n.owner_graph) |g| g.remove_node(n);
    return .nil;
}

pub fn remove_node(wm: *WM, args: Args(.remove_node), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    if (n.owner_graph) |g| g.remove_node(n);
    return .nil;
}

// ---- structure ----
pub fn reparent(wm: *WM, args: Args(.reparent), _: Allocator) !Value {
    const child = try util.node(wm, args.child);
    const parent = try util.node(wm, args.parent);
    const g = child.owner_graph orelse return error.NotInGraph;
    var i: usize = 0;
    while (i < child.constraints.items.len) {
        if (child.constraints.items[i] == .grid_cell) g.remove_constraint_at(child, i) else i += 1;
    }
    try g.add_constraint(child, .{ .grid_cell = .{ .col = 0, .row = 0, .cols = 1, .rows = 1, .container = parent } });
    return .nil;
}

pub fn set_reparent_strategy(wm: *WM, args: Args(.set_reparent_strategy), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    // Not journaled: an optional union, too large for a field entry, set at layout setup.
    n.on_remove = if (args.strategy) |st| switch (st) {
        .promote => .promote,
        .remove => .remove,
        .empty => .leave_empty,
    } else null;
    return .nil;
}

pub fn unregister_node(wm: *WM, args: Args(.unregister_node), _: Allocator) !Value {
    _ = wm.node_registry.remove(args.id);
    return .nil;
}

pub fn set_node_empty(wm: *WM, args: Args(.set_node_empty), _: Allocator) !Value {
    wm.set_node_empty(args.id);
    return .nil;
}

pub fn set_node_window(wm: *WM, args: Args(.set_node_window), _: Allocator) !Value {
    try wm.set_node_window(args.id, args.window);
    return .nil;
}

pub fn move_window_to_node(wm: *WM, args: Args(.move_window_to_node), _: Allocator) !Value {
    try wm.move_window_to_node(args.src, args.dst);
    return .nil;
}

// ---- queries ----
pub fn get_container_of(wm: *WM, args: Args(.get_container_of), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    const cont = graph_mod.get_container(n) orelse return .nil;
    return util.id_value(wm, cont);
}

pub fn get_node_type(wm: *WM, args: Args(.get_node_type), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    return .{ .str = util.type_name(n) };
}

pub fn get_node_geometry(wm: *WM, args: Args(.get_node_geometry), arena: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    return .{ .map = try arena.dupe(Value.Field, &.{
        .{ .key = "x", .value = .{ .integer = n.x } },
        .{ .key = "y", .value = .{ .integer = n.y } },
        .{ .key = "width", .value = .{ .integer = n.width } },
        .{ .key = "height", .value = .{ .integer = n.height } },
    }) };
}

pub fn get_node_info(wm: *WM, args: Args(.get_node_info), arena: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    return .{ .map = try arena.dupe(Value.Field, &.{
        .{ .key = "x", .value = .{ .integer = n.x } },
        .{ .key = "y", .value = .{ .integer = n.y } },
        .{ .key = "width", .value = .{ .integer = n.width } },
        .{ .key = "height", .value = .{ .integer = n.height } },
        .{ .key = "floating", .value = .{ .boolean = n.floating } },
        .{ .key = "type", .value = .{ .str = util.type_name(n) } },
    }) };
}

pub fn get_split_ratios(wm: *WM, args: Args(.get_split_ratios), arena: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    for (n.constraints.items) |con| {
        if (con != .split) continue;
        const out = try arena.alloc(Value, con.split.count);
        for (out, con.split.ratios[0..con.split.count]) |*v, r| v.* = .{ .number = r };
        return .{ .list = out };
    }
    return .nil;
}

/// Real windows and workspace-preview nodes of the current workspace.
pub fn get_all_windows(wm: *WM, _: void, arena: Allocator) !Value {
    var out: std.ArrayListUnmanaged(Value) = .empty;
    for (wm.current_graph.nodes.items) |n| {
        const h: types.WindowHandle = switch (n.content) {
            .window => |w| w,
            .workspace => n.preview_window orelse continue,
            .empty => continue,
        };
        if (wm.window_to_node_id.get(h)) |id| try out.append(arena, .{ .integer = id });
    }
    return .{ .list = out.items };
}
