const std = @import("std");
const core = @import("../core.zig");
const command = @import("../command.zig");
const graph_mod = @import("graph");
const util = @import("util.zig");
const protocol = @import("protocol");
const nodes_mod = @import("nodes.zig");

pub const Other = protocol.Other;
pub const ConstraintSpec = protocol.ConstraintSpec;
pub const NodeSpec = protocol.NodeSpec;
pub const LayoutSpec = protocol.LayoutSpec;
const WM = core.WM;
const Allocator = std.mem.Allocator;
const Node = graph_mod.Node;
const Graph = graph_mod.Graph;
const Constraint = graph_mod.Constraint;
const NodeId = command.NodeId;
const Value = command.Value;
const Args = util.Args;

comptime {
    for (std.meta.fields(ConstraintSpec)) |f| {
        if (!@hasField(Constraint, f.name)) @compileError("ConstraintSpec." ++ f.name ++ " has no Constraint counterpart");
    }
    for (std.meta.fields(Constraint)) |f| {
        if (!@hasField(ConstraintSpec, f.name)) @compileError("Constraint." ++ f.name ++ " is missing from ConstraintSpec");
    }
}

/// Resolves a layout's refs: ids anywhere, keys in one workspace (created on first use).
const Refs = struct {
    wm: *WM,
    g: *Graph,

    fn node(self: Refs, r: protocol.Ref) !*Node {
        return switch (r) {
            .id => |i| get(self.wm, i),
            .key => |k| self.g.keyed(k) orelse try self.create(k),
        };
    }

    /// Inside the caller's transaction, so a rollback removes it again.
    fn create(self: Refs, k: u32) !*Node {
        const n = (try nodes_mod.add_empty(self.wm, self.g)).node;
        n.key = k;
        return n;
    }
};

// ---- set_layout ----
fn get(wm: *WM, id: NodeId) !*Node {
    return wm.get_node_by_id(id) orelse error.InvalidNode;
}

fn build_split(container: *Node, axis: command.Axis, ratios: []const f64, children: []const *Node) !Constraint {
    const count = children.len;
    if (count == 0 or count > 16 or ratios.len != count) return error.InvalidSplit;
    var con: Constraint = .{ .split = .{
        .container = container,
        .axis = if (axis == .h) .horizontal else .vertical,
        .count = @intCast(count),
        .ratios = undefined,
        .children = undefined,
    } };
    for (ratios, children, 0..) |r, child, k| {
        if (!(r > 0)) return error.InvalidSplit;
        con.split.ratios[k] = @floatCast(r);
        con.split.children[k] = child;
    }
    return con;
}

/// The split command's form: ids.
pub fn make_split(wm: *WM, container: NodeId, axis: command.Axis, ratios: []const f64, children: []const NodeId) !Constraint {
    if (children.len > 16) return error.InvalidSplit;
    var nodes: [16]*Node = undefined;
    for (children, 0..) |c, k| nodes[k] = try get(wm, c);
    return build_split(try get(wm, container), axis, ratios, nodes[0..children.len]);
}

/// A layout's form: refs.
fn make_split_refs(refs: Refs, container: protocol.Ref, axis: command.Axis, ratios: []const f64, children: []const protocol.Ref) !Constraint {
    if (children.len > 16) return error.InvalidSplit;
    var nodes: [16]*Node = undefined;
    for (children, 0..) |c, k| nodes[k] = try refs.node(c);
    return build_split(try refs.node(container), axis, ratios, nodes[0..children.len]);
}

fn resolve(refs: Refs, spec: ConstraintSpec) !Constraint {
    return switch (spec) {
        inline .left_of,
        .right_of,
        .above,
        .below,
        .align_left,
        .align_top,
        .align_right,
        .align_bottom,
        .equal_width,
        .equal_height,
        => |o, tag| @unionInit(Constraint, @tagName(tag), try refs.node(o.other)),
        .fixed_x => |v| .{ .fixed_x = v.value },
        .fixed_y => |v| .{ .fixed_y = v.value },
        .fixed_width => |v| .{ .fixed_width = v.value },
        .fixed_height => |v| .{ .fixed_height = v.value },
        .fixed_ratio => |v| .{ .fixed_ratio = @floatCast(v.value) },
        .grid_cell => |g| .{ .grid_cell = .{
            .col = g.col,
            .row = g.row,
            .cols = g.cols,
            .rows = g.rows,
            .container = try refs.node(g.container),
        } },
        .grid_cell_abs => |g| .{ .grid_cell_abs = .{
            .x = g.x,
            .y = g.y,
            .w = g.w,
            .h = g.h,
            .container = try refs.node(g.container),
        } },
        .split => |s| try make_split_refs(refs, s.container, s.axis, s.ratios, s.children),
    };
}

