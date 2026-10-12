const std = @import("std");
const types = @import("types");
const graph_mod = @import("graph");
const Node = graph_mod.Node;
const WM = @import("core.zig").WM;
const float_mod = @import("float.zig");

fn node_of(wm: *WM, h: ?types.WindowHandle) ?*Node {
    const id = wm.window_to_node_id.get(h orelse return null) orelse return null;
    return wm.node_registry.get(id);
}

pub fn button_press(wm: *WM, ev: types.PointerButton) void {
    // Pan drag takes priority over everything else.
    if (wm.pan_modifier) |m| {
        if (!wm.current_graph.pan_disabled and ev.mods & m != 0 and ev.button == wm.pan_button) {
            wm.pan_dragging = true;
            wm.pan_drag_start_x = ev.pos.x;
            wm.pan_drag_start_y = ev.pos.y;
            wm.pan_drag_start_pan_x = wm.current_graph.pan_x;
            wm.pan_drag_start_pan_y = wm.current_graph.pan_y;
            return;
        }
    }

    const has_float_mod = if (wm.float_move_modifier) |m| ev.mods & m != 0 else false;
    const has_resize_mod = if (wm.resize_modifier) |m| ev.mods & m != 0 else false;

    if (!has_float_mod and !has_resize_mod and wm.click_to_focus) {
        if (node_of(wm, ev.window)) |node| {
            if (wm.focused != node) {
                wm.focus(node);
                wm.flush(wm.current_graph) catch {};
            }
        }
        return;
    }

    const h = ev.window orelse return;
    const node = node_of(wm, h) orelse return;

    if (has_float_mod and node.floating) {
        const is_move = ev.button == wm.float_move_button;
        const is_resize = ev.button == wm.float_resize_button;
        if (!is_move and !is_resize) return;

        suspend_ffm(wm);
        wm.focused = node;

        if (is_move) {
            wm.float_moving = true;
            wm.float_move_window = h;
            wm.float_move_start_x = ev.pos.x;
            wm.float_move_start_y = ev.pos.y;
            wm.float_win_start_x = node.x;
            wm.float_win_start_y = node.y;
            wm.backend.raise_window(h);
        } else {
            const e = nearest_edges(node, ev.pos);
            wm.resize_window = h;
            wm.corner_resizing = true;
            wm.resize_v_edge = e.v;
            wm.resize_h_edge = e.h;
            wm.resize_fixed_x = e.opposite_v;
            wm.resize_fixed_y = e.opposite_h;
            wm.resize_end_x = ev.pos.x;
            wm.resize_end_y = ev.pos.y;
        }
        wm.backend.capture_pointer();
        return;
    }

    // Tiled resize.
    if (!has_resize_mod or node.floating) return;
    const e = nearest_edges(node, ev.pos);
    wm.corner_resizing = true;
    suspend_ffm(wm);
    wm.resize_window = h;
    wm.resize_v_edge = e.v;
    wm.resize_h_edge = e.h;
    wm.resize_end_x = ev.pos.x;
    wm.resize_end_y = ev.pos.y;
    wm.backend.capture_pointer();
}

const Edges = struct { v: i32, h: i32, opposite_v: i32, opposite_h: i32 };

/// The vertical and horizontal edges of node closest to p, and the ones opposite them.
fn nearest_edges(node: *const Node, p: types.Point) Edges {
    const left = node.x;
    const right = node.x + @as(i32, @intCast(node.width));
    const top = node.y;
    const bottom = node.y + @as(i32, @intCast(node.height));
    const near_left = @abs(p.x - left) < @abs(p.x - right);
    const near_top = @abs(p.y - top) < @abs(p.y - bottom);
    return .{
        .v = if (near_left) left else right,
        .h = if (near_top) top else bottom,
        .opposite_v = if (near_left) right else left,
        .opposite_h = if (near_top) bottom else top,
    };
}

