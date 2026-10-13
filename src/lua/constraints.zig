const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const Node = graph_mod.Node;
const Constraint = graph_mod.Constraint;

fn pair(lua: *Lua) struct { *Node, *Node } {
    const a = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node a");
    const b = util.node_arg(lua, 2) orelse util.luaL_error_str(lua, "invalid node b");
    return .{ a, b };
}

fn add(lua: *Lua, node: *Node, con: Constraint) void {
    const g = node.owner_graph orelse util.luaL_error_str(lua, "node is not in a graph");
    g.add_constraint(node, con) catch util.luaL_error_str(lua, "out of memory");
}

// ---- relations between two nodes ----

const Relation = enum { left_of, right_of, above, below, align_left, align_top, align_right, align_bottom, equal_width, equal_height };

fn relation(comptime r: Relation) fn (*Lua) i32 {
    return struct {
        fn f(lua: *Lua) i32 {
            const a, const b = pair(lua);
            add(lua, a, @unionInit(Constraint, @tagName(r), b));
            return 0;
        }
    }.f;
}

pub const l_left_of = relation(.left_of);
pub const l_right_of = relation(.right_of);
pub const l_above = relation(.above);
pub const l_below = relation(.below);
pub const l_align_left = relation(.align_left);
pub const l_align_top = relation(.align_top);
pub const l_align_right = relation(.align_right);
pub const l_align_bottom = relation(.align_bottom);
pub const l_equal_width = relation(.equal_width);
pub const l_equal_height = relation(.equal_height);

/// Same, for floats: also place a next to b first, so the solver starts
/// near the answer, and re-solve right away.
fn float_relation(comptime r: Relation) fn (*Lua) i32 {
    return struct {
        fn f(lua: *Lua) i32 {
            const a, const b = pair(lua);
            if (!a.floating) util.luaL_error_str(lua, "node is not floating");
            const wm = util.global_wm;
            const aw: i32 = @intCast(a.width);
            const ah: i32 = @intCast(a.height);
            const bw: i32 = @intCast(b.width);
            const bh: i32 = @intCast(b.height);
            const start: ?[2]i32 = switch (r) {
                .left_of => .{ b.x - aw, b.y },
                .right_of => .{ b.x + bw, b.y },
                .above => .{ b.x, b.y - ah },
                .below => .{ b.x, b.y + bh },
                else => null,
            };
            if (start) |p| {
                wm.journal.set(a, "x", p[0]);
                wm.journal.set(a, "y", p[1]);
            }
            add(lua, a, @unionInit(Constraint, @tagName(r), b));
            wm.relayout();
            return 0;
        }
    }.f;
}

pub const l_float_left_of = float_relation(.left_of);
pub const l_float_right_of = float_relation(.right_of);
pub const l_float_above = float_relation(.above);
pub const l_float_below = float_relation(.below);
pub const l_float_align_left = float_relation(.align_left);
pub const l_float_align_top = float_relation(.align_top);
pub const l_float_align_right = float_relation(.align_right);
pub const l_float_align_bottom = float_relation(.align_bottom);
pub const l_float_equal_width = float_relation(.equal_width);
pub const l_float_equal_height = float_relation(.equal_height);

pub fn l_float_clear_constraints(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    if (!node.floating) util.luaL_error_str(lua, "node is not floating");
    const g = node.owner_graph orelse return 0;
    g.replace_constraints(node, &.{}) catch util.luaL_error_str(lua, "out of memory");
    util.global_wm.relayout();
    return 0;
}

// ---- fixed values ----
pub fn l_fixed_width(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    const w = util.check_u32(lua, 2) orelse util.luaL_error_str(lua, "width must be non-negative");
    add(lua, node, .{ .fixed_width = w });
    return 0;
}

pub fn l_fixed_height(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    const h = util.check_u32(lua, 2) orelse util.luaL_error_str(lua, "height must be non-negative");
    add(lua, node, .{ .fixed_height = h });
    return 0;
}

pub fn l_fixed_x(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    add(lua, node, .{ .fixed_x = @intCast(lua.checkInteger(2)) });
    return 0;
}

