const std = @import("std");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const groups = @import("groups.zig");
const focus_mod = @import("focus.zig");

const WM = core.WM;
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;

pub fn exchange(wm: *WM, a: *Node, b: *Node) !void {
    const id_a = wm.get_id_for_node(a) orelse return error.InvalidNode;
    const id_b = wm.get_id_for_node(b) orelse return error.InvalidNode;
    if (a.content == .empty and b.content == .empty) return;
    try exchange_raw(wm, a, b, id_a, id_b);
    wm.journal.external(undo_exchange, wm, (@as(u64, id_a) << 32) | id_b);
    try wm.flush(wm.current_graph);
}

pub fn exchange_left(wm: *WM) anyerror!void {
    const focused = wm.focused orelse return;
    if (focus_mod.find_focus_target(wm, .Left)) |target| try exchange(wm, focused, target);
}

pub fn exchange_right(wm: *WM) anyerror!void {
    const focused = wm.focused orelse return;
    if (focus_mod.find_focus_target(wm, .Right)) |target| try exchange(wm, focused, target);
}

pub fn exchange_up(wm: *WM) anyerror!void {
    const focused = wm.focused orelse return;
    if (focus_mod.find_focus_target(wm, .Up)) |target| try exchange(wm, focused, target);
}

pub fn exchange_down(wm: *WM) anyerror!void {
    const focused = wm.focused orelse return;
    if (focus_mod.find_focus_target(wm, .Down)) |target| try exchange(wm, focused, target);
}

fn undo_exchange(ctx: *anyopaque, arg: u64) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    const id_a: u32 = @truncate(arg >> 32);
    const id_b: u32 = @truncate(arg);
    const a = wm.node_registry.get(id_a) orelse return;
    const b = wm.node_registry.get(id_b) orelse return;
    exchange_raw(wm, a, b, id_a, id_b) catch {};
}

fn exchange_raw(wm: *WM, a: *Node, b: *Node, id_a: u32, id_b: u32) !void {
    // Swap contents
    const content_a = a.content;
    const content_b = b.content;
    if (content_a == .empty and content_b == .empty) return;

    // At most four entries are re-added below; after this, nothing can fail.
    try wm.window_to_node_id.ensureUnusedCapacity(wm.allocator, 4);

    // Update window_to_node_id for window nodes
    switch (content_a) {
        .window => |win| _ = wm.window_to_node_id.remove(win),
        else => {},
    }
    switch (content_b) {
        .window => |win| _ = wm.window_to_node_id.remove(win),
        else => {},
    }

    // Swap preview_window and content
    const pw_a = a.preview_window;
    const pw_b = b.preview_window;
    a.content = content_b;
    b.content = content_a;
    a.preview_window = pw_b;
    b.preview_window = pw_a;

    const a_focused = a.border_color_focused;
    const a_unfocused = a.border_color_unfocused;
    a.border_color_focused = b.border_color_focused;
    a.border_color_unfocused = b.border_color_unfocused;
    b.border_color_focused = a_focused;
    b.border_color_unfocused = a_unfocused;

    // swap window info
    const info_a = a.info;
    a.info = b.info;
    b.info = info_a;

    // Update workspace and group parent_node pointers
    if (a.inner()) |sub| sub.parent_node = a;
    if (b.inner()) |sub| sub.parent_node = b;

    // Update window_to_node_id for new positions
    switch (a.content) {
        .window => |win| try wm.window_to_node_id.put(wm.allocator, win, id_a),
        else => {},
    }
    switch (b.content) {
        .window => |win| try wm.window_to_node_id.put(wm.allocator, win, id_b),
        else => {},
    }

    // Update window_to_node_id for swapped preview windows
    if (pw_a) |pw| {
        _ = wm.window_to_node_id.remove(pw);
        try wm.window_to_node_id.put(wm.allocator, pw, id_b);
    }
    if (pw_b) |pw| {
        _ = wm.window_to_node_id.remove(pw);
        try wm.window_to_node_id.put(wm.allocator, pw, id_a);
    }

    // Update focused pointer
    if (wm.focused == a) wm.focused = b else if (wm.focused == b) wm.focused = a;
}

pub fn kill_client(wm: *WM) !void {
    const node = wm.focused orelse return;
    switch (node.content) {
        .window => |win| wm.effect(.{ .close_window = win }),
        .workspace => {
            if (node.content.workspace == wm.current_graph) {
                try wm.leave_workspace();
            }
            // Detect hidden (no-preview) sibling workspaces that still hold windows.
            var cleanup_graph: ?*Graph = null;
            if (node.owner_graph) |owner| {
                const og = owner.workspace();
                const killed_level = node.content.workspace.id.level;
                for (og.nodes.items) |sibling| {
                    if (sibling == node) continue;
                    if (sibling.content != .workspace) continue;
                    if (sibling.content.workspace.id.level != killed_level) continue;
                    if (sibling.preview_window != null) continue;
                    if (graph_has_content(wm, sibling.content.workspace)) {
                        cleanup_graph = og;
                        break;
                    }
                }
            }

            // Kill the targeted workspace itwm.
            kill_graph_windows(wm, node.content.workspace);
            if (node.preview_window) |pw| {
                wm.backend.destroy_preview_window(pw);
            }

            // sweep silently when autoclean is on, else prompt.
            if (cleanup_graph) |og| {
                if (wm.autoclean) {
                    cleanup_left_behind(wm, og);
                } else {
                    wm.pending_cleanup_graph = og;
                    notify(wm, "Windows left behind", "Hidden workspaces still have windows open");
                }
            }
        },
        else => {},
    }
}