/// Replace the constraints of every listed node, in workspace g. Everything is
/// resolved first, so a bad id anywhere changes nothing. Unknown node ids are
/// skipped: an arranger's table may mention a window that just closed. Keyed
/// containers the layout no longer mentions are destroyed.
pub fn apply(wm: *WM, g: *Graph, spec: LayoutSpec, arena: std.mem.Allocator) !void {
    const refs: Refs = .{ .wm = wm, .g = g };
    const Resolved = struct { node: *Node, cons: []Constraint };
    var resolved: std.ArrayListUnmanaged(Resolved) = .empty;
    for (spec.nodes) |ns| {
        const n = switch (ns.id) {
            .id => |i| wm.get_node_by_id(i) orelse continue,
            .key => |k| g.keyed(k) orelse try refs.create(k),
        };
        const specs = ns.constraints orelse &.{};
        const cons = try arena.alloc(Constraint, specs.len);
        for (specs, cons) |cs, *out| out.* = try resolve(refs, cs);
        try resolved.append(arena, .{ .node = n, .cons = cons });
    }
    for (resolved.items) |r| {
        const owner = r.node.owner_graph orelse continue;
        try owner.replace_constraints(r.node, r.cons);
    }
    try sweep(g, spec, arena);
}

fn mark(used: *std.AutoHashMapUnmanaged(u32, void), a: Allocator, r: protocol.Ref) !void {
    if (r == .key) try used.put(a, r.key, {});
}

/// Destroy g's keyed containers that spec doesn't mention.
fn sweep(g: *Graph, spec: LayoutSpec, arena: Allocator) !void {
    var used: std.AutoHashMapUnmanaged(u32, void) = .empty;
    for (spec.nodes) |ns| {
        try mark(&used, arena, ns.id);
        for (ns.constraints orelse &.{}) |cs| switch (cs) {
            inline .left_of,
            .right_of,
            .above,
            .below,
            .align_left,
            .align_top,
            .align_right,
            .align_bottom,
            .equal_width,
            .equal_height,
            => |o| try mark(&used, arena, o.other),
            .grid_cell => |c| try mark(&used, arena, c.container),
            .grid_cell_abs => |c| try mark(&used, arena, c.container),
            .split => |s| {
                try mark(&used, arena, s.container);
                for (s.children) |c| try mark(&used, arena, c);
            },
            else => {},
        };
    }
    try drop_keyed(g, &used, arena);
}

/// Destroy g's keyed containers, except those in keep.
pub fn drop_keyed(g: *Graph, keep: ?*const std.AutoHashMapUnmanaged(u32, void), arena: Allocator) !void {
    var doomed: std.ArrayListUnmanaged(*Node) = .empty;
    for (g.nodes.items) |n| {
        const k = n.key orelse continue;
        if (n.dead) continue;
        if (keep) |set| if (set.contains(k)) continue;
        try doomed.append(arena, n);
    }
    // Collected first: remove_node shrinks g.nodes.
    for (doomed.items) |n| g.remove_node(n);
}

// ---- get_layout ----
fn id_of(wm: *WM, n: *Node) Value {
    return if (wm.get_id_for_node(n)) |id| .{ .integer = id } else .nil;
}

/// Tiled nodes, minus workspaces that have no preview (hidden siblings).
fn listed(n: *const Node) bool {
    return !n.floating and !(n.content == .workspace and n.preview_window == null);
}

fn type_name(n: *const Node) []const u8 {
    return switch (n.content) {
        .window => "window",
        .empty => "empty",
        .workspace => "workspace",
    };
}

