const std = @import("std");
const c = @import("c").c;
const WM = @import("core.zig").WM;
const graph_mod = @import("graph");
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;

pub fn resize_vertical_edge(wm: *WM, edge_x: i32, delta: i32) !bool {
    if (wm.current_graph.lock_vertical_resize) return false;

    const in_virtual = wm.current_graph.virtual_width > wm.screen_width;
    const work = wm.get_work_area();
    const work_left: i32 = work.x;
    const work_right: i32 = work.x + @as(i32, @intCast(work.width));

    // Block resizing edges that touch the screen boundary
    if (!in_virtual) {
        if (edge_x <= work_left) return false;
        if (edge_x >= work_right) return false;
    }

    for (wm.current_graph.nodes.items) |node| {
        if (node.content == .empty) continue;
        const right: i32 = node.x + @as(i32, @intCast(node.width));
        if (right == edge_x) {
            if (@as(i32, @intCast(node.width)) + delta < 2*wm.border_width + 10) return false;
        } else if (node.x == edge_x) {
            if (@as(i32, @intCast(node.width)) - delta < 2*wm.border_width + 10) return false;
        }
    }
    var changed = false;
    for (wm.current_graph.nodes.items) |node| {
        if (node.content == .empty) continue;
        const right: i32 = node.x + @as(i32, @intCast(node.width));
        if (right == edge_x) {
            node.width = @intCast(@as(i32, @intCast(node.width)) + delta);
            changed = true;
        } else if (node.x == edge_x) {
            node.x += delta;
            node.width = @intCast(@as(i32, @intCast(node.width)) - delta);
            changed = true;
        }
    }
    return changed;
}

pub fn resize_horizontal_edge(wm: *WM, edge_y: i32, delta: i32) !bool {
    if (wm.current_graph.lock_horizontal_resize) return false;

    const in_virtual = wm.current_graph.virtual_height > wm.screen_height;
    const work = wm.get_work_area();
    const work_top: i32 = work.y;
    const work_bottom: i32 = work.y + @as(i32, @intCast(work.height));

    // Block resizing edges that touch the screen boundary
    if (!in_virtual) {
        if (edge_y <= work_top) return false;
        if (edge_y >= work_bottom) return false;
    }

    for (wm.current_graph.nodes.items) |node| {
        if (node.content == .empty) continue;
        const bottom: i32 = node.y + @as(i32, @intCast(node.height));
        if (bottom == edge_y) {
            if (@as(i32, @intCast(node.height)) + delta < 2*wm.border_width + 10) return false;
        } else if (node.y == edge_y) {
            if (@as(i32, @intCast(node.height)) - delta < 2*wm.border_width + 10) return false;
        }
    }
    var changed = false;
    for (wm.current_graph.nodes.items) |node| {
        if (node.content == .empty) continue;
        const bottom: i32 = node.y + @as(i32, @intCast(node.height));
        if (bottom == edge_y) {
            node.height = @intCast(@as(i32, @intCast(node.height)) + delta);
            changed = true;
        } else if (node.y == edge_y) {
            node.y += delta;
            node.height = @intCast(@as(i32, @intCast(node.height)) - delta);
            changed = true;
        }
    }
    return changed;
}

pub fn resize_edge(wm: *WM, node: *Node, dir: Direction, delta: i32) !void {
    switch (dir) {
        .Left  => _ = try wm.resize_vertical_edge(node.x, -delta),
        .Right => _ = try wm.resize_vertical_edge(node.x + @as(i32, @intCast(node.width)), delta),
        .Up    => _ = try wm.resize_horizontal_edge(node.y, -delta),
        .Down  => _ = try wm.resize_horizontal_edge(node.y + @as(i32, @intCast(node.height)), delta),
    }
}

pub fn resize_corner(wm: *WM, node: *Node, delta_x: i32, delta_y: i32) !void {
    if (delta_x != 0) _ = try wm.resize_vertical_edge(node.x + @as(i32, @intCast(node.width)), delta_x);
    if (delta_y != 0) _ = try wm.resize_horizontal_edge(node.y + @as(i32, @intCast(node.height)), delta_y);
}
