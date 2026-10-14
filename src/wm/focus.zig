const std = @import("std");
const WM = @import("core.zig").WM;
const graph_mod = @import("graph");
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;

pub fn rebuild_focus_edges(wm: *WM) !void {
    wm.current_graph.focus_edges.clearRetainingCapacity();
    const nodes = wm.current_graph.nodes.items;
    for (nodes) |a| {
        const a_win = switch (a.content) {
            .window => true,
            .workspace => a.preview_window != null,
            .empty => false,
        };
        if (!a_win) continue;
        if (a.hidden) continue;
        const ax = a.x;
        const ay = a.y;
        const aw: i32 = @intCast(a.width);
        const ah: i32 = @intCast(a.height);
        const a_cx = ax + @divTrunc(aw, 2);
        const a_cy = ay + @divTrunc(ah, 2);
        for (nodes) |b| {
            if (a == b) continue;
            const b_win = switch (b.content) {
                .window => true,
                .workspace => b.preview_window != null,
                .empty => false,
            };
            if (!b_win) continue;
            if (b.hidden) continue;
            const bx = b.x;
            const by = b.y;
            const bw: i32 = @intCast(b.width);
            const bh: i32 = @intCast(b.height);
            const b_cx = bx + @divTrunc(bw, 2);
            const b_cy = by + @divTrunc(bh, 2);
            const dx = b_cx - a_cx;
            const dy = b_cy - a_cy;
            if (dx == 0 and dy == 0) continue;

            const abs_dx = @abs(dx);
            const abs_dy = @abs(dy);

            // Always add the primary direction
            if (abs_dx >= abs_dy) {
                if (dx < 0) try wm.current_graph.add_focus_edge(a, b, .Left) else try wm.current_graph.add_focus_edge(a, b, .Right);
            } else {
                if (dy < 0) try wm.current_graph.add_focus_edge(a, b, .Up) else try wm.current_graph.add_focus_edge(a, b, .Down);
            }

            // Also add secondary direction whenever both components are non-trivial
            // (secondary component is at least 25% of primary)
            if (abs_dx > 0 and abs_dy > 0) {
                const minor = @min(abs_dx, abs_dy);
                const major = @max(abs_dx, abs_dy);
                if (minor * 4 >= major) {
                    // secondary
                    if (abs_dx < abs_dy) {
                        if (dx < 0) try wm.current_graph.add_focus_edge(a, b, .Left) else try wm.current_graph.add_focus_edge(a, b, .Right);
                    } else {
                        if (dy < 0) try wm.current_graph.add_focus_edge(a, b, .Up) else try wm.current_graph.add_focus_edge(a, b, .Down);
                    }
                }
            }
        }
    }
}

pub fn find_focus_target(wm: *WM, comptime dir: Direction) ?*Node {
    const focused = wm.focused orelse return null;
    const fx = focused.x;
    const fy = focused.y;
    const fw: i32 = @intCast(focused.width);
    const fh: i32 = @intCast(focused.height);

    var best: ?*Node = null;
    var best_dist: i32 = std.math.maxInt(i32);
    var best_overlap: i32 = std.math.minInt(i32);

    for (wm.current_graph.focus_edges.items) |edge| {
        if (edge.from != focused) continue;
        if (edge.dir != dir) continue;

        const node = edge.to;
        const nx = node.x;
        const ny = node.y;
        const nw: i32 = @intCast(node.width);
        const nh: i32 = @intCast(node.height);

        const dist: i32 = switch (dir) {
            .Left => fx - (nx + nw),
            .Right => nx - (fx + fw),
            .Up => fy - (ny + nh),
            .Down => ny - (fy + fh),
        };

        const overlap: i32 = switch (dir) {
            .Left, .Right => @min(fy + fh, ny + nh) - @max(fy, ny),
            .Up, .Down => @min(fx + fw, nx + nw) - @max(fx, nx),
        };

        // Prefer: 1) any overlap over no overlap, 2) closer, 3) more overlap
        const has_overlap = overlap > 0;
        const best_has_overlap = best_overlap > 0;

        if (best == null or
            (has_overlap and !best_has_overlap) or
            (has_overlap == best_has_overlap and dist < best_dist) or
            (has_overlap == best_has_overlap and dist == best_dist and overlap > best_overlap))
        {
            best = node;
            best_dist = dist;
            best_overlap = overlap;
        }
    }
    return best;
}

fn focus_via_edges(wm: *WM, comptime dir: Direction) void {
    if (find_focus_target(wm, dir)) |target| set_focus(wm, target);
}

pub fn focus_left(wm: *WM) anyerror!void {
    focus_via_edges(wm, .Left);
}
pub fn focus_right(wm: *WM) anyerror!void {
    focus_via_edges(wm, .Right);
}
pub fn focus_up(wm: *WM) anyerror!void {
    focus_via_edges(wm, .Up);
}
pub fn focus_down(wm: *WM) anyerror!void {
    focus_via_edges(wm, .Down);
}

pub fn set_focus(wm: *WM, node: *Node) void {
    wm.journal.set(wm, "focused", node);
    wm.focus_dirty = true;
    if (!wm.is_shown(node)) return; // nothing on screen to focus (yet)
    const g = wm.current_graph;
    wm.focus_clock += 1;
    node.focus_serial = wm.focus_clock;
    node.urgent = false;

    // Snap pan to bring the focused window into view
    if (!node.floating and g == wm.visible_graph) {
        const work = wm.get_work_area();
        const screen_w = @as(i32, @intCast(wm.screen_width));
        const screen_h = @as(i32, @intCast(wm.screen_height));
        const win_w = @as(i32, @intCast(node.width));
        const win_h = @as(i32, @intCast(node.height));
        var pan_changed = false;

        const vis_left = node.x - g.pan_x;
        if (vis_left < work.x) {
            g.pan_x = node.x - work.x;
            pan_changed = true;
        } else if (vis_left + win_w > screen_w) {
            g.pan_x = node.x + win_w - screen_w;
            pan_changed = true;
        }

        const vis_top = node.y - g.pan_y;
        if (vis_top < work.y) {
            g.pan_y = node.y - work.y;
            pan_changed = true;
        } else if (vis_top + win_h > screen_h) {
            g.pan_y = node.y + win_h - screen_h;
            pan_changed = true;
        }

        if (g.pan_x < 0) {
            g.pan_x = 0;
            pan_changed = true;
        }
        if (g.pan_y < 0) {
            g.pan_y = 0;
            pan_changed = true;
        }
    }

    // Focus changes border colors (and which window counts as fullscreen-focused).
    wm.flush(g) catch {};
    if (wm.get_id_for_node(node)) |id| wm.call_arranger(g, "focus", id, null);
}

pub fn top_left_window(wm: *WM) ?*Node {
    var best: ?*Node = null;
    for (wm.current_graph.nodes.items) |node| {
        const node_win = switch (node.content) {
            .window => true,
            .workspace => node.preview_window != null,
            .empty => false,
        };
        if (!node_win) continue;
        const b = best orelse {
            best = node;
            continue;
        };
        if (node.y < b.y or (node.y == b.y and node.x < b.x)) best = node;
    }
    return best;
}

pub fn clear_focus(wm: *WM) void {
    wm.journal.set(wm, "focused", null);
    wm.focus_dirty = true;
}
