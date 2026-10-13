const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const Node = graph_mod.Node;
const Constraint = graph_mod.Constraint;

// ---- set_layout: parse everything, then apply ----
const Entry = struct { node: *Node, cons: []const Constraint };

/// Read field name of the table on top of the stack.
fn field_int(lua: *Lua, name: [:0]const u8, comptime T: type) !T {
    _ = lua.getField(-1, name);
    defer lua.pop(1);
    const v = lua.toInteger(-1) catch return error.ExpectedInteger;
    return std.math.cast(T, v) orelse error.OutOfRange;
}

fn field_num(lua: *Lua, name: [:0]const u8) !f32 {
    _ = lua.getField(-1, name);
    defer lua.pop(1);
    return @floatCast(lua.toNumber(-1) catch return error.ExpectedNumber);
}

fn field_node(lua: *Lua, name: [:0]const u8) !*Node {
    const id = try field_int(lua, name, u32);
    return util.global_wm.get_node_by_id(id) orelse error.InvalidNode;
}

fn parse_split(lua: *Lua) !Constraint {
    _ = lua.getField(-1, "axis");
    const horizontal = std.mem.eql(u8, lua.toString(-1) catch "h", "h");
    lua.pop(1);
    const count = try field_int(lua, "count", u8);
    if (count == 0 or count > 16) return error.InvalidSplitCount;

    var s: @FieldType(Constraint, "split") = .{
        .container = try field_node(lua, "container"),
        .axis = if (horizontal) .horizontal else .vertical,
        .count = count,
        .ratios = undefined,
        .children = undefined,
    };

    _ = lua.getField(-1, "ratios");
    for (0..count) |k| {
        _ = lua.getIndexRaw(-1, @intCast(k + 1));
        const r = lua.toNumber(-1) catch {
            lua.pop(2);
            return error.ExpectedNumber;
        };
        lua.pop(1);
        s.ratios[k] = @floatCast(r);
    }
    lua.pop(1);

    _ = lua.getField(-1, "children");
    for (0..count) |k| {
        _ = lua.getIndexRaw(-1, @intCast(k + 1));
        const id = lua.toInteger(-1) catch 0;
        lua.pop(1);
        s.children[k] = util.global_wm.get_node_by_id(std.math.cast(u32, id) orelse 0) orelse {
            lua.pop(1);
            return error.InvalidChildId;
        };
    }
    lua.pop(1);
    return .{ .split = s };
}

/// The constraint table on top of the stack.
fn parse_constraint(lua: *Lua) !Constraint {
    _ = lua.getField(-1, "type");
    const name = lua.toString(-1) catch {
        lua.pop(1);
        return error.ExpectedType;
    };
    const tag = std.meta.stringToEnum(std.meta.Tag(Constraint), name);
    lua.pop(1);
    return switch (tag orelse return error.UnknownConstraintType) {
        .fixed_x => .{ .fixed_x = try field_int(lua, "value", i32) },
        .fixed_y => .{ .fixed_y = try field_int(lua, "value", i32) },
        .fixed_width => .{ .fixed_width = try field_int(lua, "value", u32) },
        .fixed_height => .{ .fixed_height = try field_int(lua, "value", u32) },
        .fixed_ratio => .{ .fixed_ratio = try field_num(lua, "value") },
        .grid_cell => .{ .grid_cell = .{
            .col = try field_int(lua, "col", u32),
            .row = try field_int(lua, "row", u32),
            .cols = try field_int(lua, "cols", u32),
            .rows = try field_int(lua, "rows", u32),
            .container = try field_node(lua, "container"),
        } },
        .grid_cell_abs => .{ .grid_cell_abs = .{
            .x = try field_int(lua, "x", i32),
            .y = try field_int(lua, "y", i32),
            .w = try field_int(lua, "w", u32),
            .h = try field_int(lua, "h", u32),
            .container = try field_node(lua, "container"),
        } },
        .split => try parse_split(lua),
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
        => |t| @unionInit(Constraint, @tagName(t), try field_node(lua, "other")),
    };
}

