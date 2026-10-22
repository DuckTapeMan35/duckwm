const std = @import("std");
const graph_mod = @import("graph");
const output = @import("output.zig");
const groups = @import("groups.zig");
const WM = @import("core.zig").WM;
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;

/// Focus edges of the current workspace, between what focus moves between
/// from the focused node (groups.units). They share the workspace's canvas,
/// so positions compare directly.
pub fn rebuild_focus_edges(wm: *WM) !void {
    // (current_graph is a group while its arranger or binds run.)
    const ws = wm.current_graph.workspace();
    ws.focus_edges.clearRetainingCapacity();
    var list: std.ArrayListUnmanaged(*Node) = .empty;
    defer list.deinit(wm.allocator);
    try groups.units(wm.allocator, ws, wm.focused, &list);
    for (list.items) |a| {
        for (list.items) |b| try link(ws, a, b);
    }
}

/// The edges from a to b: its main direction, and the other one too when
/// that's at least a quarter of it.
fn link(ws: *graph_mod.Graph, a: *Node, b: *Node) !void {
    if (a == b) return;
    const a_cx = a.x + @divTrunc(@as(i32, @intCast(a.width)), 2);
    const a_cy = a.y + @divTrunc(@as(i32, @intCast(a.height)), 2);
    const b_cx = b.x + @divTrunc(@as(i32, @intCast(b.width)), 2);
    const b_cy = b.y + @divTrunc(@as(i32, @intCast(b.height)), 2);
    const dx = b_cx - a_cx;
    const dy = b_cy - a_cy;
    if (dx == 0 and dy == 0) return;

    const abs_dx = @abs(dx);
    const abs_dy = @abs(dy);
    if (abs_dx >= abs_dy) {
        try ws.add_focus_edge(a, b, if (dx < 0) .Left else .Right);
    } else {
        try ws.add_focus_edge(a, b, if (dy < 0) .Up else .Down);
    }
    if (abs_dx > 0 and abs_dy > 0) {
        const minor = @min(abs_dx, abs_dy);
        const major = @max(abs_dx, abs_dy);
        if (minor * 4 >= major) {
            if (abs_dx < abs_dy) {
                try ws.add_focus_edge(a, b, if (dx < 0) .Left else .Right);
            } else {
                try ws.add_focus_edge(a, b, if (dy < 0) .Up else .Down);
            }
        }
    }
}

pub fn find_focus_target(wm: *WM, comptime dir: Direction) ?*Node {
    const focused = wm.focused orelse return null;
    // Units depend on what's focused: edges from where focus is now.
    wm.rebuild_focus_edges() catch {};
    const fx = focused.x;
    const fy = focused.y;
    const fw: i32 = @intCast(focused.width);
    const fh: i32 = @intCast(focused.height);

    var best: ?*Node = null;
    var best_dist: i32 = std.math.maxInt(i32);
    var best_overlap: i32 = std.math.minInt(i32);

    for (wm.current_graph.workspace().focus_edges.items) |edge| {
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
    if (find_focus_target(wm, dir)) |target| return set_focus(wm, target);
    // Nothing further this way on this output: on to the next one.
    _ = output.focus_across(wm, switch (dir) {
        .Left => .left,
        .Right => .right,
        .Up => .up,
        .Down => .down,
    });
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
    // A window showing on another output: that output takes focus first.
    if (node.owner_graph) |og| {
        if (output.of(wm, og)) |o| {
            if (o != wm.output and output.visible(wm, o) == og.workspace()) {
                // An arranger or rule is running: switching output now would
                // swap the workspace it borrowed. Leave focus where it is.
                if (wm.hold_output > 0) return;
                output.focus(wm, o);
            }
        }
    }
    wm.journal.set(wm, "focused", node);
    wm.focus_dirty = true;
    if (!wm.is_shown(node)) return; // nothing on screen to focus (yet)
    wm.focus_clock += 1;
    node.focus_serial = wm.focus_clock;
    node.urgent = false;

    // Pan the window's own workspace just enough to have it on its monitor.
    const og = node.owner_graph orelse return;
    const g = og.workspace();
    if (!node.floating and output.is_visible(wm, g)) {
        const work = output.work_area_of(wm, g);
        const right = work.x + @as(i32, @intCast(work.width));
        const bottom = work.y + @as(i32, @intCast(work.height));
        const nw: i32 = @intCast(node.width);
        const nh: i32 = @intCast(node.height);
        var px = g.pan_x;
        var py = g.pan_y;
        if (node.x - px < work.x) px = node.x - work.x else if (node.x - px + nw > right) px = node.x + nw - right;
        if (node.y - py < work.y) py = node.y - work.y else if (node.y - py + nh > bottom) py = node.y + nh - bottom;
        px = @max(0, px);
        py = @max(0, py);
        if (px != g.pan_x) g.set(g, "pan_x", px);
        if (py != g.pan_y) g.set(g, "pan_y", py);
    }

    // Focus changes border colors (and which window counts as fullscreen-focused).
    wm.flush(g) catch {};
    if (wm.get_id_for_node(node)) |id| wm.call_arranger(og, .focus, id, null);
    var inner = og;
    while (inner.is_group) {
        const gn = inner.parent_node.?;
        const outer = gn.owner_graph.?;
        if (wm.get_id_for_node(gn)) |id| wm.call_arranger(outer, .focus, id, null);
        inner = outer;
    }
}

pub fn top_left_window(wm: *WM) ?*Node {
    var list: std.ArrayListUnmanaged(*Node) = .empty;
    defer list.deinit(wm.allocator);
    groups.units(wm.allocator, wm.current_graph, null, &list) catch return null;
    var best: ?*Node = null;
    for (list.items) |node| {
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
