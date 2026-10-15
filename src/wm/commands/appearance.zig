const std = @import("std");
const graph_mod = @import("graph");
const core = @import("../core.zig");
const command = @import("../command.zig");
const util = @import("util.zig");
const types = @import("types");
const WM = core.WM;
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;
const Value = command.Value;
const Gaps = command.Gaps;
const Args = util.Args;
const Allocator = std.mem.Allocator;

/// Repaint at commit: the scene picks up color changes, and a rollback repaints the old ones.
fn repaint(wm: *WM) !void {
    try wm.flush(wm.current_graph);
}

fn workspace_node(wm: *WM, id: command.NodeId) ?*Node {
    const n = wm.get_node_by_id(id) orelse return null;
    return if (n.content == .workspace) n else null;
}

// ---- default colors and width ----
pub fn set_default_focused_border_color(wm: *WM, args: Args(.set_default_focused_border_color), _: Allocator) !Value {
    wm.default_border_color_focused = args.color;
    try repaint(wm);
    return .nil;
}

pub fn set_default_unfocused_border_color(wm: *WM, args: Args(.set_default_unfocused_border_color), _: Allocator) !Value {
    wm.default_border_color_unfocused = args.color;
    try repaint(wm);
    return .nil;
}

pub fn set_default_urgent_border_color(wm: *WM, args: Args(.set_default_urgent_border_color), _: Allocator) !Value {
    wm.default_border_color_urgent = args.color;
    try repaint(wm);
    return .nil;
}

pub fn set_border_width(wm: *WM, args: Args(.set_border_width), _: Allocator) !Value {
    wm.border_width = @intCast(args.width);
    wm.backend.publish_frame_extents(args.width);
    wm.relayout();
    return .nil;
}

// ---- per-node colors ----
pub fn set_node_focused_border_color(wm: *WM, args: Args(.set_node_focused_border_color), _: Allocator) !Value {
    wm.journal.set(try util.node(wm, args.id), "border_color_focused", args.color);
    try repaint(wm);
    return .nil;
}

pub fn set_node_unfocused_border_color(wm: *WM, args: Args(.set_node_unfocused_border_color), _: Allocator) !Value {
    wm.journal.set(try util.node(wm, args.id), "border_color_unfocused", args.color);
    try repaint(wm);
    return .nil;
}

pub fn clear_node_focused_border_color(wm: *WM, args: Args(.clear_node_focused_border_color), _: Allocator) !Value {
    wm.journal.set(try util.node(wm, args.id), "border_color_focused", null);
    try repaint(wm);
    return .nil;
}

pub fn clear_node_unfocused_border_color(wm: *WM, args: Args(.clear_node_unfocused_border_color), _: Allocator) !Value {
    wm.journal.set(try util.node(wm, args.id), "border_color_unfocused", null);
    try repaint(wm);
    return .nil;
}

pub fn set_node_border_side_color(wm: *WM, args: Args(.set_node_border_side_color), _: Allocator) !Value {
    const n = try util.node(wm, args.id);
    const color: ?u32 = args.color;
    switch (args.side) {
        .top => wm.journal.set(n, "border_color_top", color),
        .bottom => wm.journal.set(n, "border_color_bottom", color),
        .left => wm.journal.set(n, "border_color_left", color),
        .right => wm.journal.set(n, "border_color_right", color),
    }
    try repaint(wm);
    return .nil;
}

pub fn clear_node_border_side_colors(wm: *WM, args: Args(.clear_node_border_side_colors), _: Allocator) !Value {
    const n = try util.node(wm, args.id);
    wm.journal.set(n, "border_color_top", null);
    wm.journal.set(n, "border_color_bottom", null);
    wm.journal.set(n, "border_color_left", null);
    wm.journal.set(n, "border_color_right", null);
    try repaint(wm);
    return .nil;
}

pub fn get_node_border_side_colors(wm: *WM, args: Args(.get_node_border_side_colors), arena: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    var fields: std.ArrayListUnmanaged(Value.Field) = .empty;
    const sides = .{
        .{ "top", n.border_color_top },
        .{ "bottom", n.border_color_bottom },
        .{ "left", n.border_color_left },
        .{ "right", n.border_color_right },
    };
    inline for (sides) |s| {
        if (s[1]) |color| try fields.append(arena, .{ .key = s[0], .value = .{ .integer = color } });
    }
    return .{ .map = fields.items };
}

pub fn set_border_side_colors_focused_only(wm: *WM, args: Args(.set_border_side_colors_focused_only), _: Allocator) !Value {
    wm.border_side_colors_focused_only = args.enabled;
    try repaint(wm);
    return .nil;
}

pub fn set_indicator_color(wm: *WM, args: Args(.set_indicator_color), _: Allocator) !Value {
    wm.indicator_color = args.color;
    try repaint(wm);
    return .nil;
}