fn constraint_value(wm: *WM, a: std.mem.Allocator, con: Constraint) !Value {
    return .{ .map = switch (con) {
        inline .left_of,
        .right_of,
        .above,
        .below,
        .align_left,
        .align_top,
        .align_right,
        .align_bottom,
        .equal_width,
        .equal_height,
        => |o, tag| try a.dupe(Value.Field, &.{
            .{ .key = "type", .value = .{ .str = @tagName(tag) } },
            .{ .key = "other", .value = id_of(wm, o) },
        }),
        inline .fixed_x, .fixed_y, .fixed_width, .fixed_height => |v, tag| try a.dupe(Value.Field, &.{
            .{ .key = "type", .value = .{ .str = @tagName(tag) } },
            .{ .key = "value", .value = .{ .integer = v } },
        }),
        .fixed_ratio => |v| try a.dupe(Value.Field, &.{
            .{ .key = "type", .value = .{ .str = "fixed_ratio" } },
            .{ .key = "value", .value = .{ .number = v } },
        }),
        .grid_cell => |g| try a.dupe(Value.Field, &.{
            .{ .key = "type", .value = .{ .str = "grid_cell" } },
            .{ .key = "col", .value = .{ .integer = g.col } },
            .{ .key = "row", .value = .{ .integer = g.row } },
            .{ .key = "cols", .value = .{ .integer = g.cols } },
            .{ .key = "rows", .value = .{ .integer = g.rows } },
            .{ .key = "container", .value = id_of(wm, g.container) },
        }),
        .grid_cell_abs => |g| try a.dupe(Value.Field, &.{
            .{ .key = "type", .value = .{ .str = "grid_cell_abs" } },
            .{ .key = "x", .value = .{ .integer = g.x } },
            .{ .key = "y", .value = .{ .integer = g.y } },
            .{ .key = "w", .value = .{ .integer = g.w } },
            .{ .key = "h", .value = .{ .integer = g.h } },
            .{ .key = "container", .value = id_of(wm, g.container) },
        }),
        .split => |s| blk: {
            const ratios = try a.alloc(Value, s.count);
            const children = try a.alloc(Value, s.count);
            for (0..s.count) |k| {
                ratios[k] = .{ .number = s.ratios[k] };
                children[k] = id_of(wm, s.children[k]);
            }
            break :blk try a.dupe(Value.Field, &.{
                .{ .key = "type", .value = .{ .str = "split" } },
                .{ .key = "axis", .value = .{ .str = if (s.axis == .horizontal) "h" else "v" } },
                .{ .key = "count", .value = .{ .integer = s.count } },
                .{ .key = "container", .value = id_of(wm, s.container) },
                .{ .key = "ratios", .value = .{ .list = ratios } },
                .{ .key = "children", .value = .{ .list = children } },
            });
        },
    } };
}

/// The current workspace's tiled layout: nodes (with constraints, parent
/// and position within it), windows, focused and root.
pub fn describe(wm: *WM, a: std.mem.Allocator) !Value {
    const g = wm.current_graph;

    const Parent = struct { node: *Node, idx: u32 };
    var parents: std.AutoHashMapUnmanaged(*Node, Parent) = .empty;
    for (g.nodes.items) |n| {
        if (!listed(n)) continue;
        for (n.constraints.items) |con| {
            if (con != .split) continue;
            for (0..con.split.count) |k| {
                try parents.put(a, con.split.children[k], .{ .node = n, .idx = @intCast(k + 1) });
            }
        }
    }

    var nodes: std.ArrayListUnmanaged(Value) = .empty;
    var windows: std.ArrayListUnmanaged(Value) = .empty;
    var root: Value = .nil;
    for (g.nodes.items) |n| {
        if (!listed(n)) continue;
        const id = wm.get_id_for_node(n) orelse continue;
        const p = parents.get(n);

        const cons = try a.alloc(Value, n.constraints.items.len);
        for (n.constraints.items, cons) |con, *v| v.* = try constraint_value(wm, a, con);

        try nodes.append(a, .{ .map = try a.dupe(Value.Field, &.{
            .{ .key = "id", .value = .{ .integer = id } },
            .{ .key = "type", .value = .{ .str = type_name(n) } },
            .{ .key = "x", .value = .{ .integer = n.x } },
            .{ .key = "y", .value = .{ .integer = n.y } },
            .{ .key = "width", .value = .{ .integer = n.width } },
            .{ .key = "height", .value = .{ .integer = n.height } },
            .{ .key = "parent", .value = if (p) |pp| id_of(wm, pp.node) else .nil },
            .{ .key = "parent_idx", .value = if (p) |pp| .{ .integer = pp.idx } else .nil },
            .{ .key = "constraints", .value = .{ .list = cons } },
        }) });
        if (n.content != .empty) try windows.append(a, .{ .integer = id });
        if (root == .nil and n.content == .empty and p == null) root = .{ .integer = id };
    }

    return .{ .map = try a.dupe(Value.Field, &.{
        .{ .key = "nodes", .value = .{ .list = nodes.items } },
        .{ .key = "windows", .value = .{ .list = windows.items } },
        .{ .key = "focused", .value = if (wm.focused) |f| id_of(wm, f) else .nil },
        .{ .key = "root", .value = root },
    }) };
}

