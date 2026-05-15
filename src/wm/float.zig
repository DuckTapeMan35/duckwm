const std = @import("std");
const c = @import("c").c;
const WM = @import("core.zig").WM;
const graph_mod = @import("graph");
const ziglua = @import("ziglua");
const Node = graph_mod.Node;

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
        // ── Un-float ──────────────────────────────────────────────────────
        focused.floating = false;
        // Re-integrate into the tiling layout exactly like a new window
        wm.call_arranger(wm.current_graph, "map", id, null);
    } else {
        // ── Float ─────────────────────────────────────────────────────────
        focused.floating = true;
        // Clear constraints so the solver never touches this node again
        focused.constraints.clearRetainingCapacity();
        // Let Lua remove it from the grid and reflow the remaining windows
        wm.call_arranger(wm.current_graph, "unmap", id, null);
    }

    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
}

pub fn raise_floating_windows(wm: *WM) void {
    for (wm.current_graph.nodes.items) |node| {
        switch (node.content) {
            .window => |win| {
                if (!node.floating) continue;
                if (wm.frames.get(win)) |frame|
                    _ = c.XRaiseWindow(wm.display, frame);
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
