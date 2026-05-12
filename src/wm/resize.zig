const std = @import("std");
const c = @import("c.zig").c;
const WM = @import("core.zig").WM;
const graph_mod = @import("graph");
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;

const gap_from_wm: fn(*WM) i32 = struct {
    fn gap(wm: *WM) i32 {
        return 2 * @as(i32, @intCast(wm.border_width));
    }
}.gap;

pub fn find_edge_at(wm: *WM, root_x: i32, root_y: i32, threshold: i32) ?struct { is_vertical: bool, coordinate: i32 } {
    const gap = gap_from_wm(wm);
    const nodes = wm.graph.nodes.items;
    for (nodes) |a| {
        switch (a.content) { .window => {}, else => continue }
        for (nodes) |b| {
            if (a == b) continue;
            switch (b.content) { .window => {}, else => continue }

            // Vertical edge: a's right edge + gap == b's left edge
            const a_right = a.x + @as(i32, @intCast(a.width));
            if (a_right + gap == b.x) {
                const y_overlap_start = @max(a.y, b.y);
                const y_overlap_end = @min(a.y + @as(i32, @intCast(a.height)), b.y + @as(i32, @intCast(b.height)));
                if (y_overlap_end > y_overlap_start) {
                    if (@abs(root_x - a_right) <= threshold and root_y >= y_overlap_start and root_y <= y_overlap_end) {
                        return .{ .is_vertical = true, .coordinate = a_right };
                    }
                }
            }

            // Horizontal edge: a's bottom edge + gap == b's top edge
            const a_bottom = a.y + @as(i32, @intCast(a.height));
            if (a_bottom + gap == b.y) {
                const x_overlap_start = @max(a.x, b.x);
                const x_overlap_end = @min(a.x + @as(i32, @intCast(a.width)), b.x + @as(i32, @intCast(b.width)));
                if (x_overlap_end > x_overlap_start) {
                    if (@abs(root_y - a_bottom) <= threshold and root_x >= x_overlap_start and root_x <= x_overlap_end) {
                        return .{ .is_vertical = false, .coordinate = a_bottom };
                    }
                }
            }
        }
    }
    return null;
}

pub fn find_corner_at(wm: *WM, root_x: i32, root_y: i32, threshold: i32) ?struct { v_edge: i32, h_edge: i32 } {
    const gap = gap_from_wm(wm);
    const nodes = wm.graph.nodes.items;
    for (nodes) |a| {
        if (a.content != .window) continue;
        for (nodes) |b| {
            if (a == b) continue;
            if (b.content != .window) continue;
            const a_right = a.x + @as(i32, @intCast(a.width));
            if (a_right + gap == b.x) {
                const vy_start = @max(a.y, b.y);
                const vy_end = @min(a.y + @as(i32, @intCast(a.height)), b.y + @as(i32, @intCast(b.height)));
                if (vy_end > vy_start) {
                    for (nodes) |cw| {
                        if (cw.content != .window) continue;
                        for (nodes) |dw| {
                            if (cw == dw) continue;
                            if (dw.content != .window) continue;
                            const cw_bottom = cw.y + @as(i32, @intCast(cw.height));
                            if (cw_bottom + gap == dw.y) {
                                const hx_start = @max(cw.x, dw.x);
                                const hx_end = @min(cw.x + @as(i32, @intCast(cw.width)), dw.x + @as(i32, @intCast(dw.width)));
                                if (hx_end > hx_start) {
                                    if (cw_bottom >= vy_start and cw_bottom <= vy_end and
                                        a_right >= hx_start and a_right <= hx_end)
                                    {
                                        if (@abs(root_x - a_right) <= threshold and @abs(root_y - cw_bottom) <= threshold) {
                                            return .{ .v_edge = a_right, .h_edge = cw_bottom };
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return null;
}

pub fn resize_vertical_edge(wm: *WM, edge_x: i32, delta: i32) !bool {
    const gap = gap_from_wm(wm);
    // first pass: check limits
    for (wm.graph.nodes.items) |node| {
        const right: i32 = node.x + @as(i32, @intCast(node.width));
        if (right == edge_x) { // left of the edge
            if (@as(i32, @intCast(node.width)) + delta < 2*wm.border_width + 10) return false;
        } else if (node.x == edge_x + gap) { // right of the edge (gap-aware)
            if (@as(i32, @intCast(node.width)) - delta < 2*wm.border_width + 10) return false;
        }
    }
    // second pass: apply changes
    var changed = false;
    for (wm.graph.nodes.items) |node| {
        const right: i32 = node.x + @as(i32, @intCast(node.width));
        if (right == edge_x) {
            node.width = @intCast(@as(i32, @intCast(node.width)) + delta);
            changed = true;
        } else if (node.x == edge_x + gap) {
            node.x += delta;
            node.width = @intCast(@as(i32, @intCast(node.width)) - delta);
            changed = true;
        }
    }
    if (changed) try wm.flush(&wm.graph);
    return changed;
}

pub fn resize_horizontal_edge(wm: *WM, edge_y: i32, delta: i32) !bool {
    const gap = gap_from_wm(wm);
    // first pass: check limits
    for (wm.graph.nodes.items) |node| {
        const bottom: i32 = node.y + @as(i32, @intCast(node.height));
        if (bottom == edge_y) { // above the edge
            if (@as(i32, @intCast(node.height)) + delta < 2*wm.border_width + 10) return false;
        } else if (node.y == edge_y + gap) { // below the edge (gap-aware)
            if (@as(i32, @intCast(node.height)) - delta < 2*wm.border_width + 10) return false;
        }
    }
    // second pass: apply changes
    var changed = false;
    for (wm.graph.nodes.items) |node| {
        const bottom: i32 = node.y + @as(i32, @intCast(node.height));
        if (bottom == edge_y) {
            node.height = @intCast(@as(i32, @intCast(node.height)) + delta);
            changed = true;
        } else if (node.y == edge_y + gap) {
            node.y += delta;
            node.height = @intCast(@as(i32, @intCast(node.height)) - delta);
            changed = true;
        }
    }
    if (changed) try wm.flush(&wm.graph);
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