/// layout.nodes, as (node, new constraints) pairs. Unknown ids are skipped
fn parse_layout(lua: *Lua, a: std.mem.Allocator, out: *std.ArrayListUnmanaged(Entry)) !void {
    _ = lua.getField(1, "nodes");
    defer lua.pop(1);
    if (lua.typeOf(-1) != .table) return error.ExpectedNodesArray;

    const n: usize = @intCast(lua.lenRaw(-1));
    for (1..n + 1) |i| {
        _ = lua.getIndexRaw(-1, @intCast(i));
        defer lua.pop(1);
        const id = field_int(lua, "id", u32) catch continue;
        const node = util.global_wm.get_node_by_id(id) orelse continue;

        var cons: std.ArrayListUnmanaged(Constraint) = .empty;
        _ = lua.getField(-1, "constraints");
        defer lua.pop(1);
        if (lua.typeOf(-1) == .table) {
            const m: usize = @intCast(lua.lenRaw(-1));
            for (1..m + 1) |k| {
                _ = lua.getIndexRaw(-1, @intCast(k));
                defer lua.pop(1);
                try cons.append(a, try parse_constraint(lua));
            }
        }
        try out.append(a, .{ .node = node, .cons = cons.items });
    }
}

pub fn l_set_layout(lua: *Lua) i32 {
    lua.checkType(1, .table);
    var arena = std.heap.ArenaAllocator.init(util.global_wm.allocator);
    var entries: std.ArrayListUnmanaged(Entry) = .empty;

    // Nothing has changed if this fails.
    parse_layout(lua, arena.allocator(), &entries) catch |err| {
        arena.deinit();
        util.raise_with(lua, "set_layout: ", @errorName(err));
    };
    for (entries.items) |e| {
        const g = e.node.owner_graph orelse continue;
        g.replace_constraints(e.node, e.cons) catch {
            arena.deinit();
            util.luaL_error_str(lua, "set_layout: out of memory");
        };
    }
    arena.deinit();
    return 0;
}

// ---- get_layout and print_graph ----
fn print_graph_to_buf(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, g: *graph_mod.Graph, depth: u32) void {
    var ind = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer ind.deinit(allocator);
    for (0..depth) |_| ind.appendSlice(allocator, "  ") catch {};

    buf.print(allocator, "{s}Graph [level={}, number={}]\n\n", .{
        ind.items, g.id.level, g.id.number,
    }) catch {};

    for (g.nodes.items) |node| {
        const type_str: []const u8 = switch (node.content) {
            .window => "window",
            .empty => "empty",
            .workspace => "workspace",
        };
        const id = util.global_wm.get_id_for_node(node) orelse 0;
        buf.print(allocator, "{s}  [{d}] {s} x={} y={} w={} h={} floating={}\n", .{
            ind.items,   id,            type_str,
            node.x,      node.y,        node.width,
            node.height, node.floating,
        }) catch {};
    }

    buf.print(allocator, "{s}\n", .{ind.items}) catch {};

    for (g.nodes.items) |node| {
        const from_id = util.global_wm.get_id_for_node(node) orelse 0;
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
                    const to_id = util.global_wm.get_id_for_node(other) orelse 0;
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
                    buf.print(allocator, "{s}  [{d}] --{s}--> [{d}]\n", .{
                        ind.items, from_id, name, to_id,
                    }) catch {};
                },
                .grid_cell => |gc| {
                    const cont_id = util.global_wm.get_id_for_node(gc.container) orelse 0;
                    buf.print(allocator, "{s}  [{d}] --grid_cell(col={},row={},cols={},rows={})--> [{d}]\n", .{
                        ind.items, from_id, gc.col, gc.row, gc.cols, gc.rows, cont_id,
                    }) catch {};
                },
                .grid_cell_abs => |gc| {
                    const cont_id = util.global_wm.get_id_for_node(gc.container) orelse 0;
                    buf.print(allocator, "{s}  [{d}] --grid_cell_abs(x={},y={},w={},h={})--> [{d}]\n", .{
                        ind.items, from_id, gc.x, gc.y, gc.w, gc.h, cont_id,
                    }) catch {};
                },
                .split => |s| {
                    const cont_id = util.global_wm.get_id_for_node(s.container) orelse 0;
                    buf.print(allocator, "{s}  [{d}] --split({s},count={}", .{
                        ind.items,                               from_id,
                        if (s.axis == .horizontal) "h" else "v", s.count,
                    }) catch {};
                    for (0..s.count) |i| {
                        buf.print(allocator, ",r={d:.3}", .{s.ratios[i]}) catch {};
                    }
                    buf.print(allocator, ")--> [{d}]\n", .{cont_id}) catch {};
                },
                .fixed_width => |w| buf.print(allocator, "{s}  [{d}] fixed_width={}\n", .{ ind.items, from_id, w }) catch {},
                .fixed_height => |h| buf.print(allocator, "{s}  [{d}] fixed_height={}\n", .{ ind.items, from_id, h }) catch {},
                .fixed_x => |x| buf.print(allocator, "{s}  [{d}] fixed_x={}\n", .{ ind.items, from_id, x }) catch {},
                .fixed_y => |y| buf.print(allocator, "{s}  [{d}] fixed_y={}\n", .{ ind.items, from_id, y }) catch {},
                .fixed_ratio => |r| buf.print(allocator, "{s}  [{d}] fixed_ratio={d:.3}\n", .{ ind.items, from_id, r }) catch {},
            }
        }
    }

    buf.print(allocator, "{s}\n", .{ind.items}) catch {};

    for (g.nodes.items) |node| {
        if (node.content == .workspace) {
            print_graph_to_buf(buf, allocator, node.content.workspace, depth + 1);
        }
    }
}

