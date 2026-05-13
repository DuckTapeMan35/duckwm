const std = @import("std");
const c = @import("c").c;
const WM = @import("core.zig").WM;
const graph_mod = @import("graph");
const ziglua = @import("ziglua");
const resize_mod = @import("resize.zig");
const focus_mod = @import("focus.zig");
const float_mod = @import("float.zig");

const Node = graph_mod.Node;
const Direction = graph_mod.Direction;
const Strut = @import("core.zig").Strut;

pub var wm_detected: bool = false;

pub fn on_wm_detected(_: ?*c.Display, _: [*c]c.XErrorEvent) callconv(.c) c_int {
    wm_detected = true;
    return 0;
}

pub fn on_x_error(_: ?*c.Display, e: [*c]c.XErrorEvent) callconv(.c) c_int {
    const event = e orelse return 0;
    std.debug.print("X error: type={}, serial={}, error_code={}, request_code={}, minor_code={}\n",
        .{ event.*.type, event.*.serial, event.*.error_code, event.*.request_code, event.*.minor_code });
    return 0;
}

pub fn on_configure_request(wm: *WM, req: *c.XConfigureRequestEvent) void {
    var mask = req.value_mask;
    if (wm.dock_struts.contains(req.window)) {
        mask &= ~@as(c_ulong, c.CWX | c.CWY);
    }
    var changes = c.XWindowChanges{
        .x = req.x,
        .y = req.y,
        .width = req.width,
        .height = req.height,
        .border_width = req.border_width,
        .sibling = req.above,
        .stack_mode = req.detail,
    };
    _ = c.XConfigureWindow(wm.display, req.window, @intCast(mask), &changes);
}

fn restack_docks(wm: *WM) void {
    var top: i32 = 0;
    var bottom: i32 = 0;
    var left: i32 = 0;
    var right: i32 = 0;
    var it = wm.dock_struts.iterator();
    while (it.next()) |entry| {
        const win = entry.key_ptr.*;
        const s   = entry.value_ptr.*;
        if (s.top > 0) {
            _ = c.XMoveWindow(wm.display, win, 0, top);
            top += @intCast(s.top);
        } else if (s.bottom > 0) {
            bottom += @intCast(s.bottom);
            _ = c.XMoveWindow(wm.display, win, 0, @as(i32, @intCast(wm.screen_height)) - bottom);
        } else if (s.left > 0) {
            _ = c.XMoveWindow(wm.display, win, left, 0);
            left += @intCast(s.left);
        } else if (s.right > 0) {
            right += @intCast(s.right);
            _ = c.XMoveWindow(wm.display, win, @as(i32, @intCast(wm.screen_width)) - right, 0);
        }
    }
    _ = c.XFlush(wm.display);
}

