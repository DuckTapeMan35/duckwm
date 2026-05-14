const std = @import("std");
const c = @import("c").c;
const WM = @import("core.zig").WM;
const events_mod = @import("events.zig");
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

            const bx = b.x;
            const by = b.y;
            const bw: i32 = @intCast(b.width);
            const bh: i32 = @intCast(b.height);
            const b_cx = bx + @divTrunc(bw, 2);
            const b_cy = by + @divTrunc(bh, 2);

            const dx = b_cx - a_cx;
            const dy = b_cy - a_cy;

            if (dx == 0 and dy == 0) continue;

            if (@abs(dx) >= @abs(dy)) {
                if (dx < 0) {
                    try wm.current_graph.add_focus_edge(a, b, .Left);
                } else {
                    try wm.current_graph.add_focus_edge(a, b, .Right);
                }
            } else {
                if (dy < 0) {
                    try wm.current_graph.add_focus_edge(a, b, .Up);
                } else {
                    try wm.current_graph.add_focus_edge(a, b, .Down);
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
            .Left  => fx - (nx + nw),
            .Right => nx - (fx + fw),
            .Up    => fy - (ny + nh),
            .Down  => ny - (fy + fh),
        };

        const overlap: i32 = switch (dir) {
            .Left, .Right => @min(fy + fh, ny + nh) - @max(fy, ny),
            .Up,   .Down  => @min(fx + fw, nx + nw) - @max(fx, nx),
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

pub fn focus_left(wm: *WM)  anyerror!void { focus_via_edges(wm, .Left); }
pub fn focus_right(wm: *WM) anyerror!void { focus_via_edges(wm, .Right); }
pub fn focus_up(wm: *WM)    anyerror!void { focus_via_edges(wm, .Up); }
pub fn focus_down(wm: *WM)  anyerror!void { focus_via_edges(wm, .Down); }

pub fn set_focus(wm: *WM, node: *Node) void {
    wm.focused = node;
    const win = switch (node.content) {
        .window => |w| w,
        .workspace => node.preview_window orelse return,
        .empty => return,
    };
    // Focus the client window, not the frame
    _ = c.XSetInputFocus(wm.display, win, c.RevertToParent, c.CurrentTime);

    // Update frame borders (correctly iterates over current_graph)
    for (wm.current_graph.nodes.items) |n| {
        const n_win = switch (n.content) {
            .window => |w| w,
            .workspace => n.preview_window orelse continue,
            .empty => continue,
        };
        if (wm.frames.get(n_win)) |frame| {
            const color = if (n == node)
                n.border_color_focused orelse wm.default_border_color_focused
            else
                n.border_color_unfocused orelse wm.default_border_color_unfocused;
            _ = c.XSetWindowBorder(wm.display, frame, color);
        }
    }
    events_mod.update_net_active_window(wm, win);
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
        const b = best orelse { best = node; continue; };
        if (node.y < b.y or (node.y == b.y and node.x < b.x)) best = node;
    }
    return best;
}
