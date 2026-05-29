const std = @import("std");
const c = @import("c").c;
const WM = @import("core.zig").WM;
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
        if (entry.value_ptr.* == focused) { node_id = entry.key_ptr.*; break; }
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
            if (entry.value_ptr.* == focused) { node_id_for_arranger = entry.key_ptr.*; break; }
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
    const bw: i32 = wm.border_width;
    var moving_node: ?*graph_mod.Node = null;

    for (wm.current_graph.nodes.items) |node| {
        if (!node.floating or node.hidden) continue;
        // defer the moving window to raise last
        if (wm.float_moving) {
            switch (node.content) {
                .window => |w| {
                    if (wm.frames.get(w)) |frame| {
                        if (frame == wm.float_move_frame) {
                            moving_node = node;
                            continue;
                        }
                    }
                },
                .workspace => {
                    if (node.preview_window) |pw| {
                        if (wm.frames.get(pw)) |frame| {
                            if (frame == wm.float_move_frame) {
                                moving_node = node;
                                continue;
                            }
                        }
                    }
                },
                else => {},
            }
        }
        // raise non-moving windows normally
        raise_one(wm, node, bw);
    }

    // raise the moving window last so it stays on top
    if (moving_node) |node| raise_one(wm, node, bw);
}

fn raise_one(wm: *WM, node: *graph_mod.Node, bw: i32) void {
    switch (node.content) {
        .window => |win| {
            if (wm.frames.get(win)) |frame| {
                _ = c.XSelectInput(wm.display, frame, c.SubstructureNotifyMask | c.ExposureMask | c.ButtonPressMask | c.ButtonReleaseMask);
                _ = c.XRaiseWindow(wm.display, frame);
                _ = c.XSelectInput(wm.display, frame, c.SubstructureNotifyMask | c.ExposureMask | c.ButtonPressMask | c.ButtonReleaseMask | c.EnterWindowMask | c.LeaveWindowMask);
                var ce: c.XEvent = std.mem.zeroes(c.XEvent);
                ce.xconfigure.type = c.ConfigureNotify;
                ce.xconfigure.display = wm.display;
                ce.xconfigure.event = win;
                ce.xconfigure.window = win;
                ce.xconfigure.x = node.x;
                ce.xconfigure.y = node.y;
                ce.xconfigure.width = @intCast(@max(1, node.width));
                ce.xconfigure.height = @intCast(@max(1, node.height));
                ce.xconfigure.border_width = 0;
                ce.xconfigure.above = c.None;
                ce.xconfigure.override_redirect = 0;
                _ = c.XSendEvent(wm.display, win, 0, c.StructureNotifyMask, &ce);
                _ = bw;
            }
        },
        .workspace => {
            if (node.preview_window) |pw| {
                if (wm.frames.get(pw)) |frame| {
                    _ = c.XSelectInput(wm.display, frame, c.SubstructureNotifyMask | c.ExposureMask | c.ButtonPressMask | c.ButtonReleaseMask);
                    _ = c.XRaiseWindow(wm.display, frame);
                    _ = c.XSelectInput(wm.display, frame, c.SubstructureNotifyMask | c.ExposureMask | c.ButtonPressMask | c.ButtonReleaseMask | c.EnterWindowMask | c.LeaveWindowMask);
                }
            }
        },
        else => {},
    }
}

pub fn toggle_fullscreen(wm: *WM) !void {
    const focused = wm.focused orelse return;
    if (focused.content != .window) return;

    if (wm.fullscreen_node == focused) {
        // Restore
        focused.x      = wm.fullscreen_saved_x;
        focused.y      = wm.fullscreen_saved_y;
        focused.width  = wm.fullscreen_saved_w;
        focused.height = wm.fullscreen_saved_h;
        focused.floating = false;
        focused.constraints.clearRetainingCapacity();
        wm.fullscreen_node = null;

        var node_id: ?u32 = null;
        var prev_id: ?u32 = null;
        var it = wm.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == focused) {
                node_id = entry.key_ptr.*;
            }
        }
        // Find a tiled window to use as prev_id
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
        wm.fullscreen_saved_x = focused.x;
        wm.fullscreen_saved_y = focused.y;
        wm.fullscreen_saved_w = focused.width;
        wm.fullscreen_saved_h = focused.height;
        focused.floating = true;
        focused.constraints.clearRetainingCapacity();
        focused.x = 0;
        focused.y = 0;
        focused.width  = wm.screen_width;
        focused.height = wm.screen_height;
        wm.fullscreen_node = focused;

        var node_id: ?u32 = null;
        var it = wm.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == focused) { node_id = entry.key_ptr.*; break; }
        }
        if (node_id) |nid| wm.call_arranger(wm.current_graph, "unmap", nid, null);
    }

    // Update _NET_WM_STATE_FULLSCREEN
    if (focused.content == .window) {
        const win = focused.content.window;
        const net_wm_state = c.XInternAtom(wm.display, "_NET_WM_STATE", 0);
        const net_wm_state_fullscreen = c.XInternAtom(wm.display, "_NET_WM_STATE_FULLSCREEN", 0);
        const xa_atom = c.XInternAtom(wm.display, "ATOM", 0);
        if (wm.fullscreen_node == focused) {
            _ = c.XChangeProperty(wm.display, win, net_wm_state, xa_atom, 32,
                c.PropModeReplace, @ptrCast(&net_wm_state_fullscreen), 1);
        } else {
            _ = c.XChangeProperty(wm.display, win, net_wm_state, xa_atom, 32,
                c.PropModeReplace, @ptrCast(&net_wm_state_fullscreen), 0);
        }
    }

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
    focused.width  = @intCast(@max(10, @as(i32, @intCast(focused.width))  + delta_width));
    focused.height = @intCast(@max(10, @as(i32, @intCast(focused.height)) + delta_height));
    try wm.resolve(wm.current_graph);
    try wm.flush(wm.current_graph);
}
