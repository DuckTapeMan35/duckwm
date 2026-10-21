const std = @import("std");
const registry = @import("registry.zig");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const output = @import("output.zig");
const scene = @import("scene.zig");
const WM = core.WM;
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;

var rearranging = false;

/// Groups nest at most this deep (Nodes keeps a fixed stack).
pub const max_depth = 15;

pub const OutlineStyle = struct { width: u32, color: u32 };

/// Every node of a graph and of the groups inside it, depth first, in order.
/// Group nodes themselves are skipped unless with_groups.
pub const Nodes = struct {
    stack: [max_depth + 1]struct { g: *Graph, i: usize } = undefined,
    depth: usize = 0,
    with_groups: bool = false,

    pub fn init(g: *Graph) Nodes {
        var it: Nodes = .{};
        it.stack[0] = .{ .g = g, .i = 0 };
        it.depth = 1;
        return it;
    }

    /// As init, but the group nodes are returned too (before their contents).
    pub fn all(g: *Graph) Nodes {
        var it = init(g);
        it.with_groups = true;
        return it;
    }

    pub fn next(self: *Nodes) ?*Node {
        while (self.depth > 0) {
            const top = &self.stack[self.depth - 1];
            if (top.i >= top.g.nodes.items.len) {
                self.depth -= 1;
                continue;
            }
            const n = top.g.nodes.items[top.i];
            top.i += 1;
            if (n.content == .group) {
                if (self.depth < self.stack.len) {
                    self.stack[self.depth] = .{ .g = n.content.group, .i = 0 };
                    self.depth += 1;
                }
                if (self.with_groups) return n;
                continue;
            }
            return n;
        }
        return null;
    }
};

/// Can focus land on n (if it isn't hidden): a window or a workspace preview.
pub fn focusable(n: *const Node) bool {
    return switch (n.content) {
        .window => true,
        .workspace => n.preview_window != null,
        .group, .empty => false,
    };
}

/// Groups in ws whose area changed size since their arranger last laid them
/// out get an area event, as workspaces do when their monitor changes.
pub fn rearrange_resized(wm: *WM, ws: *Graph) void {
    // An arranger answering area may resolve the workspace again.
    if (rearranging) return;
    rearranging = true;
    defer rearranging = false;
    check_sizes(wm, ws);
}

fn check_sizes(wm: *WM, g: *Graph) void {
    for (g.nodes.items) |n| {
        const sub = switch (n.content) {
            .group => |s| s,
            else => continue,
        };
        const a = area(wm, sub);
        const changed = a.width != sub.arranged_w or a.height != sub.arranged_h;
        if (a.width > 0 and a.height > 0 and changed) {
            // A new group was just laid out by its map events: only note its size.
            const first = sub.arranged_w == 0;
            sub.set(sub, "arranged_w", a.width);
            sub.set(sub, "arranged_h", a.height);
            if (!first) {
                const fid: u32 = if (wm.focused) |f| wm.get_id_for_node(f) orelse 0 else 0;
                wm.call_arranger(sub, .area, fid, null);
                scene.resolve(wm, sub) catch {};
            }
        }
        // Then the groups inside it, which its new layout may have resized.
        check_sizes(wm, sub);
    }
}

/// The graph commands act on: that of the node being resized, else of the
/// focused one, if it's in the current workspace; else the workspace.
pub fn active(wm: *WM) *Graph {
    const n: ?*Node = blk: {
        if (wm.edge_resizing or wm.corner_resizing) {
            if (wm.window_to_node_id.get(wm.resize_window)) |id| break :blk wm.node_registry.get(id);
        }
        break :blk wm.focused;
    };
    if (n) |f| {
        if (f.owner_graph) |og| {
            if (og.within(wm.current_graph)) return og;
        }
    }
    return wm.current_graph;
}

/// After geometry in g changed by hand (a resize): the groups in it fit
/// their own nodes to their new rectangles.
pub fn refit(wm: *WM, g: *Graph) void {
    for (g.nodes.items) |n| {
        if (n.content == .group) scene.resolve(wm, n.content.group) catch {};
    }
}

/// Does g hold anything but empty containers (in it or its groups)?
pub fn has_content(g: *Graph) bool {
    var it = Nodes.init(g);
    while (it.next()) |n| {
        if (n.content != .empty) return true;
    }
    return false;
}

/// An empty group (and any group that leaves empty in turn) leaves its graph;
/// that graph's arranger closes the gap. g may be freed after this.
pub fn dissolve_if_empty(wm: *WM, g: *Graph) void {
    var cur = g;
    while (cur.is_group and !has_content(cur)) {
        const node = cur.parent_node.?;
        if (node.dead) return;
        const parent = node.owner_graph orelse return;
        if (wm.get_id_for_node(node)) |id| {
            const prev: ?u32 = if (wm.focused) |f| wm.get_id_for_node(f) else null;
            if (!node.floating) wm.call_arranger(parent, .unmap, id, prev);
            _ = wm.node_registry.remove(id);
        }
        parent.remove_node(node);
        cur = parent;
    }
}

// ---- creating, moving, ungrouping ----
/// How many groups g is nested in (0: a workspace).
pub fn depth_of(g: *const Graph) usize {
    var d: usize = 0;
    var cur = g;
    while (cur.is_group) : (d += 1) cur = cur.parent_node.?.owner_graph.?;
    return d;
}

