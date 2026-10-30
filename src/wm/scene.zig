const std = @import("std");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const lifecycle = @import("lifecycle.zig");
const settings = @import("settings.zig");
const output = @import("output.zig");
const groups = @import("groups.zig");
const subscriptions = @import("subscriptions.zig");
const WM = core.WM;
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;

/// How a workspace is drawn: its canvas scaled by z around the work area's
/// corner, after the pan.
const View = struct { z: f64, pan_x: i32, pan_y: i32 };

/// Push everything changed during this loop iteration to the backend, once.
pub fn commit(wm: *WM) void {
    if (wm.scene_dirty) {
        // Catch containers emptied by any path, not just a close.
        const g = wm.visible_graph;
        const before = g.nodes.items.len;
        lifecycle.sweep_dead_containers(wm);
        if (g.nodes.items.len != before) {
            resolve(wm, g) catch {};
            wm.rebuild_focus_edges() catch {};
        }

        wm.scene_dirty = false;
        apply_scene(wm) catch |err| std.debug.print("commit: {}\n", .{err});
    }
    // After the scene, so a window focused this iteration is already mapped.
    if (wm.focus_dirty) {
        wm.focus_dirty = false;
        if (wm.focused) |f| {
            const n = if (f.content == .group) groups.last_focused_in(f.content.group) else f;
            if (n) |t| {
                if (wm.is_shown(t)) {
                    if (t.window()) |h| _ = wm.backend.set_input_focus(h, t.content == .window);
                }
            }
        } else {
            _ = wm.backend.set_input_focus(null, false);
        }
    }
    if (wm.sync_on_commit) {
        wm.sync_on_commit = false;
        wm.backend.sync();
    }
    // Last: subscribers hear about what's now on screen.
    subscriptions.deliver(wm);
}

/// Ask for g's state to be pushed to the screen at the next commit.
pub fn flush(wm: *WM, g: *Graph) !void {
    if (output.is_visible(wm, g)) wm.scene_dirty = true;
}

/// Recompute and push the current layout. Becomes mark_dirty once commits land.
pub fn relayout(wm: *WM) void {
    resolve(wm, wm.current_graph) catch {};
    wm.rebuild_focus_edges() catch {};
    flush(wm, wm.current_graph) catch {};
}

pub fn resolve(wm: *WM, g: *Graph) anyerror!void {
    const work = output.work_area_of(wm, g);
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        switch (node.content) {
            .empty => { // Only update "container/root" nodes
                if (node.constraints.items.len == 0) {
                    node.x = 0;
                    node.y = 0;
                    node.width = work.width;
                    node.height = work.height;
                }
            },
            else => {},
        }
    }

    // Step 1: revert tiled nodes to relative coordinates
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        node.x -= g.work_x;
        node.y -= g.work_y;
    }

    // Step 2: run the layout solver in the relative coordinate space
    const solve_width = if (g.virtual_width > work.width) g.virtual_width else work.width;
    const solve_height = if (g.virtual_height > work.height) g.virtual_height else work.height;
    try g.solve(solve_width, solve_height);

    // Step 3: apply the new offset to tiled nodes
    for (g.nodes.items) |node| {
        if (node.floating) continue;
        node.x += work.x;
        node.y += work.y;
    }

    // Step 4: remember the offset for the next call
    g.work_x = work.x;
    g.work_y = work.y;

    // Top down: each group inside the rectangle just solved for it.
    for (g.nodes.items) |node| {
        if (node.content == .group) try resolve(wm, node.content.group);
    }
    if (g.is_group) return;
    groups.rearrange_resized(wm, g);
    wm.backend.publish_work_area(work);
}

pub fn get_work_area(wm: *WM) types.Rect {
    return output.work_area_of(wm, wm.current_graph);
}