pub fn on_map_request(wm: *WM, req: *c.XMapRequestEvent) !void {
    var attrs: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(wm.display, req.window, &attrs);
    if (attrs.override_redirect != 0) return;

    if (is_dock_or_toolbar(wm.display, req.window)) {
        _ = c.XMapWindow(wm.display, req.window);
        const s = get_strut(wm.display, req.window) orelse Strut{ .left = 0, .right = 0, .top = 0, .bottom = 0 };

        // Sum existing struts BEFORE inserting this dock
        var existing_top: u32 = 0;
        var existing_bottom: u32 = 0;
        var existing_left: u32 = 0;
        var existing_right: u32 = 0;
        var strut_it = wm.dock_struts.valueIterator();
        while (strut_it.next()) |es| {
            existing_top    += es.top;
            existing_bottom += es.bottom;
            existing_left   += es.left;
            existing_right  += es.right;
        }

        // Reposition the dock so it stacks after existing ones on the same side
        if (s.top > 0) {
            _ = c.XMoveWindow(wm.display, req.window, 0, @intCast(existing_top));
        } else if (s.bottom > 0) {
            const new_y: i32 = @intCast(wm.screen_height - existing_bottom - s.bottom);
            _ = c.XMoveWindow(wm.display, req.window, 0, new_y);
        } else if (s.left > 0) {
            _ = c.XMoveWindow(wm.display, req.window, @intCast(existing_left), 0);
        } else if (s.right > 0) {
            const new_x: i32 = @intCast(wm.screen_width - existing_right - s.right);
            _ = c.XMoveWindow(wm.display, req.window, new_x, 0);
        }

        try wm.dock_struts.put(req.window, s);
        restack_docks(wm);
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        return;
    }

    const node = try wm.current_graph.add_node(.{ .window = req.window });
    try wm.frame(req.window, node);
    _ = c.XMapWindow(wm.display, req.window);
    const prev_focused = wm.focused;
    if (wm.focused == null) wm.focus(node);
    const id = try wm.register_node(req.window, node);

    if (wm.lua) |lua| {
        if (wm.on_map_ref != 0) {
            _ = lua.getIndexRaw(ziglua.registry_index, wm.on_map_ref);
            lua.pushInteger(@intCast(id));
            if (prev_focused) |f| {
                var focused_id: ?u32 = null;
                var it = wm.node_registry.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == f) {
                        focused_id = entry.key_ptr.*;
                        break;
                    }
                }
                if (focused_id) |fid| lua.pushInteger(@intCast(fid)) else lua.pushNil();
            } else {
                lua.pushNil();
            }
            try lua.protectedCall(.{ .args = 2, .results = 0 });
        }
    }

    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);

    // Listen for future property changes on client
    _ = c.XSelectInput(wm.display, req.window, c.PropertyChangeMask);

    // Re‑check type in case it was set after MapRequest
    if (is_dock_or_toolbar(wm.display, req.window)) {
        // We must undo the frame & tiling – reuse destroy logic
        const node_id = wm.window_to_node_id.get(req.window) orelse return;
        const node_dock = wm.node_registry.get(node_id) orelse return;
        // Record strut
        if (get_strut(wm.display, req.window)) |s| {
            try wm.dock_struts.put(req.window, s);
        }
        // Unframe, unmap, reparent, etc.
        if (wm.frames.get(req.window)) |frame| {
            _ = c.XUnmapWindow(wm.display, req.window);
            _ = c.XReparentWindow(wm.display, req.window, wm.root, 0, 0);
            _ = c.XDestroyWindow(wm.display, frame);
            _ = wm.frames.remove(req.window);
        }
        _ = c.XMapWindow(wm.display, req.window);
        // Remove from graph and registry
        wm.current_graph.remove_node(node_dock);
        _ = wm.node_registry.remove(node_id);
        _ = wm.window_to_node_id.remove(req.window);
        // Relayout
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        return;
    }
}

pub fn on_property_notify(wm: *WM, ev: *c.XPropertyEvent) !void {
    const net_wm_window_type = c.XInternAtom(wm.display, "_NET_WM_WINDOW_TYPE", 0);
    const win = ev.window;

    if (ev.atom == net_wm_window_type) {
        // only act if this window is currently managed
        if (wm.window_to_node_id.contains(win)) {
            if (is_dock_or_toolbar(wm.display, win)) {
                // It became a dock – unmanage it
                const node_id = wm.window_to_node_id.get(win).?;
                const node = wm.node_registry.get(node_id).?;
                // Record strut
                if (get_strut(wm.display, win)) |s| {
                    try wm.dock_struts.put(win, s);
                }
                // Unframe, unmap, reparent, etc.
                if (wm.frames.get(win)) |frame| {
                    _ = c.XUnmapWindow(wm.display, win);
                    _ = c.XReparentWindow(wm.display, win, wm.root, 0, 0);
                    _ = c.XDestroyWindow(wm.display, frame);
                    _ = wm.frames.remove(win);
                }
                _ = c.XMapWindow(wm.display, win);

                wm.current_graph.remove_node(node);
                _ = wm.node_registry.remove(node_id);
                _ = wm.window_to_node_id.remove(win);

                try wm.resolve(wm.current_graph);
                try wm.rebuild_focus_edges();
                try wm.flush(wm.current_graph);
            }
        }
    }
    // also handle strut changes for existing docks
    else if (ev.atom == c.XInternAtom(wm.display, "_NET_WM_STRUT_PARTIAL", 0)) {
        if (wm.dock_struts.contains(win)) {
            // update strut
            if (get_strut(wm.display, win)) |s| {
                try wm.dock_struts.put(win, s);
            } else {
                _ = wm.dock_struts.remove(win);
            }
            try wm.resolve(wm.current_graph);
            try wm.rebuild_focus_edges();
            try wm.flush(wm.current_graph);
        }
    }
}

