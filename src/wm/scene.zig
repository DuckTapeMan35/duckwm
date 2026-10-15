const std = @import("std");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const lifecycle = @import("lifecycle.zig");
const settings = @import("settings.zig");
const WM = core.WM;
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;

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
        if (wm.focused) |n| {
            if (wm.is_shown(n)) {
                if (n.window()) |h| _ = wm.backend.set_input_focus(h, n.content == .window);
            }
        } else {
            _ = wm.backend.set_input_focus(null, false);
        }
    }
    if (wm.sync_on_commit) {
        wm.sync_on_commit = false;
        wm.backend.sync();
    }
}

/// Ask for g's state to be pushed to the screen at the next commit.
pub fn flush(wm: *WM, g: *Graph) !void {
    if (g == wm.visible_graph) wm.scene_dirty = true;
}

/// Recompute and push the current layout. Becomes mark_dirty once commits land.
pub fn relayout(wm: *WM) void {
    resolve(wm, wm.current_graph) catch {};
    wm.rebuild_focus_edges() catch {};
    flush(wm, wm.current_graph) catch {};
}

pub fn resolve(wm: *WM, g: *Graph) !void {
    const work = get_work_area(wm);
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

    wm.backend.publish_work_area(work);
}

pub fn get_work_area(wm: *WM) types.Rect {
    const r = wm.backend.reserved_insets();
    return .{
        .x = @intCast(r.left),
        .y = @intCast(r.top),
        .width = wm.screen_width -| r.left -| r.right,
        .height = wm.screen_height -| r.top -| r.bottom,
    };
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
    if (node.owner_graph != wm.visible_graph) return false;
    return switch (node.content) {
        .window => !node.hidden,
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
    const g = wm.visible_graph;
    wm.flushing = true;
    defer wm.flushing = false;

    try compute_scene(wm, g);

    const fullscreen: ?types.WindowHandle = if (g.fullscreen_node) |n| switch (n.content) {
        .window => |w| w,
        else => null,
    } else null;
    wm.backend.apply_windows(wm.scene.items, fullscreen);

    for (g.nodes.items) |node| {
        if (node.content == .workspace and preview_visible(wm, node)) wm.repaint_preview(node);
    }
}

/// the desired state of every visible window in g.
fn compute_scene(wm: *WM, g: *Graph) !void {
    wm.scene.clearRetainingCapacity();
    const bw: u32 = @intCast(@max(0, wm.border_width));
    const work = get_work_area(wm);

    for (g.nodes.items) |node| {
        switch (node.content) {
            .window => |win| {
                if (node.hidden) continue;
                const is_fullscreen = wm.focused == node and g.fullscreen_node == node;
                try wm.scene.append(wm.allocator, .{
                    .handle = win,
                    .frame = if (node.floating) floating_rect(node) else tiled_rect(g, node, work),
                    .border_width = if (is_fullscreen) 0 else bw,
                    .borders = if (wants_borders(wm, node)) border_colors(wm, node) else null,
                    .tiled = !node.floating,
                    .interactive = node.floating and wm.float_moving and wm.float_move_window == win,
                });
            },
            .workspace => {
                if (!preview_visible(wm, node)) continue;
                try wm.scene.append(wm.allocator, .{
                    .handle = node.preview_window.?,
                    .frame = if (node.floating) floating_rect(node) else tiled_rect(g, node, work),
                    .border_width = bw,
                    .borders = if (wants_borders(wm, node)) border_colors(wm, node) else null,
                    .tiled = !node.floating,
                    .interactive = node.floating and wm.float_moving and wm.float_move_window == node.preview_window.?,
                });
            },
            .empty => {},
        }
    }
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

fn tiled_rect(g: *const Graph, node: *const Node, work: types.Rect) types.Rect {
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

    return .{
        .x = node.x + @as(i32, @intCast(gap_left)) - g.pan_x,
        .y = node.y + @as(i32, @intCast(gap_top)) - g.pan_y,
        .width = @max(1, node.width -| gap_left -| gap_right),
        .height = @max(1, node.height -| gap_top -| gap_bottom),
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