pub fn set_node_indicator(wm: *WM, args: Args(.set_node_indicator), _: Allocator) !Value {
    const n = try util.node(wm, args.id);
    const side: types.Side = switch (args.side) {
        inline else => |s| @field(types.Side, @tagName(s)),
    };
    wm.journal.set(n, "indicator_side", side);
    try repaint(wm);
    return .nil;
}

pub fn clear_node_indicator(wm: *WM, args: Args(.clear_node_indicator), _: Allocator) !Value {
    wm.journal.set(try util.node(wm, args.id), "indicator_side", null);
    try repaint(wm);
    return .nil;
}

// ---- gaps ----
fn set_graph_gaps(g: *Graph, gaps: Gaps) void {
    g.set(g, "gap_inner_h", gaps.inner_h);
    g.set(g, "gap_inner_v", gaps.inner_v);
    g.set(g, "gap_outer_h", gaps.outer_h);
    g.set(g, "gap_outer_v", gaps.outer_v);
}

fn set_gaps_recursive(g: *Graph, gaps: Gaps) void {
    set_graph_gaps(g, gaps);
    for (g.nodes.items) |n| {
        if (n.content == .workspace) set_gaps_recursive(n.content.workspace, gaps);
    }
}

pub fn set_gaps(wm: *WM, args: Args(.set_gaps), _: Allocator) !Value {
    const gaps: Gaps = .{ .inner_h = args.inner_h, .inner_v = args.inner_v, .outer_h = args.outer_h, .outer_v = args.outer_v };
    wm.default_gap_inner_h = gaps.inner_h;
    wm.default_gap_inner_v = gaps.inner_v;
    wm.default_gap_outer_h = gaps.outer_h;
    wm.default_gap_outer_v = gaps.outer_v;
    set_gaps_recursive(&wm.graph, gaps);
    wm.relayout();
    return .nil;
}

pub fn set_gaps_workspace(wm: *WM, args: Args(.set_gaps_workspace), _: Allocator) !Value {
    const n = workspace_node(wm, args.id) orelse return .nil;
    const sub = n.content.workspace;
    set_graph_gaps(sub, .{ .inner_h = args.inner_h, .inner_v = args.inner_v, .outer_h = args.outer_h, .outer_v = args.outer_v });
    if (sub == wm.current_graph) wm.relayout();
    return .nil;
}

// ---- previews ----
/// Repaint the visible previews in the current workspace after a global style change.
fn repaint_previews(wm: *WM) void {
    for (wm.current_graph.nodes.items) |n| {
        if (n.content == .workspace and !n.hidden) wm.repaint_preview(n);
    }
}

pub fn set_preview_colors(wm: *WM, args: Args(.set_preview_colors), _: Allocator) !Value {
    wm.set_preview_colors(args.bg, args.win_bg, args.border, args.text);
    repaint_previews(wm);
    return .nil;
}

pub fn set_preview_colors_workspace(wm: *WM, args: Args(.set_preview_colors_workspace), _: Allocator) !Value {
    const n = workspace_node(wm, args.id) orelse return .nil;
    const sub = n.content.workspace;
    sub.set(sub, "preview_bg", args.bg);
    sub.set(sub, "preview_win_bg", args.win_bg);
    sub.set(sub, "preview_border", args.border);
    sub.set(sub, "preview_text", args.text);
    wm.repaint_preview(n);
    return .nil;
}

pub fn set_preview_font(wm: *WM, args: Args(.set_preview_font), _: Allocator) !Value {
    wm.set_preview_font(args.name);
    repaint_previews(wm);
    return .nil;
}

pub fn set_preview_font_workspace(wm: *WM, args: Args(.set_preview_font_workspace), _: Allocator) !Value {
    const n = workspace_node(wm, args.id) orelse return .nil;
    n.content.workspace.set_preview_font(args.name);
    wm.repaint_preview(n);
    return .nil;
}

pub fn set_preview_max_icon_size(wm: *WM, args: Args(.set_preview_max_icon_size), _: Allocator) !Value {
    wm.set_preview_max_icon_size(args.size);
    repaint_previews(wm);
    return .nil;
}

// ---- frames ----
pub fn set_argb_frames(wm: *WM, args: Args(.set_argb_frames), _: Allocator) !Value {
    wm.argb_frames = args.enabled;
    return .nil;
}

pub fn force_rgb_frames(wm: *WM, args: Args(.force_rgb_frames), _: Allocator) !Value {
    const owned = try wm.allocator.dupe(u8, args.class_name);
    errdefer wm.allocator.free(owned);
    try wm.rgb_frame_classes.append(wm.allocator, owned);
    return .nil;
}