pub fn on_create_notify(_: *WM, event: *c.XCreateWindowEvent) void {
    std.debug.print("CreateNotify: window={}, parent={}, x={}, y={}, width={}, height={}\n",
        .{ event.window, event.parent, event.x, event.y, event.width, event.height });
}

pub fn on_destroy_notify(wm: *WM, event: *c.XDestroyWindowEvent) !void {
    const win = event.window;

    // If it was a dock/toolbar, remove its strut and recalc
    if (wm.dock_struts.remove(win)) {
        restack_docks(wm);
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        return;  // no frame cleanup needed
    }

    // Check if this is a frame being destroyed (we initiated this)
    var is_frame = false;
    var frame_iter = wm.frames.iterator();
    while (frame_iter.next()) |entry| {
        if (entry.value_ptr.* == win) {
            is_frame = true;
            break;
        }
    }
    
    // Ignore frame destroy events - we handle cleanup when the client is destroyed
    if (is_frame) {
        return;
    }

    // Find the dying node and its ID before any modifications
    var dying: ?*Node = null;
    var dying_id: ?u32 = null;
    
    if (wm.window_to_node_id.get(win)) |id| {
        dying_id = id;
        if (wm.node_registry.get(id)) |node| {
            dying = node;
        }
    }
    
    // If this window isn't managed, nothing to do
    if (dying == null) {
        return;
    }

    // Determine next focus BEFORE removing anything
    var next_focus: ?*Node = null;
    const focused_is_dying = (wm.focused == dying);

    if (focused_is_dying) {
        // Try focus edges first
        for (wm.current_graph.focus_edges.items) |edge| {
            if (edge.from == dying and edge.to != dying) {
                next_focus = edge.to;
                break;
            }
        }
        
        // Fallback: any other window node
        if (next_focus == null) {
            for (wm.current_graph.nodes.items) |node| {
                if (node == dying) continue;
                switch (node.content) {
                    .window => {
                        next_focus = node;
                        break;
                    },
                    else => continue,
                }
            }
        }
    }

    // Notify Lua BEFORE removing the node
    if (dying_id) |id| {
        if (wm.lua) |lua| {
            if (wm.on_unmap_ref != 0) {
                _ = lua.getIndexRaw(ziglua.registry_index, wm.on_unmap_ref);
                lua.pushInteger(@intCast(id));
                lua.protectedCall(.{ .args = 1, .results = 0 }) catch |err| {
                    std.debug.print("Lua on_unmap callback error: {}\n", .{err});
                };
            }
        }
    }

    // Clean up frame
    if (wm.frames.get(win)) |win_frame| {
        _ = c.XUnmapWindow(wm.display, win_frame);
        _ = c.XDestroyWindow(wm.display, win_frame);
        _ = wm.frames.remove(win);
    }

    // Clean up registry BEFORE removing from graph
    if (dying_id) |id| {
        _ = wm.node_registry.remove(id);
        _ = wm.window_to_node_id.remove(win);
    }

    // if a window dies while resizing cancel the resize
    if (wm.edge_resizing) {
        wm.edge_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
    }

    // Remove from graph - this frees the node pointer
    if (dying) |d| {
        wm.current_graph.remove_node(d);
    }

    // Update focus - never touch the freed node
    if (focused_is_dying) {
        wm.focused = next_focus;
        if (next_focus) |n| {
            wm.focus(n);
        }
    }

    // fallback input restoration
    if (wm.focused == null) {
        _ = c.XSetInputFocus(wm.display, wm.root, c.RevertToParent, c.CurrentTime);
    }

    // Only rebuild if we still have nodes
    if (wm.current_graph.nodes.items.len > 0) {
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
    } else {
        wm.reset_root_state();
        wm.current_graph.focus_edges.clearRetainingCapacity();
    }
}

