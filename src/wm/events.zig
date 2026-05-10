const std = @import("std");
const c = @import("c.zig").c;
const WM = @import("core.zig").WM;
const graph_mod = @import("graph");
const ziglua = @import("ziglua");
const resize_mod = @import("resize.zig");
const focus_mod = @import("focus.zig");
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;

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
    var changes = c.XWindowChanges{
        .x = req.x,
        .y = req.y,
        .width = req.width,
        .height = req.height,
        .border_width = req.border_width,
        .sibling = req.above,
        .stack_mode = req.detail,
    };
    _ = c.XConfigureWindow(wm.display, req.window, @intCast(req.value_mask), &changes);
}

pub fn on_map_request(wm: *WM, req: *c.XMapRequestEvent) !void {
    var attrs: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(wm.display, req.window, &attrs);
    if (attrs.override_redirect != 0) return;

    try wm.frame(req.window);
    _ = c.XMapWindow(wm.display, req.window);
    const node = try wm.graph.add_node(.{ .window = req.window });
    const prev_focused = wm.focused;
    if (wm.focused == null) wm.focus(node);
    const id = try wm.register_node(req.window, node);

    if (wm.lua) |lua| {
        if (wm.on_map_ref != 0) {
            _ = lua.rawGetIndex(ziglua.registry_index, wm.on_map_ref);
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

    try wm.resolve(&wm.graph);
    try wm.rebuild_focus_edges();
    try wm.flush(&wm.graph);
}

pub fn on_create_notify(_: *WM, event: *c.XCreateWindowEvent) void {
    std.debug.print("CreateNotify: window={}, parent={}, x={}, y={}, width={}, height={}\n",
        .{ event.window, event.parent, event.x, event.y, event.width, event.height });
}

pub fn on_destroy_notify(wm: *WM, event: *c.XDestroyWindowEvent) !void {
    const win = event.window;

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
        for (wm.graph.focus_edges.items) |edge| {
            if (edge.from == dying and edge.to != dying) {
                next_focus = edge.to;
                break;
            }
        }
        
        // Fallback: any other window node
        if (next_focus == null) {
            for (wm.graph.nodes.items) |node| {
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
                _ = lua.rawGetIndex(ziglua.registry_index, wm.on_unmap_ref);
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
        wm.graph.remove_node(d);
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
    if (wm.graph.nodes.items.len > 0) {
        try wm.resolve(&wm.graph);
        try wm.rebuild_focus_edges();
        try wm.flush(&wm.graph);
    } else {
        wm.reset_root_state();
        wm.graph.focus_edges.clearRetainingCapacity();
    }
}

pub fn on_reparent_notify(_: *WM, event: *c.XReparentEvent) void {
    std.debug.print("ReparentNotify: window={}, parent={}, x={}, y={}\n",
        .{ event.window, event.parent, event.x, event.y });
}

pub fn on_button_press(wm: *WM, ev: *c.XButtonEvent) void {
    // first check for corner
    if (resize_mod.find_corner_at(wm, ev.x_root, ev.y_root, 8)) |corner| {
        wm.corner_resizing = true;
        wm.resize_v_edge = corner.v_edge;
        wm.resize_h_edge = corner.h_edge;
        wm.resize_end_x = ev.x_root;
        wm.resize_end_y = ev.y_root;
        _ = c.XGrabPointer(wm.display, ev.window, 1,
            c.PointerMotionMask | c.ButtonReleaseMask,
            c.GrabModeAsync, c.GrabModeAsync, c.None, c.None, c.CurrentTime);
        return;
    }
    // fallback: try to find an edge for resizing
    if (resize_mod.find_edge_at(wm, ev.x_root, ev.y_root, 8)) |edge| {
        wm.edge_resizing = true;
        wm.edge_is_vertical = edge.is_vertical;
        if (edge.is_vertical) {
            wm.edge_x = edge.coordinate;
        } else {
            wm.edge_y = edge.coordinate;
        }
        wm.resize_end_x = ev.x_root;
        wm.resize_end_y = ev.y_root;
        // Grab pointer for motion events
        _ = c.XGrabPointer(wm.display, ev.window, 1,
            c.PointerMotionMask | c.ButtonReleaseMask,
            c.GrabModeAsync, c.GrabModeAsync, c.None, c.None, c.CurrentTime);
    } else {
    }
}

pub fn on_motion_notify(wm: *WM, ev: *c.XMotionEvent) void {
    if (wm.corner_resizing) {
        const delta_x = ev.x_root - wm.resize_end_x;
        const delta_y = ev.y_root - wm.resize_end_y;
        if (delta_x != 0) {
            if (try resize_mod.resize_vertical_edge(wm, wm.resize_v_edge, delta_x)) {
                wm.resize_v_edge += delta_x;
            }
            wm.resize_end_x = ev.x_root;
        }
        if (delta_y != 0) {
            if (try resize_mod.resize_horizontal_edge(wm, wm.resize_h_edge, delta_y)) {
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
                if (try resize_mod.resize_vertical_edge(wm, wm.edge_x, delta_x)) {
                    wm.edge_x += delta_x; // edge moved
                }
                wm.resize_end_x = ev.x_root;
            }
        } else {
            if (delta_y != 0) {
                if (try resize_mod.resize_horizontal_edge(wm, wm.edge_y, delta_y)) {
                    wm.edge_y += delta_y; // edge moved
                }
                wm.resize_end_y = ev.y_root;
            }
        }
    }
}

pub fn on_button_release(wm: *WM, _: *c.XButtonEvent) void {
    if (wm.corner_resizing) {
        wm.corner_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
    }
    if (wm.edge_resizing) {
        wm.edge_resizing = false;
        _ = c.XUngrabPointer(wm.display, c.CurrentTime);
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
                    _ = lua.rawGetIndex(ziglua.registry_index, ref);
                    lua.protectedCall(.{ .args = 0, .results = 0 }) catch |err| {
                        std.debug.print("Lua keybinding error: {}\n", .{err});
                    };
                }
            },
        }
    }
}
