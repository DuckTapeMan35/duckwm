const std = @import("std");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const window_ops = @import("window_ops.zig");
const WM = core.WM;
const Node = graph_mod.Node;

pub fn on_node_freed(ctx: *anyopaque, node: *Node) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    if (node.parked_term) |term| {
        node.parked_term = null;
        window_ops.free_parked_terminal(wm, term);
    }
    switch (node.content) {
        .window => |win| _ = wm.window_to_node_id.remove(win),
        .workspace => if (node.preview_window) |pw| {
            _ = wm.window_to_node_id.remove(pw);
        },
        // destroy_node has already freed the group's nodes (free_subgraph);
        // what's left is what only the group's graph held, then the graph itself.
        .group => |sub| {
            wm.drop_owned_binds(sub);
            if (sub.arranger) |cb| wm.release_callback(cb);
            if (sub.arranger_name.len > 0) wm.allocator.free(sub.arranger_name);
            wm.allocator.destroy(sub);
        },
        .empty => {},
    }
    if (get_id_for_node(wm, node)) |id| {
        _ = wm.node_registry.remove(id);
    }
    if (wm.focused == node) wm.focused = null;
    if (node.owner_graph) |og| {
        if (og.fullscreen_node == node) og.fullscreen_node = null;
    }
}

pub fn register_node(wm: *WM, win: ?types.WindowHandle, node: *Node) !u32 {
    const id = wm.next_node_id;
    try wm.node_registry.put(wm.allocator, id, node);
    if (win) |w| {
        try wm.window_to_node_id.put(wm.allocator, w, id);
    }
    wm.journal.external(undo_register, wm, id);
    wm.next_node_id += 1;
    return id;
}
fn undo_register(ctx: *anyopaque, id: u64) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    const kv = wm.node_registry.fetchRemove(@intCast(id)) orelse return;
    var it = wm.window_to_node_id.iterator();
    while (it.next()) |e| {
        if (e.value_ptr.* == kv.key) {
            _ = wm.window_to_node_id.remove(e.key_ptr.*);
            break;
        }
    }
}

pub fn get_node_by_id(wm: *WM, id: u32) ?*Node {
    const node = wm.node_registry.get(id) orelse return null;
    return if (node.dead) null else node;
}

pub fn get_id_for_node(wm: *WM, node: *Node) ?u32 {
    var it = wm.node_registry.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == node) return entry.key_ptr.*;
    }
    return null;
}

pub fn set_node_empty(wm: *WM, node_id: u32) void {
    if (wm.node_registry.get(node_id)) |node| {
        switch (node.content) {
            .window => |win| {
                _ = wm.window_to_node_id.remove(win);
            },
            else => {},
        }
        node.content = .empty;
        node.info = .{};
    }
}

pub fn set_node_window(wm: *WM, node_id: u32, win: types.WindowHandle) !void {
    if (wm.node_registry.get(node_id)) |node| {
        switch (node.content) {
            .window => |old_win| {
                _ = wm.window_to_node_id.remove(old_win);
            },
            else => {},
        }
        node.content = .{ .window = win };
        node.info = wm.backend.window_info(win);
        try wm.window_to_node_id.put(wm.allocator, win, node_id);
    }
}

pub fn move_window_to_node(wm: *WM, src_node_id: u32, dst_node_id: u32) !void {
    const src = wm.node_registry.get(src_node_id) orelse return error.InvalidNode;
    const dst = wm.node_registry.get(dst_node_id) orelse return error.InvalidNode;
    if (src.content != .window or dst.content != .empty)
        return error.InvalidState;

    const win = src.content.window;
    _ = wm.window_to_node_id.remove(win);
    dst.content = .{ .window = win };
    try wm.window_to_node_id.put(wm.allocator, win, dst_node_id);
    src.content = .empty;
    dst.info = src.info;
    src.info = .{};
}