/// what color each side of node's border should be right now.
pub fn border_colors(wm: *WM, node: *Node) types.BorderColors {
    const focused = wm.focused == node;
    const base: u32 = if (node.urgent)
        node.border_color_focused orelse wm.default_border_color_urgent
    else if (focused)
        node.border_color_focused orelse wm.default_border_color_focused
    else
        node.border_color_unfocused orelse wm.default_border_color_unfocused;

    const sides = !wm.border_side_colors_focused_only or focused;
    const ind: ?types.Side = if (sides) node.indicator_side else null;
    return .{
        .top = if (ind == .top) wm.indicator_color else if (sides) node.border_color_top orelse base else base,
        .bottom = if (ind == .bottom) wm.indicator_color else if (sides) node.border_color_bottom orelse base else base,
        .left = if (ind == .left) wm.indicator_color else if (sides) node.border_color_left orelse base else base,
        .right = if (ind == .right) wm.indicator_color else if (sides) node.border_color_right orelse base else base,
    };
}

/// Repaint node's border. Pass the frame size if known to skip a server query.
pub fn paint_borders(wm: *WM, node: *Node, size: ?types.Size) void {
    if (!wants_borders(wm, node)) return;
    const h = node.window() orelse return;
    wm.backend.draw_borders(h, border_colors(wm, node), @intCast(wm.border_width), size);
}

pub fn frame(wm: *WM, win: types.WindowHandle, node: *Node) !void {
    _ = try wm.backend.frame_window(win, frame_options(wm, node));
}

pub fn frame_options(wm: *WM, node: *Node) types.FrameOptions {
    return .{
        .allow_argb = wm.argb_frames and !settings.forces_rgb(wm, node),
        .border_width = @intCast(@max(0, wm.border_width)),
        .border_color = if (wm.focused == node)
            node.border_color_focused orelse wm.default_border_color_focused
        else
            node.border_color_unfocused orelse wm.default_border_color_unfocused,
        .configured_size = if (node.width > 0 and node.height > 0)
            .{ .width = node.width, .height = node.height }
        else
            null,
    };
}
/// Will node be on screen after the next commit?
pub fn is_shown(wm: *WM, node: *Node) bool {
    const og = node.owner_graph orelse return false;
    if (!output.is_visible(wm, og)) return false;
    return switch (node.content) {
        .window, .group => !node.hidden,
        .workspace => preview_visible(wm, node),
        .empty => false,
    };
}

fn preview_visible(wm: *WM, node: *Node) bool {
    if (node.hidden or node.preview_window == null) return false;
    if (node.floating) return true;
    const sub = node.content.workspace;
    if (sub == wm.current_graph) return false;
    for (wm.workspace_stack.items) |s| {
        if (s == sub) return false;
    }
    return true;
}

fn apply_scene(wm: *WM) !void {
    wm.flushing = true;
    defer wm.flushing = false;

    // One scene for every output: whatever isn't in it gets hidden.
    wm.scene.clearRetainingCapacity();
    wm.outlines.clearRetainingCapacity();
    var fullscreen: ?types.WindowHandle = null;
    for (wm.outputs.items) |o| {
        const g = output.visible(wm, o);
        try compute_scene(wm, g);
        if (fullscreen == null) {
            if (fullscreen_in(g)) |n| {
                if (n.content == .window) fullscreen = n.content.window;
            }
        }
    }
    wm.backend.apply_outlines(wm.outlines.items);
    wm.backend.apply_windows(wm.scene.items, fullscreen);
    wm.scene_fullscreen = fullscreen;
    wm.scene_serial += 1;
    if (wm.picker_open) offer_workspaces(wm) catch |err| std.debug.print("offering workspaces: {}\n", .{err});

    for (wm.outputs.items) |o| repaint_previews(wm, output.visible(wm, o));
}

/// Repaint the previews in g and in its groups.
fn repaint_previews(wm: *WM, g: *Graph) void {
    for (g.nodes.items) |node| switch (node.content) {
        .workspace => if (preview_visible(wm, node)) wm.repaint_preview(node),
        .group => |sub| repaint_previews(wm, sub),
        else => {},
    };
}

/// The fullscreen window of g or of a group in it.
fn fullscreen_in(g: *Graph) ?*Node {
    if (g.fullscreen_node) |n| return n;
    for (g.nodes.items) |n| {
        if (n.content == .group) {
            if (fullscreen_in(n.content.group)) |f| return f;
        }
    }
    return null;
}

/// the desired state of every visible window in g.
fn compute_scene(wm: *WM, g: *Graph) !void {
    const out = (output.of(wm, g) orelse wm.output).rect;
    const work = output.work_area_of(wm, g);
    try compute_nodes(wm, g, work, work, view_of(g, work), out, false, false);
}

