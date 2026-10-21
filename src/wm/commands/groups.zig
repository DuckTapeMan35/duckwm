const std = @import("std");
const graph_mod = @import("graph");
const core = @import("../core.zig");
const command = @import("../command.zig");
const groups = @import("../groups.zig");
const util = @import("util.zig");
const output = @import("../output.zig");
const WM = core.WM;
const Node = graph_mod.Node;
const Graph = graph_mod.Graph;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

fn group_graph(wm: *WM, id: u32) !*Graph {
    const n = try util.node(wm, id);
    return switch (n.content) {
        .group => |g| g,
        else => error.NotAGroup,
    };
}

/// A new group around ids (or the focused window), where the first of them was.
pub fn create_group(wm: *WM, args: Args(.create_group), _: Allocator) !Value {
    var members: std.ArrayListUnmanaged(*Node) = .empty;
    defer members.deinit(wm.allocator);
    const ids = args.ids orelse &.{};
    if (ids.len == 0) {
        const f = wm.focused orelse return .nil;
        try members.append(wm.allocator, f);
    } else for (ids) |id| try members.append(wm.allocator, try util.node(wm, id));
    return .{ .integer = try groups.create(wm, members.items) };
}

/// Its members go where the group was; the group goes.
pub fn ungroup(wm: *WM, args: Args(.ungroup), _: Allocator) !Value {
    try groups.ungroup(wm, try util.node(wm, args.id));
    return .nil;
}

/// Into group (its arranger places it), or with no group, out of the one it's in.
pub fn move_to_group(wm: *WM, args: Args(.move_to_group), _: Allocator) !Value {
    const n = try util.node(wm, args.id);
    const src = n.owner_graph orelse return error.NotInGraph;
    const target: *Graph = if (args.group) |gid|
        try group_graph(wm, gid)
    else if (src.is_group)
        src.parent_node.?.owner_graph.?
    else
        return .nil;
    // Read before the move: src may be dissolved by it.
    const src_ws = src.workspace();
    const target_ws = target.workspace();
    try groups.move(wm, args.id, target);
    try groups.settle(wm, target_ws);
    if (src_ws != target_ws) try groups.settle(wm, src_ws);
    return .nil;
}

/// The group node is in, or nil.
pub fn get_group(wm: *WM, args: Args(.get_group), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    const g = groups.group_of(n) orelse return .nil;
    return util.id_value(wm, g);
}

/// What the group holds directly (windows, groups, workspaces), in order.
pub fn get_group_members(wm: *WM, args: Args(.get_group_members), arena: Allocator) !Value {
    const g = try group_graph(wm, args.id);
    var out: std.ArrayListUnmanaged(Value) = .empty;
    for (g.nodes.items) |n| {
        if (n.content == .empty) continue;
        if (wm.get_id_for_node(n)) |id| try out.append(arena, .{ .integer = id });
    }
    return .{ .list = out.items };
}

/// Lay out every workspace on screen again: outlines take room from groups.
fn relayout_visible(wm: *WM) !void {
    for (wm.outputs.items) |o| {
        const g = output.visible(wm, o);
        try wm.resolve(g);
        try wm.flush(g);
    }
    try wm.rebuild_focus_edges();
}

/// The outline of every group without its own (width 0: none).
pub fn set_group_outline(wm: *WM, args: Args(.set_group_outline), _: Allocator) !Value {
    wm.journal.set(wm, "group_outline_width", args.width);
    wm.journal.set(wm, "group_outline_color", args.color);
    try relayout_visible(wm);
    return .nil;
}

/// One group's outline; nil for either goes back to set_group_outline's.
pub fn set_group_outline_of(wm: *WM, args: Args(.set_group_outline_of), _: Allocator) !Value {
    const g = try group_graph(wm, args.id);
    g.set(g, "outline_width", args.width);
    g.set(g, "outline_color", args.color);
    try relayout_visible(wm);
    return .nil;
}
