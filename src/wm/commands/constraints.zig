const std = @import("std");
const graph_mod = @import("graph");
const core = @import("../core.zig");
const command = @import("../command.zig");
const layouts = @import("layouts.zig");
const util = @import("util.zig");
const WM = core.WM;
const Node = graph_mod.Node;
const Constraint = graph_mod.Constraint;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

const Handler = fn (*WM, command.Pair, Allocator) anyerror!Value;

// ---- relations between two nodes ----
fn relation(comptime name: []const u8) Handler {
    return struct {
        fn f(wm: *WM, p: command.Pair, _: Allocator) anyerror!Value {
            const a, const b = try util.pair(wm, p);
            try util.add(a, @unionInit(Constraint, name, b));
            return .nil;
        }
    }.f;
}

pub const left_of = relation("left_of");
pub const right_of = relation("right_of");
pub const above = relation("above");
pub const below = relation("below");
pub const align_left = relation("align_left");
pub const align_top = relation("align_top");
pub const align_right = relation("align_right");
pub const align_bottom = relation("align_bottom");
pub const equal_width = relation("equal_width");
pub const equal_height = relation("equal_height");

// ---- the same for floats ----
/// Start a float next to b, so the solver begins near the answer.
fn place_beside(wm: *WM, a: *Node, b: *Node, comptime rel: []const u8) void {
    const aw: i32 = @intCast(a.width);
    const ah: i32 = @intCast(a.height);
    const bw: i32 = @intCast(b.width);
    const bh: i32 = @intCast(b.height);
    const p: [2]i32 = if (comptime std.mem.eql(u8, rel, "left_of"))
        .{ b.x - aw, b.y }
    else if (comptime std.mem.eql(u8, rel, "right_of"))
        .{ b.x + bw, b.y }
    else if (comptime std.mem.eql(u8, rel, "above"))
        .{ b.x, b.y - ah }
    else if (comptime std.mem.eql(u8, rel, "below"))
        .{ b.x, b.y + bh }
    else
        return;
    wm.journal.set(a, "x", p[0]);
    wm.journal.set(a, "y", p[1]);
}

/// Like relation, for floats: placed next to b first, then solved right away.
fn float_relation(comptime rel: []const u8) Handler {
    return struct {
        fn f(wm: *WM, p: command.Pair, _: Allocator) anyerror!Value {
            const a, const b = try util.pair(wm, p);
            if (!a.floating) return error.NotFloating;
            place_beside(wm, a, b, rel);
            try util.add(a, @unionInit(Constraint, rel, b));
            wm.relayout();
            return .nil;
        }
    }.f;
}

pub const float_left_of = float_relation("left_of");
pub const float_right_of = float_relation("right_of");
pub const float_above = float_relation("above");
pub const float_below = float_relation("below");
pub const float_align_left = float_relation("align_left");
pub const float_align_top = float_relation("align_top");
pub const float_align_right = float_relation("align_right");
pub const float_align_bottom = float_relation("align_bottom");
pub const float_equal_width = float_relation("equal_width");
pub const float_equal_height = float_relation("equal_height");

pub fn float_clear_constraints(wm: *WM, args: Args(.float_clear_constraints), _: Allocator) !Value {
    const n = try util.node(wm, args.id);
    if (!n.floating) return error.NotFloating;
    const g = n.owner_graph orelse return error.NotInGraph;
    try g.replace_constraints(n, &.{});
    wm.relayout();
    return .nil;
}

// ---- fixed values ----
// Lenient: a node that's gone is not an error for these.
pub fn fixed_width(wm: *WM, args: Args(.fixed_width), _: Allocator) !Value {
    if (wm.get_node_by_id(args.id)) |n| try util.add(n, .{ .fixed_width = args.value });
    return .nil;
}

pub fn fixed_height(wm: *WM, args: Args(.fixed_height), _: Allocator) !Value {
    if (wm.get_node_by_id(args.id)) |n| try util.add(n, .{ .fixed_height = args.value });
    return .nil;
}

pub fn fixed_x(wm: *WM, args: Args(.fixed_x), _: Allocator) !Value {
    if (wm.get_node_by_id(args.id)) |n| try util.add(n, .{ .fixed_x = args.value });
    return .nil;
}

pub fn fixed_y(wm: *WM, args: Args(.fixed_y), _: Allocator) !Value {
    if (wm.get_node_by_id(args.id)) |n| try util.add(n, .{ .fixed_y = args.value });
    return .nil;
}

pub fn fixed_ratio(wm: *WM, args: Args(.fixed_ratio), _: Allocator) !Value {
    if (!(args.ratio > 0)) return error.OutOfRange;
    try util.add(try util.node(wm, args.id), .{ .fixed_ratio = @floatCast(args.ratio) });
    return .nil;
}

// ---- containers ----
pub fn grid_cell(wm: *WM, args: Args(.grid_cell), _: Allocator) !Value {
    if (args.cols == 0 or args.rows == 0 or args.col >= args.cols or args.row >= args.rows)
        return error.InvalidGridCell;
    try util.add(try util.node(wm, args.id), .{ .grid_cell = .{
        .col = args.col,
        .row = args.row,
        .cols = args.cols,
        .rows = args.rows,
        .container = try util.node(wm, args.container),
    } });
    return .nil;
}

pub fn grid_cell_abs(wm: *WM, args: Args(.grid_cell_abs), _: Allocator) !Value {
    try util.add(try util.node(wm, args.id), .{ .grid_cell_abs = .{
        .x = args.x,
        .y = args.y,
        .w = args.w,
        .h = args.h,
        .container = try util.node(wm, args.container),
    } });
    return .nil;
}

pub fn split(wm: *WM, args: Args(.split), _: Allocator) !Value {
    const con = try layouts.make_split(wm, args.container, args.axis, args.ratios, args.children);
    try util.add(con.split.container, con);
    return .nil;
}

// ---- removal ----
pub fn clear_constraints(wm: *WM, args: Args(.clear_constraints), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    const g = n.owner_graph orelse return .nil;
    try g.replace_constraints(n, &.{});
    return .nil;
}

pub fn remove_constraint(wm: *WM, args: Args(.remove_constraint), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    const g = n.owner_graph orelse return .nil;
    const tag = std.meta.stringToEnum(std.meta.Tag(Constraint), @tagName(args.kind)).?;
    var i: usize = 0;
    while (i < n.constraints.items.len) {
        if (n.constraints.items[i] == tag) g.remove_constraint_at(n, i) else i += 1;
    }
    return .nil;
}