/// A new, empty group graph for a group in parent.
fn new_graph(wm: *WM, parent: *Graph) !*Graph {
    const sub = try wm.allocator.create(Graph);
    sub.* = Graph.init(wm.allocator);
    sub.is_group = true;
    sub.on_node_free = registry.on_node_freed;
    sub.on_node_free_ctx = wm;
    sub.journal = &wm.journal;
    sub.id = parent.id;
    sub.output = parent.output;
    // Its nodes sit as far apart as the windows around it; no outer gap of
    // its own, since its node already has one in the parent.
    sub.gap_inner_h = parent.gap_inner_h;
    sub.gap_inner_v = parent.gap_inner_v;
    if (wm.default_arranger_name.len > 0) sub.arranger_name = try wm.allocator.dupe(u8, wm.default_arranger_name);
    return sub;
}

/// Rollback of new_graph (it's empty by then: its nodes were rolled back first).
fn undo_new_graph(ctx: *anyopaque, arg: u64) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    const g: *Graph = @ptrFromInt(@as(usize, @intCast(arg)));
    if (g.arranger) |cb| wm.release_callback(cb);
    g.nodes.deinit(wm.allocator);
    g.focus_edges.deinit(wm.allocator);
    wm.allocator.free(g.arranger_state);
    if (g.arranger_name.len > 0) wm.allocator.free(g.arranger_name);
    wm.allocator.destroy(g);
}

/// A new group where the first tiled member was, with members moved into it,
/// in order. They must all be in one graph. Returns the group's id.
pub fn create(wm: *WM, members: []const *Node) !u32 {
    if (members.len == 0) return error.InvalidNode;
    const parent = members[0].owner_graph orelse return error.NotInGraph;
    for (members) |m| {
        if (m.owner_graph != parent) return error.NotSameGraph;
        if (m.content == .empty) return error.InvalidNode;
    }
    if (depth_of(parent) >= max_depth) return error.TooDeep;
    const keep_focus = wm.focused;

    // The group's node, placed by the parent's arranger next to the first
    // tiled member (which leaves next, so the group takes its place).
    const sub = try new_graph(wm, parent);
    wm.journal.external(undo_new_graph, wm, @intFromPtr(sub));
    const node = try parent.add_node(.{ .group = sub });
    sub.parent_node = node;
    const id = try wm.register_node(null, node);
    const anchor: ?u32 = for (members) |m| {
        if (!m.floating) break wm.get_id_for_node(m);
    } else null;
    wm.call_arranger(parent, .map, id, anchor);

    // Laid out now, so the members' map events see the group's real area.
    try wm.resolve(parent.workspace());
    const a = area(wm, sub);
    sub.arranged_w = a.width;
    sub.arranged_h = a.height;

    for (members) |m| {
        const mid = wm.get_id_for_node(m) orelse continue;
        try wm.send_to_workspace(mid, sub);
    }
    try settle(wm, parent.workspace());
    if (keep_focus) |f| if (!f.dead) wm.set_focus(f);
    return id;
}

/// Move node into target (a group, or a workspace). Focus stays on it if it
/// had it; a group it leaves empty goes.
pub fn move(wm: *WM, node_id: u32, target: *Graph) !void {
    const node = wm.get_node_by_id(node_id) orelse return error.InvalidNode;
    const src = node.owner_graph orelse return error.NotInGraph;
    if (src == target) return;
    if (node.content == .group) {
        // Not into itself, nor into a group inside it.
        if (target.within(node.content.group)) return error.InvalidNode;
        if (depth_of(target) >= max_depth) return error.TooDeep;
    }
    const had_focus = wm.focused == node;
    try wm.send_to_workspace(node_id, target);
    if (had_focus and !node.dead) wm.set_focus(node);
}

/// Everything in the group goes to the graph holding it, where the group
/// was, in order; then the group goes.
pub fn ungroup(wm: *WM, group: *Node) !void {
    const sub = switch (group.content) {
        .group => |s| s,
        else => return error.NotAGroup,
    };
    const parent = group.owner_graph orelse return error.NotInGraph;
    const keep_focus = wm.focused;

    var prev: ?u32 = wm.get_id_for_node(group);
    while (true) {
        const n = for (sub.nodes.items) |x| {
            if (x.content != .empty) break x;
        } else break;
        const nid = wm.get_id_for_node(n) orelse break;
        sub.detach_node(n);
        try sub.replace_constraints(n, &.{});
        try parent.attach_node(n);
        if (!n.floating) {
            wm.call_arranger(sub, .unmap, nid, null);
            wm.call_arranger(parent, .map, nid, prev);
            prev = nid;
        }
    }
    dissolve_if_empty(wm, sub);
    try settle(wm, parent.workspace());
    if (keep_focus) |f| if (!f.dead) wm.set_focus(f);
}

/// Lay the workspace out again and redraw it.
pub fn settle(wm: *WM, ws: *Graph) !void {
    try wm.resolve(ws);
    try wm.rebuild_focus_edges();
    try wm.flush(ws);
}

/// The group holding node, if it's in one.
pub fn group_of(node: *const Node) ?*Node {
    const og = node.owner_graph orelse return null;
    return if (og.is_group) og.parent_node else null;
}

pub fn outline_of(wm: *const WM, g: *const Graph) OutlineStyle {
    return .{
        .width = g.outline_width orelse wm.group_outline_width,
        .color = g.outline_color orelse wm.group_outline_color,
    };
}

/// The group node's rectangle on the canvas, gaps taken off (as drawn at zoom 1).
pub fn frame_of(wm: *WM, g: *const Graph) types.Rect {
    const node = g.parent_node.?;
    if (node.floating) return .{ .x = node.x, .y = node.y, .width = node.width, .height = node.height };
    const parent = node.owner_graph.?;
    return scene.gapped_rect(parent, node, output.work_area_of(wm, parent));
}

/// Where a group's own nodes are laid out: its frame, inside the outline.
pub fn area(wm: *WM, g: *const Graph) types.Rect {
    const ow = outline_of(wm, g).width;
    return frame_of(wm, g).inset(.{ .left = ow, .right = ow, .top = ow, .bottom = ow });
}
