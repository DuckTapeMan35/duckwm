const std = @import("std");
const c = @import("c").c;
const WM = @import("core.zig").WM;
const graph_mod = @import("graph");
const ziglua = @import("ziglua");
const resize_mod = @import("resize.zig");
const focus_mod = @import("focus.zig");
const float_mod = @import("float.zig");
const swallow_mod = @import("swallow.zig");

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
        var attrs: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(wm.display, win, &attrs) == 0) continue;
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

fn get_transient_for(wm: *WM, win: c.Window) ?c.Window {
    var transient: c.Window = 0;
    if (c.XGetTransientForHint(wm.display, win, &transient) != 0 and transient != 0 and
        transient != win and transient != wm.root)
    {
        if (wm.window_to_node_id.contains(transient)) return transient;
        if (wm.get_client_from_frame(transient)) |client| return client;
        return transient; // unmanaged parent — still a transient
    }
    return null;
}

fn is_focusable_panel(display: *c.Display, win: c.Window) bool {
    const net_wm_window_type = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE", 0);
    const override_type = c.XInternAtom(display, "_KDE_NET_WM_WINDOW_TYPE_OVERRIDE", 0);

    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var prop: ?*c_ulong = null;

    if (c.XGetWindowProperty(display, win, net_wm_window_type,
        0, 8, 0, 0, &actual_type, &actual_format, &nitems, &bytes_after,
        @ptrCast(&prop)) != c.Success) return false;
    defer if (prop) |p| { _ = c.XFree(@ptrCast(p)); };
    if (nitems == 0 or actual_format != 32) return false;

    const atoms: [*]c_ulong = @ptrCast(prop);
    for (atoms[0..nitems]) |a| {
        if (a == override_type) return true;
    }
    return false;
}

fn should_float(display: *c.Display, win: c.Window) bool {
    const net_wm_window_type = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE", 0);
    const dialog   = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_DIALOG", 0);
    const utility  = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_UTILITY", 0);
    const splash   = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_SPLASH", 0);
    const popup    = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_POPUP_MENU", 0);
    const menu     = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_MENU", 0);
    const tooltip  = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_TOOLTIP", 0);
    const notification = c.XInternAtom(display, "_NET_WM_WINDOW_TYPE_NOTIFICATION", 0);

    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var prop: ?*c_ulong = null;

    if (c.XGetWindowProperty(display, win, net_wm_window_type,
        0, 8, 0, 0, &actual_type, &actual_format, &nitems, &bytes_after,
        @ptrCast(&prop)) != c.Success) return false;
    defer if (prop) |p| { _ = c.XFree(@ptrCast(p)); };
    if (nitems == 0 or actual_format != 32) return false;

    const atoms: [*]c_ulong = @ptrCast(prop);
    for (atoms[0..nitems]) |a| {
        if (a == dialog or a == utility or a == splash or
            a == popup  or a == menu    or a == tooltip or
            a == notification)
            return true;
    }
    return false;
}

