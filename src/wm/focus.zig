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
        const ax = a.x; const ay = a.y;
        const aw: i32 = @intCast(a.width); const ah: i32 = @intCast(a.height);
        const a_center_x = ax + @divTrunc(aw, 2);
        const a_center_y = ay + @divTrunc(ah, 2);

        for (nodes) |b| {
            if (a == b) continue;
            switch (b.content) { .window => {}, else => continue }
            const bx = b.x; const by = b.y;
            const bw: i32 = @intCast(b.width); const bh: i32 = @intCast(b.height);
            const b_center_x = bx + @divTrunc(bw, 2);
            const b_center_y = by + @divTrunc(bh, 2);

            const dx = b_center_x - a_center_x;
            const dy = b_center_y - a_center_y;

            // ── Left / Right ─────────────────────────────────
            if (@abs(dx) >= @abs(dy)) {
                const v_overlap = @min(ay + ah, by + bh) - @max(ay, by);
                if (v_overlap > 0) {
                    if (dx < 0)  {
                        try wm.current_graph.add_focus_edge(a, b, .Left);
                    }
                    else if (dx > 0) {
                        try wm.current_graph.add_focus_edge(a, b, .Right);
                    }
                }
            }
            // ── Up / Down ────────────────────────────────────
            else {
                const h_overlap = @min(ax + aw, bx + bw) - @max(ax, bx);
                if (h_overlap > 0) {
                    if (dy < 0)  {
                        try wm.current_graph.add_focus_edge(a, b, .Up);
                    }
                    else if (dy > 0)  {
                        try wm.current_graph.add_focus_edge(a, b, .Down);
                    }
                }
            }
        }
    }
}

pub fn find_focus_target(wm: *WM, comptime dir: Direction) ?*Node {
    const focused = wm.focused orelse return null;
    const fx = focused.x; const fy = focused.y;
    const fw: i32 = @intCast(focused.width);
    const fh: i32 = @intCast(focused.height);

    var best: ?*Node = null;
    var best_primary: i32 = std.math.maxInt(i32);
    var best_overlap: i32 = 0;

    for (wm.current_graph.focus_edges.items) |edge| {
        if (edge.from != focused) continue;
        if (edge.dir != dir) continue;

        const node = edge.to;
        const nx = node.x; const ny = node.y;
        const nw: i32 = @intCast(node.width);
        const nh: i32 = @intCast(node.height);

        switch (dir) {
            .Left => {
                const dist = fx - (nx + nw);
                const overlap = @min(fy + fh, ny + nh) - @max(fy, ny);
                if (overlap <= 0) continue;
                if (dist < best_primary or (dist == best_primary and overlap > best_overlap)) {
                    best = node; best_primary = dist; best_overlap = overlap;
                }
            },
            .Right => {
                const dist = nx - (fx + fw);
                const overlap = @min(fy + fh, ny + nh) - @max(fy, ny);
                if (overlap <= 0) continue;
                if (dist < best_primary or (dist == best_primary and overlap > best_overlap)) {
                    best = node; best_primary = dist; best_overlap = overlap;
                }
            },
            .Up => {
                const dist = fy - (ny + nh);
                const overlap = @min(fx + fw, nx + nw) - @max(fx, nx);
                if (overlap <= 0) continue;
                if (dist < best_primary or (dist == best_primary and overlap > best_overlap)) {
                    best = node; best_primary = dist; best_overlap = overlap;
                }
            },
            .Down => {
                const dist = ny - (fy + fh);
                const overlap = @min(fx + fw, nx + nw) - @max(fx, nx);
                if (overlap <= 0) continue;
                if (dist < best_primary or (dist == best_primary and overlap > best_overlap)) {
                    best = node; best_primary = dist; best_overlap = overlap;
                }
            },
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
        .workspace => node.preview_window orelse return,  // no window → can't focus
        .empty => return,
    };
    _ = c.XSetInputFocus(wm.display, win, c.RevertToParent, c.CurrentTime);
    // Update frame borders
    for (wm.graph.nodes.items) |n| {
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