/// g's windows (g: a workspace, or a group in one). Tiled nodes take their
/// gaps from work and are drawn with the workspace's view from its corner
/// (origin); nothing tiled is drawn outside clip.
fn compute_nodes(
    wm: *WM,
    g: *Graph,
    work: types.Rect,
    origin: types.Rect,
    view: View,
    clip: types.Rect,
    in_float: bool,
    in_drag: bool,
) anyerror!void {
    const bw: u32 = @intCast(@max(0, wm.border_width));
    const out = clip;

    for (g.nodes.items) |node| {
        switch (node.content) {
            .window => |win| {
                if (node.hidden) continue;
                const is_fullscreen = wm.focused == node and g.fullscreen_node == node;
                const r = if (node.floating) floating_rect(node) else tiled_rect(g, node, work, origin, view);
                // Laid out in its graph: cut to its area, and skipped if wholly outside it.
                const clipped = !node.floating and !is_fullscreen;
                if (clipped and !overlaps(r, out)) continue;
                try wm.scene.append(wm.allocator, .{
                    .handle = win,
                    .frame = r,
                    .border_width = if (is_fullscreen) 0 else bw,
                    .borders = if (wants_borders(wm, node)) border_colors(wm, node) else null,
                    // Stacking: inside a floating group it floats with the group.
                    .tiled = !node.floating and !in_float,
                    .interactive = in_drag or (node.floating and wm.float_moving and wm.float_move_window == win),
                    .clip = if (clipped) out else null,
                });
            },
            .workspace => {
                if (!preview_visible(wm, node)) continue;
                const r = if (node.floating) floating_rect(node) else tiled_rect(g, node, work, origin, view);
                const tiled = !node.floating;
                if (tiled and !overlaps(r, out)) continue;
                try wm.scene.append(wm.allocator, .{
                    .handle = node.preview_window.?,
                    .frame = r,
                    .border_width = bw,
                    .borders = if (wants_borders(wm, node)) border_colors(wm, node) else null,
                    .tiled = !node.floating and !in_float,
                    .interactive = in_drag or (node.floating and wm.float_moving and wm.float_move_window == node.preview_window.?),
                    .clip = if (tiled) out else null,
                });
            },
            .group => |sub| {
                if (node.hidden) continue;
                const r = if (node.floating) floating_rect(node) else tiled_rect(g, node, work, origin, view);
                const inner_clip = intersect(r, out) orelse continue;
                var ol = groups.outline_of(wm, sub);
                if (wm.focused == node) ol.color = node.border_color_focused orelse wm.default_border_color_focused;
                if (ol.width > 0 and ol.color != 0) try wm.outlines.append(wm.allocator, .{
                    .key = @intFromPtr(sub),
                    .rect = r,
                    .clip = inner_clip,
                    .width = ol.width,
                    .color = ol.color,
                });
                // Being dragged: everything in it moves with the pointer, unanimated.
                const dragged = in_drag or (node.floating and wm.float_moving and
                    wm.float_target != null and wm.get_id_for_node(node) == wm.float_target);
                // Its nodes are drawn no further out than its frame.
                const area = groups.area(wm, sub);
                if (node.floating) {
                    // A floating group isn't panned or zoomed: drawn as laid out.
                    try compute_nodes(
                        wm,
                        sub,
                        area,
                        area,
                        .{ .z = 1.0, .pan_x = 0, .pan_y = 0 },
                        inner_clip,
                        in_float or node.floating,
                        dragged,
                    );
                } else {
                    try compute_nodes(
                        wm,
                        sub,
                        area,
                        origin,
                        view,
                        inner_clip,
                        in_float or node.floating,
                        dragged,
                    );
                }
            },
            .empty,
            => {},
        }
    }
}

fn intersect(a: types.Rect, b: types.Rect) ?types.Rect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + @as(i32, @intCast(a.width)), b.x + @as(i32, @intCast(b.width)));
    const y1 = @min(a.y + @as(i32, @intCast(a.height)), b.y + @as(i32, @intCast(b.height)));
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = x0, .y = y0, .width = @intCast(x1 - x0), .height = @intCast(y1 - y0) };
}