pub fn on_reparent_notify(_: *WM, event: *c.XReparentEvent) void {
    std.debug.print("ReparentNotify: window={}, parent={}, x={}, y={}\n",
        .{ event.window, event.parent, event.x, event.y });
}

/// Helper: check if a point is near an edge or corner of a floating window.
fn find_float_edge_or_corner(node: *Node, x: i32, y: i32, threshold: i32) struct {
    is_edge: bool,
    is_corner: bool,
    edge_vertical: bool,
    edge_coord: i32,
    corner_v: i32,
    corner_h: i32,
} {
    const left = node.x;
    const right = node.x + @as(i32, @intCast(node.width));
    const top = node.y;
    const bottom = node.y + @as(i32, @intCast(node.height));

    const near_left = @abs(x - left) <= threshold;
    const near_right = @abs(x - right) <= threshold;
    const near_top = @abs(y - top) <= threshold;
    const near_bottom = @abs(y - bottom) <= threshold;

    const is_corner = (near_left and near_top) or (near_left and near_bottom) or
                      (near_right and near_top) or (near_right and near_bottom);
    const is_edge = (near_left or near_right or near_top or near_bottom) and !is_corner;

    var edge_vertical = false;
    var edge_coord: i32 = 0;
    var corner_v: i32 = 0;
    var corner_h: i32 = 0;

    if (is_edge) {
        if (near_left) {
            edge_vertical = true;
            edge_coord = left;
        } else if (near_right) {
            edge_vertical = true;
            edge_coord = right;
        } else if (near_top) {
            edge_vertical = false;
            edge_coord = top;
        } else if (near_bottom) {
            edge_vertical = false;
            edge_coord = bottom;
        }
    } else if (is_corner) {
        if (near_left) corner_v = left else if (near_right) corner_v = right;
        if (near_top) corner_h = top else if (near_bottom) corner_h = bottom;
    }

    return .{
        .is_edge = is_edge,
        .is_corner = is_corner,
        .edge_vertical = edge_vertical,
        .edge_coord = edge_coord,
        .corner_v = corner_v,
        .corner_h = corner_h,
    };
}

