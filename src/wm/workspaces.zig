const std = @import("std");
const graph_mod = @import("graph");
const core = @import("core.zig");
const WM = core.WM;
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;
const NodeList = std.ArrayListUnmanaged(*Node);

/// The graph holding the current workspace and its siblings.
pub fn parent_graph(wm: *WM) *Graph {
    const pn = wm.current_graph.parent_node orelse return &wm.graph;
    return pn.owner_graph orelse &wm.graph;
}

/// Where "the previous workspace" can be found when switching back.
pub fn siblings(wm: *WM) []const *Node {
    if (wm.current_graph.parent_node == null) return wm.current_graph.nodes.items;
    return parent_graph(wm).nodes.items;
}

fn by_id(wm: *WM, a: *Node, b: *Node) bool {
    const id_a = wm.get_id_for_node(a) orelse return false;
    const id_b = wm.get_id_for_node(b) orelse return false;
    return id_a < id_b;
}

fn sorted_workspaces(wm: *WM, g: *Graph, out: *NodeList) !void {
    out.clearRetainingCapacity();
    for (g.nodes.items) |n| {
        if (n.content == .workspace) try out.append(wm.allocator, n);
    }
    std.sort.heap(*Node, out.items, wm, by_id);
}

/// Does the workspace hold any windows or nested workspaces?
pub fn has_content(sub: *Graph) bool {
    for (sub.nodes.items) |n| switch (n.content) {
        .window, .workspace => return true,
        .empty => {},
    };
    return false;
}

/// Grow parent to at least count workspaces. New ones have the highest
/// ids, so appending keeps list sorted.
fn ensure(wm: *WM, parent: *Graph, list: *NodeList, count: usize) !void {
    while (list.items.len < count) try list.append(wm.allocator, try wm.add_workspace_node(parent));
}

/// Enter target, or the previous workspace if target is already current
/// and the switch mode is "previous".
pub fn enter_or_back(wm: *WM, target: *Node, candidates: []const *Node) !void {
    const current = wm.current_graph;
    if (target.content.workspace != current) {
        wm.journal.set(wm, "previous_graph", current);
        return wm.enter_workspace(target);
    }
    if (wm.workspace_switch_mode != .previous) return;
    const prev = wm.previous_graph orelse return;
    for (candidates) |n| {
        if (n.content == .workspace and n.content.workspace == prev) {
            wm.journal.set(wm, "previous_graph", current);
            return wm.enter_workspace(n);
        }
    }
}

pub fn switch_to(wm: *WM, index: usize) !void {
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    const parent = parent_graph(wm);
    try sorted_workspaces(wm, parent, &list);
    try ensure(wm, parent, &list, index);
    try enter_or_back(wm, list.items[index - 1], list.items);
}

pub fn send_to(wm: *WM, node_id: u32, index: usize) !void {
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    const parent = parent_graph(wm);
    try sorted_workspaces(wm, parent, &list);
    try ensure(wm, parent, &list, index);
    try wm.send_to_workspace(node_id, list.items[index - 1].content.workspace);
}

/// A new workspace with a preview, mapped into the current one. Returns its id.
pub fn create_nested(wm: *WM) !u32 {
    const g = wm.current_graph;
    const n = try wm.create_workspace_node_with_preview(g);
    const id = try wm.register_node(n.preview_window, n);

    const prev_id: ?u32 = if (wm.focused) |f|
        (if (f.owner_graph == g) wm.get_id_for_node(f) else null)
    else
        null;
    wm.call_arranger(g, "map", id, prev_id);

    // A new graph and node: no journal entries needed for their own fields.
    const sub = n.content.workspace;
    sub.gap_inner_h = wm.default_gap_inner_h;
    sub.gap_inner_v = wm.default_gap_inner_v;
    sub.gap_outer_h = wm.default_gap_outer_h;
    sub.gap_outer_v = wm.default_gap_outer_v;
    n.hidden = false;

    wm.relayout();
    if (wm.focused) |f| wm.focus(f);
    return id;
}

/// The id of the index-th workspace nested in the current one.
pub fn workspace_at(wm: *WM, index: usize) !?u32 {
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    try sorted_workspaces(wm, wm.current_graph, &list);
    if (index < 1 or index > list.items.len) return null;
    return wm.get_id_for_node(list.items[index - 1]);
}

pub const State = enum { focused, active, inactive };

/// The state of every sibling workspace, in index order.
pub fn states(wm: *WM, a: std.mem.Allocator) ![]State {
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    try sorted_workspaces(wm, parent_graph(wm), &list);
    const out = try a.alloc(State, list.items.len);
    for (list.items, out) |n, *s| {
        const sub = n.content.workspace;
        s.* = if (sub == wm.current_graph) .focused else if (has_content(sub)) .active else .inactive;
    }
    return out;
}

/// The current workspace's index among its siblings.
pub fn current_position(wm: *WM) !?usize {
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    try sorted_workspaces(wm, parent_graph(wm), &list);
    for (list.items, 1..) |n, pos| {
        if (n.content.workspace == wm.current_graph) return pos;
    }
    return null;
}

/// 1-based numbers of the workspaces at the current level that are current or have content.
pub fn level_numbers(wm: *WM, a: std.mem.Allocator) ![]u32 {
    const level = wm.current_graph.id.level;
    const parent: *Graph = if (wm.current_graph.parent_node) |pn| pn.owner_graph orelse wm.current_graph else wm.current_graph;
    var out: std.ArrayListUnmanaged(u32) = .empty;
    for (parent.nodes.items) |n| {
        if (n.content != .workspace) continue;
        const sub = n.content.workspace;
        if (sub.id.level != level) continue;
        if (sub == wm.current_graph or has_content(sub)) try out.append(a, sub.id.number + 1);
    }
    std.mem.sort(u32, out.items, {}, std.sort.asc(u32));
    return out.items;
}
