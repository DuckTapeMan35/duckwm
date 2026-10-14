const std = @import("std");
const graph = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const focus = @import("focus.zig");
const registry = @import("registry.zig");
const WM = core.WM;
const Graph = graph.Graph;
const Node = graph.Node;

pub const WorkspaceSwitchMode = enum { none, previous };

pub fn free_graph(wm: *WM, g: *Graph) void {
    if (g.arranger_name.len > 0) {
        wm.allocator.free(g.arranger_name);
    }
    for (g.nodes.items) |node| {
        if (wm.focused == node) {
            wm.focused = null;
        }
        if (g.fullscreen_node == node) {
            g.fullscreen_node = null;
        }
        if (node.content == .workspace) {
            free_graph(wm, node.content.workspace);
            wm.allocator.destroy(node.content.workspace);
        }
        // destroy any preview window
        if (node.preview_window) |pw| wm.backend.destroy_preview_window(pw);
        node.deinit(wm.allocator);
        wm.allocator.destroy(node);
    }
    g.nodes.deinit(wm.allocator);
    g.focus_edges.deinit(wm.allocator);
}

pub fn enter_workspace(wm: *WM, node: *Node) !void {
    if (node.content != .workspace) return error.NotWorkspace;
    const new = node.content.workspace;

    if (new == wm.current_graph) return;
    const old = wm.current_graph;

    // push parent
    try stack_push(wm, old);

    // switch
    try stack_push(wm, old);
    wm.journal.set(wm, "current_graph", new);
    wm.journal.set(wm, "visible_graph", new);

    // re-layout and paint the new graph into place first
    try wm.resolve(new);
    try wm.flush(new);

    // focus something
    try wm.rebuild_focus_edges();
    if (focus.top_left_window(wm)) |n| {
        wm.set_focus(n);
    } else {
        wm.clear_focus();
    }
    sync_workspace_state(wm);
}

pub fn leave_workspace(wm: *WM) !void {
    if (wm.workspace_stack.items.len == 0) return;
    const target_idx = find_leave_target(wm) orelse return;
    const old = wm.current_graph;

    wm.clear_focus();

    while (wm.workspace_stack.items.len > target_idx + 1) _ = stack_pop(wm);
    const back = stack_pop(wm).?;
    wm.journal.set(wm, "current_graph", back);
    wm.journal.set(wm, "visible_graph", back);

    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
    if (old.parent_node) |pn| {
        wm.repaint_preview(pn);
    }
    if (focus.top_left_window(wm)) |n| wm.set_focus(n) else {
        wm.clear_focus();
    }
    sync_workspace_state(wm);
}

pub fn activate_window(wm: *WM, node: *Node) !void {
    const target = node.owner_graph orelse return;

    // dont yank the user to the "virtual" workspace scratchpads use
    if (target == wm.scratch_graph) {
        if (wm.get_id_for_node(node)) |id| try wm.show_scratchpad(id);
        return;
    }

    if (target != wm.current_graph) {
        // get onto a shared ancestor of the target
        var target_anc = std.AutoHashMapUnmanaged(*Graph, void){};
        defer target_anc.deinit(wm.allocator);
        {
            var g: *Graph = target;
            while (true) {
                try target_anc.put(wm.allocator, g, {});
                const pn = g.parent_node orelse break;
                g = pn.owner_graph orelse break;
            }
        }
        var guard: usize = 0;
        while (!target_anc.contains(wm.current_graph) and guard < 64) : (guard += 1) {
            const before = wm.current_graph;
            try leave_workspace(wm);
            if (wm.current_graph == before) break; // level-1 stall (common ancestor is root)
        }

        // walk down the parent_node chain into target
        var chain: std.ArrayListUnmanaged(*Node) = .{ .items = &.{}, .capacity = 0 };
        defer chain.deinit(wm.allocator);
        var g: *Graph = target;
        while (g != wm.current_graph) {
            const pn = g.parent_node orelse break;
            try chain.append(wm.allocator, pn);
            g = pn.owner_graph orelse break;
        }
        var i = chain.items.len;
        while (i > 0) {
            i -= 1;
            try enter_workspace(wm, chain.items[i]);
        }
    }

    wm.set_focus(node);
    try wm.flush(wm.current_graph);
}