pub fn on_button_press(wm: *WM, ev: *c.XButtonEvent) void {
    const lookup_win = if (ev.window == wm.root) ev.subwindow else ev.window;
    if (lookup_win == 0) return;

    // ----- Floating handling -----
    if (wm.float_move_modifier) |float_modifier| {
        if (ev.state & float_modifier != 0) {
            const client = wm.get_client_from_frame(lookup_win) orelse return;
            const node_id = wm.window_to_node_id.get(client) orelse return;
            const node = wm.node_registry.get(node_id) orelse return;
            if (node.floating) {
                const info = find_float_edge_or_corner(node, ev.x_root, ev.y_root, 8);

                const left   = node.x;
                const right  = node.x + @as(i32, @intCast(node.width));
                const top    = node.y;
                const bottom = node.y + @as(i32, @intCast(node.height));

                if (info.is_corner) {
                    wm.corner_resizing = true;
                    wm.resize_v_edge   = info.corner_v;
                    wm.resize_h_edge   = info.corner_h;
                    wm.resize_end_x    = ev.x_root;
                    wm.resize_end_y    = ev.y_root;
                    // fixed point is the opposite corner
                    wm.resize_fixed_x = if (info.corner_v == left) right else left;
                    wm.resize_fixed_y = if (info.corner_h == top) bottom else top;
                } else if (info.is_edge) {
                    wm.edge_resizing    = true;
                    wm.edge_is_vertical = info.edge_vertical;
                    if (info.edge_vertical) {
                        wm.edge_x = info.edge_coord;
                        wm.resize_fixed_x = if (info.edge_coord == left) right else left;
                    } else {
                        wm.edge_y = info.edge_coord;
                        wm.resize_fixed_y = if (info.edge_coord == top) bottom else top;
                    }
                    wm.resize_end_x = ev.x_root;
                    wm.resize_end_y = ev.y_root;
                } else {
                    wm.float_moving       = true;
                    wm.float_move_frame   = lookup_win;   // <-- FIX: store the frame window
                    wm.float_move_start_x = ev.x_root;
                    wm.float_move_start_y = ev.y_root;
                    wm.float_win_start_x  = node.x;
                    wm.float_win_start_y  = node.y;
                }
                _ = c.XGrabPointer(wm.display, lookup_win, 1,
                    c.PointerMotionMask | c.ButtonReleaseMask,
                    c.GrabModeAsync, c.GrabModeAsync, c.None, c.None, c.CurrentTime);
                return;
            }
        }
    }

    // ----- Tiling resize -----
    if (wm.resize_modifier) |resize_modifier| {
        if (ev.state & resize_modifier == 0) return;
    } else return;

    if (resize_mod.find_corner_at(wm, ev.x_root, ev.y_root, 8)) |corner| {
        wm.corner_resizing = true;
        wm.resize_v_edge   = corner.v_edge;
        wm.resize_h_edge   = corner.h_edge;
        wm.resize_end_x    = ev.x_root;
        wm.resize_end_y    = ev.y_root;
        _ = c.XGrabPointer(wm.display, lookup_win, 1,
            c.PointerMotionMask | c.ButtonReleaseMask,
            c.GrabModeAsync, c.GrabModeAsync, c.None, c.None, c.CurrentTime);
        return;
    }
    if (resize_mod.find_edge_at(wm, ev.x_root, ev.y_root, 8)) |edge| {
        wm.edge_resizing    = true;
        wm.edge_is_vertical = edge.is_vertical;
        if (edge.is_vertical) wm.edge_x = edge.coordinate
        else                  wm.edge_y = edge.coordinate;
        wm.resize_end_x = ev.x_root;
        wm.resize_end_y = ev.y_root;
        _ = c.XGrabPointer(wm.display, lookup_win, 1,
            c.PointerMotionMask | c.ButtonReleaseMask,
            c.GrabModeAsync, c.GrabModeAsync, c.None, c.None, c.CurrentTime);
    }
}

