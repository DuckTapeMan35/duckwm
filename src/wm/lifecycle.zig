const std = @import("std");
const types = @import("types");
const graph_mod = @import("graph");
const core = @import("core.zig");
const swallow_mod = @import("swallow.zig");
const groups = @import("groups.zig");

const Graph = graph_mod.Graph;
const WM = core.WM;
const Node = graph_mod.Node;

fn apply_initial_hints(node: *Node, h: types.InitialHints) void {
    if (h.fullscreen) node.wants_fullscreen = true;
    if (h.urgent) node.urgent = true;
    if (h.keep_above) node.floating = true;
    if (h.fixed_size) |s| {
        node.floating = true;
        node.width = s.width;
        node.height = s.height;
    }
    if (h.fixed_aspect) node.floating = true;
}

/// Drop empty, unreferenced containers from the current workspace and its groups.
pub fn sweep_dead_containers(wm: *WM) void {
    sweep_graph(wm, wm.current_graph);
}

fn sweep_graph(wm: *WM, g: *Graph) void {
    for (g.nodes.items) |n| {
        if (n.content == .group) sweep_graph(wm, n.content.group);
    }
    var i: usize = 0;
    while (i < g.nodes.items.len) {
        const node = g.nodes.items[i];
        if (node.content == .empty and node.constraints.items.len == 0) {
            // Don't sweep nodes still in the registry (e.g. anchor containers)
            var in_registry = false;
            var rit = wm.node_registry.iterator();
            while (rit.next()) |entry| {
                if (entry.value_ptr.* == node) {
                    in_registry = true;
                    break;
                }
            }
            if (in_registry) {
                i += 1;
                continue;
            }

            var referenced = false;
            for (g.nodes.items) |other| {
                for (other.constraints.items) |con| {
                    const refs = switch (con) {
                        .grid_cell => |gc| gc.container == node,
                        .grid_cell_abs => |gc| gc.container == node,
                        else => false,
                    };
                    if (refs) {
                        referenced = true;
                        break;
                    }
                }
                if (referenced) break;
            }
            if (!referenced) {
                var it = wm.node_registry.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == node) {
                        _ = wm.node_registry.remove(entry.key_ptr.*);
                        break;
                    }
                }
                g.nodes.items[i].deinit(wm.allocator);
                wm.allocator.destroy(g.nodes.items[i]);
                _ = g.nodes.swapRemove(i);
                continue;
            }
        }
        i += 1;
    }
}

pub fn window_mapped(wm: *WM, req: types.MapRequest) !void {
    const h = req.window;

    // A node survived losing its frame: drop it and manage the window afresh.
    if (wm.window_to_node_id.get(h)) |id| {
        if (wm.node_registry.get(id)) |stale| {
            if (stale.owner_graph) |og| og.remove_node(stale);
        }
        _ = wm.node_registry.remove(id);
        _ = wm.window_to_node_id.remove(h);
    }

    const is_transient = req.traits.kind == .floating;

    // Into the focused window's group, if it's in one here.
    const g: *Graph = if (is_transient) wm.current_graph else groups.active(wm);
    const node = try g.add_node(.{ .window = h });
    node.info = wm.backend.window_info(h);
    node.width = req.size.width;
    node.height = req.size.height;
    if (is_transient) node.floating = true;
    node.hidden = true;
    const was_floating = node.floating;
    apply_initial_hints(node, wm.backend.window_hints(h));
    if (node.floating and !was_floating) wm.center_node(node);

    wm.frame(h, node) catch |err| {
        g.remove_node(node);
        if (err == error.WindowGone) return;
        return err;
    };

    const prev_focused = wm.focused;
    if (wm.focused == null) wm.focused = node;
    const id = try wm.register_node(h, node);

    const prev_id = arranger_anchor(wm, g, prev_focused, id);
    wm.call_rules("pre_map", id);
    wm.call_arranger(g, .pre_map, id, prev_id);
    const is_floating = if (wm.node_registry.get(id)) |n| n.floating else false;
    if (!is_floating) wm.call_arranger(g, .map, id, prev_id);

    try wm.resolve(wm.current_graph);
    swallow_mod.try_swallow(wm, id);

    if (node.parked_term == null) {
        node.hidden = false;
        try wm.flush(wm.current_graph);
        var it = groups.Nodes.init(wm.current_graph);
        while (it.next()) |n| {
            if (!n.floating) continue;
            switch (n.content) {
                .window => |w| wm.backend.raise_window(w),
                else => {},
            }
        }
        if (wm.focused) |f| wm.set_focus(f);
    }

    try wm.rebuild_focus_edges();
    wm.sync_workspace_state();
    wm.sync_window_workspace(h);

    if (is_transient) {
        if (wm.node_registry.get(id)) |n| wm.center_node(n);
        try wm.resolve(wm.current_graph);
        node.hidden = false;
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        if (wm.node_registry.get(id)) |n| wm.set_focus(n);
        return;
    }

    if (node.wants_fullscreen) {
        node.wants_fullscreen = false;
        wm.focused = node;
        try wm.toggle_fullscreen();
        try wm.flush(wm.current_graph);
    }
}

