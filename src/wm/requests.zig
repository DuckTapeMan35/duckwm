const std = @import("std");
const types = @import("types");
const graph_mod = @import("graph");
const navigation = @import("navigation.zig");

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

/// Show the workspace published as index, as switching to it does.
pub fn workspace(wm: *WM, index: u32) void {
    const node = navigation.published_workspace(wm, index) orelse return;
    if (node.content.workspace == wm.current_graph) return;
    wm.journal.set(wm, "previous_graph", wm.current_graph);
    wm.enter_workspace(node) catch {};
}

/// Put a window on the workspace published as index, as sending it does.
pub fn window_workspace(wm: *WM, r: types.WorkspaceRequest) void {
    const n = node_for(wm, r.window) orelse return;
    const node = navigation.published_workspace(wm, r.workspace) orelse return;
    wm.send_to_workspace(n.id, node.content.workspace) catch {};
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
