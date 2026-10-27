const std = @import("std");
const graph_mod = @import("graph");
const types = @import("types");
const protocol = @import("protocol");
const core = @import("core.zig");
const registry = @import("registry.zig");
const navigation = @import("navigation.zig");
const focus_mod = @import("focus.zig");
const groups = @import("groups.zig");
const workspace_settings = @import("workspace_settings.zig");
const subscriptions = @import("subscriptions.zig");
const WM = core.WM;
const Graph = graph_mod.Graph;

/// More than anyone plugs in; backends fill at most this many.
pub const max_outputs = 16;

const zero: types.Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 };

pub const Output = struct {
    /// The backend's id for it; graphs on it carry this in Graph.output.
    id: u32,
    /// Where it is, in global coordinates.
    rect: types.Rect,
    /// rect minus the docks, bars and error bar on it: where tiling happens.
    usable: types.Rect,
    /// Its connector, as the backend names it ("DP-1"); may be empty.
    name: types.OutputInfo.Name = .{},
    /// The usable area its arrangers last laid out for (to tell when they must again).
    arranged: types.Rect = zero,
    /// Its workspaces, as the one root graph used to hold them all.
    root: Graph,

    // Navigation state, kept here while another output has focus.
    current_graph: *Graph = undefined,
    visible_graph: *Graph = undefined,
    previous_graph: ?*Graph = null,
    workspace_stack: std.ArrayListUnmanaged(*Graph) = .empty,
    /// The node focused when this output last lost focus.
    last_focused: ?u32 = null,
};

// ---- lifecycle ----
/// At startup, before the config: one output per monitor, the primary focused.
/// No workspaces yet (populate makes them, once the config has set gaps and arrangers).
pub fn init_all(wm: *WM) !void {
    var buf: [max_outputs]types.OutputInfo = undefined;
    for (wm.backend.outputs(&buf)) |info| _ = try add(wm, info);
    if (wm.outputs.items.len == 0) return error.NoOutputs;
    load(wm, wm.outputs.items[0]);
}

/// Give every output its first workspace. Focus ends on the primary.
pub fn populate(wm: *WM) !void {
    const first = wm.output;
    for (wm.outputs.items) |o| {
        focus(wm, o);
        try wm.create_initial_workspace();
        o.arranged = o.usable;
    }
    focus(wm, first);
}

/// Monitors came, went, moved, or had docks change: catch up with the backend.
pub fn sync(wm: *WM) !void {
    var buf: [max_outputs]types.OutputInfo = undefined;
    const infos = wm.backend.outputs(&buf);
    if (infos.len == 0) return; // everything off for a moment: keep what's there

    var changed = false;
    for (infos) |info| {
        if (find(wm, info.id)) |o| {
            o.rect = info.rect;
            o.usable = info.usable;
            // river can name it after listing it
            if (!std.mem.eql(u8, o.name.slice(), info.name.slice())) changed = true;
            o.name = info.name;
        } else {
            try create(wm, info);
            changed = true;
        }
    }
    var i = wm.outputs.items.len;
    while (i > 0) {
        i -= 1;
        const o = wm.outputs.items[i];
        const listed = for (infos) |info| {
            if (info.id == o.id) break true;
        } else false;
        if (!listed) {
            try remove(wm, o);
            changed = true;
        }
    }
    if (changed) subscriptions.queue(wm, .{ .topic = .outputs });
    wm.screen_width = wm.output.rect.width;
    wm.screen_height = wm.output.rect.height;
    // Outputs renamed (river names them late) or workspaces moved to another.
    workspace_settings.apply_all(wm);
}

/// Free every output and its workspaces.
pub fn deinit_all(wm: *WM) void {
    for (wm.outputs.items) |o| {
        navigation.free_graph(wm, &o.root);
        if (o != wm.output) o.workspace_stack.deinit(wm.allocator);
        wm.allocator.destroy(o);
    }
    wm.outputs.deinit(wm.allocator);
}

fn add(wm: *WM, info: types.OutputInfo) !*Output {
    const o = try wm.allocator.create(Output);
    errdefer wm.allocator.destroy(o);
    o.* = .{
        .id = info.id,
        .rect = info.rect,
        .usable = info.usable,
        .name = info.name,
        .root = Graph.init(wm.allocator),
    };
    o.root.output = info.id;
    o.root.on_node_free = registry.on_node_freed;
    o.root.on_node_free_ctx = wm;
    o.root.journal = &wm.journal;
    o.current_graph = &o.root;
    o.visible_graph = &o.root;
    try wm.outputs.append(wm.allocator, o);
    return o;
}