fn read_initial_hints(wm: *WM, win: c.Window, node: *Node) void {
    // _NET_WM_STATE
    const net_wm_state               = c.XInternAtom(wm.display, "_NET_WM_STATE", 0);
    const net_wm_state_fullscreen    = c.XInternAtom(wm.display, "_NET_WM_STATE_FULLSCREEN", 0);
    const net_wm_state_attention     = c.XInternAtom(wm.display, "_NET_WM_STATE_DEMANDS_ATTENTION", 0);
    const net_wm_state_above         = c.XInternAtom(wm.display, "_NET_WM_STATE_ABOVE", 0);
    const net_wm_state_sticky        = c.XInternAtom(wm.display, "_NET_WM_STATE_STICKY", 0);

    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var prop: ?*c_ulong = null;

    if (c.XGetWindowProperty(wm.display, win, net_wm_state,
        0, 32, 0, 0, &actual_type, &actual_format,
        &nitems, &bytes_after, @ptrCast(&prop)) == c.Success) {
        defer if (prop) |p| { _ = c.XFree(@ptrCast(p)); };
        if (nitems > 0 and actual_format == 32) {
            const atoms: [*]c_ulong = @ptrCast(prop);
            for (atoms[0..nitems]) |a| {
                if (a == net_wm_state_fullscreen) {
                    node.wants_fullscreen = true;
                } else if (a == net_wm_state_attention) {
                    node.urgent = true;
                } else if (a == net_wm_state_above or a == net_wm_state_sticky) {
                    node.floating = true;
                }
            }
        }
    }

    // WM_NORMAL_HINTS
    var hints: c.XSizeHints = undefined;
    var supplied: c_long = 0;
    if (c.XGetWMNormalHints(wm.display, win, &hints, &supplied) != 0) {
        // Fixed size: min == max
        const has_min = (hints.flags & c.PMinSize) != 0;
        const has_max = (hints.flags & c.PMaxSize) != 0;
        if (has_min and has_max and
            hints.min_width  == hints.max_width and
            hints.min_height == hints.max_height and
            hints.min_width > 0 and hints.min_height > 0)
        {
            node.floating = true;
            node.width  = @intCast(hints.min_width);
            node.height = @intCast(hints.min_height);
        }

        // Fixed aspect ratio
        if ((hints.flags & c.PAspect) != 0 and
            hints.min_aspect.x == hints.max_aspect.x and
            hints.min_aspect.y == hints.max_aspect.y and
            hints.min_aspect.y > 0)
        {
            node.floating = true;
        }
    }

    // WM_HINTS
    const wm_hints = c.XGetWMHints(wm.display, win);
    if (wm_hints) |h| {
        defer _ = c.XFree(h);
        if ((h.*.flags & c.XUrgencyHint) != 0) {
            node.urgent = true;
        }
    }

    // WM_PROTOCOLS
    const wm_take_focus = c.XInternAtom(wm.display, "WM_TAKE_FOCUS", 0);
    var protocols: [*c]c.Atom = null;
    var n_protocols: c_int = 0;
    if (c.XGetWMProtocols(wm.display, win, &protocols, &n_protocols) != 0) {
        defer _ = c.XFree(@ptrCast(protocols));
        for (protocols[0..@intCast(n_protocols)]) |proto| {
            if (proto == wm_take_focus) {
                // Send WM_TAKE_FOCUS when we focus this window
                // Store flag on node — checked in focus.zig
                node.urgent = node.urgent; // placeholder: see note below
                break;
            }
        }
    }
}

pub fn on_map_request(wm: *WM, req: *c.XMapRequestEvent) !void {
    var attrs: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(wm.display, req.window, &attrs);
    if (attrs.override_redirect != 0) return;

    if (wm.window_to_node_id.contains(req.window)) {
        // If it has a frame, just map it
        if (wm.frames.get(req.window) != null) {
            _ = c.XMapWindow(wm.display, req.window);
            return;
        }
        // Node exists but frame was lost — clean up and re-manage
        if (wm.window_to_node_id.get(req.window)) |id| {
            if (wm.node_registry.get(id)) |node| {
                if (node.owner_graph) |og| og.remove_node(node);
            }
            _ = wm.node_registry.remove(id);
            _ = wm.window_to_node_id.remove(req.window);
        }
    }

    const is_transient = get_transient_for(wm, req.window) != null or should_float(wm.display, req.window);

    if (!is_transient and is_dock_or_toolbar(wm.display, req.window)) {
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
        wm.update_ewmh();
        wm.update_net_wm_desktop(req.window);
        // If it also wants to be focusable, track it
        if (is_focusable_panel(wm.display, req.window)) {
            try wm.overlay_windows.put(req.window, {});
        }
        return;
    }

    const node = try wm.current_graph.add_node(.{ .window = req.window });
    node.width  = @intCast(attrs.width);
    node.height = @intCast(attrs.height);
    if (is_transient) node.floating = true;
    node.hidden = true;
    const was_floating = node.floating;
    read_initial_hints(wm, req.window, node);
    if (node.floating and !was_floating) {
        wm.center_node(node);
    }
    try wm.frame(req.window, node);
    const prev_focused = wm.focused;
    if (wm.focused == null) wm.focused = node;
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
                        for (wm.current_graph.nodes.items) |n| {
                            if (n.floating) continue;
                            if (n.content != .window and n.content != .workspace) continue;
                            if (n.content == .workspace and n.preview_window == null) continue;
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
        wm.call_rules("pre_map", id);
        wm.call_arranger(wm.current_graph, "pre_map", id, prev_id);
        const is_floating = if (wm.node_registry.get(id)) |n| n.floating else false;
        if (!is_floating) {
            wm.call_arranger(wm.current_graph, "map", id, prev_id);
        }
    }

    try wm.resolve(wm.current_graph);

    swallow_mod.try_swallow(wm, id);

    if (node.parked_term == null) {
        node.hidden = false;
        try wm.flush(wm.current_graph);

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
    }

    try wm.rebuild_focus_edges();

    _ = c.XSync(wm.display, 0);
    var discard: c.XEvent = undefined;
    while (c.XCheckTypedEvent(wm.display, c.EnterNotify, &discard) != 0) {}

    _ = c.XSelectInput(wm.display, req.window, c.PropertyChangeMask);

    if (is_transient) {
        if (wm.node_registry.get(id)) |n| {
            wm.center_node(n);
        }
        try wm.resolve(wm.current_graph);
        node.hidden = false;
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        if (wm.node_registry.get(id)) |n| {
            wm.focus(n);
        }
        return;
    }

    if (node.wants_fullscreen) {
        node.wants_fullscreen = false;
        wm.focused = node;
        try wm.toggle_fullscreen();
        try wm.flush(wm.current_graph);
    }
}

