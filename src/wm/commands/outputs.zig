const std = @import("std");
const core = @import("../core.zig");
const command = @import("../command.zig");
const output = @import("../output.zig");
const util = @import("util.zig");
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
