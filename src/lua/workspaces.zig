const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;
const NodeList = std.ArrayListUnmanaged(*Node);

// ---- helpers ----
/// The graph holding the current workspace and its siblings.
fn parent_graph() *Graph {
    const wm = util.global_wm;
    const pn = wm.current_graph.parent_node orelse return &wm.graph;
    return pn.owner_graph orelse &wm.graph;
}

fn by_id(_: void, a: *Node, b: *Node) bool {
    const wm = util.global_wm;
    const id_a = wm.get_id_for_node(a) orelse return false;
    const id_b = wm.get_id_for_node(b) orelse return false;
    return id_a < id_b;
}

/// The workspace nodes of g, in creation order. These are the 1-based indices the API uses.
fn sorted_workspaces(g: *Graph, out: *NodeList) !void {
    out.clearRetainingCapacity();
    for (g.nodes.items) |node| {
        if (node.content == .workspace) try out.append(util.global_wm.allocator, node);
    }
    std.sort.heap(*Node, out.items, {}, by_id);
}

/// Does the workspace hold any windows or nested workspaces?
fn has_content(sub: *Graph) bool {
    for (sub.nodes.items) |n| switch (n.content) {
        .window, .workspace => return true,
        .empty => {},
    };
    return false;
}

/// Grow parent to at least count workspaces. New ones have the highest
/// ids, so appending keeps list sorted.
fn ensure_workspaces(parent: *Graph, list: *NodeList, count: usize) !void {
    const wm = util.global_wm;
    while (list.items.len < count) {
        try list.append(wm.allocator, try wm.add_workspace_node(parent));
    }
}

/// Enter target, or the previous workspace if target is already current
/// and switch mode is "previous". siblings are the candidates for "previous".
fn enter_or_back(target: *Node, siblings: []const *Node) !void {
    const wm = util.global_wm;
    const current = wm.current_graph;
    if (target.content.workspace != current) {
        wm.journal.set(wm, "previous_graph", current);
        return wm.enter_workspace(target);
    }
    if (wm.workspace_switch_mode != .previous) return;
    const prev = wm.previous_graph orelse return;
    for (siblings) |n| {
        if (n.content == .workspace and n.content.workspace == prev) {
            wm.journal.set(wm, "previous_graph", current);
            return wm.enter_workspace(n);
        }
    }
}

// ---- switching ----
fn switch_to(index: usize) !void {
    const wm = util.global_wm;
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    const parent = parent_graph();
    try sorted_workspaces(parent, &list);
    try ensure_workspaces(parent, &list, index);
    try enter_or_back(list.items[index - 1], list.items);
}

pub fn l_switch_to_workspace(lua: *Lua) i32 {
    const index = lua.checkInteger(1);
    if (index < 1) util.luaL_error_str(lua, "workspace index must be >= 1");
    switch_to(@intCast(index)) catch |err| util.raise_with(lua, "switch_to_workspace: ", @errorName(err));
    return 0;
}

fn send_to(node_id: u32, index: usize) !void {
    const wm = util.global_wm;
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    const parent = parent_graph();
    try sorted_workspaces(parent, &list);
    try ensure_workspaces(parent, &list, index);
    try wm.send_to_workspace(node_id, list.items[index - 1].content.workspace);
}

pub fn l_send_to_workspace(lua: *Lua) i32 {
    const node_id = util.check_node_id(lua, 1) orelse util.luaL_error_str(lua, "invalid node id");
    const index = lua.checkInteger(2);
    if (index < 1) util.luaL_error_str(lua, "workspace index must be >= 1");
    send_to(node_id, @intCast(index)) catch |err| util.raise_with(lua, "send_to_workspace: ", @errorName(err));
    return 0;
}

pub fn l_enter_workspace_by_id(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid workspace id");
    if (node.content != .workspace) util.luaL_error_str(lua, "node is not a workspace");
    const siblings = if (util.global_wm.current_graph.parent_node) |_| parent_graph().nodes.items else util.global_wm.current_graph.nodes.items;
    enter_or_back(node, siblings) catch |err| util.raise_with(lua, "enter_workspace_by_id: ", @errorName(err));
    return 0;
}

// ---- nesting ----
pub fn l_create_nested_workspace(lua: *Lua) i32 {
    const wm = util.global_wm;
    const g = wm.current_graph;
    const node = wm.create_workspace_node_with_preview(g) catch util.luaL_error_str(lua, "create failed");
    const id = wm.register_node(node.preview_window, node) catch util.luaL_error_str(lua, "register failed");

    const prev_id: ?u32 = if (wm.focused) |f|
        (if (f.owner_graph == g) wm.get_id_for_node(f) else null)
    else
        null;
    wm.call_arranger(g, "map", id, prev_id);

    // New graph and node: no journal entries needed for their own fields.
    const sub = node.content.workspace;
    sub.gap_inner_h = wm.default_gap_inner_h;
    sub.gap_inner_v = wm.default_gap_inner_v;
    sub.gap_outer_h = wm.default_gap_outer_h;
    sub.gap_outer_v = wm.default_gap_outer_v;
    node.hidden = false;

    wm.relayout();
    if (wm.focused) |f| wm.focus(f);
    lua.pushInteger(@intCast(id));
    return 1;
}

pub fn l_enter_nested(lua: *Lua) i32 {
    const node = util.global_wm.focused orelse return 0;
    if (node.content != .workspace) return 0;
    util.global_wm.enter_workspace(node) catch util.luaL_error_str(lua, "enter failed");
    return 0;
}