pub fn motion(wm: *WM, pos: types.Point) void {
    if (wm.pan_dragging) {
        const dx = pos.x - wm.pan_drag_start_x;
        const dy = pos.y - wm.pan_drag_start_y;
        wm.current_graph.pan_x = @max(0, wm.pan_drag_start_pan_x - dx);
        wm.current_graph.pan_y = @max(0, wm.pan_drag_start_pan_y - dy);
        wm.flushing = false;
        wm.flush(wm.current_graph) catch {};
        return;
    }

    if (wm.float_moving) {
        const dx = pos.x - wm.float_move_start_x;
        const dy = pos.y - wm.float_move_start_y;
        if (dx == 0 and dy == 0) return;
        const node = node_of(wm, wm.float_move_window) orelse return;
        if (!node.floating) return;
        node.x = wm.float_win_start_x + dx;
        node.y = wm.float_win_start_y + dy;
        if (throttle_elapsed(wm)) {
            wm.resolve(wm.current_graph) catch {};
            wm.flush(wm.current_graph) catch {};
        }
        return;
    }

    if (!wm.edge_resizing and !wm.corner_resizing) return;
    const target = node_of(wm, wm.resize_window) orelse return;
    if (target.floating) resize_floating(wm, target, pos) else resize_tiled(wm, pos);
}

fn resize_floating(wm: *WM, focused: *Node, pos: types.Point) void {
    const min_size: i32 = 10;

    if (wm.corner_resizing) {
        const dx = pos.x - wm.resize_end_x;
        const dy = pos.y - wm.resize_end_y;
        if (dx != 0 or dy != 0) {
            wm.resize_v_edge += dx;
            wm.resize_h_edge += dy;
            wm.resize_end_x = pos.x;
            wm.resize_end_y = pos.y;
            if (@abs(wm.resize_fixed_x - wm.resize_v_edge) < min_size) {
                wm.resize_v_edge = if (wm.resize_v_edge > wm.resize_fixed_x)
                    wm.resize_fixed_x + min_size
                else
                    wm.resize_fixed_x - min_size;
            }
            if (@abs(wm.resize_fixed_y - wm.resize_h_edge) < min_size) {
                wm.resize_h_edge = if (wm.resize_h_edge > wm.resize_fixed_y)
                    wm.resize_fixed_y + min_size
                else
                    wm.resize_fixed_y - min_size;
            }
            focused.x = @min(wm.resize_fixed_x, wm.resize_v_edge);
            focused.y = @min(wm.resize_fixed_y, wm.resize_h_edge);
            focused.width = @intCast(@abs(wm.resize_fixed_x - wm.resize_v_edge));
            focused.height = @intCast(@abs(wm.resize_fixed_y - wm.resize_h_edge));
        }
    } else if (wm.edge_resizing) {
        if (wm.edge_is_vertical) {
            const dx = pos.x - wm.resize_end_x;
            if (dx != 0) {
                wm.edge_x += dx;
                wm.resize_end_x = pos.x;
                if (@abs(wm.resize_fixed_x - wm.edge_x) < min_size) {
                    wm.edge_x = if (wm.edge_x > wm.resize_fixed_x)
                        wm.resize_fixed_x + min_size
                    else
                        wm.resize_fixed_x - min_size;
                }
                focused.x = @min(wm.resize_fixed_x, wm.edge_x);
                focused.width = @intCast(@abs(wm.resize_fixed_x - wm.edge_x));
            }
        } else {
            const dy = pos.y - wm.resize_end_y;
            if (dy != 0) {
                wm.edge_y += dy;
                wm.resize_end_y = pos.y;
                if (@abs(wm.resize_fixed_y - wm.edge_y) < min_size) {
                    wm.edge_y = if (wm.edge_y > wm.resize_fixed_y)
                        wm.resize_fixed_y + min_size
                    else
                        wm.resize_fixed_y - min_size;
                }
                focused.y = @min(wm.resize_fixed_y, wm.edge_y);
                focused.height = @intCast(@abs(wm.resize_fixed_y - wm.edge_y));
            }
        }
    }

    if (throttle_elapsed(wm)) {
        wm.resolve(wm.current_graph) catch {};
        wm.flush(wm.current_graph) catch {};
        wm.repaint_preview(focused);
        wm.sync_on_commit = true;
    }
}

