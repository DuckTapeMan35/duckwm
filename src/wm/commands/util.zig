const std = @import("std");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("../core.zig");
const command = @import("../command.zig");
const protocol = @import("protocol");
const WM = core.WM;
const Node = graph_mod.Node;
const Constraint = graph_mod.Constraint;
const Value = command.Value;
const NodeId = command.NodeId;

/// The payload type of a command, for handler signatures.
pub fn Args(comptime tag: std.meta.Tag(command.Command)) type {
    return @FieldType(command.Command, @tagName(tag));
}

pub fn node(wm: *WM, id: NodeId) !*Node {
    return wm.get_node_by_id(id) orelse error.InvalidNode;
}

pub fn pair(wm: *WM, p: command.Pair) !struct { *Node, *Node } {
    return .{ try node(wm, p.a), try node(wm, p.b) };
}

pub fn add(n: *Node, con: Constraint) !void {
    const g = n.owner_graph orelse return error.NotInGraph;
    try g.add_constraint(n, con);
}

pub fn id_value(wm: *WM, n: *Node) Value {
    return if (wm.get_id_for_node(n)) |id| .{ .integer = id } else .nil;
}

pub fn type_name(n: *const Node) []const u8 {
    return switch (n.content) {
        .window => "window",
        .empty => "empty",
        .workspace => "workspace",
        .group => "group",
    };
}

/// A copy in the arena: results must not point into nodes the batch may free at commit.
pub fn text(arena: std.mem.Allocator, s: []const u8) !Value {
    if (s.len == 0) return .nil;
    return .{ .str = try arena.dupe(u8, s) };
}

pub fn center(n: *const Node) types.Point {
    return .{
        .x = n.x + @divTrunc(@as(i32, @intCast(n.width)), 2),
        .y = n.y + @divTrunc(@as(i32, @intCast(n.height)), 2),
    };
}

pub fn point(arena: std.mem.Allocator, p: types.Point) !Value {
    return .{ .multi = try arena.dupe(Value, &.{ .{ .integer = p.x }, .{ .integer = p.y } }) };
}

/// A command's callback argument, as duckwm stores it.
pub fn callback(wm: *WM, cb: protocol.Callback) !types.Callback {
    return switch (wm.callback_source) {
        .lua => .{ .lua = std.math.cast(i32, cb.id) orelse return error.InvalidCallback },
        .none => error.NoCallbackHost,
        .client => |id| .{ .remote = .{ .client = id, .id = cb.id } },
    };
}
