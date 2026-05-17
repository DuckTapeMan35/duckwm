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
    node.width  = @intCast(attrs.width);
    node.height = @intCast(attrs.height);
    try wm.frame(req.window, node);
    const prev_focused = wm.focused;
    if (wm.focused == null) wm.focus(node);
    const id = try wm.register_node(req.window, node);

    {
        var prev_id: ?u32 = null;
        if (prev_focused) |f| {
            var in_current = false;
            for (wm.current_graph.nodes.items) |n| {
                if (n == f) { in_current = true; break; }
            }
            if (in_current) {
                var it = wm.node_registry.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == f) { prev_id = entry.key_ptr.*; break; }
                }
            }
            if (prev_id) |pid| {
                if (wm.node_registry.get(pid)) |pnode| {
                    if (pnode.floating) {
                        prev_id = null;
                        // Find any tiled window in the current graph that isn't the new node
                        for (wm.current_graph.nodes.items) |n| {
                            if (n.floating) continue;
                            if (n.content != .window and n.content != .workspace) continue;
                            if (wm.get_id_for_node(n)) |nid| {
                                if (nid != id) {
                                    prev_id = nid;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
        wm.call_arranger(wm.current_graph, "pre_map", id, prev_id);
        const is_floating = if (wm.node_registry.get(id)) |n| n.floating else false;
        if (!is_floating) {
            wm.call_arranger(wm.current_graph, "map", id, prev_id);
        }
    }

    try wm.resolve(wm.current_graph);
    try wm.rebuild_focus_edges();
    try wm.flush(wm.current_graph);

    // Re-raise floating windows above the newly mapped window
    for (wm.current_graph.nodes.items) |n| {
        switch (n.content) {
            .window => |win| {
                if (!n.floating) continue;
                if (wm.frames.get(win)) |frame| {
                    _ = c.XRaiseWindow(wm.display, frame);
                }
            },
            else => {},
        }
    }

    if (wm.focused) |f| wm.focus(f);

    // Listen for future property changes on client
    _ = c.XSelectInput(wm.display, req.window, c.PropertyChangeMask);

    // Re-check type in case it was set after MapRequest
    if (is_dock_or_toolbar(wm.display, req.window)) {
        const node_id = wm.window_to_node_id.get(req.window) orelse return;
        const node_dock = wm.node_registry.get(node_id) orelse return;
        if (get_strut(wm.display, req.window)) |s| {
            try wm.dock_struts.put(req.window, s);
        }
        if (wm.frames.get(req.window)) |frame| {
            _ = c.XUnmapWindow(wm.display, req.window);
            _ = c.XReparentWindow(wm.display, req.window, wm.root, 0, 0);
            _ = c.XDestroyWindow(wm.display, frame);
            _ = wm.frames.remove(req.window);
        }
        _ = c.XMapWindow(wm.display, req.window);
        if (node_dock.owner_graph) |graph| {
            graph.remove_node(node_dock);
        }
        _ = wm.node_registry.remove(node_id);
        _ = wm.window_to_node_id.remove(req.window);
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        return;
    }
}

pub fn on_client_message(wm: *WM, ev: *c.XClientMessageEvent) !void {
    const net_wm_state = c.XInternAtom(wm.display, "_NET_WM_STATE", 0);
    const net_wm_state_fullscreen = c.XInternAtom(wm.display, "_NET_WM_STATE_FULLSCREEN", 0);
    const net_wm_state_demands_attention = c.XInternAtom(wm.display, "_NET_WM_STATE_DEMANDS_ATTENTION", 0);

    if (ev.message_type == net_wm_state) {
        const action = ev.data.l[0];
        const prop1: c.Atom = @intCast(ev.data.l[1]);
        const prop2: c.Atom = @intCast(ev.data.l[2]);

        const is_fullscreen = (prop1 == net_wm_state_fullscreen or
                               prop2 == net_wm_state_fullscreen);
        if (is_fullscreen) {
            const node_id = wm.window_to_node_id.get(ev.window) orelse return;
            const node = wm.node_registry.get(node_id) orelse return;
            const currently_fullscreen = (wm.fullscreen_node == node);
            const should_fullscreen = switch (action) {
                0 => false,
                1 => true,
                2 => !currently_fullscreen,
                else => return,
            };
            if (should_fullscreen != currently_fullscreen) {
                wm.focused = node;
                try wm.toggle_fullscreen();
            }
        }

        const is_attention = (prop1 == net_wm_state_demands_attention or
                              prop2 == net_wm_state_demands_attention);
        if (is_attention) {
            if (wm.window_to_node_id.get(ev.window)) |node_id| {
                if (wm.node_registry.get(node_id)) |node| {
                    const should_urgent = (action != 0);
                    node.urgent = should_urgent;
                    if (wm.frames.get(ev.window)) |frame| {
                        const color = if (should_urgent)
                            wm.default_border_color_urgent
                        else if (wm.focused == node)
                            node.border_color_focused orelse wm.default_border_color_focused
                        else
                            node.border_color_unfocused orelse wm.default_border_color_unfocused;
                        _ = c.XSetWindowBorder(wm.display, frame, color);
                        _ = c.XFlush(wm.display);
                    }
                }
            }
        }
    }
}

pub fn on_property_notify(wm: *WM, ev: *c.XPropertyEvent) !void {
    const win = ev.window;

    const net_wm_window_type    = c.XInternAtom(wm.display, "_NET_WM_WINDOW_TYPE", 0);
    const net_wm_strut_partial  = c.XInternAtom(wm.display, "_NET_WM_STRUT_PARTIAL", 0);
    const wm_hints_atom         = c.XInternAtom(wm.display, "WM_HINTS", 0);

    if (ev.atom == net_wm_window_type) {
        if (wm.window_to_node_id.contains(win)) {
            if (is_dock_or_toolbar(wm.display, win)) {
                const node_id = wm.window_to_node_id.get(win).?;
                const node = wm.node_registry.get(node_id).?;
                if (get_strut(wm.display, win)) |s| {
                    try wm.dock_struts.put(win, s);
                }
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
    } else if (ev.atom == net_wm_strut_partial) {
        if (wm.dock_struts.contains(win)) {
            if (get_strut(wm.display, win)) |s| {
                try wm.dock_struts.put(win, s);
            } else {
                _ = wm.dock_struts.remove(win);
            }
            try wm.resolve(wm.current_graph);
            try wm.rebuild_focus_edges();
            try wm.flush(wm.current_graph);
        }
    } else if (ev.atom == wm_hints_atom) {
        if (wm.window_to_node_id.get(win)) |node_id| {
            if (wm.node_registry.get(node_id)) |node| {
                // If this window isn't focused, treat any WM_HINTS change as urgent
                if (wm.focused != node) {
                    const hints = c.XGetWMHints(wm.display, win);
                    const urgent = if (hints != null) blk: {
                        defer _ = c.XFree(hints);
                        break :blk (hints.*.flags & c.XUrgencyHint) != 0;
                    } else true; // null means xterm already cleared it — still signal urgency
                    node.urgent = urgent;
                    if (wm.frames.get(win)) |frame| {
                        const color = if (urgent)
                            wm.default_border_color_urgent
                        else
                            node.border_color_unfocused orelse wm.default_border_color_unfocused;
                        _ = c.XSetWindowBorder(wm.display, frame, color);
                        _ = c.XFlush(wm.display);
                    }
                }
            }
        }
    }
}

pub fn on_create_notify(_: *WM, event: *c.XCreateWindowEvent) void {
    std.debug.print("CreateNotify: window={}, parent={}, x={}, y={}, width={}, height={}\n",
        .{ event.window, event.parent, event.x, event.y, event.width, event.height });
}

fn sweep_dead_containers(wm: *WM) void {
    const g = wm.current_graph;
    var i: usize = 0;
    while (i < g.nodes.items.len) {
        const node = g.nodes.items[i];
        if (node.content == .empty and node.constraints.items.len == 0) {
            // Don't sweep nodes still in the registry (e.g. anchor containers)
            var in_registry = false;
            var rit = wm.node_registry.iterator();
            while (rit.next()) |entry| {
                if (entry.value_ptr.* == node) {
                    in_registry = true;
                    break;
                }
            }
            if (in_registry) {
                i += 1;
                continue;
            }

            var referenced = false;
            for (g.nodes.items) |other| {
                for (other.constraints.items) |con| {
                    const refs = switch (con) {
                        .grid_cell     => |gc| gc.container == node,
                        .grid_cell_abs => |gc| gc.container == node,
                        else           => false,
                    };
                    if (refs) { referenced = true; break; }
                }
                if (referenced) break;
            }
            if (!referenced) {
                var it = wm.node_registry.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == node) {
                        _ = wm.node_registry.remove(entry.key_ptr.*);
                        break;
                    }
                }
                g.nodes.items[i].deinit(wm.allocator);
                wm.allocator.destroy(g.nodes.items[i]);
                _ = g.nodes.swapRemove(i);
                continue;
            }
        }
        i += 1;
    }
}

pub fn on_destroy_notify(wm: *WM, event: *c.XDestroyWindowEvent) !void {
    const win = event.window;

    // If it was a dock/toolbar, remove its strut and recalc
    if (wm.dock_struts.remove(win)) {
        restack_docks(wm);
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        return;
    }

    // Ignore frame destroy events - we handle cleanup when the client is destroyed
    var is_frame = false;
    var frame_iter = wm.frames.iterator();
    while (frame_iter.next()) |entry| {
        if (entry.value_ptr.* == win) {
            is_frame = true;
            break;
        }
    }
    if (is_frame) return;

    // Find the dying node and its ID before any modifications
    var dying: ?*Node = null;
    var dying_id: ?u32 = null;

    if (wm.window_to_node_id.get(win)) |id| {
        dying_id = id;
        if (wm.node_registry.get(id)) |node| {
            dying = node;
        }
    }

    if (dying == null) return;

    // Determine next focus BEFORE removing anything
    var next_focus: ?*Node = null;
    const focused_is_dying = (wm.focused == dying);

    if (focused_is_dying) {
        for (wm.current_graph.focus_edges.items) |edge| {
            if (edge.from == dying and edge.to != dying) {
                next_focus = edge.to;
                break;
            }
        }
        if (next_focus == null) {
            for (wm.current_graph.nodes.items) |node| {
                if (node == dying) continue;
                switch (node.content) {
                    .window => { next_focus = node; break; },
                    else => continue,
                }
            }
        }
    }

    // Notify Lua before unmapping or destroying anything, so it can query properties if needed
    if (dying_id) |id| {
        const is_floating = if (dying) |d| d.floating else false;
        if (!is_floating) {
            wm.call_arranger(wm.current_graph, "unmap", id, null);
        }
    }

    // Now remove from registry
    if (dying_id) |id| {
        _ = wm.node_registry.remove(id);
        _ = wm.window_to_node_id.remove(win);
    }

    // Clean up frame
    if (wm.frames.get(win)) |win_frame| {
        _ = c.XUnmapWindow(wm.display, win_frame);
        _ = c.XDestroyWindow(wm.display, win_frame);
        _ = wm.frames.remove(win);
    }

    // Cancel any in-progress resize
    if (wm.edge_resizing) {
        wm.edge_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
    }

    // Remove from graph
    if (dying) |d| {
        std.debug.print("Destroying node for window {} (id {})\n", .{ win, dying_id orelse 0 });
        if (d.owner_graph) |g| {
            g.remove_node(d);
        }
    }

    // Sweep orphaned empty containers left behind by Lua
    {
        var i: usize = 0;
        while (i < wm.current_graph.nodes.items.len) {
            const node = wm.current_graph.nodes.items[i];
            if (node.content != .empty or node.constraints.items.len != 0) {
                i += 1;
                continue;
            }
            var referenced = false;
            for (wm.current_graph.nodes.items) |other| {
                if (other == node) continue;
                for (other.constraints.items) |con| {
                    switch (con) {
                        .grid_cell => |g| if (g.container == node) {
                            referenced = true;
                            break;
                        },
                        else => {},
                    }
                    if (referenced) break;
                }
                if (referenced) break;
            }
            if (!referenced) {
                var it = wm.node_registry.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == node) {
                        _ = wm.node_registry.remove(entry.key_ptr.*);
                        break;
                    }
                }
                node.deinit(wm.allocator);
                wm.allocator.destroy(node);
                _ = wm.current_graph.nodes.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    // Update focus
    if (focused_is_dying) {
        wm.focused = next_focus;
        if (next_focus) |n| wm.focus(n);
    }

    if (wm.focused == null) {
        focus_mod.clear_active_window(wm);
        _ = c.XSetInputFocus(wm.display, wm.root, c.RevertToParent, c.CurrentTime);
    }

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

pub fn on_button_press(wm: *WM, ev: *c.XButtonEvent) !void {
    if (wm.click_to_focus) {
        const lookup = if (ev.window == wm.root) ev.subwindow else ev.window;
        if (lookup != 0) {
            const client = wm.get_client_from_frame(lookup) orelse lookup;
            if (wm.window_to_node_id.get(client)) |node_id| {
                if (wm.node_registry.get(node_id)) |node| {
                    if (wm.focused != node) {
                        wm.focus(node);
                        wm.flush(wm.current_graph) catch {};
                    }
                }
            }
        }
        // Replay the event so the click reaches the application
        _ = c.XAllowEvents(wm.display, c.ReplayPointer, c.CurrentTime);
        return;
    }
    // Dismiss error bar on click
    if (wm.error_bar_win != 0 and ev.window == wm.error_bar_win) {
        _ = c.XDestroyWindow(wm.display, wm.error_bar_win);
        _ = c.XFlush(wm.display);
        wm.error_bar_win = 0;
        return;
    }
    const lookup_win = if (ev.window == wm.root) ev.subwindow else ev.window;
    if (lookup_win == 0) return;

    const clean_state = ev.state & ~@as(c_uint, c.LockMask | c.Mod2Mask | c.Mod3Mask | c.Mod5Mask);

    // ----- Floating handling -----
    if (wm.float_move_modifier) |float_modifier| {
        if (clean_state & float_modifier != 0) {
            const client = wm.get_client_from_frame(lookup_win) orelse return;
            const node_id = wm.window_to_node_id.get(client) orelse return;
            const node = wm.node_registry.get(node_id) orelse return;
            if (node.floating) {
                const is_move   = ev.button == wm.float_move_button;
                const is_resize = ev.button == wm.float_resize_button;
                if (!is_move and !is_resize) return;

                if (is_move) {
                    wm.float_moving       = true;
                    wm.float_move_frame   = lookup_win;
                    wm.float_move_start_x = ev.x_root;
                    wm.float_move_start_y = ev.y_root;
                    wm.float_win_start_x  = node.x;
                    wm.float_win_start_y  = node.y;
                } else {
                    // resize — quadrant based
                    const cx = node.x + @divTrunc(@as(i32, @intCast(node.width)), 2);
                    const cy = node.y + @divTrunc(@as(i32, @intCast(node.height)), 2);
                    const right_half  = ev.x_root > cx;
                    const bottom_half = ev.y_root > cy;

                    const left   = node.x;
                    const right  = node.x + @as(i32, @intCast(node.width));
                    const top    = node.y;
                    const bottom = node.y + @as(i32, @intCast(node.height));

                    if (right_half and bottom_half) {
                        wm.corner_resizing = true;
                        wm.resize_v_edge   = right;
                        wm.resize_h_edge   = bottom;
                        wm.resize_end_x    = ev.x_root;
                        wm.resize_end_y    = ev.y_root;
                        wm.resize_fixed_x  = left;
                        wm.resize_fixed_y  = top;
                    } else if (!right_half and !bottom_half) {
                        wm.corner_resizing = true;
                        wm.resize_v_edge   = left;
                        wm.resize_h_edge   = top;
                        wm.resize_end_x    = ev.x_root;
                        wm.resize_end_y    = ev.y_root;
                        wm.resize_fixed_x  = right;
                        wm.resize_fixed_y  = bottom;
                    } else if (right_half) {
                        wm.edge_resizing    = true;
                        wm.edge_is_vertical = true;
                        wm.edge_x           = right;
                        wm.resize_fixed_x   = left;
                        wm.resize_end_x     = ev.x_root;
                        wm.resize_end_y     = ev.y_root;
                    } else {
                        wm.edge_resizing    = true;
                        wm.edge_is_vertical = false;
                        wm.edge_y           = bottom;
                        wm.resize_fixed_y   = top;
                        wm.resize_end_x     = ev.x_root;
                        wm.resize_end_y     = ev.y_root;
                    }
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
        if (clean_state & resize_modifier == 0) return;
    } else return;

    const client = wm.get_client_from_frame(lookup_win) orelse return;
    const node_id = wm.window_to_node_id.get(client) orelse return;
    const node = wm.node_registry.get(node_id) orelse return;
    if (node.floating) return;

    const cx = node.x + @divTrunc(@as(i32, @intCast(node.width)), 2);
    const cy = node.y + @divTrunc(@as(i32, @intCast(node.height)), 2);
    const right_half  = ev.x_root > cx;
    const bottom_half = ev.y_root > cy;

    if (right_half and bottom_half) {
        wm.corner_resizing = true;
        wm.resize_v_edge = node.x + @as(i32, @intCast(node.width));
        wm.resize_h_edge = node.y + @as(i32, @intCast(node.height));
    } else if (!right_half and !bottom_half) {
        wm.corner_resizing = true;
        wm.resize_v_edge = node.x;
        wm.resize_h_edge = node.y;
    } else if (right_half) {
        wm.edge_resizing    = true;
        wm.edge_is_vertical = true;
        wm.edge_x = node.x + @as(i32, @intCast(node.width));
    } else {
        wm.edge_resizing    = true;
        wm.edge_is_vertical = false;
        wm.edge_y = node.y + @as(i32, @intCast(node.height));
    }

    wm.resize_end_x = ev.x_root;
    wm.resize_end_y = ev.y_root;
    _ = c.XGrabPointer(wm.display, lookup_win, 1,
        c.PointerMotionMask | c.ButtonReleaseMask,
        c.GrabModeAsync, c.GrabModeAsync, c.None, c.None, c.CurrentTime);
}

pub fn on_motion_notify(wm: *WM, ev: *c.XMotionEvent) void {
    // Coalesce: discard all but the last pending MotionNotify
    var latest = ev.*;
    var next: c.XEvent = undefined;
    while (c.XCheckTypedEvent(wm.display, c.MotionNotify, &next) != 0) {
        latest = next.xmotion;
    }
    const e = &latest;

    // Floating window moving
    if (wm.float_moving) {
        const delta_x = e.x_root - wm.float_move_start_x;
        const delta_y = e.y_root - wm.float_move_start_y;
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

            if (wm.corner_resizing) {
                const delta_x = e.x_root - wm.resize_end_x;
                const delta_y = e.y_root - wm.resize_end_y;
                if (delta_x != 0 or delta_y != 0) {
                    if (delta_x != 0) wm.resize_v_edge += delta_x;
                    if (delta_y != 0) wm.resize_h_edge += delta_y;
                    wm.resize_end_x = e.x_root;
                    wm.resize_end_y = e.y_root;

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
                    const delta_x = e.x_root - wm.resize_end_x;
                    if (delta_x != 0) {
                        wm.edge_x += delta_x;
                        wm.resize_end_x = e.x_root;
                        const new_x = @min(wm.resize_fixed_x, wm.edge_x);
                        const new_w: u32 = @intCast(@max(10, @abs(wm.resize_fixed_x - wm.edge_x)));
                        focused.x = new_x;
                        focused.width = new_w;
                    }
                } else {
                    const delta_y = e.y_root - wm.resize_end_y;
                    if (delta_y != 0) {
                        wm.edge_y += delta_y;
                        wm.resize_end_y = e.y_root;
                        const new_y = @min(wm.resize_fixed_y, wm.edge_y);
                        const new_h: u32 = @intCast(@max(10, @abs(wm.resize_fixed_y - wm.edge_y)));
                        focused.y = new_y;
                        focused.height = new_h;
                    }
                }
            }

            if (wm.frames.get(client)) |frame| {
                _ = c.XMoveResizeWindow(wm.display, frame, focused.x, focused.y, focused.width, focused.height);

                var ts: std.os.linux.timespec = undefined;
                _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
                const now_ms: i64 = ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
                if (now_ms - wm.last_resize_flush >= wm.resize_refresh_interval) {
                    wm.last_resize_flush = now_ms;
                    _ = c.XResizeWindow(wm.display, client, focused.width, focused.height);
                }
            }
            return;
        } else {
            // Tiling resize
            if (wm.corner_resizing) {
                const delta_x = e.x_root - wm.resize_end_x;
                const delta_y = e.y_root - wm.resize_end_y;
                if (wm.current_graph.lock_vertical_resize and wm.current_graph.lock_horizontal_resize) {
                    // both locked, nothing to do
                } else if (wm.current_graph.lock_vertical_resize) {
                    if (delta_y != 0) {
                        if (resize_mod.resize_horizontal_edge(wm, wm.resize_h_edge, delta_y) catch false) {
                            wm.resize_h_edge += delta_y;
                        }
                        wm.resize_end_y = e.y_root;
                    }
                } else if (wm.current_graph.lock_horizontal_resize) {
                    if (delta_x != 0) {
                        if (resize_mod.resize_vertical_edge(wm, wm.resize_v_edge, delta_x) catch false) {
                            wm.resize_v_edge += delta_x;
                        }
                        wm.resize_end_x = e.x_root;
                    }
                } else {
                    if (delta_x != 0) {
                        if (resize_mod.resize_vertical_edge(wm, wm.resize_v_edge, delta_x) catch false) {
                            wm.resize_v_edge += delta_x;
                        }
                        wm.resize_end_x = e.x_root;
                    }
                    if (delta_y != 0) {
                        if (resize_mod.resize_horizontal_edge(wm, wm.resize_h_edge, delta_y) catch false) {
                            wm.resize_h_edge += delta_y;
                        }
                        wm.resize_end_y = e.y_root;
                    }
                }
            }
            if (wm.edge_resizing) {
                const delta_x = e.x_root - wm.resize_end_x;
                const delta_y = e.y_root - wm.resize_end_y;
                if (wm.edge_is_vertical) {
                    if (!wm.current_graph.lock_vertical_resize and delta_x != 0) {
                        if (resize_mod.resize_vertical_edge(wm, wm.edge_x, delta_x) catch false) {
                            wm.edge_x += delta_x;
                        }
                        wm.resize_end_x = e.x_root;
                    }
                } else {
                    if (!wm.current_graph.lock_horizontal_resize and delta_y != 0) {
                        if (resize_mod.resize_horizontal_edge(wm, wm.edge_y, delta_y) catch false) {
                            wm.edge_y += delta_y;
                        }
                        wm.resize_end_y = e.y_root;
                    }
                }
            }

            const current_edge_x = if (wm.corner_resizing) wm.resize_v_edge else wm.edge_x;
            const current_edge_y = if (wm.corner_resizing) wm.resize_h_edge else wm.edge_y;
            const edge_changed = current_edge_x != wm.last_flushed_edge_x or
                                 current_edge_y != wm.last_flushed_edge_y;
            if (edge_changed) {
                var ts: std.os.linux.timespec = undefined;
                _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
                const now_ms: i64 = ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
                if (now_ms - wm.last_resize_flush >= wm.resize_refresh_interval) {
                    wm.last_resize_flush = now_ms;
                    wm.last_flushed_edge_x = current_edge_x;
                    wm.last_flushed_edge_y = current_edge_y;
                    wm.flush(wm.current_graph) catch {};
                    _ = c.XSync(wm.display, 0);
                }
            }
        }
    }
}

pub fn on_button_release(wm: *WM, _: *c.XButtonEvent) void {
    if (wm.float_moving) {
        wm.float_moving = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
        float_mod.raise_floating_windows(wm);
    }
    if (wm.corner_resizing) {
        wm.corner_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
        if (wm.focused) |node| {
            if (node.floating) {
                float_mod.raise_floating_windows(wm);
            } else {
                for (wm.current_graph.nodes.items) |n| {
                    if (n.floating) continue;
                    switch (n.content) {
                        .window, .workspace => {
                            if (wm.get_id_for_node(n)) |node_id| {
                                wm.call_arranger(wm.current_graph, "resize", node_id, null);
                            }
                        },
                        else => {},
                    }
                }
            }
        }
    }
    if (wm.edge_resizing) {
        wm.edge_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
        if (wm.focused) |node| {
            if (node.floating) {
                float_mod.raise_floating_windows(wm);
            } else {
                // Fire resize on all tiled window nodes in current graph
                for (wm.current_graph.nodes.items) |n| {
                    if (n.floating) continue;
                    switch (n.content) {
                        .window, .workspace => {
                            if (wm.get_id_for_node(n)) |node_id| {
                                wm.call_arranger(wm.current_graph, "resize", node_id, null);
                            }
                        },
                        else => {},
                    }
                }
            }
        }
    }
    wm.last_flushed_edge_x = -1;
    wm.last_flushed_edge_y = -1;
    wm.flush(wm.current_graph) catch {};
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
                    const top = lua.getTop();
                    _ = lua.getIndexRaw(ziglua.registry_index, ref);
                    lua.protectedCall(.{ .args = 0, .results = 0 }) catch |err| {
                        const msg = lua.toString(-1) catch null;
                        std.debug.print("Lua keybinding error: {} {s}\n", .{ err, msg orelse "" });
                        lua.setTop(top);
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

pub fn on_enter_notify(wm: *WM, ev: *c.XCrossingEvent) void {
    if (!wm.focus_follows_mouse) return;
    // ignore grab-related crossing events
    if (ev.mode != c.NotifyNormal) return;

    const lookup_win = if (ev.window == wm.root) ev.subwindow else ev.window;
    if (lookup_win == 0) return;

    const client = wm.get_client_from_frame(lookup_win) orelse return;
    const node_id = wm.window_to_node_id.get(client) orelse return;
    const node = wm.node_registry.get(node_id) orelse return;
    if (wm.focused == node) return;
    wm.focus(node);
    wm.flush(wm.current_graph) catch {};
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

pub fn announce_supported_hints(wm: *WM) void {
    const net_supported = c.XInternAtom(wm.display, "_NET_SUPPORTED", 0);
    const xa_atom = c.XInternAtom(wm.display, "ATOM", 0);

    const atoms = [_]c.Atom{
        c.XInternAtom(wm.display, "_NET_WM_STATE", 0),
        c.XInternAtom(wm.display, "_NET_WM_STATE_FULLSCREEN", 0),
        c.XInternAtom(wm.display, "_NET_WM_STATE_DEMANDS_ATTENTION", 0),
        c.XInternAtom(wm.display, "_NET_WM_WINDOW_TYPE", 0),
        c.XInternAtom(wm.display, "_NET_WM_WINDOW_TYPE_DOCK", 0),
        c.XInternAtom(wm.display, "_NET_WM_WINDOW_TYPE_TOOLBAR", 0),
        c.XInternAtom(wm.display, "_NET_WM_STRUT_PARTIAL", 0),
        c.XInternAtom(wm.display, "_NET_WM_PID", 0),
        c.XInternAtom(wm.display, "_NET_WORKAREA", 0),
        c.XInternAtom(wm.display, "_NET_ACTIVE_WINDOW", 0),
        c.XInternAtom(wm.display, "WM_HINTS", 0),
    };

    _ = c.XChangeProperty(wm.display, wm.root, net_supported,
        xa_atom, 32, c.PropModeReplace,
        @ptrCast(&atoms), @intCast(atoms.len));
}