pub fn kill_graph_windows(wm: *WM, g: *graph_mod.Graph) void {
    for (g.nodes.items) |node| {
        switch (node.content) {
            .window => |win| {
                wm.backend.unframe(win, true);
                wm.effect(.{ .close_window = win });
                if (wm.window_to_node_id.get(win)) |id| {
                    _ = wm.node_registry.remove(id);
                    _ = wm.window_to_node_id.remove(win);
                }
            },
            .workspace, .group => |sub| kill_graph_windows(wm, sub),
            .empty => {},
        }
    }
}

pub fn cleanup_left_behind(wm: *WM, og: *Graph) void {
    var i: usize = 0;
    while (i < og.nodes.items.len) {
        const node = og.nodes.items[i];
        if (node.content != .workspace or node.preview_window != null) {
            i += 1;
            continue;
        }
        if (!graph_has_content(wm, node.content.workspace)) {
            i += 1;
            continue;
        }
        kill_graph_windows(wm, node.content.workspace);
        og.remove_node(node);
    }
}

pub fn graph_has_content(wm: *WM, g: *graph_mod.Graph) bool {
    for (g.nodes.items) |node| {
        switch (node.content) {
            .window => return true,
            .workspace, .group => |sub| if (graph_has_content(wm, sub)) return true,
            .empty => {},
        }
    }
    return false;
}

pub fn show_scratchpad(wm: *WM, node_id: u32) !void {
    const node = wm.node_registry.get(node_id) orelse return;
    if (node.window() == null) return;

    wm.journal.set(node, "floating", true);

    try wm.send_to_workspace(node_id, wm.current_graph);

    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
    if (node.content == .workspace) wm.repaint_preview(node);
    wm.set_focus(node);
}

pub fn hide_scratchpad(wm: *WM, node_id: u32) !void {
    const node = wm.node_registry.get(node_id) orelse return;
    if (node.window() == null) return;

    try wm.send_to_workspace(node_id, wm.scratch_graph);
    wm.journal.set(node, "floating", true);

    if (focus_mod.top_left_window(wm)) |n| wm.set_focus(n);
}

pub fn toggle_scratchpad(wm: *WM, node_id: u32) !void {
    const node = wm.node_registry.get(node_id) orelse return;
    if (node.window() == null) return;

    if (node.owner_graph == wm.scratch_graph)
        try show_scratchpad(wm, node_id)
    else
        try hide_scratchpad(wm, node_id);
}

pub fn unmanage_as_dock(wm: *WM, win: types.WindowHandle) !void {
    const node_id = wm.window_to_node_id.get(win) orelse return;
    const node = wm.node_registry.get(node_id) orelse return;

    wm.backend.release_window(win);

    // Remove from graph and registry
    _ = wm.node_registry.remove(node_id);
    _ = wm.window_to_node_id.remove(win);
    if (node.owner_graph) |graph| {
        graph.remove_node(node);
        groups.dissolve_if_empty(wm, graph);
    }

    // Recalculate layout
    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);
}

pub fn notify(wm: *WM, summary: []const u8, body: []const u8) void {
    const cmd = std.fmt.allocPrint(
        wm.allocator,
        "action=$(notify-send -a duckwm -t 0 --action 'default=Clean up' --wait '{s}' '{s}'); " ++
            "[ \"$action\" = default ] && quack cleanup_left_behind",
        .{ summary, body },
    ) catch return;
    defer wm.allocator.free(cmd);
    const argv = [_][]const u8{ "sh", "-c", cmd };
    wm.spawn(&argv) catch {};
}

pub fn free_parked_terminal(wm: *WM, term: *Node) void {
    switch (term.content) {
        .window => |win| {
            wm.backend.unframe(win, true);
            wm.backend.close_window(win);
            _ = wm.window_to_node_id.remove(win);
        },
        else => {},
    }
    if (wm.get_id_for_node(term)) |tid| _ = wm.node_registry.remove(tid);
    if (wm.focused == term) wm.focused = null;
    if (term.owner_graph) |og| {
        if (og.fullscreen_node == term) og.fullscreen_node = null;
    }
    term.deinit(wm.allocator);
    wm.allocator.destroy(term);
}