fn wants_borders(wm: *WM, node: *Node) bool {
    if (wm.border_width <= 0) return false;
    if (node.owner_graph) |og| {
        if (og.fullscreen_node == node) return false;
    }
    return true;
}

fn floating_rect(node: *const Node) types.Rect {
    return .{ .x = node.x, .y = node.y, .width = @max(1, node.width), .height = @max(1, node.height) };
}

/// node's rectangle on the canvas with g's gaps taken off, as drawn at zoom 1
/// with no pan (what a group lays its own nodes out in).
pub fn gapped_rect(g: *const Graph, node: *const Node, work: types.Rect) types.Rect {
    return tiled_rect(g, node, work, work, .{
        .z = 1.0,
        .pan_x = 0,
        .pan_y = 0,
    });
}

/// Where tiled node is drawn: outer gaps where it meets the edges of the area
/// it's laid out in (work), scaled by the view from the workspace's corner (origin).
fn tiled_rect(g: *const Graph, node: *const Node, work: types.Rect, origin: types.Rect, v: View) types.Rect {
    const nw: i32 = @intCast(node.width);
    const nh: i32 = @intCast(node.height);
    const ww: i32 = @intCast(work.width);
    const wh: i32 = @intCast(work.height);

    const at_left = node.x <= work.x;
    const at_top = node.y <= work.y;
    const at_right = node.x + nw >= work.x + ww;
    const at_bottom = node.y + nh >= work.y + wh;

    const half_h = g.gap_inner_h / 2;
    const half_v = g.gap_inner_v / 2;
    const gap_left: u32 = if (at_left) g.gap_outer_h else half_h;
    const gap_right: u32 = if (at_right) g.gap_outer_h else half_h;
    const gap_top: u32 = if (at_top) g.gap_outer_v else half_v;
    const gap_bottom: u32 = if (at_bottom) g.gap_outer_v else half_v;

    // Both edges scaled, so neighbours still meet exactly; gaps stay their size.
    const x0 = origin.x + scaled(node.x - origin.x - v.pan_x, v.z);
    const x1 = origin.x + scaled(node.x + nw - origin.x - v.pan_x, v.z);
    const y0 = origin.y + scaled(node.y - origin.y - v.pan_y, v.z);
    const y1 = origin.y + scaled(node.y + nh - origin.y - v.pan_y, v.z);
    const w: u32 = @intCast(@max(0, x1 - x0));
    const h: u32 = @intCast(@max(0, y1 - y0));

    return .{
        .x = x0 + @as(i32, @intCast(gap_left)),
        .y = y0 + @as(i32, @intCast(gap_top)),
        .width = @max(1, w -| gap_left -| gap_right),
        .height = @max(1, h -| gap_top -| gap_bottom),
    };
}

/// Smallest node in the current graph containing p (most specific hit).
pub fn node_at(wm: *WM, p: types.Point) ?*Node {
    var best: ?*Node = null;
    var best_area: u64 = std.math.maxInt(u64);
    for (wm.current_graph.nodes.items) |node| {
        if (node.width == 0 or node.height == 0) continue;
        const nw: i32 = @intCast(node.width);
        const nh: i32 = @intCast(node.height);
        if (p.x >= node.x and p.x < node.x + nw and p.y >= node.y and p.y < node.y + nh) {
            const area = @as(u64, node.width) * node.height;
            if (area < best_area) {
                best = node;
                best_area = area;
            }
        }
    }
    return best;
}

fn view_of(g: *const Graph, work: types.Rect) View {
    const ww: f64 = @floatFromInt(work.width);
    const wh: f64 = @floatFromInt(work.height);
    const cw: f64 = @floatFromInt(@max(g.virtual_width, work.width));
    const ch: f64 = @floatFromInt(@max(g.virtual_height, work.height));
    const z = if (g.zoom > 0) g.zoom else @min(1.0, @min(ww / cw, wh / ch));
    if (z == 1.0) return .{ .z = 1.0, .pan_x = g.pan_x, .pan_y = g.pan_y };
    // Zoomed out, the view covers more canvas: keep it inside.
    const max_x: i32 = @intFromFloat(@max(0, cw - ww / z));
    const max_y: i32 = @intFromFloat(@max(0, ch - wh / z));
    return .{
        .z = z,
        .pan_x = std.math.clamp(g.pan_x, 0, max_x),
        .pan_y = std.math.clamp(g.pan_y, 0, max_y),
    };
}