/// Which existing node the arranger should place a new one relative to.
fn arranger_anchor(wm: *WM, g: *Graph, prev_focused: ?*Node, new_id: u32) ?u32 {
    const f = prev_focused orelse return null;
    var in_current = false;
    for (g.nodes.items) |n| {
        if (n == f) {
            in_current = true;
            break;
        }
    }
    if (!in_current) return null;

    const pid = wm.get_id_for_node(f) orelse return null;
    const pnode = wm.node_registry.get(pid) orelse return null;
    if (!pnode.floating) return pid;

    // The focused window floats: anchor on the first tiled window instead.
    for (g.nodes.items) |n| {
        if (n.floating) continue;
        if (n.content != .window and n.content != .workspace) continue;
        if (n.content == .workspace and n.preview_window == null) continue;
        if (wm.get_id_for_node(n)) |nid| {
            if (nid != new_id) return nid;
        }
    }
    return null;
}

pub fn window_gone(wm: *WM, h: types.WindowHandle) !void {
    if (swallow_mod.try_terminal_died(wm, h)) return;
    if (wm.window_to_node_id.get(h)) |child_id| {
        if (swallow_mod.try_unswallow(wm, child_id)) return;
    }

    const dying_id = wm.window_to_node_id.get(h) orelse return;
    const dying = wm.node_registry.get(dying_id) orelse return;

    const focused_is_dying = wm.focused == dying;
    const next_focus: ?*Node = if (focused_is_dying) pick_next_focus(wm, dying) else null;

    if (!dying.floating) {
        if (dying.owner_graph) |og| {
            if (og.within(wm.current_graph)) {
                const prev_id: ?u32 = if (wm.focused) |f| wm.get_id_for_node(f) else null;
                wm.call_arranger(og, .unmap, dying_id, prev_id);
            }
        }
    }
    wm.call_rules("unmap", dying_id);
    _ = wm.node_registry.remove(dying_id);
    _ = wm.window_to_node_id.remove(h);

    if (wm.edge_resizing) {
        wm.edge_resizing = false;
        wm.backend.release_pointer();
    }

    if (dying.owner_graph) |og| {
        if (og.fullscreen_node == dying) og.fullscreen_node = null;
        og.remove_node(dying);
        // The last window of a group: the group goes too.
        groups.dissolve_if_empty(wm, og);
    }
    sweep_dead_containers(wm);

    if (wm.current_graph.nodes.items.len > 0) {
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        if (focused_is_dying) {
            wm.focused = next_focus;
            if (next_focus) |n| wm.set_focus(n) else wm.clear_focus();
        }
        wm.sync_workspace_state();
    } else {
        if (focused_is_dying) wm.focused = null;
        wm.focus_dirty = true;
        wm.current_graph.focus_edges.clearRetainingCapacity();
        wm.flush(wm.current_graph) catch {};
    }
}

fn pick_next_focus(wm: *WM, dying: *Node) ?*Node {
    // A closing dialog hands focus back to a tiled window first.
    if (dying.floating) {
        var it = groups.Nodes.init(wm.current_graph);
        while (it.next()) |n| {
            if (n == dying or n.hidden or n.floating) continue;
            if (n.content == .window) return n;
        }
    }
    for (wm.current_graph.focus_edges.items) |edge| {
        if (edge.from == dying and edge.to != dying) return edge.to;
    }
    // Its group's windows first, then any.
    if (dying.owner_graph) |og| {
        if (og.is_group) {
            var it = groups.Nodes.init(og);
            while (it.next()) |n| {
                if (n == dying or n.hidden) continue;
                if (n.content == .window) return n;
            }
        }
    }
    var it = groups.Nodes.init(wm.current_graph);
    while (it.next()) |n| {
        if (n == dying or n.hidden) continue;
        if (n.content == .window) return n;
    }
    return null;
}