pub fn on_motion_notify(wm: *WM, ev: *c.XMotionEvent) void {
    // Floating window moving
    if (wm.float_moving) {
        const delta_x = ev.x_root - wm.float_move_start_x;
        const delta_y = ev.y_root - wm.float_move_start_y;
        if (delta_x != 0 or delta_y != 0) {
            const client = wm.get_client_from_frame(wm.float_move_frame) orelse return;
            const node_id = wm.window_to_node_id.get(client) orelse return;
            const node = wm.node_registry.get(node_id) orelse return;
            if (node.floating) {
                node.x = wm.float_win_start_x + delta_x;
                node.y = wm.float_win_start_y + delta_y;
                if (wm.frames.get(client)) |frame| {
                    _ = c.XMoveWindow(wm.display, frame, node.x, node.y);
                }
            }
        }
        return;
    }

    // Floating / tiling resizing
    if (wm.edge_resizing or wm.corner_resizing) {
        const focused = wm.focused orelse return;
        if (focused.floating) {
            const client = switch (focused.content) {
                .window => |win| win,
                else => return,
            };

            // --- Floating resize with fixed anchor ---
            if (wm.corner_resizing) {
                const delta_x = ev.x_root - wm.resize_end_x;
                const delta_y = ev.y_root - wm.resize_end_y;
                if (delta_x != 0 or delta_y != 0) {
                    if (delta_x != 0) wm.resize_v_edge += delta_x;
                    if (delta_y != 0) wm.resize_h_edge += delta_y;
                    wm.resize_end_x = ev.x_root;
                    wm.resize_end_y = ev.y_root;

                    const new_x = @min(wm.resize_fixed_x, wm.resize_v_edge);
                    const new_y = @min(wm.resize_fixed_y, wm.resize_h_edge);
                    const new_w: u32 = @intCast(@max(10, @abs(wm.resize_fixed_x - wm.resize_v_edge)));
                    const new_h: u32 = @intCast(@max(10, @abs(wm.resize_fixed_y - wm.resize_h_edge)));
                    focused.x = new_x;
                    focused.y = new_y;
                    focused.width = new_w;
                    focused.height = new_h;
                }
            } else if (wm.edge_resizing) {
                if (wm.edge_is_vertical) {
                    const delta_x = ev.x_root - wm.resize_end_x;
                    if (delta_x != 0) {
                        wm.edge_x += delta_x;
                        wm.resize_end_x = ev.x_root;
                        const new_x = @min(wm.resize_fixed_x, wm.edge_x);
                        const new_w: u32 = @intCast(@max(10, @abs(wm.resize_fixed_x - wm.edge_x)));
                        focused.x = new_x;
                        focused.width = new_w;
                    }
                } else {
                    const delta_y = ev.y_root - wm.resize_end_y;
                    if (delta_y != 0) {
                        wm.edge_y += delta_y;
                        wm.resize_end_y = ev.y_root;
                        const new_y = @min(wm.resize_fixed_y, wm.edge_y);
                        const new_h: u32 = @intCast(@max(10, @abs(wm.resize_fixed_y - wm.edge_y)));
                        focused.y = new_y;
                        focused.height = new_h;
                    }
                }
            }

            // Apply geometry changes to frame and client
            if (wm.frames.get(client)) |frame| {
                _ = c.XMoveResizeWindow(wm.display, frame, focused.x, focused.y, focused.width, focused.height);
                const border_2x = 2 * @as(u32, @intCast(wm.border_width));
                const client_w = if (focused.width >= 2 * wm.border_width) focused.width - border_2x else 0;
                const client_h = if (focused.height >= 2 * wm.border_width) focused.height - border_2x else 0;
                _ = c.XResizeWindow(wm.display, client, client_w, client_h);
            }
            return;
        } else {
            // Tiling resize (unchanged original logic)
            if (wm.corner_resizing) {
                const delta_x = ev.x_root - wm.resize_end_x;
                const delta_y = ev.y_root - wm.resize_end_y;
                if (delta_x != 0) {
                    if (resize_mod.resize_vertical_edge(wm, wm.resize_v_edge, delta_x) catch false) {
                        wm.resize_v_edge += delta_x;
                    }
                    wm.resize_end_x = ev.x_root;
                }
                if (delta_y != 0) {
                    if (resize_mod.resize_horizontal_edge(wm, wm.resize_h_edge, delta_y) catch false) {
                        wm.resize_h_edge += delta_y;
                    }
                    wm.resize_end_y = ev.y_root;
                }
                return;
            }
            if (wm.edge_resizing) {
                const delta_x = ev.x_root - wm.resize_end_x;
                const delta_y = ev.y_root - wm.resize_end_y;
                if (wm.edge_is_vertical) {
                    if (delta_x != 0) {
                        if (resize_mod.resize_vertical_edge(wm, wm.edge_x, delta_x) catch false) {
                            wm.edge_x += delta_x;
                        }
                        wm.resize_end_x = ev.x_root;
                    }
                } else {
                    if (delta_y != 0) {
                        if (resize_mod.resize_horizontal_edge(wm, wm.edge_y, delta_y) catch false) {
                            wm.edge_y += delta_y;
                        }
                        wm.resize_end_y = ev.y_root;
                    }
                }
            }
        }
    }
}

pub fn on_button_release(wm: *WM, _: *c.XButtonEvent) void {
    if (wm.float_moving) {
        wm.float_moving = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
        // Raise all floating windows to keep them on top after moving
        float_mod.raise_floating_windows(wm);
    }
    if (wm.corner_resizing) {
        wm.corner_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
        // For floating resize, raise after completion
        if (wm.focused) |node| {
            if (node.floating) float_mod.raise_floating_windows(wm);
        }
    }
    if (wm.edge_resizing) {
        wm.edge_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
        if (wm.focused) |node| {
            if (node.floating) float_mod.raise_floating_windows(wm);
        }
    }
}