pub fn zoom_of(wm: *WM, g: *const Graph) f64 {
    return view_of(g, output.work_area_of(wm, g)).z;
}

fn scaled(v: i32, z: f64) i32 {
    return @intFromFloat(@round(@as(f64, @floatFromInt(v)) * z));
}

fn overlaps(a: types.Rect, b: types.Rect) bool {
    return a.x < b.x + @as(i32, @intCast(b.width)) and b.x < a.x + @as(i32, @intCast(a.width)) and
        a.y < b.y + @as(i32, @intCast(b.height)) and b.y < a.y + @as(i32, @intCast(a.height));
}

// ---- screen sharing ----
/// While a screen-sharing picker is open: every workspace with windows and
/// no workspaces of its own, for the backend to offer, the hidden ones laid
/// out as they would be if shown.
fn offer_workspaces(wm: *WM) !void {
    var arena = std.heap.ArenaAllocator.init(wm.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Hidden ones' windows go after the scene in its list, and come off
    // again once offered (as do the outlines laying them out adds).
    const scene_len = wm.scene.items.len;
    const outlines_len = wm.outlines.items.len;
    defer {
        wm.scene.shrinkRetainingCapacity(scene_len);
        wm.outlines.shrinkRetainingCapacity(outlines_len);
    }
    var found: std.ArrayListUnmanaged(Found) = .empty;
    for (wm.outputs.items) |o| try find_offers(wm, a, &o.root, "", &found);
    // Only now: the list may have moved while it grew.
    const offers = try a.alloc(types.WorkspaceOffer, found.items.len);
    for (found.items, offers) |f, *offer| offer.* = .{
        .key = @intFromPtr(f.g),
        .output = f.g.output,
        .name = f.name,
        .shown = f.shown,
        .windows = wm.scene.items[f.from..f.to],
    };
    wm.backend.offer_workspaces(offers);
}

/// A workspace to offer, and where its windows are in wm.scene.
const Found = struct { g: *Graph, name: []const u8, shown: bool, from: usize, to: usize };

/// The workspaces to offer in g, each named by its path from the top
/// ("2", "2/1": their places, as switch_to_workspace counts; a named one
/// by its name), the hidden ones laid out.
fn find_offers(
    wm: *WM,
    a: std.mem.Allocator,
    g: *Graph,
    prefix: []const u8,
    found: *std.ArrayListUnmanaged(Found),
) !void {
    var subs: std.ArrayListUnmanaged(*Node) = .empty;
    var it = groups.Nodes.init(g);
    while (it.next()) |n| {
        if (n.content == .workspace and n.content.workspace != wm.scratch_graph) try subs.append(a, n);
    }
    // In the order switch_to_workspace counts them: by node id.
    std.sort.heap(*Node, subs.items, wm, struct {
        fn lt(w: *WM, x: *Node, y: *Node) bool {
            const ix = w.get_id_for_node(x) orelse return false;
            const iy = w.get_id_for_node(y) orelse return false;
            return ix < iy;
        }
    }.lt);
    for (subs.items, 1..) |n, place| {
        const sub = n.content.workspace;
        const own = if (n.name.len > 0) n.name else try std.fmt.allocPrint(a, "{d}", .{place});
        const name = if (prefix.len == 0) own else try std.fmt.allocPrint(a, "{s}/{s}", .{ prefix, own });
        if (holds(sub, .workspace)) {
            try find_offers(wm, a, sub, name, found);
            continue;
        }
        if (!holds(sub, .window)) continue;
        const shown = output.is_visible(wm, sub);
        const from = wm.scene.items.len;
        if (!shown) try compute_scene(wm, sub);
        try found.append(a, .{ .g = sub, .name = name, .shown = shown, .from = from, .to = wm.scene.items.len });
    }
}

/// Does g hold a node of this kind (in it or in its groups)?
fn holds(g: *Graph, kind: std.meta.Tag(@FieldType(Node, "content"))) bool {
    var it = groups.Nodes.init(g);
    while (it.next()) |n| if (n.content == kind) return true;
    return false;
}