pub fn l_fixed_y(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    add(lua, node, .{ .fixed_y = @intCast(lua.checkInteger(2)) });
    return 0;
}

pub fn l_fixed_ratio(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node");
    const ratio = lua.checkNumber(2);
    if (ratio <= 0.0) util.luaL_error_str(lua, "ratio must be positive");
    add(lua, node, .{ .fixed_ratio = @floatCast(ratio) });
    return 0;
}

// ---- containers ----
pub fn l_grid_cell(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node");
    const col = lua.checkInteger(2);
    const row = lua.checkInteger(3);
    const cols = lua.checkInteger(4);
    const rows = lua.checkInteger(5);
    const container = util.node_arg(lua, 6) orelse util.luaL_error_str(lua, "invalid container");
    if (cols <= 0 or rows <= 0) util.luaL_error_str(lua, "grid_cell: cols and rows must be positive");
    if (col < 0 or row < 0 or col >= cols or row >= rows) util.luaL_error_str(lua, "grid_cell: cell (col,row) out of range");
    add(lua, node, .{ .grid_cell = .{
        .col = @intCast(col),
        .row = @intCast(row),
        .cols = @intCast(cols),
        .rows = @intCast(rows),
        .container = container,
    } });
    return 0;
}

pub fn l_grid_cell_abs(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node");
    const x: i32 = @intCast(lua.checkInteger(2));
    const y: i32 = @intCast(lua.checkInteger(3));
    const w = util.check_u32(lua, 4) orelse util.luaL_error_str(lua, "width must be non-negative");
    const h = util.check_u32(lua, 5) orelse util.luaL_error_str(lua, "height must be non-negative");
    const container = util.node_arg(lua, 6) orelse util.luaL_error_str(lua, "invalid container");
    add(lua, node, .{ .grid_cell_abs = .{ .x = x, .y = y, .w = w, .h = h, .container = container } });
    return 0;
}

pub fn l_split(lua: *Lua) i32 {
    const container = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid container");
    const axis_str = lua.checkString(2);
    lua.checkType(3, .table);
    lua.checkType(4, .table);

    const len = lua.lenRaw(3);
    if (len == 0 or len > 16) util.luaL_error_str(lua, "split: need 1-16 children");
    if (lua.lenRaw(4) != len) util.luaL_error_str(lua, "split: ratios and children must have the same length");
    const count: u8 = @intCast(len);

    var con: Constraint = .{ .split = .{
        .container = container,
        .axis = if (std.mem.eql(u8, axis_str, "h")) .horizontal else .vertical,
        .count = count,
        .ratios = undefined,
        .children = undefined,
    } };
    for (0..count) |i| {
        _ = lua.getIndexRaw(3, @intCast(i + 1));
        const ratio = lua.toNumber(-1) catch util.luaL_error_str(lua, "split: ratios must be numbers");
        lua.pop(1);
        if (ratio <= 0.0) util.luaL_error_str(lua, "split: ratios must be positive");
        con.split.ratios[i] = @floatCast(ratio);

        _ = lua.getIndexRaw(4, @intCast(i + 1));
        const child = util.node_arg(lua, -1) orelse util.luaL_error_str(lua, "split: invalid child id");
        lua.pop(1);
        con.split.children[i] = child;
    }
    add(lua, container, con);
    return 0;
}

// ---- removal ----
pub fn l_clear_constraints(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    const g = node.owner_graph orelse return 0;
    g.replace_constraints(node, &.{}) catch util.luaL_error_str(lua, "out of memory");
    return 0;
}

pub fn l_remove_constraint(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse return 0;
    const tag = std.meta.stringToEnum(std.meta.Tag(Constraint), lua.checkString(2)) orelse
        util.luaL_error_str(lua, "remove_constraint: unknown constraint type");
    const g = node.owner_graph orelse return 0;
    var i: usize = 0;
    while (i < node.constraints.items.len) {
        if (node.constraints.items[i] == tag) g.remove_constraint_at(node, i) else i += 1;
    }
    return 0;
}
