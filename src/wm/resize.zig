const std = @import("std");
const graph_mod = @import("graph");
const output = @import("output.zig");
const groups = @import("groups.zig");
const Graph = graph_mod.Graph;
const WM = @import("core.zig").WM;
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;

pub fn resize_vertical_edge(wm: *WM, edge_x: i32, delta: i32, floating: bool) !bool {
    return vertical_in(wm, groups.active(wm), edge_x, delta, floating);
}

pub fn resize_horizontal_edge(wm: *WM, edge_y: i32, delta: i32, floating: bool) !bool {
    return horizontal_in(wm, groups.active(wm), edge_y, delta, floating);
}

fn vertical_in(wm: *WM, g: *Graph, edge_x: i32, delta: i32, floating: bool) anyerror!bool {
    if (g.lock_vertical_resize) return false;
    const work = output.work_area_of(wm, g);
    const work_left: i32 = work.x;
    const work_right: i32 = work.x + @as(i32, @intCast(work.width));

    if (g.is_group and !floating) {
        // On the group's border: it's the group's own edge, moved in its parent.
        if (edge_x <= work_left or edge_x >= work_right) {
            const gn = g.parent_node.?;
            if (gn.floating) return false;
            const outer = gn.owner_graph.?;
            const e = if (edge_x <= work_left) gn.x else gn.x + @as(i32, @intCast(gn.width));
            return vertical_in(wm, outer, e, delta, false);
        }
    } else {
        const in_virtual = g.virtual_width > wm.screen_width;
        // block resizing edges that touch the screen boundary
        if (!in_virtual) {
            if (edge_x <= work_left) return false;
            if (edge_x >= work_right) return false;
        }
    }
    const tol: i32 = 1;
    for (g.nodes.items) |node| {
        if ((node.content == .empty and node.key == null) or node.floating != floating) continue;
        const right: i32 = node.x + @as(i32, @intCast(node.width));
        if (@abs(right - edge_x) <= tol) {
            if (@as(i32, @intCast(node.width)) + delta < 2 * wm.border_width + 10) return false;
        } else if (@abs(node.x - edge_x) <= tol) {
            if (@as(i32, @intCast(node.width)) - delta < 2 * wm.border_width + 10) return false;
        }
    }
    var changed = false;
    for (g.nodes.items) |node| {
        if ((node.content == .empty and node.key == null) or node.floating != floating) continue;
        const right: i32 = node.x + @as(i32, @intCast(node.width));
        if (@abs(right - edge_x) <= tol) {
            node.width = @intCast(@as(i32, @intCast(node.width)) + delta);
            changed = true;
        } else if (@abs(node.x - edge_x) <= tol) {
            node.x += delta;
            node.width = @intCast(@as(i32, @intCast(node.width)) - delta);
            changed = true;
        }
    }
    if (changed) groups.refit(wm, g);
    return changed;
}

fn horizontal_in(wm: *WM, g: *Graph, edge_y: i32, delta: i32, floating: bool) anyerror!bool {
    if (g.lock_horizontal_resize) return false;
    const work = output.work_area_of(wm, g);
    const work_top: i32 = work.y;
    const work_bottom: i32 = work.y + @as(i32, @intCast(work.height));

    if (g.is_group and !floating) {
        // On the group's border: it's the group's own edge, moved in its parent.
        if (edge_y <= work_top or edge_y >= work_bottom) {
            const gn = g.parent_node.?;
            if (gn.floating) return false;
            const outer = gn.owner_graph.?;
            const e = if (edge_y <= work_top) gn.y else gn.y + @as(i32, @intCast(gn.height));
            return horizontal_in(wm, outer, e, delta, false);
        }
    } else {
        const in_virtual = g.virtual_height > wm.screen_height;
        // block resizing edges that touch the screen boundary
        if (!in_virtual) {
            if (edge_y <= work_top) return false;
            if (edge_y >= work_bottom) return false;
        }
    }
    const tol: i32 = 1;
    for (g.nodes.items) |node| {
        if ((node.content == .empty and node.key == null) or node.floating != floating) continue;
        const bottom: i32 = node.y + @as(i32, @intCast(node.height));
        if (@abs(bottom - edge_y) <= tol) {
            if (@as(i32, @intCast(node.height)) + delta < 2 * wm.border_width + 10) return false;
        } else if (@abs(node.y - edge_y) <= tol) {
            if (@as(i32, @intCast(node.height)) - delta < 2 * wm.border_width + 10) return false;
        }
    }
    var changed = false;
    for (g.nodes.items) |node| {
        if ((node.content == .empty and node.key == null) or node.floating != floating) continue;
        const bottom: i32 = node.y + @as(i32, @intCast(node.height));
        if (@abs(bottom - edge_y) <= tol) {
            node.height = @intCast(@as(i32, @intCast(node.height)) + delta);
            changed = true;
        } else if (@abs(node.y - edge_y) <= tol) {
            node.y += delta;
            node.height = @intCast(@as(i32, @intCast(node.height)) - delta);
            changed = true;
        }
    }
    if (changed) groups.refit(wm, g);
    return changed;
}

pub fn resize_edge(wm: *WM, node: *Node, dir: Direction, delta: i32) !void {
    const f = node.floating;
    switch (dir) {
        .Left => _ = try wm.resize_vertical_edge(node.x, -delta, f),
        .Right => _ = try wm.resize_vertical_edge(node.x + @as(i32, @intCast(node.width)), delta, f),
        .Up => _ = try wm.resize_horizontal_edge(node.y, -delta, f),
        .Down => _ = try wm.resize_horizontal_edge(node.y + @as(i32, @intCast(node.height)), delta, f),
    }
}

pub fn resize_corner(wm: *WM, node: *Node, delta_x: i32, delta_y: i32) !void {
    const f = node.floating;
    if (delta_x != 0) _ = try wm.resize_vertical_edge(node.x + @as(i32, @intCast(node.width)), delta_x, f);
    if (delta_y != 0) _ = try wm.resize_horizontal_edge(node.y + @as(i32, @intCast(node.height)), delta_y, f);
}

/// After a resize by hand: constraints take on the new geometry, in the
/// current workspace and every group in it.
pub fn sync_constraints_from_geometry(wm: *WM) void {
    sync_graph(wm.current_graph);
    var it = groups.Nodes.all(wm.current_graph);
    while (it.next()) |n| {
        if (n.content == .group) sync_graph(n.content.group);
    }
}

fn sync_graph(g: *Graph) void {
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        for (node.constraints.items, 0..) |con, i| {
            var new = con;
            switch (new) {
                .fixed_x => |*v| v.* = node.x,
                .fixed_y => |*v| v.* = node.y,
                .fixed_width => |*v| v.* = node.width,
                .fixed_height => |*v| v.* = node.height,
                .split => |*s| {
                    const cont = s.container;
                    if (cont.width == 0 and cont.height == 0) continue;
                    var ratio_sum: f32 = 0;
                    for (0..s.count) |k| {
                        const child = s.children[k];
                        const ratio: f32 = if (s.axis == .horizontal)
                            @as(f32, @floatFromInt(child.width)) / @as(f32, @floatFromInt(cont.width))
                        else
                            @as(f32, @floatFromInt(child.height)) / @as(f32, @floatFromInt(cont.height));
                        s.ratios[k] = @max(0.01, ratio);
                        ratio_sum += s.ratios[k];
                    }
                    if (ratio_sum > 0) {
                        for (0..s.count) |k| s.ratios[k] /= ratio_sum;
                    }
                },
                else => continue,
            }
            if (!std.meta.eql(new, con)) g.change_constraint_at(node, i, new);
        }
    }
}