pub fn l_enter_nested_by_id(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse util.luaL_error_str(lua, "invalid node");
    if (node.content != .workspace) util.luaL_error_str(lua, "not a workspace");
    util.global_wm.enter_workspace(node) catch util.luaL_error_str(lua, "enter failed");
    return 0;
}

pub fn l_leave_nested(lua: *Lua) i32 {
    util.global_wm.leave_workspace() catch util.luaL_error_str(lua, "leave failed");
    return 0;
}

// ---- queries ----
fn push_workspace_at(lua: *Lua, index: usize) !void {
    const wm = util.global_wm;
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    try sorted_workspaces(wm.current_graph, &list);
    if (index > list.items.len) return lua.pushNil();
    const id = wm.get_id_for_node(list.items[index - 1]) orelse return lua.pushNil();
    lua.pushInteger(@intCast(id));
}

pub fn l_get_workspace(lua: *Lua) i32 {
    const index = lua.checkInteger(1);
    if (index < 1) {
        lua.pushNil();
        return 1;
    }
    push_workspace_at(lua, @intCast(index)) catch util.luaL_error_str(lua, "get_workspace: out of memory");
    return 1;
}

fn push_positions(lua: *Lua, comptime with_state: bool) !void {
    const wm = util.global_wm;
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    try sorted_workspaces(parent_graph(), &list);

    lua.newTable();
    var out: i64 = 1;
    for (list.items, 1..) |node, pos| {
        const sub = node.content.workspace;
        const current = sub == wm.current_graph;
        const content = has_content(sub);
        if (with_state) {
            lua.newTable();
            lua.pushInteger(@intCast(pos));
            lua.setField(-2, "position");
            _ = lua.pushString(if (current) "focused" else if (content) "active" else "inactive");
            lua.setField(-2, "state");
            lua.setIndexRaw(-2, @intCast(pos));
        } else if (current or content) {
            lua.pushInteger(@intCast(pos));
            lua.setIndexRaw(-2, out);
            out += 1;
        }
    }
}

pub fn l_get_workspace_positions(lua: *Lua) i32 {
    push_positions(lua, false) catch util.luaL_error_str(lua, "get_workspace_positions: out of memory");
    return 1;
}

pub fn l_get_workspace_states(lua: *Lua) i32 {
    push_positions(lua, true) catch util.luaL_error_str(lua, "get_workspace_states: out of memory");
    return 1;
}

fn current_position() !?usize {
    const wm = util.global_wm;
    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    try sorted_workspaces(parent_graph(), &list);
    for (list.items, 1..) |node, pos| {
        if (node.content.workspace == wm.current_graph) return pos;
    }
    return null;
}

pub fn l_get_current_workspace_position(lua: *Lua) i32 {
    const pos = current_position() catch util.luaL_error_str(lua, "get_current_workspace_position: out of memory");
    if (pos) |p| lua.pushInteger(@intCast(p)) else lua.pushNil();
    return 1;
}

fn push_levels(lua: *Lua) !void {
    const wm = util.global_wm;
    const level = wm.current_graph.id.level;
    const parent: *Graph = if (wm.current_graph.parent_node) |pn| pn.owner_graph orelse wm.current_graph else wm.current_graph;

    var list: NodeList = .empty;
    defer list.deinit(wm.allocator);
    for (parent.nodes.items) |node| {
        if (node.content != .workspace) continue;
        const sub = node.content.workspace;
        if (sub.id.level != level) continue;
        if (sub == wm.current_graph or has_content(sub)) try list.append(wm.allocator, node);
    }
    std.sort.heap(*Node, list.items, {}, struct {
        fn lt(_: void, a: *Node, b: *Node) bool {
            return a.content.workspace.id.number < b.content.workspace.id.number;
        }
    }.lt);

    lua.newTable();
    for (list.items, 1..) |node, i| {
        lua.pushInteger(@intCast(node.content.workspace.id.number + 1));
        lua.setIndexRaw(-2, @intCast(i));
    }
}

pub fn l_get_workspaces_at_level(lua: *Lua) i32 {
    push_levels(lua) catch util.luaL_error_str(lua, "get_workspaces_at_level: out of memory");
    return 1;
}

pub fn l_get_current_workspace(lua: *Lua) i32 {
    lua.pushInteger(@intCast(util.global_wm.current_graph.id.number + 1));
    return 1;
}

pub fn l_get_current_level(lua: *Lua) i32 {
    lua.pushInteger(@intCast(util.global_wm.current_graph.id.level));
    return 1;
}

pub fn l_get_node_level(lua: *Lua) i32 {
    const node = util.node_arg(lua, 1) orelse {
        lua.pushNil();
        return 1;
    };
    const g = node.owner_graph orelse {
        lua.pushNil();
        return 1;
    };
    lua.pushInteger(@intCast(g.id.level));
    return 1;
}

// ---- settings and cleanup ----
pub fn l_set_workspace_switch_mode(lua: *Lua) i32 {
    const mode = lua.checkString(1);
    util.global_wm.workspace_switch_mode = if (std.mem.eql(u8, mode, "previous")) .previous else .none;
    return 0;
}

pub fn l_set_autoclean(lua: *Lua) i32 {
    util.global_wm.set_autoclean(lua.toBoolean(1));
    return 0;
}

pub fn l_cleanup_left_behind(lua: *Lua) i32 {
    _ = lua;
    const wm = util.global_wm;
    const og = wm.pending_cleanup_graph orelse return 0;
    wm.cleanup_left_behind(og);
    wm.pending_cleanup_graph = null;
    return 0;
}