pub fn l_get_layout(lua: *Lua) i32 {
    const g = util.global_wm.current_graph;

    lua.checkStack(20) catch {};

    var parent_map = std.AutoHashMapUnmanaged(*graph_mod.Node, *graph_mod.Node){};
    defer parent_map.deinit(util.global_wm.allocator);
    var parent_idx_map = std.AutoHashMapUnmanaged(*graph_mod.Node, u8){};
    defer parent_idx_map.deinit(util.global_wm.allocator);

    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content == .workspace and node.preview_window == null) continue;
        for (node.constraints.items) |con| {
            if (con == .split) {
                for (0..con.split.count) |i| {
                    parent_map.put(util.global_wm.allocator, con.split.children[i], node) catch {};
                    parent_idx_map.put(util.global_wm.allocator, con.split.children[i], @intCast(i + 1)) catch {};
                }
            }
        }
    }

    lua.newTable();
    lua.newTable();

    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content == .workspace and node.preview_window == null) continue;
        const id = util.global_wm.get_id_for_node(node) orelse continue;

        lua.checkStack(30) catch {};

        lua.newTable();

        lua.pushInteger(@intCast(id));
        lua.setField(-2, "id");

        _ = switch (node.content) {
            .window => lua.pushString("window"),
            .empty => lua.pushString("empty"),
            .workspace => lua.pushString("workspace"),
        };
        lua.setField(-2, "type");

        lua.pushInteger(node.x);
        lua.setField(-2, "x");
        lua.pushInteger(node.y);
        lua.setField(-2, "y");
        lua.pushInteger(node.width);
        lua.setField(-2, "width");
        lua.pushInteger(node.height);
        lua.setField(-2, "height");

        if (parent_map.get(node)) |pn| {
            if (util.global_wm.get_id_for_node(pn)) |pid| {
                lua.pushInteger(@intCast(pid));
                lua.setField(-2, "parent");
                lua.pushInteger(@intCast(parent_idx_map.get(node) orelse 1));
                lua.setField(-2, "parent_idx");
            } else {
                lua.pushNil();
                lua.setField(-2, "parent");
                lua.pushNil();
                lua.setField(-2, "parent_idx");
            }
        } else {
            lua.pushNil();
            lua.setField(-2, "parent");
            lua.pushNil();
            lua.setField(-2, "parent_idx");
        }

        lua.newTable();
        for (node.constraints.items, 0..) |con, ci| {
            lua.checkStack(20) catch {};
            lua.newTable();
            switch (con) {
                .fixed_x => |v| {
                    _ = lua.pushString("fixed_x");
                    lua.setField(-2, "type");
                    lua.pushInteger(v);
                    lua.setField(-2, "value");
                },
                .fixed_y => |v| {
                    _ = lua.pushString("fixed_y");
                    lua.setField(-2, "type");
                    lua.pushInteger(v);
                    lua.setField(-2, "value");
                },
                .fixed_width => |v| {
                    _ = lua.pushString("fixed_width");
                    lua.setField(-2, "type");
                    lua.pushInteger(v);
                    lua.setField(-2, "value");
                },
                .fixed_height => |v| {
                    _ = lua.pushString("fixed_height");
                    lua.setField(-2, "type");
                    lua.pushInteger(v);
                    lua.setField(-2, "value");
                },
                .fixed_ratio => |v| {
                    _ = lua.pushString("fixed_ratio");
                    lua.setField(-2, "type");
                    lua.pushNumber(v);
                    lua.setField(-2, "value");
                },
                .grid_cell => |gc| {
                    _ = lua.pushString("grid_cell");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(gc.col));
                    lua.setField(-2, "col");
                    lua.pushInteger(@intCast(gc.row));
                    lua.setField(-2, "row");
                    lua.pushInteger(@intCast(gc.cols));
                    lua.setField(-2, "cols");
                    lua.pushInteger(@intCast(gc.rows));
                    lua.setField(-2, "rows");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(gc.container) orelse 0));
                    lua.setField(-2, "container");
                },
                .grid_cell_abs => |gc| {
                    _ = lua.pushString("grid_cell_abs");
                    lua.setField(-2, "type");
                    lua.pushInteger(gc.x);
                    lua.setField(-2, "x");
                    lua.pushInteger(gc.y);
                    lua.setField(-2, "y");
                    lua.pushInteger(gc.w);
                    lua.setField(-2, "w");
                    lua.pushInteger(gc.h);
                    lua.setField(-2, "h");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(gc.container) orelse 0));
                    lua.setField(-2, "container");
                },
                .split => |s| {
                    _ = lua.pushString("split");
                    lua.setField(-2, "type");
                    _ = lua.pushString(if (s.axis == .horizontal) "h" else "v");
                    lua.setField(-2, "axis");
                    lua.pushInteger(@intCast(s.count));
                    lua.setField(-2, "count");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(s.container) orelse 0));
                    lua.setField(-2, "container");
                    lua.newTable();
                    for (0..s.count) |ri| {
                        lua.pushNumber(s.ratios[ri]);
                        lua.setIndexRaw(-2, @intCast(ri + 1));
                    }
                    lua.setField(-2, "ratios");
                    lua.newTable();
                    for (0..s.count) |ci2| {
                        lua.pushInteger(@intCast(util.global_wm.get_id_for_node(s.children[ci2]) orelse 0));
                        lua.setIndexRaw(-2, @intCast(ci2 + 1));
                    }
                    lua.setField(-2, "children");
                },
                .left_of => |o| {
                    _ = lua.pushString("left_of");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .right_of => |o| {
                    _ = lua.pushString("right_of");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .above => |o| {
                    _ = lua.pushString("above");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .below => |o| {
                    _ = lua.pushString("below");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .align_left => |o| {
                    _ = lua.pushString("align_left");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .align_top => |o| {
                    _ = lua.pushString("align_top");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .align_right => |o| {
                    _ = lua.pushString("align_right");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .align_bottom => |o| {
                    _ = lua.pushString("align_bottom");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .equal_width => |o| {
                    _ = lua.pushString("equal_width");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
                .equal_height => |o| {
                    _ = lua.pushString("equal_height");
                    lua.setField(-2, "type");
                    lua.pushInteger(@intCast(util.global_wm.get_id_for_node(o) orelse 0));
                    lua.setField(-2, "other");
                },
            }
            lua.setIndexRaw(-2, @intCast(ci + 1));
        }
        lua.setField(-2, "constraints");

        lua.pushValue(-1);
        lua.setIndexRaw(-3, @intCast(id));
        lua.pop(1);
    }

    // nodes array
    lua.newTable();
    var ni: usize = 0;
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content == .workspace and node.preview_window == null) continue;
        const id = util.global_wm.get_id_for_node(node) orelse continue;
        lua.pushInteger(@intCast(id));
        _ = lua.getTable(-3);
        if (lua.typeOf(-1) == .nil) {
            lua.pop(1);
            continue;
        }
        lua.setIndexRaw(-2, @intCast(ni + 1));
        ni += 1;
    }
    lua.setField(-3, "nodes");

    lua.setField(-2, "by_id");

    // windows array
    lua.newTable();
    var wi: usize = 0;
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content == .workspace and node.preview_window == null) continue;
        switch (node.content) {
            .window, .workspace => {
                if (util.global_wm.get_id_for_node(node)) |id| {
                    lua.pushInteger(@intCast(id));
                    lua.setIndexRaw(-2, @intCast(wi + 1));
                    wi += 1;
                }
            },
            else => {},
        }
    }
    lua.setField(-2, "windows");

    if (util.global_wm.focused) |f| {
        if (util.global_wm.get_id_for_node(f)) |fid| {
            lua.pushInteger(@intCast(fid));
        } else {
            lua.pushNil();
        }
    } else {
        lua.pushNil();
    }
    lua.setField(-2, "focused");

    // root
    var root_id: u32 = 0;
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        if (node.content != .empty) continue;
        if (parent_map.get(node) == null) {
            if (util.global_wm.get_id_for_node(node)) |id| {
                root_id = id;
                break;
            }
        }
    }
    if (root_id != 0) {
        lua.pushInteger(@intCast(root_id));
    } else {
        lua.pushNil();
    }
    lua.setField(-2, "root");

    return 1;
}

pub fn l_print_graph(lua: *Lua) i32 {
    var buf = std.ArrayListUnmanaged(u8){ .items = &.{}, .capacity = 0 };
    defer buf.deinit(util.global_wm.allocator);
    print_graph_to_buf(&buf, util.global_wm.allocator, util.global_wm.current_graph, 0);
    _ = lua.pushString(buf.items);
    return 1;
}
