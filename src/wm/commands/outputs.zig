const std = @import("std");
const core = @import("../core.zig");
const command = @import("../command.zig");
const output = @import("../output.zig");
const util = @import("util.zig");
const graph = @import("graph");
const workspaces = @import("workspaces.zig");
const WM = core.WM;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

pub fn get_outputs(wm: *WM, _: void, arena: Allocator) !Value {
    const out = try arena.alloc(Value, wm.outputs.items.len);
    for (wm.outputs.items, out) |o, *v| {
        v.* = .{ .map = try arena.dupe(Value.Field, &.{
            .{ .key = "id", .value = .{ .integer = o.id } },
            .{ .key = "x", .value = .{ .integer = o.rect.x } },
            .{ .key = "y", .value = .{ .integer = o.rect.y } },
            .{ .key = "width", .value = .{ .integer = o.rect.width } },
            .{ .key = "height", .value = .{ .integer = o.rect.height } },
            .{ .key = "focused", .value = .{ .boolean = o == wm.output } },
        }) };
    }
    return .{ .list = out };
}

pub fn focus_output(wm: *WM, args: Args(.focus_output), _: Allocator) !Value {
    const to = output.neighbour(wm, wm.output, args.dir) orelse return .nil;
    output.focus(wm, to);
    output.focus_something(wm);
    return .nil;
}

/// Onto the workspace showing on the neighbouring output; focus stays where it is.
pub fn send_to_output(wm: *WM, args: Args(.send_to_output), _: Allocator) !Value {
    const n = try util.node(wm, args.id);
    const from = output.of(wm, n.owner_graph orelse return error.NotInGraph) orelse return .nil;
    const to = output.neighbour(wm, from, args.dir) orelse return .nil;
    if (n.floating) { // same place relative to the output
        n.x += to.rect.x - from.rect.x;
        n.y += to.rect.y - from.rect.y;
    }
    try wm.send_to_workspace(args.id, output.visible(wm, to));
    return .nil;
}

/// What every monitor shows, in one call: for bars, one per monitor.
pub fn get_output_states(wm: *WM, _: void, arena: Allocator) !Value {
    const focused_output = wm.output;
    const out = try arena.alloc(Value, wm.outputs.items.len);
    for (wm.outputs.items, out) |o, *v| {
        const prev = output.borrow(wm, o);
        defer output.give_back(wm, prev);
        v.* = try state_of(wm, o, o == focused_output, arena);
    }
    return .{ .list = out };
}

/// o's state, with its navigation fields loaded into wm.
fn state_of(wm: *WM, o: *output.Output, is_focused: bool, arena: Allocator) !Value {
    const g = wm.current_graph;

    var positions: std.ArrayListUnmanaged(Value) = .empty;
    for (try workspaces.states(wm, arena), 1..) |s, pos| {
        if (s != .inactive) try positions.append(arena, .{ .integer = @intCast(pos) });
    }
    const current = try workspaces.current_position(wm);

    var count: usize = 0;
    for (g.nodes.items) |n| {
        if (n.content != .empty and wm.get_id_for_node(n) != null) count += 1;
    }

    // Its focused window: the real one on the focused monitor, the last one elsewhere.
    const f: ?*graph.Node = if (is_focused)
        wm.focused
    else if (o.last_focused) |id| wm.get_node_by_id(id) else null;
    const win = if (f) |n| (if (n.owner_graph == g) n else null) else null;

    return .{ .map = try arena.dupe(Value.Field, &.{
        .{ .key = "id", .value = .{ .integer = o.id } },
        .{ .key = "x", .value = .{ .integer = o.rect.x } },
        .{ .key = "y", .value = .{ .integer = o.rect.y } },
        .{ .key = "focused", .value = .{ .boolean = is_focused } },
        .{ .key = "workspaces", .value = .{ .list = positions.items } },
        .{ .key = "current", .value = if (current) |c| .{ .integer = @intCast(c) } else .nil },
        .{ .key = "level", .value = .{ .integer = g.id.level } },
        .{ .key = "layout", .value = try util.text(arena, g.arranger_name) },
        .{ .key = "windows", .value = .{ .integer = @intCast(count) } },
        .{ .key = "window", .value = if (win) |n| try window_value(wm, n, arena) else .nil },
    }) };
}

fn window_value(wm: *WM, n: *graph.Node, arena: Allocator) !Value {
    return .{ .map = try arena.dupe(Value.Field, &.{
        .{ .key = "id", .value = util.id_value(wm, n) },
        .{ .key = "title", .value = try util.text(arena, n.info.title()) },
        .{ .key = "class", .value = try util.text(arena, n.info.class()) },
    }) };
}