pub fn send_to_workspace(wm: *WM, node_id: u32, target_graph: *graph.Graph) !void {
    const node = wm.get_node_by_id(node_id) orelse return error.InvalidNode;
    const src_graph = node.owner_graph orelse return error.InvalidNode;
    if (src_graph == target_graph) return;

    src_graph.detach_node(node);
    try src_graph.replace_constraints(node, &.{});
    try target_graph.attach_node(node);

    if (wm.focused == node) {
        if (src_graph.fullscreen_node == node) src_graph.set(src_graph, "fullscreen_node", null);
        wm.clear_focus();
    }

    // Call source arranger in source graph context
    const saved_graph = wm.current_graph;
    wm.current_graph = src_graph;
    if (!node.floating) {
        wm.call_arranger(src_graph, "unmap", node_id, null);
    }
    wm.resolve(src_graph) catch {};
    wm.rebuild_focus_edges() catch {};
    wm.flush(src_graph) catch {};

    // Call target arranger in target graph context
    wm.current_graph = target_graph;
    var target_prev_id: ?u32 = null;
    for (target_graph.nodes.items) |n| {
        if (n == node) continue;
        if (n.content == .window or n.content == .workspace) {
            if (wm.get_id_for_node(n)) |id| {
                target_prev_id = id;
                break;
            }
        }
    }

    if (!node.floating) {
        wm.call_arranger(target_graph, "map", node_id, target_prev_id);
    }

    // Hide frame if target is not visible
    if (target_graph != saved_graph) {
        if (node.window()) |h| wm.backend.hide_window(h);
    } else {
        wm.resolve(target_graph) catch {};
        wm.rebuild_focus_edges() catch {};
        wm.flush(target_graph) catch {};
    }

    wm.current_graph = saved_graph;
    switch (node.content) {
        .window => |win| wm.sync_window_workspace(win),
        else => {},
    }
    sync_workspace_state(wm);
}

pub fn sync_workspace_state(wm: *WM) void {
    const parent_graph: *graph.Graph = if (wm.current_graph.parent_node) |pn|
        pn.owner_graph orelse &wm.graph
    else
        &wm.graph;

    var count: u32 = 0;
    var current: u32 = 0;
    for (parent_graph.nodes.items) |node| {
        if (node.content != .workspace) continue;
        if (node.content.workspace == wm.current_graph) current = count;
        count += 1;
    }
    wm.backend.publish_workspaces(@max(count, 1), current);

    var client_list: std.ArrayListUnmanaged(types.WindowHandle) = .empty;
    defer client_list.deinit(wm.allocator);
    var it = wm.window_to_node_id.iterator();
    while (it.next()) |entry| {
        const node = wm.node_registry.get(entry.value_ptr.*) orelse continue;
        if (node.content != .window) continue;
        client_list.append(wm.allocator, entry.key_ptr.*) catch {};
    }
    wm.backend.publish_window_list(client_list.items);
}

pub fn sync_window_workspace(wm: *WM, win: types.WindowHandle) void {
    const node_id = wm.window_to_node_id.get(win) orelse return;
    const node = wm.node_registry.get(node_id) orelse return;
    const owner = node.owner_graph orelse return;

    const parent_graph: *graph.Graph = if (owner.parent_node) |pn|
        pn.owner_graph orelse &wm.graph
    else
        &wm.graph;

    var idx: u32 = 0;
    for (parent_graph.nodes.items) |n| {
        if (n.content != .workspace) continue;
        if (n.content.workspace == owner) break;
        idx += 1;
    }
    wm.backend.publish_window_workspace(win, idx);
}

pub fn create_workspace_graph(wm: *WM, level: u32) !*graph.Graph {
    const sub = try wm.allocator.create(graph.Graph);
    sub.* = graph.Graph.init(wm.allocator);
    sub.on_node_free = registry.on_node_freed;
    sub.on_node_free_ctx = wm;
    sub.id = try alloc_workspace_id(wm, level);
    sub.gap_inner_h = wm.default_gap_inner_h;
    sub.gap_inner_v = wm.default_gap_inner_v;
    sub.gap_outer_h = wm.default_gap_outer_h;
    sub.gap_outer_v = wm.default_gap_outer_v;
    sub.journal = &wm.journal;
    if (wm.default_arranger_name.len > 0 and sub.arranger_name.len == 0) {
        sub.arranger_name = try wm.allocator.dupe(u8, wm.default_arranger_name);
    }
    return sub;
}