/// A monitor plugged in: a new output with its first workspace. Focus stays put.
fn create(wm: *WM, info: types.OutputInfo) !void {
    const o = try add(wm, info);
    const prev = wm.output;
    const prev_focus = wm.focused;
    focus(wm, o);
    defer {
        focus(wm, prev);
        if (prev_focus) |f| wm.set_focus(f) else wm.clear_focus();
    }
    try wm.create_initial_workspace();
    o.arranged = o.usable;
}

/// A monitor unplugged: its workspaces join another output's, after its own.
fn remove(wm: *WM, o: *Output) !void {
    const to = for (wm.outputs.items) |other| {
        if (other != o) break other;
    } else return; // never the last one
    if (wm.output == o) focus(wm, to);

    var i: usize = 0;
    while (i < o.root.nodes.items.len) {
        const n = o.root.nodes.items[i];
        if (n.content != .workspace) {
            i += 1;
            continue;
        }
        o.root.detach_node(n);
        try o.root.replace_constraints(n, &.{});
        n.hidden = true;
        try to.root.attach_node(n);
        set_output(n.content.workspace, to.id);
    }

    // What's left is its root container: out of the registry, then freed.
    for (o.root.nodes.items) |n| {
        if (wm.get_id_for_node(n)) |id| _ = wm.node_registry.remove(id);
    }
    for (wm.outputs.items, 0..) |x, k| {
        if (x == o) {
            _ = wm.outputs.orderedRemove(k);
            break;
        }
    }
    navigation.free_graph(wm, &o.root);
    o.workspace_stack.deinit(wm.allocator);
    wm.allocator.destroy(o);
    if (wm.focused == null) focus_something(wm);
}

fn set_output(g: *Graph, id: u32) void {
    g.output = id;
    for (g.nodes.items) |n| {
        if (n.inner()) |sub| set_output(sub, id);
    }
}

// ---- lookups ----
pub fn find(wm: *WM, id: u32) ?*Output {
    for (wm.outputs.items) |o| {
        if (o.id == id) return o;
    }
    return null;
}

/// The output graph g is on.
pub fn of(wm: *WM, g: *const Graph) ?*Output {
    return find(wm, g.output);
}

/// The workspace on screen on o.
pub fn visible(wm: *WM, o: *Output) *Graph {
    return if (o == wm.output) wm.visible_graph else o.visible_graph;
}

/// Is g (or the workspace holding it, for a group) on screen on some output?
pub fn is_visible(wm: *WM, g: *const Graph) bool {
    const ws = g.workspace();
    for (wm.outputs.items) |o| {
        if (visible(wm, o) == ws) return true;
    }
    return false;
}

/// Where tiling happens on the output g is on (in a group: inside the group).
pub fn work_area_of(wm: *WM, g: *const Graph) types.Rect {
    if (g.is_group) return groups.area(wm, g);
    const o = of(wm, g) orelse wm.output;
    return o.usable;
}

/// The nearest output from `from` in direction dir, by their centres.
pub fn neighbour(wm: *WM, from: *Output, dir: protocol.Dir) ?*Output {
    const fx = from.rect.x + @as(i32, @intCast(from.rect.width / 2));
    const fy = from.rect.y + @as(i32, @intCast(from.rect.height / 2));
    var best: ?*Output = null;
    var best_d: i64 = std.math.maxInt(i64);
    for (wm.outputs.items) |o| {
        if (o == from) continue;
        const dx: i64 = o.rect.x + @as(i32, @intCast(o.rect.width / 2)) - fx;
        const dy: i64 = o.rect.y + @as(i32, @intCast(o.rect.height / 2)) - fy;
        const ok = switch (dir) {
            .left => dx < 0 and @abs(dx) >= @abs(dy),
            .right => dx > 0 and @abs(dx) >= @abs(dy),
            .up => dy < 0 and @abs(dy) >= @abs(dx),
            .down => dy > 0 and @abs(dy) >= @abs(dx),
        };
        if (!ok) continue;
        const d = dx * dx + dy * dy;
        if (d < best_d) {
            best = o;
            best_d = d;
        }
    }
    return best;
}

// ---- focus ----
/// Make o the output commands, new windows and arrangers act on.
/// Journaled: a rolled-back transaction gives focus back.
pub fn focus(wm: *WM, o: *Output) void {
    if (o == wm.output) return;
    const prev = wm.output;
    save(wm);
    load(wm, o);
    wm.journal.external(undo_focus, wm, @intFromPtr(prev));
    // Its windows may have moved since its focus edges were built (sent here, resized).
    wm.rebuild_focus_edges() catch {};
}

