const std = @import("std");
const WM = @import("core.zig").WM;
const types = @import("types");
const graph_mod = @import("graph");
const ziglua = @import("ziglua");
const Node = graph_mod.Node;

pub fn center_node(wm: *WM, node: *Node) void {
    if (node.width < 10) node.width = 800;
    if (node.height < 10) node.height = 600;
    node.x = wm.output.rect.x + @as(i32, @intCast(wm.screen_width / 2)) - @as(i32, @intCast(node.width / 2));
    node.y = wm.output.rect.y + @as(i32, @intCast(wm.screen_height / 2)) - @as(i32, @intCast(node.height / 2));
}

/// Float or tile n, telling its workspace's arranger: an unmap while it's
/// still tiled, a map once it's back. Journaled: a failed transaction undoes it.
pub fn set_floating(wm: *WM, n: *Node, val: bool) !void {
    if (n.content != .window and n.content != .workspace) return;
    if (n.floating == val) return;
    const g = n.owner_graph orelse return error.NotInGraph;
    const id = wm.get_id_for_node(n) orelse return error.NoId;
    if (val) {
        // Leaves the tiling like a close: the snapshot still lists it, as the unmapped one.
        wm.call_arranger(g, .unmap, id, null);
        try g.replace_constraints(n, &.{});
        wm.journal.set(n, "floating", true);
        center_node(wm, n);
    } else {
        try g.replace_constraints(n, &.{});
        wm.journal.set(n, "floating", false);
        // Rejoins like a new window; with no prev, the arranger puts it last.
        wm.call_arranger(g, .map, id, null);
    }
}

pub fn toggle_floating(wm: *WM) !void {
    const n = wm.focused orelse return;
    try set_floating(wm, n, !n.floating);
    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
}

pub fn raise_floating_windows(wm: *WM) void {
    var moving: ?types.WindowHandle = null;
    for (wm.current_graph.nodes.items) |node| {
        if (!node.floating or node.hidden) continue;
        const h = node.window() orelse continue;
        // The window being dragged goes last, so it ends up on top.
        if (wm.float_moving and h == wm.float_move_window) {
            moving = h;
            continue;
        }
        wm.backend.raise_window(h);
    }
    if (moving) |h| wm.backend.raise_window(h);
}

pub fn toggle_fullscreen(wm: *WM) !void {
    const n = wm.focused orelse return;
    if (n.content != .window) return;
    const win = n.content.window;
    const g = n.owner_graph orelse wm.current_graph;
    const id = wm.get_id_for_node(n) orelse return;
    if (g.fullscreen_node == n) {
        n.x = g.fullscreen_saved_x;
        n.y = g.fullscreen_saved_y;
        n.width = g.fullscreen_saved_w;
        n.height = g.fullscreen_saved_h;
        try g.replace_constraints(n, &.{});
        wm.journal.set(n, "floating", false);
        wm.journal.set(g, "fullscreen_node", null);
        // Back into the tiling like a new window.
        wm.call_arranger(g, .map, id, null);
    } else {
        g.fullscreen_saved_x = n.x;
        g.fullscreen_saved_y = n.y;
        g.fullscreen_saved_w = n.width;
        g.fullscreen_saved_h = n.height;
        // Out of the tiling while the snapshot still lists it.
        wm.call_arranger(g, .unmap, id, null);
        try g.replace_constraints(n, &.{});
        wm.journal.set(n, "floating", true);
        wm.journal.set(g, "fullscreen_node", n);
        n.x = wm.output.rect.x;
        n.y = wm.output.rect.y;
        n.width = wm.screen_width;
        n.height = wm.screen_height;
    }
    wm.backend.publish_window_fullscreen(win, g.fullscreen_node == n);
    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
    wm.set_focus(n);
}

pub fn move_floating(wm: *WM, delta_x: i32, delta_y: i32) !void {
    const focused = wm.focused orelse return;
    if (!focused.floating or focused.content != .window) return;
    focused.x += delta_x;
    focused.y += delta_y;
    try wm.resolve(wm.current_graph);
    try wm.flush(wm.current_graph);
}

pub fn resize_floating(wm: *WM, delta_width: i32, delta_height: i32) !void {
    const focused = wm.focused orelse return;
    if (!focused.floating or focused.content != .window) return;
    focused.width = @intCast(@max(10, @as(i32, @intCast(focused.width)) + delta_width));
    focused.height = @intCast(@max(10, @as(i32, @intCast(focused.height)) + delta_height));
    try wm.resolve(wm.current_graph);
    try wm.flush(wm.current_graph);
}