pub fn create_workspace_node_with_preview(wm: *WM, owner_graph: *graph.Graph) !*Node {
    const sub = try create_workspace_graph(wm, owner_graph.id.level + 1);
    wm.journal.external(undo_free_graph, wm, @intFromPtr(sub));
    const node = try owner_graph.add_node(.{ .workspace = sub });
    sub.parent_node = node;
    node.floating = false;
    node.hidden = true;
    node.preview_window = try wm.backend.create_preview_window(wm.frame_options(node));
    wm.journal.external(undo_destroy_preview, wm, node.preview_window.?);
    wm.repaint_preview(node);
    return node;
}

/// A workspace without a preview window, registered and ready to enter.
pub fn add_workspace_node(wm: *WM, parent: *graph.Graph) !*Node {
    const sub = try create_workspace_graph(wm, parent.id.level + 1);
    wm.journal.external(undo_free_graph, wm, @intFromPtr(sub));
    const node = try parent.add_node(.{ .workspace = sub });
    sub.parent_node = node;
    node.floating = false;
    _ = try wm.register_node(null, node);
    return node;
}

/// Create the very first workspace node in the top-level graph.
/// This is called once in run so that Super+Ctrl+1 always works
/// and the screen is never empty.
pub fn create_initial_workspace(wm: *WM) !void {
    // Root container
    const root_node = try wm.current_graph.add_node(.empty);
    root_node.width = wm.screen_width;
    root_node.height = wm.screen_height;
    root_node.x = 0;
    root_node.y = 0;
    _ = try wm.register_node(null, root_node);

    // Workspace sub-graph
    const sub = try create_workspace_graph(wm, 1);

    const ws_node = try wm.current_graph.add_node(.{ .workspace = sub });
    sub.parent_node = ws_node;
    ws_node.floating = false;
    const pw = try wm.backend.create_preview_window(wm.frame_options(ws_node));
    ws_node.preview_window = pw;
    _ = try wm.register_node(pw, ws_node);

    // Constraint to fill root
    const g = graph.Constraint{ .grid_cell = .{
        .col = 0,
        .row = 0,
        .cols = 1,
        .rows = 1,
        .container = root_node,
    } };
    try wm.current_graph.add_constraint(ws_node, g);

    // Resolve, paint, then enter
    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
    wm.repaint_preview(ws_node); // paint while still on parent graph
    try enter_workspace(wm, ws_node);
}

fn alloc_workspace_id(wm: *WM, level: u32) !graph.GraphId {
    const entry = try wm.next_workspace_number.getOrPut(wm.allocator, level);
    if (!entry.found_existing) entry.value_ptr.* = 0;
    const number = entry.value_ptr.*;
    entry.value_ptr.* += 1;
    return .{ .level = level, .number = number };
}

fn find_leave_target(wm: *WM) ?usize {
    const current_level = wm.current_graph.id.level;
    var i = wm.workspace_stack.items.len;
    while (i > 0) {
        i -= 1;
        const g = wm.workspace_stack.items[i];
        if (g == &wm.graph) break;
        if (g.id.level < current_level) return i;
    }
    return null;
}

fn stack_push(wm: *WM, g: *Graph) !void {
    try wm.workspace_stack.append(wm.allocator, g);
    wm.journal.external(undo_stack_push, wm, 0);
}

fn stack_pop(wm: *WM) ?*Graph {
    const g = wm.workspace_stack.pop() orelse return null;
    wm.journal.external(undo_stack_pop, wm, @intFromPtr(g));
    return g;
}

fn undo_stack_push(ctx: *anyopaque, _: u64) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    _ = wm.workspace_stack.pop();
}

fn undo_stack_pop(ctx: *anyopaque, arg: u64) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    wm.workspace_stack.append(wm.allocator, @ptrFromInt(@as(usize, @intCast(arg)))) catch {};
}

fn undo_free_graph(ctx: *anyopaque, arg: u64) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    const g: *graph.Graph = @ptrFromInt(@as(usize, @intCast(arg)));
    g.nodes.deinit(wm.allocator);
    g.focus_edges.deinit(wm.allocator);
    if (g.arranger_name.len > 0) wm.allocator.free(g.arranger_name);
    wm.allocator.destroy(g);
}

fn undo_destroy_preview(ctx: *anyopaque, arg: u64) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    wm.backend.destroy_preview_window(arg);
}
