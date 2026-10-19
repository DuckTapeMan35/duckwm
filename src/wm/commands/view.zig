const std = @import("std");
const graph_mod = @import("graph");
const core = @import("../core.zig");
const command = @import("../command.zig");
const scene = @import("../scene.zig");
const util = @import("util.zig");
const WM = core.WM;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

// ---- screen and work area ----
pub fn screen_width(wm: *WM, _: void, _: Allocator) !Value {
    return .{ .integer = wm.screen_width };
}

pub fn screen_height(wm: *WM, _: void, _: Allocator) !Value {
    return .{ .integer = wm.screen_height };
}

pub fn get_work_area(wm: *WM, _: void, arena: Allocator) !Value {
    const w = wm.get_work_area();
    return .{ .multi = try arena.dupe(Value, &.{
        .{ .integer = w.x },
        .{ .integer = w.y },
        .{ .integer = w.width },
        .{ .integer = w.height },
    }) };
}

// ---- pan and virtual size (current workspace) ----
pub fn set_pan(wm: *WM, args: Args(.set_pan), _: Allocator) !Value {
    const g = wm.current_graph;
    g.set(g, "pan_x", args.x);
    g.set(g, "pan_y", args.y);
    try wm.flush(g);
    return .nil;
}

pub fn pan_by(wm: *WM, args: Args(.pan_by), _: Allocator) !Value {
    const g = wm.current_graph;
    g.set(g, "pan_x", g.pan_x + args.dx);
    g.set(g, "pan_y", g.pan_y + args.dy);
    try wm.flush(g);
    return .nil;
}

pub fn get_pan(wm: *WM, _: void, arena: Allocator) !Value {
    return .{ .multi = try arena.dupe(Value, &.{
        .{ .integer = wm.current_graph.pan_x },
        .{ .integer = wm.current_graph.pan_y },
    }) };
}

pub fn set_virtual_size(wm: *WM, args: Args(.set_virtual_size), _: Allocator) !Value {
    const g = wm.current_graph;
    g.set(g, "virtual_width", args.width);
    g.set(g, "virtual_height", args.height);
    return .nil;
}

pub fn set_pan_disabled(wm: *WM, args: Args(.set_pan_disabled), _: Allocator) !Value {
    const g = wm.current_graph;
    g.set(g, "pan_disabled", args.disabled);
    return .nil;
}

pub fn set_lock_horizontal_resize(wm: *WM, args: Args(.set_lock_horizontal_resize), _: Allocator) !Value {
    const g = wm.current_graph;
    g.set(g, "lock_horizontal_resize", args.locked);
    return .nil;
}

pub fn set_lock_vertical_resize(wm: *WM, args: Args(.set_lock_vertical_resize), _: Allocator) !Value {
    const g = wm.current_graph;
    g.set(g, "lock_vertical_resize", args.locked);
    return .nil;
}

// ---- resizing ----
fn direction(d: command.Dir) graph_mod.Direction {
    return switch (d) {
        .left => .Left,
        .right => .Right,
        .up => .Up,
        .down => .Down,
    };
}

pub fn resize_edge(wm: *WM, args: Args(.resize_edge), _: Allocator) !Value {
    try wm.resize_edge(try util.node(wm, args.id), direction(args.direction), args.delta);
    return .nil;
}

pub fn resize_corner(wm: *WM, args: Args(.resize_corner), _: Allocator) !Value {
    try wm.resize_corner(try util.node(wm, args.id), args.dx, args.dy);
    return .nil;
}

pub fn resize_focused_edge(wm: *WM, args: Args(.resize_focused_edge), _: Allocator) !Value {
    if (wm.focused) |n| try wm.resize_edge(n, direction(args.direction), args.delta);
    return .nil;
}

pub fn resize_focused_corner(wm: *WM, args: Args(.resize_focused_corner), _: Allocator) !Value {
    if (wm.focused) |n| try wm.resize_corner(n, args.dx, args.dy);
    return .nil;
}

pub fn set_zoom(wm: *WM, args: Args(.set_zoom), _: Allocator) !Value {
    if (!std.math.isFinite(args.zoom) or args.zoom < 0 or args.zoom > 1) return error.InvalidZoom;
    wm.current_graph.zoom = args.zoom;
    wm.relayout();
    return .nil;
}

/// The zoom in effect: 0 (fit) comes back as the factor it works out to.
pub fn get_zoom(wm: *WM, _: void, _: Allocator) !Value {
    return .{ .number = scene.zoom_of(wm, wm.current_graph) };
}