// ---- print_graph ----
fn print_graph_to_buf(wm: *WM, buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, g: *graph_mod.Graph, depth: u32) !void {
    var ind = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer ind.deinit(allocator);
    for (0..depth) |_| ind.appendSlice(allocator, "  ") catch {};

    try buf.print(allocator, "{s}Graph [level={}, number={}]\n\n", .{
        ind.items, g.id.level, g.id.number,
    });

    for (g.nodes.items) |node| {
        const type_str: []const u8 = switch (node.content) {
            .window => "window",
            .empty => "empty",
            .workspace => "workspace",
        };
        const id = wm.get_id_for_node(node) orelse 0;
        try buf.print(allocator, "{s}  [{d}] {s} x={} y={} w={} h={} floating={}\n", .{
            ind.items,   id,            type_str,
            node.x,      node.y,        node.width,
            node.height, node.floating,
        });
    }

    try buf.print(allocator, "{s}\n", .{ind.items});

    for (g.nodes.items) |node| {
        const from_id = wm.get_id_for_node(node) orelse 0;
        for (node.constraints.items) |con| {
            switch (con) {
                .left_of, .right_of, .above, .below, .align_left, .align_top, .align_right, .align_bottom, .equal_width, .equal_height => {
                    const other: *graph_mod.Node = switch (con) {
                        .left_of => |o| o,
                        .right_of => |o| o,
                        .above => |o| o,
                        .below => |o| o,
                        .align_left => |o| o,
                        .align_top => |o| o,
                        .align_right => |o| o,
                        .align_bottom => |o| o,
                        .equal_width => |o| o,
                        .equal_height => |o| o,
                        else => unreachable,
                    };
                    const to_id = wm.get_id_for_node(other) orelse 0;
                    const name: []const u8 = switch (con) {
                        .left_of => "left_of",
                        .right_of => "right_of",
                        .above => "above",
                        .below => "below",
                        .align_left => "align_left",
                        .align_top => "align_top",
                        .align_right => "align_right",
                        .align_bottom => "align_bottom",
                        .equal_width => "equal_width",
                        .equal_height => "equal_height",
                        else => unreachable,
                    };
                    try buf.print(allocator, "{s}  [{d}] --{s}--> [{d}]\n", .{
                        ind.items, from_id, name, to_id,
                    });
                },
                .grid_cell => |gc| {
                    const cont_id = wm.get_id_for_node(gc.container) orelse 0;
                    try buf.print(allocator, "{s}  [{d}] --grid_cell(col={},row={},cols={},rows={})--> [{d}]\n", .{
                        ind.items, from_id, gc.col, gc.row, gc.cols, gc.rows, cont_id,
                    });
                },
                .grid_cell_abs => |gc| {
                    const cont_id = wm.get_id_for_node(gc.container) orelse 0;
                    try buf.print(allocator, "{s}  [{d}] --grid_cell_abs(x={},y={},w={},h={})--> [{d}]\n", .{
                        ind.items, from_id, gc.x, gc.y, gc.w, gc.h, cont_id,
                    });
                },
                .split => |s| {
                    const cont_id = wm.get_id_for_node(s.container) orelse 0;
                    try buf.print(allocator, "{s}  [{d}] --split({s},count={}", .{
                        ind.items,                               from_id,
                        if (s.axis == .horizontal) "h" else "v", s.count,
                    });
                    for (0..s.count) |i| {
                        try buf.print(allocator, ",r={d:.3}", .{s.ratios[i]});
                    }
                    try buf.print(allocator, ")--> [{d}]\n", .{cont_id});
                },
                .fixed_width => |w| try buf.print(allocator, "{s}  [{d}] fixed_width={}\n", .{ ind.items, from_id, w }),
                .fixed_height => |h| try buf.print(allocator, "{s}  [{d}] fixed_height={}\n", .{ ind.items, from_id, h }),
                .fixed_x => |x| try buf.print(allocator, "{s}  [{d}] fixed_x={}\n", .{ ind.items, from_id, x }),
                .fixed_y => |y| try buf.print(allocator, "{s}  [{d}] fixed_y={}\n", .{ ind.items, from_id, y }),
                .fixed_ratio => |r| try buf.print(allocator, "{s}  [{d}] fixed_ratio={d:.3}\n", .{ ind.items, from_id, r }),
            }
        }
    }

    try buf.print(allocator, "{s}\n", .{ind.items});

    for (g.nodes.items) |node| {
        if (node.content == .workspace) {
            try print_graph_to_buf(wm, buf, allocator, node.content.workspace, depth + 1);
        }
    }
}

/// A readable dump of the current workspace and everything nested in it.
pub fn print(wm: *WM, a: std.mem.Allocator) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    try print_graph_to_buf(wm, &buf, a, wm.current_graph, 0);
    return buf.items;
}

pub fn get_layout(wm: *WM, _: void, arena: Allocator) !Value {
    return describe(wm, arena);
}

pub fn set_layout(wm: *WM, args: Args(.set_layout), arena: Allocator) !Value {
    try apply(wm, wm.current_graph, args.layout, arena);
    return .nil;
}

pub fn print_graph(wm: *WM, _: void, arena: Allocator) !Value {
    return .{ .str = try print(wm, arena) };
}
