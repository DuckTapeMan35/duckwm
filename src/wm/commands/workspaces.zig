const std = @import("std");
const core = @import("../core.zig");
const command = @import("../command.zig");
const groups = @import("../groups.zig");
const workspace_settings = @import("../workspace_settings.zig");
const util = @import("util.zig");
const graph_mod = @import("graph");
const WM = core.WM;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;
const NodeList = std.ArrayListUnmanaged(*Node);

/// The graph holding the current workspace and its siblings.
pub fn parent_graph(wm: *WM) *Graph {
    const pn = wm.current_graph.workspace().parent_node orelse return wm.root;
    return if (pn.owner_graph) |og| og.workspace() else wm.root;
}

fn by_id(wm: *WM, a: *Node, b: *Node) bool {
    const id_a = wm.get_id_for_node(a) orelse return false;
    const id_b = wm.get_id_for_node(b) orelse return false;
    return id_a < id_b;
}

fn sorted_workspaces(wm: *WM, g: *Graph, out: *NodeList) !void {
    out.clearRetainingCapacity();
    var it = groups.Nodes.init(g);
    while (it.next()) |n| {
        if (n.content == .workspace) try out.append(wm.allocator, n);
    }
    std.sort.heap(*Node, out.items, wm, by_id);
}

/// Does the workspace hold any windows or nested workspaces?
pub fn has_content(sub: *Graph) bool {
    for (sub.nodes.items) |n| switch (n.content) {
        .window, .workspace, .group => return true,
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
pub fn enter_or_back(wm: *WM, target: *Node) !void {
    const current = wm.current_graph;
    if (target.content.workspace != current) {
        wm.journal.set(wm, "previous_graph", current);
        return wm.enter_workspace(target);
    }
    if (wm.workspace_switch_mode != .previous) return;
    const prev = wm.previous_graph orelse return;
    const pn = prev.parent_node orelse return;
    const og = pn.owner_graph orelse return;
    // Same level: the previous one's parent is the current one's.
    if (og.workspace() != parent_graph(wm)) return;
    wm.journal.set(wm, "previous_graph", current);
    return wm.enter_workspace(pn);
}

pub fn switch_to(wm: *WM, index: usize) !void {
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    const parent = parent_graph(wm);
    try sorted_workspaces(wm, parent, &list);
    try ensure(wm, parent, &list, index);
    try enter_or_back(wm, list.items[index - 1]);
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
    wm.call_arranger(g, .map, id, prev_id);

    // A new graph and node: no journal entries needed for their own fields.
    const sub = n.content.workspace;
    sub.gap_inner_h = wm.default_gap_inner_h;
    sub.gap_inner_v = wm.default_gap_inner_v;
    sub.gap_outer_h = wm.default_gap_outer_h;
    sub.gap_outer_v = wm.default_gap_outer_v;
    n.hidden = false;

    workspace_settings.apply_to(wm, n);

    wm.relayout();
    if (wm.focused) |f| wm.set_focus(f);
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
    const parent: *Graph = if (wm.current_graph.parent_node) |pn|
        (if (pn.owner_graph) |og| og.workspace() else wm.current_graph)
    else
        wm.current_graph;
    var out: std.ArrayListUnmanaged(u32) = .empty;
    var it = groups.Nodes.init(parent);
    while (it.next()) |n| {
        if (n.content != .workspace) continue;
        const sub = n.content.workspace;
        if (sub.id.level != level) continue;
        if (sub == wm.current_graph or has_content(sub)) try out.append(a, sub.id.number + 1);
    }
    std.mem.sort(u32, out.items, {}, std.sort.asc(u32));
    return out.items;
}

// ---- switching and sending ----
pub fn switch_to_workspace(wm: *WM, args: Args(.switch_to_workspace), _: Allocator) !Value {
    if (args.index < 1) return error.OutOfRange;
    try switch_to(wm, args.index);
    return .nil;
}

pub fn send_to_workspace(wm: *WM, args: Args(.send_to_workspace), _: Allocator) !Value {
    if (args.index < 1) return error.OutOfRange;
    try send_to(wm, args.id, args.index);
    return .nil;
}

pub fn enter_workspace_by_id(wm: *WM, args: Args(.enter_workspace_by_id), _: Allocator) !Value {
    const n = try util.node(wm, args.id);
    if (n.content != .workspace) return error.NotAWorkspace;
    try enter_or_back(wm, n);
    return .nil;
}

// ---- nesting ----
pub fn create_nested_workspace(wm: *WM, _: void, _: Allocator) !Value {
    return .{ .integer = try create_nested(wm) };
}

pub fn enter_nested(wm: *WM, _: void, _: Allocator) !Value {
    const n = wm.focused orelse return .nil;
    if (n.content == .workspace) try wm.enter_workspace(n);
    return .nil;
}

pub fn enter_nested_by_id(wm: *WM, args: Args(.enter_nested_by_id), _: Allocator) !Value {
    const n = try util.node(wm, args.id);
    if (n.content != .workspace) return error.NotAWorkspace;
    try wm.enter_workspace(n);
    return .nil;
}

pub fn leave_nested(wm: *WM, _: void, _: Allocator) !Value {
    try wm.leave_workspace();
    return .nil;
}

// ---- settings and cleanup ----
pub fn set_workspace_switch_mode(wm: *WM, args: Args(.set_workspace_switch_mode), _: Allocator) !Value {
    wm.workspace_switch_mode = args.mode;
    return .nil;
}

pub fn set_autoclean(wm: *WM, args: Args(.set_autoclean), _: Allocator) !Value {
    wm.set_autoclean(args.enabled);
    return .nil;
}

pub fn cleanup_left_behind(wm: *WM, _: void, _: Allocator) !Value {
    const og = wm.pending_cleanup_graph orelse return .nil;
    wm.cleanup_left_behind(og);
    wm.pending_cleanup_graph = null;
    return .nil;
}

// ---- queries ----
pub fn get_workspace(wm: *WM, args: Args(.get_workspace), _: Allocator) !Value {
    const id = try workspace_at(wm, args.index) orelse return .nil;
    return .{ .integer = id };
}

pub fn get_workspace_positions(wm: *WM, _: void, arena: Allocator) !Value {
    const st = try states(wm, arena);
    var out: std.ArrayListUnmanaged(Value) = .empty;
    for (st, 1..) |s, pos| {
        if (s != .inactive) try out.append(arena, .{ .integer = @intCast(pos) });
    }
    return .{ .list = out.items };
}

pub fn get_workspace_states(wm: *WM, _: void, arena: Allocator) !Value {
    const st = try states(wm, arena);
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    try sorted_workspaces(wm, parent_graph(wm), &list); // the same order as states
    const out = try arena.alloc(Value, st.len);
    for (st, list.items, out, 1..) |s, n, *v, pos| {
        v.* = .{ .map = try arena.dupe(Value.Field, &.{
            .{ .key = "position", .value = .{ .integer = @intCast(pos) } },
            .{ .key = "state", .value = .{ .str = @tagName(s) } },
            .{ .key = "id", .value = util.id_value(wm, n) },
        }) };
    }
    return .{ .list = out };
}

pub fn get_current_workspace_position(wm: *WM, _: void, _: Allocator) !Value {
    const pos = try current_position(wm) orelse return .nil;
    return .{ .integer = @intCast(pos) };
}

pub fn get_workspaces_at_level(wm: *WM, _: void, arena: Allocator) !Value {
    const nums = try level_numbers(wm, arena);
    const out = try arena.alloc(Value, nums.len);
    for (nums, out) |num, *v| v.* = .{ .integer = num };
    return .{ .list = out };
}

pub fn get_current_workspace(wm: *WM, _: void, _: Allocator) !Value {
    return .{ .integer = wm.current_graph.id.number + 1 };
}

pub fn get_current_level(wm: *WM, _: void, _: Allocator) !Value {
    return .{ .integer = wm.current_graph.id.level };
}

pub fn get_node_level(wm: *WM, args: Args(.get_node_level), _: Allocator) !Value {
    const n = wm.get_node_by_id(args.id) orelse return .nil;
    const g = n.owner_graph orelse return .nil;
    return .{ .integer = g.id.level };
}
