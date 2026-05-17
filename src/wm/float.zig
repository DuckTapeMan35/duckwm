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
    if (focused.content != .window) return;

    // Resolve the numeric ID we'll pass to Lua
    var node_id: ?u32 = null;
    var it = wm.node_registry.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == focused) { node_id = entry.key_ptr.*; break; }
    }
    const id = node_id orelse return;

    if (focused.floating) {
        focused.floating = false;
        // Re-integrate into the tiling layout exactly like a new window
        wm.call_arranger(wm.current_graph, "map", id, null);
    } else {
        focused.floating = true;
        // Clear constraints so the solver never touches this node again
        focused.constraints.clearRetainingCapacity();
        // Center the window on the screen as a starting point
        center_node(wm, focused);
        // Let Lua remove it from the grid and reflow the remaining windows
        wm.call_arranger(wm.current_graph, "unmap", id, null);
    }

    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
}

pub fn raise_floating_windows(wm: *WM) void {
    const bw: i32 = wm.border_width;
    for (wm.current_graph.nodes.items) |node| {
        switch (node.content) {
            .window => |win| {
                if (!node.floating) continue;
                if (wm.frames.get(win)) |frame| {
                    const fw: u32 = node.width  -| @as(u32, @intCast(@max(0, 2 * bw)));
                    const fh: u32 = node.height -| @as(u32, @intCast(@max(0, 2 * bw)));
                    _ = c.XMoveResizeWindow(wm.display, frame, node.x, node.y, @max(1, fw), @max(1, fh));
                    _ = c.XMoveResizeWindow(wm.display, win, 0, 0, @max(1, fw), @max(1, fh));
                }
            },
            else => {},
        }
    }
}

pub fn move_floating(wm: *WM, delta_x: i32, delta_y: i32) !void {
    const focused = wm.focused orelse return;
    if (!focused.floating or focused.content != .window) return;
    focused.x += delta_x;
    focused.y += delta_y;
    if (wm.frames.get(focused.content.window)) |frame|
        _ = c.XMoveWindow(wm.display, frame, focused.x, focused.y);
}

pub fn resize_floating(wm: *WM, delta_width: i32, delta_height: i32) !void {
    const focused = wm.focused orelse return;
    if (!focused.floating or focused.content != .window) return;
    focused.width  = @intCast(@max(10, @as(i32, @intCast(focused.width))  + delta_width));
    focused.height = @intCast(@max(10, @as(i32, @intCast(focused.height)) + delta_height));
    if (wm.frames.get(focused.content.window)) |frame|
        _ = c.XMoveResizeWindow(wm.display, frame, focused.x, focused.y, focused.width, focused.height);
}