/// After switching outputs: focus what was focused there last, or its top-left
/// window, and put the pointer on it.
pub fn focus_something(wm: *WM) void {
    const last = if (wm.output.last_focused) |id| wm.get_node_by_id(id) else null;
    const target = if (last) |n| (if (n.owner_graph != null and n.owner_graph.?.within(wm.current_graph)) n else null) else null;
    if (target orelse focus_mod.top_left_window(wm)) |n| {
        focus_node(wm, n);
    } else {
        wm.clear_focus();
        const r = wm.output.rect;
        wm.backend.warp_pointer(.{ .x = r.x + @as(i32, @intCast(r.width / 2)), .y = r.y + @as(i32, @intCast(r.height / 2)) });
    }
}

/// Focus n (switching output if it's on another) and put the pointer on it,
/// so focus-follows-mouse doesn't take focus straight back.
pub fn focus_node(wm: *WM, n: *graph_mod.Node) void {
    wm.set_focus(n);
    const ws = n.owner_graph.?.workspace();
    wm.backend.warp_pointer(.{
        .x = n.x - ws.pan_x + @as(i32, @intCast(n.width / 2)),
        .y = n.y - ws.pan_y + @as(i32, @intCast(n.height / 2)),
    });
}

/// Directional focus that ran out of windows on this output: the window on
/// the facing edge of the next output that way, the one most in line with
/// the focused window. Returns false if there's no output that way.
pub fn focus_across(wm: *WM, dir: protocol.Dir) bool {
    const to = neighbour(wm, wm.output, dir) orelse return false;
    // What to line up with: the focused window, or the middle of this output.
    const from: types.Rect = if (wm.focused) |f|
        .{ .x = f.x, .y = f.y, .width = f.width, .height = f.height }
    else
        wm.output.rect;

    var best: ?*graph_mod.Node = null;
    var best_overlap: i32 = std.math.minInt(i32);
    var best_edge: i32 = std.math.maxInt(i32);
    var list: std.ArrayListUnmanaged(*graph_mod.Node) = .empty;
    defer list.deinit(wm.allocator);
    groups.units(wm.allocator, visible(wm, to), null, &list) catch {};
    for (list.items) |n| {
        const nw: i32 = @intCast(n.width);
        const nh: i32 = @intCast(n.height);
        const fw: i32 = @intCast(from.width);
        const fh: i32 = @intCast(from.height);
        // How far n is from the edge we arrive through, and how much it lines up.
        const edge: i32, const overlap: i32 = switch (dir) {
            .right => .{ n.x, @min(from.y + fh, n.y + nh) - @max(from.y, n.y) },
            .left => .{ -(n.x + nw), @min(from.y + fh, n.y + nh) - @max(from.y, n.y) },
            .down => .{ n.y, @min(from.x + fw, n.x + nw) - @max(from.x, n.x) },
            .up => .{ -(n.y + nh), @min(from.x + fw, n.x + nw) - @max(from.x, n.x) },
        };
        const better = if ((overlap > 0) != (best_overlap > 0))
            overlap > 0
        else if (edge != best_edge)
            edge < best_edge
        else
            overlap > best_overlap;
        if (best == null or better) {
            best = n;
            best_edge = edge;
            best_overlap = overlap;
        }
    }

    focus(wm, to);
    if (best) |n| focus_node(wm, n) else focus_something(wm);
    return true;
}

/// Put o's navigation state into core's fields.
pub fn load(wm: *WM, o: *Output) void {
    wm.output = o;
    wm.root = &o.root;
    wm.current_graph = o.current_graph;
    wm.visible_graph = o.visible_graph;
    wm.previous_graph = o.previous_graph;
    wm.workspace_stack = o.workspace_stack;
    wm.screen_width = o.rect.width;
    wm.screen_height = o.rect.height;
}

/// Park core's navigation fields back in the focused output.
fn save(wm: *WM) void {
    save_nav(wm);
    wm.output.last_focused = if (wm.focused) |f| wm.get_id_for_node(f) else null;
}

fn save_nav(wm: *WM) void {
    const o = wm.output;
    o.current_graph = wm.current_graph;
    o.visible_graph = wm.visible_graph;
    o.previous_graph = wm.previous_graph;
    o.workspace_stack = wm.workspace_stack;
}

/// Load o's navigation state into core's fields for a moment, to read it,
/// without focusing it. Hand the result to give_back.
pub fn borrow(wm: *WM, o: *Output) ?*Output {
    if (o == wm.output) return null;
    const prev = wm.output;
    save_nav(wm);
    load(wm, o);
    return prev;
}

pub fn give_back(wm: *WM, prev: ?*Output) void {
    const p = prev orelse return;
    save_nav(wm);
    load(wm, p);
}

fn undo_focus(ctx: *anyopaque, arg: u64) void {
    const wm: *WM = @ptrCast(@alignCast(ctx));
    save(wm);
    load(wm, @ptrFromInt(@as(usize, @intCast(arg))));
}