fn resize_tiled(wm: *WM, pos: types.Point) void {
    const g = wm.current_graph;
    const dx = pos.x - wm.resize_end_x;
    const dy = pos.y - wm.resize_end_y;

    if (wm.corner_resizing) {
        if (!g.lock_vertical_resize and dx != 0) {
            if (wm.resize_vertical_edge(wm.resize_v_edge, dx, false) catch false) wm.resize_v_edge += dx;
            wm.resize_end_x = pos.x;
        }
        if (!g.lock_horizontal_resize and dy != 0) {
            if (wm.resize_horizontal_edge(wm.resize_h_edge, dy, false) catch false) wm.resize_h_edge += dy;
            wm.resize_end_y = pos.y;
        }
    }
    if (wm.edge_resizing) {
        if (wm.edge_is_vertical) {
            if (!g.lock_vertical_resize and dx != 0) {
                if (wm.resize_vertical_edge(wm.edge_x, dx, false) catch false) wm.edge_x += dx;
                wm.resize_end_x = pos.x;
            }
        } else {
            if (!g.lock_horizontal_resize and dy != 0) {
                if (wm.resize_horizontal_edge(wm.edge_y, dy, false) catch false) wm.edge_y += dy;
                wm.resize_end_y = pos.y;
            }
        }
    }

    const cx = if (wm.corner_resizing) wm.resize_v_edge else wm.edge_x;
    const cy = if (wm.corner_resizing) wm.resize_h_edge else wm.edge_y;
    if (cx == wm.last_flushed_edge_x and cy == wm.last_flushed_edge_y) return;
    if (!throttle_elapsed(wm)) return;
    wm.last_flushed_edge_x = cx;
    wm.last_flushed_edge_y = cy;
    wm.flush(wm.current_graph) catch {};
    wm.sync_on_commit = true;
}

fn throttle_elapsed(wm: *WM) bool {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    const now_ms: i64 = ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
    if (now_ms - wm.last_resize_flush < wm.resize_refresh_interval) return false;
    wm.last_resize_flush = now_ms;
    return true;
}

pub fn button_release(wm: *WM) void {
    if (wm.pan_dragging) {
        wm.pan_dragging = false;
        for (wm.current_graph.nodes.items) |n| wm.paint_borders(n, null);
        return;
    }
    if (wm.float_moving) {
        wm.float_moving = false;
        wm.backend.release_pointer();
        wm.resolve(wm.current_graph) catch {};
        wm.backend.raise_window(wm.float_move_window);
    }
    if (wm.corner_resizing) {
        wm.corner_resizing = false;
        wm.backend.release_pointer();
        finish_resize(wm);
    }
    if (wm.edge_resizing) {
        wm.edge_resizing = false;
        wm.backend.release_pointer();
        finish_resize(wm);
    }
    wm.last_flushed_edge_x = -1;
    wm.last_flushed_edge_y = -1;
    wm.flush(wm.current_graph) catch {};
    resume_ffm(wm);
}

fn finish_resize(wm: *WM) void {
    const node = node_of(wm, wm.resize_window) orelse return;
    if (node.floating) {
        float_mod.raise_floating_windows(wm);
        return;
    }
    wm.sync_constraints_from_geometry();
    for (wm.current_graph.nodes.items) |n| {
        if (n.floating) continue;
        switch (n.content) {
            .window, .workspace => if (wm.get_id_for_node(n)) |id| {
                wm.call_arranger(wm.current_graph, "resize", id, null);
            },
            .empty => {},
        }
    }
}

pub fn enter(wm: *WM, h: types.WindowHandle) void {
    if (!wm.focus_follows_mouse) return;
    const node = node_of(wm, h) orelse return;
    if (wm.focused == node) return;
    if (wm.current_graph != node.owner_graph) return;
    wm.focus(node);
    wm.flush(wm.current_graph) catch {};
}

/// Turn focus-follows-mouse off for the duration of a drag.
fn suspend_ffm(wm: *WM) void {
    if (wm.ffm_suspended) return;
    wm.saved_focus_follows_mouse = wm.focus_follows_mouse;
    wm.focus_follows_mouse = false;
    wm.ffm_suspended = true;
}

/// Restore it, but only if a drag suspended it.
fn resume_ffm(wm: *WM) void {
    if (!wm.ffm_suspended) return;
    wm.focus_follows_mouse = wm.saved_focus_follows_mouse;
    wm.ffm_suspended = false;
}