pub fn on_map_notify(wm: *WM, ev: *c.XMapEvent) void {
    if (!wm.overlay_windows.contains(ev.window)) return;
    _ = c.XSetInputFocus(wm.display, ev.window, c.RevertToParent, c.CurrentTime);
    _ = c.XFlush(wm.display);
}

pub fn on_client_message(wm: *WM, ev: *c.XClientMessageEvent) !void {
    // Forward XdndStatus/XdndFinished from client back to drag source
    const xdnd_status   = c.XInternAtom(wm.display, "XdndStatus",   0);
    const xdnd_finished = c.XInternAtom(wm.display, "XdndFinished", 0);
    if (ev.message_type == xdnd_status or ev.message_type == xdnd_finished) {
        const source: c.Window = @intCast(ev.data.l[0]);
        if (source != 0) {
            var fwd = ev.*;
            fwd.window = source;
            _ = c.XSendEvent(wm.display, source, 0, c.NoEventMask,
                @ptrCast(&fwd));
            _ = c.XFlush(wm.display);
            return;
        }
    }

    // Handle XDND messages received by frame windows
    const xdnd_atoms = [_][:0]const u8{
        "XdndEnter", "XdndPosition", "XdndLeave", "XdndDrop",
    };
    for (xdnd_atoms) |name| {
        const atom = c.XInternAtom(wm.display, name.ptr, 0);
        if (atom != 0 and ev.message_type == atom) {
            const client = wm.get_client_from_frame(ev.window) orelse break;
            const source: c.Window = @intCast(ev.data.l[0]);

            const xdnd_enter       = c.XInternAtom(wm.display, "XdndEnter",       0);
            const xdnd_position    = c.XInternAtom(wm.display, "XdndPosition",    0);
            const xdnd_drop        = c.XInternAtom(wm.display, "XdndDrop",        0);
            const xdnd_leave       = c.XInternAtom(wm.display, "XdndLeave",       0);
            const xdnd_status_atom = c.XInternAtom(wm.display, "XdndStatus",      0);

            if (atom == xdnd_enter or atom == xdnd_position) {
                // Forward to client so it knows about the drag
                var fwd = ev.*;
                fwd.window = client;
                _ = c.XSendEvent(wm.display, client, 0, c.NoEventMask, @ptrCast(&fwd));

                // Send XdndStatus back to source on behalf of the frame
                const xdnd_action_copy = c.XInternAtom(wm.display, "XdndActionCopy", 0);
                var status: c.XEvent = std.mem.zeroes(c.XEvent);
                status.xclient.type         = c.ClientMessage;
                status.xclient.display      = wm.display;
                status.xclient.window       = source;
                status.xclient.message_type = xdnd_status_atom;
                status.xclient.format       = 32;
                status.xclient.data.l[0]    = @intCast(ev.window); // frame = target
                status.xclient.data.l[1]    = 1; // accept drop
                status.xclient.data.l[2]    = 0; // no rect
                status.xclient.data.l[3]    = 0;
                status.xclient.data.l[4]    = @intCast(xdnd_action_copy);
                _ = c.XSendEvent(wm.display, source, 0, c.NoEventMask, &status);
                _ = c.XFlush(wm.display);
            } else if (atom == xdnd_drop or atom == xdnd_leave) {
                // Forward drop/leave to client
                var fwd = ev.*;
                fwd.window = client;
                _ = c.XSendEvent(wm.display, client, 0, c.NoEventMask, @ptrCast(&fwd));
                _ = c.XFlush(wm.display);
            }
            return;
        }
    }

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
    const wm_class_atom = c.XInternAtom(wm.display, "WM_CLASS", 0);
    const net_wm_name_atom = c.XInternAtom(wm.display, "_NET_WM_NAME", 0);
    const wm_name_atom = c.XInternAtom(wm.display, "WM_NAME", 0);

    if (ev.atom == wm_class_atom or ev.atom == net_wm_name_atom or ev.atom == wm_name_atom) {
        if (wm.window_to_node_id.get(win)) |node_id| {
            if (wm.node_registry.get(node_id)) |node| {
                if (node.owner_graph == wm.current_graph) {
                    wm.call_rules("prop", node_id);
                }
            }
        }
    }

    if (ev.atom == net_wm_window_type) {
        if (wm.window_to_node_id.contains(win)) {
            if (is_dock_or_toolbar(wm.display, win)) {
                const node_id = wm.window_to_node_id.get(win).?;
                const node = wm.node_registry.get(node_id).?;
                if (get_strut(wm.display, win)) |s| {
                    try wm.dock_struts.put(win, s);
                }
                if (wm.frames.get(win) != null) {
                    _ = c.XUnmapWindow(wm.display, win);
                    _ = c.XReparentWindow(wm.display, win, wm.root, 0, 0);
                    wm.destroy_frame(win);
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

pub fn on_create_notify(_: *WM, _: *c.XCreateWindowEvent) void {
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

pub fn on_unmap_notify(wm: *WM, event: *c.XUnmapEvent) !void {
    const win = event.window;

    // Restore focus when a focusable panel hides
    if (wm.overlay_windows.contains(win)) {
        if (wm.focused) |n| wm.focus(n);
        return;
    }

    // Clean up dock strut if the dock unmaps
    if (wm.dock_struts.remove(win)) {
        restack_docks(wm);
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        return;
    }

    // Ignore frame unmap events
    var is_frame = false;
    var frame_iter = wm.frames.iterator();
    while (frame_iter.next()) |entry| {
        if (entry.value_ptr.* == win) {
            is_frame = true;
            break;
        }
    }
    if (is_frame) return;

    // Ignore windows we don't manage
    if (!wm.window_to_node_id.contains(win)) return;

    // Ignore synthetic unmaps generated by reparenting
    if (event.send_event != 0) return;

    // Treat unmap as destroy — clean up fully
    var ev = c.XDestroyWindowEvent{ .type = c.DestroyNotify, .serial = 0, .send_event = 0, .display = wm.display, .event = event.event, .window = win };
    try on_destroy_notify(wm, &ev);
}

pub fn on_destroy_notify(wm: *WM, event: *c.XDestroyWindowEvent) !void {
    const win = event.window;

    if (wm.dock_struts.remove(win)) {
        restack_docks(wm);
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        return;
    }

    if (swallow_mod.try_terminal_died(wm, win)) return;

    if (wm.window_to_node_id.get(win)) |child_id| {
        if (swallow_mod.try_unswallow(wm, child_id)) return;
    }

    var is_frame = false;
    var frame_iter = wm.frames.iterator();
    while (frame_iter.next()) |entry| {
        if (entry.value_ptr.* == win) {
            is_frame = true;
            break;
        }
    }
    if (is_frame) return;

    var dying: ?*Node = null;
    var dying_id: ?u32 = null;

    if (wm.window_to_node_id.get(win)) |id| {
        dying_id = id;
        if (wm.node_registry.get(id)) |node| {
            dying = node;
        }
    }

    if (dying == null) return;

    if (wm.fullscreen_node == dying) {
        wm.fullscreen_node = null;
    }

    var next_focus: ?*Node = null;
    const focused_is_dying = (wm.focused == dying);

    if (focused_is_dying) {
        const dying_is_transient = if (dying) |d| d.floating else false;

        if (dying_is_transient) {
            for (wm.current_graph.nodes.items) |node| {
                if (node == dying) continue;
                if (node.hidden) continue;
                if (node.floating) continue;
                switch (node.content) {
                    .window => { next_focus = node; break; },
                    else => continue,
                }
            }
        }

        if (next_focus == null) {
            for (wm.current_graph.focus_edges.items) |edge| {
                if (edge.from == dying and edge.to != dying) {
                    next_focus = edge.to;
                    break;
                }
            }
        }

        if (next_focus == null) {
            for (wm.current_graph.nodes.items) |node| {
                if (node == dying) continue;
                if (node.hidden) continue;
                switch (node.content) {
                    .window => { next_focus = node; break; },
                    else => continue,
                }
            }
        }
    }

    if (dying_id) |id| {
        const is_floating = if (dying) |d| d.floating else false;
        const in_current = if (dying) |d| d.owner_graph == wm.current_graph else false;
        if (!is_floating and in_current) {
            const prev_id: ?u32 = if (wm.focused) |f| wm.get_id_for_node(f) else null;
            wm.call_arranger(wm.current_graph, "unmap", id, prev_id);
        }
        wm.call_rules("unmap", id);
        _ = wm.node_registry.remove(id);
        _ = wm.window_to_node_id.remove(win);
    }

    if (wm.frames.get(win)) |win_frame| {
        _ = c.XUnmapWindow(wm.display, win_frame);
        wm.destroy_frame(win);
    }

    if (wm.edge_resizing) {
        wm.edge_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
    }

    if (dying) |d| {
        if (d.owner_graph) |og| {
            og.remove_node(d);
        }
    }

    sweep_dead_containers(wm);
    _ = wm.overlay_windows.remove(win);

    if (wm.current_graph.nodes.items.len > 0) {
        try wm.resolve(wm.current_graph);
        try wm.rebuild_focus_edges();
        try wm.flush(wm.current_graph);
        if (focused_is_dying) {
            wm.focused = next_focus;
            if (next_focus) |n| wm.focus(n) else {
                focus_mod.clear_active_window(wm);
                _ = c.XSetInputFocus(wm.display, wm.root, c.RevertToParent, c.CurrentTime);
            }
        }
        wm.update_ewmh();
    } else {
        if (focused_is_dying) {
            wm.focused = null;
            focus_mod.clear_active_window(wm);
        }
        wm.reset_root_state();
        wm.current_graph.focus_edges.clearRetainingCapacity();
    }
}

pub fn on_reparent_notify(_: *WM, _: *c.XReparentEvent) void {
}

pub fn on_button_press(wm: *WM, ev: *c.XButtonEvent) !void {
    // Dismiss error bar on click
    if (wm.error_bar_win != 0 and ev.window == wm.error_bar_win) {
        _ = c.XDestroyWindow(wm.display, wm.error_bar_win);
        _ = c.XFlush(wm.display);
        wm.error_bar_win = 0;
        return;
    }

    const clean_state = ev.state & ~@as(c_uint, c.LockMask | c.Mod2Mask | c.Mod3Mask | c.Mod5Mask);

    // Pan drag — must be first before any other checks
    var started_pan = false;
    if (wm.pan_modifier) |pan_mod| {
        if (!wm.current_graph.pan_disabled and clean_state & pan_mod != 0 and ev.button == wm.pan_button) {
            wm.pan_dragging = true;
            wm.pan_drag_start_x = ev.x_root;
            wm.pan_drag_start_y = ev.y_root;
            wm.pan_drag_start_pan_x = wm.current_graph.pan_x;
            wm.pan_drag_start_pan_y = wm.current_graph.pan_y;
            started_pan = true;
        }
    }
    if (started_pan) return;

    const has_float_mod  = if (wm.float_move_modifier)  |m| clean_state & m != 0 else false;
    const has_resize_mod = if (wm.resize_modifier)       |m| clean_state & m != 0 else false;

    if (!has_float_mod and !has_resize_mod and wm.click_to_focus) {
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
        _ = c.XAllowEvents(wm.display, c.ReplayPointer, c.CurrentTime);
        return;
    }

    const lookup_win = if (ev.window == wm.root) ev.subwindow else ev.window;
    if (lookup_win == 0) return;

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
                    wm.saved_focus_follows_mouse = wm.focus_follows_mouse;
                    wm.focus_follows_mouse = false;
                    _ = c.XRaiseWindow(wm.display, lookup_win);
                } else {
                    const left_edge   = node.x;
                    const right_edge  = node.x + @as(i32, @intCast(node.width));
                    const top_edge    = node.y;
                    const bottom_edge = node.y + @as(i32, @intCast(node.height));

                    const dist_left   = @abs(ev.x_root - left_edge);
                    const dist_right  = @abs(ev.x_root - right_edge);
                    const dist_top    = @abs(ev.y_root - top_edge);
                    const dist_bottom = @abs(ev.y_root - bottom_edge);

                    const v_edge = if (dist_left < dist_right) left_edge else right_edge;
                    const h_edge = if (dist_top  < dist_bottom) top_edge  else bottom_edge;

                    wm.corner_resizing = true;
                    wm.resize_v_edge   = v_edge;
                    wm.resize_h_edge   = h_edge;
                    wm.resize_end_x    = ev.x_root;
                    wm.resize_end_y    = ev.y_root;
                    wm.resize_fixed_x  = if (dist_left < dist_right) right_edge else left_edge;
                    wm.resize_fixed_y  = if (dist_top  < dist_bottom) bottom_edge else top_edge;
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

    const left_edge   = node.x;
    const right_edge  = node.x + @as(i32, @intCast(node.width));
    const top_edge    = node.y;
    const bottom_edge = node.y + @as(i32, @intCast(node.height));

    const dist_left   = @abs(ev.x_root - left_edge);
    const dist_right  = @abs(ev.x_root - right_edge);
    const dist_top    = @abs(ev.y_root - top_edge);
    const dist_bottom = @abs(ev.y_root - bottom_edge);

    wm.corner_resizing = true;
    wm.saved_focus_follows_mouse = wm.focus_follows_mouse;
    wm.focus_follows_mouse = false;
    wm.resize_v_edge   = if (dist_left < dist_right) left_edge else right_edge;
    wm.resize_h_edge   = if (dist_top  < dist_bottom) top_edge  else bottom_edge;
    wm.resize_end_x    = ev.x_root;
    wm.resize_end_y    = ev.y_root;

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

    if (wm.pan_dragging) {
        const delta_x = e.x_root - wm.pan_drag_start_x;
        const delta_y = e.y_root - wm.pan_drag_start_y;
        const new_pan_x = @max(0, wm.pan_drag_start_pan_x - delta_x);
        const new_pan_y = @max(0, wm.pan_drag_start_pan_y - delta_y);
        wm.current_graph.pan_x = new_pan_x;
        wm.current_graph.pan_y = new_pan_y;
        wm.flushing = false;
        wm.flush(wm.current_graph) catch {};
        return;
    }

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
                wm.resolve(wm.current_graph) catch {};
                wm.flush(wm.current_graph) catch {};
            }
        }
        return;
    }

    // Floating / tiling resizing
    if (wm.edge_resizing or wm.corner_resizing) {
        const focused = wm.focused orelse return;
        if (focused.floating) {
            if (wm.corner_resizing) {
                const delta_x = e.x_root - wm.resize_end_x;
                const delta_y = e.y_root - wm.resize_end_y;
                if (delta_x != 0 or delta_y != 0) {
                    if (delta_x != 0) wm.resize_v_edge += delta_x;
                    if (delta_y != 0) wm.resize_h_edge += delta_y;
                    wm.resize_end_x = e.x_root;
                    wm.resize_end_y = e.y_root;

                    const min_size: i32 = 10;
                    if (@abs(wm.resize_fixed_x - wm.resize_v_edge) < min_size) {
                        wm.resize_v_edge = if (wm.resize_v_edge > wm.resize_fixed_x)
                            wm.resize_fixed_x + min_size else wm.resize_fixed_x - min_size;
                    }
                    if (@abs(wm.resize_fixed_y - wm.resize_h_edge) < min_size) {
                        wm.resize_h_edge = if (wm.resize_h_edge > wm.resize_fixed_y)
                            wm.resize_fixed_y + min_size else wm.resize_fixed_y - min_size;
                    }

                    const new_x = @min(wm.resize_fixed_x, wm.resize_v_edge);
                    const new_y = @min(wm.resize_fixed_y, wm.resize_h_edge);
                    const new_w: u32 = @intCast(@abs(wm.resize_fixed_x - wm.resize_v_edge));
                    const new_h: u32 = @intCast(@abs(wm.resize_fixed_y - wm.resize_h_edge));
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

                        const min_size: i32 = 10;
                        if (@abs(wm.resize_fixed_x - wm.edge_x) < min_size) {
                            wm.edge_x = if (wm.edge_x > wm.resize_fixed_x)
                                wm.resize_fixed_x + min_size else wm.resize_fixed_x - min_size;
                        }

                        const new_x = @min(wm.resize_fixed_x, wm.edge_x);
                        const new_w: u32 = @intCast(@abs(wm.resize_fixed_x - wm.edge_x));
                        focused.x = new_x;
                        focused.width = new_w;
                    }
                } else {
                    const delta_y = e.y_root - wm.resize_end_y;
                    if (delta_y != 0) {
                        wm.edge_y += delta_y;
                        wm.resize_end_y = e.y_root;

                        const min_size: i32 = 10;
                        if (@abs(wm.resize_fixed_y - wm.edge_y) < min_size) {
                            wm.edge_y = if (wm.edge_y > wm.resize_fixed_y)
                                wm.resize_fixed_y + min_size else wm.resize_fixed_y - min_size;
                        }

                        const new_y = @min(wm.resize_fixed_y, wm.edge_y);
                        const new_h: u32 = @intCast(@abs(wm.resize_fixed_y - wm.edge_y));
                        focused.y = new_y;
                        focused.height = new_h;
                    }
                }
            }
            var ts: std.os.linux.timespec = undefined;
            _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
            const now_ms: i64 = ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
            if (now_ms - wm.last_resize_flush >= wm.resize_refresh_interval) {
                wm.last_resize_flush = now_ms;
                wm.resolve(wm.current_graph) catch {};
                wm.flush(wm.current_graph) catch {};
                _ = c.XSync(wm.display, 0);
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
    if (wm.pan_dragging) {
        wm.pan_dragging = false;
        _ = c.XFlush(wm.display);
        // Just update border colors, don't snap pan
        for (wm.current_graph.nodes.items) |n| {
            const n_win = switch (n.content) {
                .window => |w| w,
                .workspace => n.preview_window orelse continue,
                .empty => continue,
            };
            if (wm.frames.get(n_win)) |frame| {
                const color = if (wm.focused == n)
                    n.border_color_focused orelse wm.default_border_color_focused
                else
                    n.border_color_unfocused orelse wm.default_border_color_unfocused;
                _ = c.XSetWindowBorder(wm.display, frame, color);
            }
        }
        return;
    }
    if (wm.float_moving) {
        wm.float_moving = false;
        wm.focus_follows_mouse = wm.saved_focus_follows_mouse;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
        _ = c.XRaiseWindow(wm.display, wm.float_move_frame);
        _ = c.XFlush(wm.display);
    }
    if (wm.corner_resizing) {
        wm.corner_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
        if (wm.focused) |node| {
            if (node.floating) {
                float_mod.raise_floating_windows(wm);
            } else {
                wm.sync_constraints_from_geometry();
                for (wm.current_graph.nodes.items) |n| {
                    if (n.floating) continue;
                    switch (n.content) {
                        .window, .workspace => {
                            if (wm.get_id_for_node(n)) |node_id| {
                                wm.call_arranger(wm.current_graph, "resize", node_id, null);
                                wm.focus_follows_mouse = wm.saved_focus_follows_mouse;
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
                wm.sync_constraints_from_geometry();
                // Fire resize on all tiled window nodes in current graph
                for (wm.current_graph.nodes.items) |n| {
                    if (n.floating) continue;
                    switch (n.content) {
                        .window, .workspace => {
                            if (wm.get_id_for_node(n)) |node_id| {
                                wm.call_arranger(wm.current_graph, "resize", node_id, null);
                                wm.focus_follows_mouse = wm.saved_focus_follows_mouse;
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
    const mods = event.state & ~@as(c_uint, c.LockMask | c.Mod2Mask);
    if (wm.keybinds.get(.{ .modifiers = mods, .keysym = keysym })) |kb| {
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
            a == net_wm_window_type_toolbar)
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
    if (ev.mode != c.NotifyNormal) return;
    if (ev.detail == c.NotifyInferior) return;

    const lookup_win = if (ev.window == wm.root) ev.subwindow else ev.window;
    if (lookup_win == 0) return;

    const is_managed = wm.window_to_node_id.contains(lookup_win) or
        wm.get_client_from_frame(lookup_win) != null;

    if (!is_managed) {
        wm.ungrab_keyboard();
        return;
    }

    if (!wm.focus_follows_mouse) return;

    const client = wm.get_client_from_frame(lookup_win) orelse return;
    const node_id = wm.window_to_node_id.get(client) orelse return;
    const node = wm.node_registry.get(node_id) orelse return;
    if (wm.focused == node) return;

    var discard: c.XEvent = undefined;
    while (c.XCheckTypedEvent(wm.display, c.EnterNotify, &discard) != 0) {}

    wm.focus(node);
    wm.flush(wm.current_graph) catch {};
}

pub fn on_expose(wm: *WM, ev: *c.XExposeEvent) void {
    if (ev.count != 0) return;
    // Check if it's a regular client frame
    if (wm.get_client_from_frame(ev.window)) |client| {
        if (wm.window_to_node_id.get(client)) |node_id| {
            if (wm.node_registry.get(node_id)) |node| {
                wm.draw_frame_borders(ev.window, node);
                return;
            }
        }
    }
    // Check if it's a workspace preview frame
    var it = wm.frames.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == ev.window) {
            const pw = entry.key_ptr.*;
            if (wm.window_to_node_id.get(pw)) |node_id| {
                if (wm.node_registry.get(node_id)) |node| {
                    wm.draw_frame_borders(ev.window, node);
                    wm.repaint_preview(node);
                }
            }
            return;
        }
    }
}

pub fn on_leave_notify(wm: *WM, ev: *c.XCrossingEvent) void {
    if (ev.mode != c.NotifyNormal) return;

    const lookup_win = if (ev.window == wm.root) ev.subwindow else ev.window;
    if (lookup_win == 0) return;

    const is_managed = wm.window_to_node_id.contains(lookup_win) or
        wm.get_client_from_frame(lookup_win) != null;

    if (!is_managed) {
        // leaving an unmanaged window (panel/dock), regrab keys
        var it = wm.keybinds.iterator();
        while (it.next()) |entry| {
            wm.grab_key(entry.key_ptr.*.modifiers, entry.key_ptr.*.keysym);
        }
        _ = c.XSync(wm.display, 0);
    }
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
    const net_supporting_wm_check = c.XInternAtom(wm.display, "_NET_SUPPORTING_WM_CHECK", 0);
    const net_wm_name = c.XInternAtom(wm.display, "_NET_WM_NAME", 0);
    const utf8_string = c.XInternAtom(wm.display, "UTF8_STRING", 0);
    const xa_window = c.XInternAtom(wm.display, "WINDOW", 0);

    const atoms = [_]c.Atom{
        c.XInternAtom(wm.display, "_NET_WM_STATE", 0),
        c.XInternAtom(wm.display, "_NET_WM_STATE_FULLSCREEN", 0),
        c.XInternAtom(wm.display, "_NET_WM_STATE_DEMANDS_ATTENTION", 0),
        c.XInternAtom(wm.display, "_NET_WM_WINDOW_TYPE", 0),
        c.XInternAtom(wm.display, "_NET_WM_WINDOW_TYPE_DOCK", 0),
        c.XInternAtom(wm.display, "_NET_WM_WINDOW_TYPE_TOOLBAR", 0),
        c.XInternAtom(wm.display, "_NET_WM_STRUT_PARTIAL", 0),
        c.XInternAtom(wm.display, "_NET_WORKAREA", 0),
        c.XInternAtom(wm.display, "_NET_ACTIVE_WINDOW", 0),
        c.XInternAtom(wm.display, "_NET_NUMBER_OF_DESKTOPS", 0),
        c.XInternAtom(wm.display, "_NET_CURRENT_DESKTOP", 0),
        c.XInternAtom(wm.display, "_NET_CLIENT_LIST", 0),
        c.XInternAtom(wm.display, "_NET_WM_DESKTOP", 0),
        c.XInternAtom(wm.display, "WM_HINTS", 0),
        net_supporting_wm_check,
        net_wm_name,
    };
    _ = c.XChangeProperty(wm.display, wm.root, net_supported,
        xa_atom, 32, c.PropModeReplace,
        @ptrCast(&atoms), @intCast(atoms.len));

    wm.check_win = c.XCreateSimpleWindow(
        wm.display, wm.root, -1, -1, 1, 1, 0, 0, 0);
    _ = c.XChangeProperty(wm.display, wm.root,
        net_supporting_wm_check, xa_window, 32, c.PropModeReplace,
        @ptrCast(&wm.check_win), 1);
    _ = c.XChangeProperty(wm.display, wm.check_win,
        net_supporting_wm_check, xa_window, 32, c.PropModeReplace,
        @ptrCast(&wm.check_win), 1);
    _ = c.XChangeProperty(wm.display, wm.check_win,
        net_wm_name, utf8_string, 8, c.PropModeReplace,
        "duckwm", 6);
}