pub fn on_key_press(wm: *WM, event: *c.XKeyEvent) void {
    const keysym = c.XKeycodeToKeysym(wm.display, @as(u8, @truncate(event.keycode)), 0);
    if (wm.keybinds.get(.{ .modifiers = event.state, .keysym = keysym })) |kb| {
        switch (kb) {
            .zig => |a| {
                a(wm) catch |err| {
                    std.debug.print("Keybinding error: {}\n", .{err});
                };
            },
            .lua => |ref| {
                if (wm.lua) |lua| {
                    _ = lua.getIndexRaw(ziglua.registry_index, ref);
                    lua.protectedCall(.{ .args = 0, .results = 0 }) catch |err| {
                        std.debug.print("Lua keybinding error: {}\n", .{err});
                    };
                }
            },
        }
    }
}

fn is_dock_or_toolbar(display: *c.Display, win: c.Window) bool {
    const net_wm_window_type = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE", 0);
    const net_wm_window_type_dock = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", 0);
    const net_wm_window_type_toolbar = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_TOOLBAR", 0);
    const net_wm_window_type_menu = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_MENU", 0);
    const net_wm_window_type_utility = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_UTILITY", 0);

    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var prop: ?*c_ulong = null;

    if (c.XGetWindowProperty(
        display,
        win,
        net_wm_window_type,
        0, 2, 0,
        0,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        @ptrCast(&prop),
    ) != c.Success) return false;

    // No property → not a dock
    if (nitems == 0) return false;

    // Ensure memory is freed when we leave this function
    defer {
        if (prop) |p| _ = c.XFree(@ptrCast(p));
    }

    if (actual_format != 32) return false;

    const atoms: [*]c_ulong = @ptrCast(prop);
    for (atoms[0..nitems]) |a| {
        if (a == net_wm_window_type_dock or
            a == net_wm_window_type_toolbar or
            a == net_wm_window_type_menu or
            a == net_wm_window_type_utility)
            return true;
    }
    return false;
}

fn get_strut(display: *c.Display, win: c.Window) ?Strut {
    const strut_partial = c.XInternAtom(display, "_NET_WM_STRUT_PARTIAL", 0);
    const XA_CARDINAL = c.XInternAtom(display, "CARDINAL", 0);

    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var prop: ?*c_ulong = null;

    if (c.XGetWindowProperty(
        display,
        win,
        strut_partial,
        0, 12, 0,
        XA_CARDINAL,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        @ptrCast(&prop),
    ) != c.Success) return null;

    // No property or too few items
    if (nitems < 12) {
        if (prop) |p| _ = c.XFree(@ptrCast(p));
        return null;
    }

    // Free after reading
    defer {
        if (prop) |p| _ = c.XFree(@ptrCast(p));
    }

    if (actual_format != 32) return null;

    const data: [*]c_ulong = @ptrCast(prop);
    return Strut{
        .left   = @intCast(data[0]),
        .right  = @intCast(data[1]),
        .top    = @intCast(data[2]),
        .bottom = @intCast(data[3]),
    };
}

// Set _NET_ACTIVE_WINDOW on the root
pub fn update_net_active_window(wm: *WM, active_window: c.Window) void {
    const atom = c.XInternAtom(wm.display, "_NET_ACTIVE_WINDOW", 0);
    const XA_WINDOW = c.XInternAtom(wm.display, "WINDOW", 0);
    const new_val: c.Window = active_window;
    _ = c.XChangeProperty(wm.display, wm.root, atom,
        XA_WINDOW, 32, c.PropModeReplace,
        @ptrCast(&new_val), 1);
}

pub fn announce_supported_hints(self: *WM) void {
    const supported = c.XInternAtom(self.display, "_NET_SUPPORTED", 0);
    const XA_ATOM = c.XInternAtom(self.display, "ATOM", 0);
    const atoms = [_]c.Atom{
        supported,
        c.XInternAtom(self.display, "_NET_ACTIVE_WINDOW", 0),
        c.XInternAtom(self.display, "_NET_WM_WINDOW_TYPE", 0),
        c.XInternAtom(self.display, "_NET_WM_STRUT_PARTIAL", 0),
        c.XInternAtom(self.display, "_NET_WORKAREA", 0),
    };
    _ = c.XChangeProperty(self.display, self.root, supported,
        XA_ATOM, 32, c.PropModeReplace,
        @ptrCast(&atoms), atoms.len);
}
