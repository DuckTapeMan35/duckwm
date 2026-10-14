const std = @import("std");
const WM = @import("core.zig").WM;
const types = @import("types");
const graph_mod = @import("graph");
const ziglua = @import("ziglua");
const Node = graph_mod.Node;

pub fn center_node(wm: *WM, node: *Node) void {
    if (node.width < 10) node.width = 800;
    if (node.height < 10) node.height = 600;
    node.x = @as(i32, @intCast(wm.screen_width / 2)) - @as(i32, @intCast(node.width / 2));
    node.y = @as(i32, @intCast(wm.screen_height / 2)) - @as(i32, @intCast(node.height / 2));
}

pub fn toggle_floating(wm: *WM) !void {
    const focused = wm.focused orelse return;
    if (focused.content != .window and focused.content != .workspace) return;

    var node_id: ?u32 = null;
    var it = wm.node_registry.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == focused) {
            node_id = entry.key_ptr.*;
            break;
        }
    }
    const id = node_id orelse return;

    if (focused.floating) {
        focused.floating = false;
        focused.constraints.clearRetainingCapacity();

        var prev_id: ?u32 = null;
        for (wm.current_graph.nodes.items) |n| {
            if (n.floating) continue;
            if (n == focused) continue;
            if (n.content != .window and n.content != .workspace) continue;
            if (wm.get_id_for_node(n)) |nid| {
                prev_id = nid;
                break;
            }
        }
        wm.call_arranger(wm.current_graph, "map", id, prev_id);
    } else {
        // call arranger first while node is still tiled
        var node_id_for_arranger: ?u32 = null;
        var it2 = wm.node_registry.iterator();
        while (it2.next()) |entry| {
            if (entry.value_ptr.* == focused) {
                node_id_for_arranger = entry.key_ptr.*;
                break;
            }
        }
        if (node_id_for_arranger) |nid| wm.call_arranger(wm.current_graph, "unmap", nid, null);

        focused.floating = true;
        focused.constraints.clearRetainingCapacity();
        center_node(wm, focused);
    }

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
    const focused = wm.focused orelse return;
    if (focused.content != .window) return;
    const win = focused.content.window;
    const g = focused.owner_graph orelse wm.current_graph;
    const node_id = wm.get_id_for_node(focused);
    if (g.fullscreen_node == focused) {
        // Restore
        focused.x = g.fullscreen_saved_x;
        focused.y = g.fullscreen_saved_y;
        focused.width = g.fullscreen_saved_w;
        focused.height = g.fullscreen_saved_h;
        focused.floating = false;
        focused.constraints.clearRetainingCapacity();
        g.fullscreen_node = null;
        var prev_id: ?u32 = null;
        for (wm.current_graph.nodes.items) |n| {
            if (n.floating) continue;
            if (n == focused) continue;
            if (n.content != .window and n.content != .workspace) continue;
            if (wm.get_id_for_node(n)) |nid| {
                prev_id = nid;
                break;
            }
        }
        if (node_id) |nid| wm.call_arranger(wm.current_graph, "map", nid, prev_id);
    } else {
        // Go fullscreen
        g.fullscreen_saved_x = focused.x;
        g.fullscreen_saved_y = focused.y;
        g.fullscreen_saved_w = focused.width;
        g.fullscreen_saved_h = focused.height;
        focused.floating = true;
        focused.constraints.clearRetainingCapacity();
        focused.x = 0;
        focused.y = 0;
        focused.width = wm.screen_width;
        focused.height = wm.screen_height;
        g.fullscreen_node = focused;
        if (node_id) |nid| wm.call_arranger(wm.current_graph, "unmap", nid, null);
    }
    wm.backend.publish_window_fullscreen(win, g.fullscreen_node == focused);
    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
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
