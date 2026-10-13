const std = @import("std");
const types = @import("types");
const graph_mod = @import("graph");
const Node = graph_mod.Node;
const WM = @import("core.zig").WM;

fn node_for(wm: *WM, h: types.WindowHandle) ?struct { id: u32, node: *Node } {
    const id = wm.window_to_node_id.get(h) orelse return null;
    const node = wm.node_registry.get(id) orelse return null;
    return .{ .id = id, .node = node };
}

pub fn info_changed(wm: *WM, h: types.WindowHandle) void {
    const n = node_for(wm, h) orelse return;
    n.node.info = wm.backend.window_info(h);
    if (n.node.owner_graph == wm.current_graph) wm.call_rules("prop", n.id);
}

pub fn urgency_hint(wm: *WM, hint: types.UrgencyHint) void {
    const n = node_for(wm, hint.window) orelse return;
    if (wm.focused == n.node) return; // the focused window is never urgent
    n.node.urgent = hint.urgent;
    wm.paint_borders(n.node, null);
}

pub fn activate(wm: *WM, h: types.WindowHandle) void {
    const n = node_for(wm, h) orelse return;
    wm.activate_window(n.node) catch {};
}

pub fn state_request(wm: *WM, r: types.StateRequest) !void {
    const n = node_for(wm, r.window) orelse return;
    const node = n.node;

    if (r.fullscreen) {
        const current = if (node.owner_graph) |og| og.fullscreen_node == node else false;
        const want = switch (r.action) {
            .remove => false,
            .add => true,
            .toggle => !current,
        };
        if (want != current) {
            wm.journal.set(wm, "focused", node);
            try wm.toggle_fullscreen();
        }
    }

    if (r.attention) {
        node.urgent = switch (r.action) {
            .remove => false,
            .add => true,
            .toggle => !node.urgent,
        };
        wm.paint_borders(node, null);
    }
}
