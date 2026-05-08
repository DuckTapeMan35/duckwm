const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
});
const std = @import("std");
const graph_mod = @import("graph");
const ziglua = @import("ziglua");
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;
const Lua = ziglua.Lua;

var wm_detected: bool = false;

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

pub const KeybindKey = struct {
    modifiers: c_uint,
    keysym: c.KeySym,
};

pub const Keybind = union(enum) {
    zig: *const fn(*WM) anyerror!void,
    lua: i32,
};

pub const WM = struct {
    // X11 data
    display: *c.Display,
    root: c.Window,
    frames: std.AutoHashMap(c.Window, c.Window),

    // user defined keybindings
    keybinds: std.AutoHashMap(KeybindKey, Keybind),

    // internal representation of the layout
    graph: Graph,
    focused: ?*Node,

    // resize state fields
    edge_resizing: bool,
    edge_x: i32,
    edge_y: i32,
    edge_is_vertical: bool,
    resize_end_x: i32,
    resize_end_y: i32,
    corner_resizing: bool,
    resize_v_edge: i32,
    resize_h_edge: i32,

    // data for the lua API and callbacks
    node_registry: std.AutoHashMap(u32, *Node),
    window_to_node_id: std.AutoHashMap(c.Window, u32),
    next_node_id: u32,
    lua: ?*Lua,
    on_map_ref: i32,
    on_unmap_ref: i32,
    border_width: i32,

    // allocator
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !WM {
        const display = c.XOpenDisplay(null) orelse return error.CannotOpenDisplay;
        return WM{
            .display = display,
            .root = c.XDefaultRootWindow(display),
            .frames = std.AutoHashMap(c.Window, c.Window).init(allocator),

            .keybinds = std.AutoHashMap(KeybindKey, Keybind).init(allocator),

            .graph = Graph.init(allocator),
            .focused = null,

            .edge_resizing = false,
            .edge_x = 0,
            .edge_y = 0,
            .edge_is_vertical = false,
            .resize_end_x = 0,
            .resize_end_y = 0,
            .corner_resizing = false,
            .resize_v_edge = 0,
            .resize_h_edge = 0,

            .node_registry = std.AutoHashMap(u32, *Node).init(allocator),
            .window_to_node_id = std.AutoHashMap(c.Window, u32).init(allocator),
            .next_node_id = 1,
            .lua = null,
            .on_map_ref = 0,
            .on_unmap_ref = 0,
            .border_width = 2,

            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WM) void {
        if (self.lua) |lua| lua.deinit();
        self.keybinds.deinit();
        self.graph.deinit();
        self.frames.deinit();
        self.node_registry.deinit();
        self.window_to_node_id.deinit();
        _ = c.XCloseDisplay(self.display);
    }

    pub fn register_node(self: *WM, win: c.Window, node: *Node) !u32 {
        const id = self.next_node_id;
        try self.node_registry.put(id, node);
        try self.window_to_node_id.put(win, id);
        self.next_node_id += 1;
        return id;
    }

    pub fn get_node_by_id(self: *WM, id: u32) ?*Node {
        return self.node_registry.get(id);
    }


    pub fn bind_lua(self: *WM, modifiers: c_uint, keysym: c.KeySym, ref: i32) !void {
        try self.keybinds.put(.{ .modifiers = modifiers, .keysym = keysym }, .{ .lua = ref });
        const keycode = c.XKeysymToKeycode(self.display, keysym);
        _ = c.XGrabKey(self.display, keycode, modifiers, self.root, 1, c.GrabModeAsync, c.GrabModeAsync);
    }

    pub fn bind(self: *WM, modifiers: c_uint, keysym: c.KeySym, action: *const fn(*WM) anyerror!void) !void {
        try self.keybinds.put(.{ .modifiers = modifiers, .keysym = keysym }, .{ .zig = action });
        const keycode = c.XKeysymToKeycode(self.display, keysym);
        _ = c.XGrabKey(self.display, keycode, modifiers, self.root, 1, c.GrabModeAsync, c.GrabModeAsync);
    }

    pub fn ungrab_keys(self: *WM) void {
        var it = self.keybinds.iterator();
        while (it.next()) |entry| {
            const keycode = c.XKeysymToKeycode(self.display, entry.key_ptr.*.keysym);
            if (keycode != 0) {
                _ = c.XUngrabKey(self.display, keycode, entry.key_ptr.*.modifiers, self.root);
            }
        }
        _ = c.XSync(self.display, 0);
    }

    pub fn on_key_press(self: *WM, event: *c.XKeyEvent) void {
        const keysym = c.XKeycodeToKeysym(self.display, @as(u8, @truncate(event.keycode)), 0);
        std.debug.print("KeyPress: mods={x} keysym={x} keycode={}\n", .{ event.state, keysym, event.keycode });
        if (self.keybinds.get(.{ .modifiers = event.state, .keysym = keysym })) |kb| {
            switch (kb) {
                .zig => |a| {
                    a(self) catch |err| {
                        std.debug.print("Keybinding error: {}\n", .{err});
                    };
                },
                .lua => |ref| {
                    if (self.lua) |lua| {
                        _ = lua.rawGetIndex(ziglua.registry_index, ref);
                        lua.protectedCall(.{ .args = 0, .results = 0 }) catch |err| {
                            std.debug.print("Lua keybinding error: {}\n", .{err});
                        };
                    }
                },
            }
        }
    }

    pub fn on_configure_request(self: *WM, req: *c.XConfigureRequestEvent) void {
        var changes = c.XWindowChanges{
            .x = req.x,
            .y = req.y,
            .width = req.width,
            .height = req.height,
            .border_width = req.border_width,
            .sibling = req.above,
            .stack_mode = req.detail,
        };
        _ = c.XConfigureWindow(self.display, req.window, @intCast(req.value_mask), &changes);
    }

    pub fn on_map_request(self: *WM, req: *c.XMapRequestEvent) !void {
        var attrs: c.XWindowAttributes = undefined;
        _ = c.XGetWindowAttributes(self.display, req.window, &attrs);
        if (attrs.override_redirect != 0) return;

        try self.frame(req.window);
        _ = c.XMapWindow(self.display, req.window);
        const node = try self.graph.add_node(.{ .window = req.window });
        const prev_focused = self.focused;
        if (self.focused == null) self.focus(node);
        const id = try self.register_node(req.window, node);

        if (self.lua) |lua| {
            if (self.on_map_ref != 0) {
                _ = lua.rawGetIndex(ziglua.registry_index, self.on_map_ref);
                lua.pushInteger(@intCast(id));
                if (prev_focused) |f| {
                    var focused_id: ?u32 = null;
                    var it = self.node_registry.iterator();
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

        try self.resolve(&self.graph);
        try self.rebuild_focus_edges();
        try self.flush(&self.graph);
    }

    pub fn frame(self: *WM, win: c.Window) !void {
        const border_color = 0xFF0000;
        const bg_color = 0x000000;

        var x_window_attributes: c.XWindowAttributes = undefined;
        _ = c.XGetWindowAttributes(self.display, win, &x_window_attributes);

        const win_frame = c.XCreateSimpleWindow(
            self.display,
            self.root,
            x_window_attributes.x,
            x_window_attributes.y,
            @intCast(x_window_attributes.width),
            @intCast(x_window_attributes.height),
            @intCast(self.border_width),
            border_color,
            bg_color,
        );

        _ = c.XSelectInput(self.display, win_frame, c.SubstructureRedirectMask | c.SubstructureNotifyMask);
        _ = c.XAddToSaveSet(self.display, win);
        _ = c.XReparentWindow(self.display, win, win_frame, self.border_width, self.border_width);
        _ = c.XMapWindow(self.display, win_frame);

        try self.frames.put(win, win_frame);
    }

    pub fn on_create_notify(_: *WM, event: *c.XCreateWindowEvent) void {
        std.debug.print("CreateNotify: window={}, parent={}, x={}, y={}, width={}, height={}\n",
            .{ event.window, event.parent, event.x, event.y, event.width, event.height });
    }

    pub fn reset_root_state(self: *WM) void {
        std.debug.print("Resetting root window state\n", .{});
        self.ungrab_keys();
        _ = c.XSelectInput(self.display, self.root,
            c.SubstructureRedirectMask | c.SubstructureNotifyMask | c.KeyPressMask | c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask);
        _ = c.XSetInputFocus(self.display, self.root, c.RevertToParent, c.CurrentTime);
        _ = c.XSync(self.display, 0);
        var it = self.keybinds.iterator();
        while (it.next()) |entry| {
            const keycode = c.XKeysymToKeycode(self.display, entry.key_ptr.*.keysym);
            if (keycode == 0) {
                std.debug.print("Failed to get keycode for keysym: {x}\n", .{entry.key_ptr.*.keysym});
                continue;
            }
            const grab_result = c.XGrabKey(self.display, keycode, entry.key_ptr.*.modifiers,
                self.root, 1, c.GrabModeAsync, c.GrabModeAsync);
            // XGrabKey returns GrabSuccess (0) on success, otherwise an error code
            if (grab_result != 0) {
                std.debug.print("XGrabKey failed with code: {}\n", .{grab_result});
            } else {
                std.debug.print("Grabbed key: mods={x} keysym={x} keycode={}\n", .{entry.key_ptr.*.modifiers, entry.key_ptr.*.keysym, keycode});
            }
        }
        _ = c.XFlush(self.display);
        _ = c.XSync(self.display, 0);
        std.debug.print("Root state reset complete\n", .{});
    }

    pub fn on_destroy_notify(self: *WM, event: *c.XDestroyWindowEvent) !void {
        const win = event.window;

        // Check if this is a frame being destroyed (we initiated this)
        var is_frame = false;
        var frame_iter = self.frames.iterator();
        while (frame_iter.next()) |entry| {
            if (entry.value_ptr.* == win) {
                is_frame = true;
                break;
            }
        }
        
        // Ignore frame destroy events - we handle cleanup when the client is destroyed
        if (is_frame) {
            std.debug.print("DestroyNotify for frame: {}\n", .{win});
            return;
        }

        // Find the dying node and its ID before any modifications
        var dying: ?*Node = null;
        var dying_id: ?u32 = null;
        
        if (self.window_to_node_id.get(win)) |id| {
            dying_id = id;
            if (self.node_registry.get(id)) |node| {
                dying = node;
            }
        }
        
        // If this window isn't managed, nothing to do
        if (dying == null) {
            std.debug.print("DestroyNotify for unmanaged window: {}\n", .{win});
            return;
        }

        std.debug.print("DestroyNotify for client window: {} (id={})\n", .{win, dying_id.?});

        // Determine next focus BEFORE removing anything
        var next_focus: ?*Node = null;
        const focused_is_dying = (self.focused == dying);

        if (focused_is_dying) {
            // Try focus edges first
            for (self.graph.focus_edges.items) |edge| {
                if (edge.from == dying and edge.to != dying) {
                    next_focus = edge.to;
                    break;
                }
            }
            
            // Fallback: layout edges
            if (next_focus == null and dying != null) {
                const d = dying.?;
                next_focus = d.left orelse d.right orelse d.up orelse d.down;
            }
            
            // Fallback: any other window node
            if (next_focus == null) {
                for (self.graph.nodes.items) |node| {
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
            if (self.lua) |lua| {
                if (self.on_unmap_ref != 0) {
                    _ = lua.rawGetIndex(ziglua.registry_index, self.on_unmap_ref);
                    lua.pushInteger(@intCast(id));
                    lua.protectedCall(.{ .args = 1, .results = 0 }) catch |err| {
                        std.debug.print("Lua on_unmap callback error: {}\n", .{err});
                    };
                }
            }
        }

        // Clean up frame
        if (self.frames.get(win)) |win_frame| {
            _ = c.XUnmapWindow(self.display, win_frame);
            _ = c.XDestroyWindow(self.display, win_frame);
            _ = self.frames.remove(win);
        }

        // Clean up registry BEFORE removing from graph
        if (dying_id) |id| {
            _ = self.node_registry.remove(id);
            _ = self.window_to_node_id.remove(win);
        }

        // if a window dies while resizing cancel the resize
        if (self.edge_resizing) {
            self.edge_resizing = false;
            _ = c.XUngrabPointer(self.display, c.CurrentTime);
        }

        // Remove from graph - this frees the node pointer
        if (dying) |d| {
            self.graph.remove_node(d);
        }

        // Update focus - never touch the freed node
        if (focused_is_dying) {
            self.focused = next_focus;
            if (next_focus) |n| {
                self.focus(n);
            }
        }

        // Only rebuild if we still have nodes
        if (self.graph.nodes.items.len > 0) {
            try self.resolve(&self.graph);
            try self.rebuild_focus_edges();
            try self.flush(&self.graph);
        } else {
            self.reset_root_state();
            self.graph.focus_edges.clearRetainingCapacity();
            std.debug.print("No windows remaining, root state reset\n", .{});
        }
    }

    pub fn on_reparent_notify(_: *WM, event: *c.XReparentEvent) void {
        std.debug.print("ReparentNotify: window={}, parent={}, x={}, y={}\n",
            .{ event.window, event.parent, event.x, event.y });
    }

    pub fn resolve(self: *WM, g: *Graph) !void {
        const screen_width: u32 = @intCast(c.XDisplayWidth(self.display, 0));
        const screen_height: u32 = @intCast(c.XDisplayHeight(self.display, 0));

        var origins = try g.get_origins();
        defer origins.deinit(self.allocator);
        if (origins.items.len == 0) return;
        if (g.active_workspace >= origins.items.len) return error.InvalidWorkspace;

        try self.resolve_node(origins.items[g.active_workspace], 0, 0, screen_width, screen_height);
    }

    fn resolve_node(self: *WM, node: *Node, x: i32, y: i32, width: u32, height: u32) !void {
        if (node.right != null and node.down != null) {
            const h_weight = if (node.split_h) |sh| switch (sh) {
                .equal => @as(f32, 0.5),
                .weighted => |w| w,
            } else 0.5;
            const left_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(width)) * h_weight));

            const v_weight = if (node.split_v) |sv| switch (sv) {
                .equal => @as(f32, 0.5),
                .weighted => |w| w,
            } else 0.5;
            const top_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(height)) * v_weight));

            node.x = x;
            node.y = y;
            node.width = left_width;
            node.height = top_height;

            try self.resolve_node(node.down.?, x, y + @as(i32, @intCast(top_height)), left_width, height - top_height);
            try self.resolve_node(node.right.?, x + @as(i32, @intCast(left_width)), y, width - left_width, height);
        } else if (node.right) |right| {
            const weight = if (node.split_h) |sh| switch (sh) {
                .equal => @as(f32, 0.5),
                .weighted => |w| w,
            } else 0.5;
            const left_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(width)) * weight));

            node.x = x;
            node.y = y;
            node.width = left_width;
            node.height = height;

            try self.resolve_node(right, x + @as(i32, @intCast(left_width)), y, width - left_width, height);
        } else if (node.down) |down| {
            const weight = if (node.split_v) |sv| switch (sv) {
                .equal => @as(f32, 0.5),
                .weighted => |w| w,
            } else 0.5;
            const top_height = @as(u32, @intFromFloat(@as(f32, @floatFromInt(height)) * weight));

            node.x = x;
            node.y = y;
            node.width = width;
            node.height = top_height;

            try self.resolve_node(down, x, y + @as(i32, @intCast(top_height)), width, height - top_height);
        } else {
            node.x = x;
            node.y = y;
            node.width = width;
            node.height = height;
        }

        switch (node.content) {
            .workspace => |child_graph| {
                var origins = try child_graph.get_origins();
                defer origins.deinit(self.allocator);
                if (origins.items.len > 0 and child_graph.active_workspace < origins.items.len) {
                    try self.resolve_node(origins.items[child_graph.active_workspace], node.x, node.y, node.width, node.height);
                }
            },
            else => {},
        }
    }

    fn rebuild_focus_edges(self: *WM) !void {
        self.graph.focus_edges.clearRetainingCapacity();
        const nodes = self.graph.nodes.items;
        const eps: i32 = 4;
        for (nodes) |a| {
            switch (a.content) { .window => {}, else => continue }
            for (nodes) |b| {
                if (a == b) continue;
                switch (b.content) { .window => {}, else => continue }
                const ax = a.x; const ay = a.y;
                const aw: i32 = @intCast(a.width); const ah: i32 = @intCast(a.height);
                const bx = b.x; const by = b.y;
                const bw: i32 = @intCast(b.width); const bh: i32 = @intCast(b.height);

                // b is directly right of a — add both directions
                if (@abs(bx - (ax + aw)) <= eps) {
                    const overlap = @min(ay + ah, by + bh) - @max(ay, by);
                    if (overlap > 0) {
                        try self.graph.add_focus_edge(a, b);
                        try self.graph.add_focus_edge(b, a);
                    }
                }
                // b is directly below a — add both directions
                if (@abs(by - (ay + ah)) <= eps) {
                    const overlap = @min(ax + aw, bx + bw) - @max(ax, bx);
                    if (overlap > 0) {
                        try self.graph.add_focus_edge(a, b);
                        try self.graph.add_focus_edge(b, a);
                    }
                }
            }
        }
    }

    fn top_left_window(self: *WM) ?*Node {
        var best: ?*Node = null;
        for (self.graph.nodes.items) |node| {
            switch (node.content) {
                .window => {},
                else => continue,
            }
            const b = best orelse { best = node; continue; };
            if (node.y < b.y or (node.y == b.y and node.x < b.x)) best = node;
        }
        return best;
    }

    fn find_focus_target(self: *WM, comptime dir: Direction) ?*Node {
        const focused = self.focused orelse return null;
        const fx = focused.x;
        const fy = focused.y;
        const fw: i32 = @intCast(focused.width);
        const fh: i32 = @intCast(focused.height);

        var best: ?*Node = null;
        var best_primary: i32 = std.math.maxInt(i32);
        var best_overlap: i32 = 0;

        for (self.graph.focus_edges.items) |edge| {
            if (edge.from != focused) continue;
            const node = edge.to;
            const nx = node.x;
            const ny = node.y;
            const nw: i32 = @intCast(node.width);
            const nh: i32 = @intCast(node.height);
            switch (dir) {
                .Left => {
                    if (nx + nw > fx) continue;
                    const dist = fx - (nx + nw);
                    const overlap = @min(fy + fh, ny + nh) - @max(fy, ny);
                    if (overlap <= 0) continue;
                    if (dist < best_primary or (dist == best_primary and overlap > best_overlap)) {
                        best = node;
                        best_primary = dist;
                        best_overlap = overlap;
                    }
                },
                .Right => {
                    if (nx < fx + fw) continue;
                    const dist = nx - (fx + fw);
                    const overlap = @min(fy + fh, ny + nh) - @max(fy, ny);
                    if (overlap <= 0) continue;
                    if (dist < best_primary or (dist == best_primary and overlap > best_overlap)) {
                        best = node;
                        best_primary = dist;
                        best_overlap = overlap;
                    }
                },
                .Up => {
                    if (ny + nh > fy) continue;
                    const dist = fy - (ny + nh);
                    const overlap = @min(fx + fw, nx + nw) - @max(fx, nx);
                    if (overlap <= 0) continue;
                    if (dist < best_primary or (dist == best_primary and overlap > best_overlap)) {
                        best = node;
                        best_primary = dist;
                        best_overlap = overlap;
                    }
                },
                .Down => {
                    if (ny < fy + fh) continue;
                    const dist = ny - (fy + fh);
                    const overlap = @min(fx + fw, nx + nw) - @max(fx, nx);
                    if (overlap <= 0) continue;
                    if (dist < best_primary or (dist == best_primary and overlap > best_overlap)) {
                        best = node;
                        best_primary = dist;
                        best_overlap = overlap;
                    }
                },
            }
        }
        return best;
    }

    fn focus_via_edges(self: *WM, comptime dir: Direction) void {
        if (self.find_focus_target(dir)) |target| { self.focus(target); return; }

        // fallback: layout edge
        const focused = self.focused orelse return;

        const layout_target: ?*Node = switch (dir) {
            .Left  => focused.left,
            .Right => focused.right,
            .Up    => focused.up,
            .Down  => focused.down,
        };
        if (layout_target) |b| { self.focus(b); return; }
    }

    pub fn focus_left(self: *WM) anyerror!void { self.focus_via_edges(.Left); }
    pub fn focus_right(self: *WM) anyerror!void { self.focus_via_edges(.Right); }
    pub fn focus_up(self: *WM) anyerror!void { self.focus_via_edges(.Up); }
    pub fn focus_down(self: *WM) anyerror!void { self.focus_via_edges(.Down); }

    pub fn flush(self: *WM, g: *Graph) !void {
        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => |win| {
                    if (self.frames.get(win)) |win_frame| {
                        _ = c.XMoveResizeWindow(self.display, win_frame, node.x, node.y, node.width, node.height);
                        const border_2x = 2 * @as(u32, @intCast(self.border_width));
                        const client_w = if (node.width >= 2*self.border_width) node.width - border_2x else 0;
                        const client_h = if (node.height >= 2*self.border_width) node.height - border_2x else 0;
                        _ = c.XResizeWindow(self.display, win, client_w, client_h);
                    }
                },
                .workspace => |child_graph| try self.flush(child_graph),
                .empty => {},
            }
        }
        _ = c.XFlush(self.display);
    }

    pub fn focus(self: *WM, node: *Node) void {
        self.focused = node;
        switch (node.content) {
            .window => |win| {
                _ = c.XSetInputFocus(self.display, win, c.RevertToParent, c.CurrentTime);
                if (self.frames.get(win)) |win_frame| {
                    _ = c.XSetWindowBorder(self.display, win_frame, 0xFFFFFF);
                }
            },
            else => {},
        }
        for (self.graph.nodes.items) |n| {
            if (n != node) {
                switch (n.content) {
                    .window => |win| {
                        if (self.frames.get(win)) |win_frame| {
                            _ = c.XSetWindowBorder(self.display, win_frame, 0xFF0000);
                        }
                    },
                    else => {},
                }
            }
        }
    }

    fn find_edge_at(self: *WM, root_x: i32, root_y: i32, threshold: i32) ?struct { is_vertical: bool, coordinate: i32 } {
        const nodes = self.graph.nodes.items;
        for (nodes) |a| {
            switch (a.content) { .window => {}, else => continue }
            for (nodes) |b| {
                if (a == b) continue;
                switch (b.content) { .window => {}, else => continue }

                // Check vertical edges: a's right edge == b's left edge
                const a_right = a.x + @as(i32, @intCast(a.width));
                if (a_right == b.x) {
                    const y_overlap_start = @max(a.y, b.y);
                    const y_overlap_end = @min(a.y + @as(i32, @intCast(a.height)), b.y + @as(i32, @intCast(b.height)));
                    if (y_overlap_end > y_overlap_start) {
                        // cursor near this vertical edge?
                        if (@abs(root_x - a_right) <= threshold and root_y >= y_overlap_start and root_y <= y_overlap_end) {
                            return .{ .is_vertical = true, .coordinate = a_right };
                        }
                    }
                }

                // Check horizontal edges: a's bottom edge == b's top edge
                const a_bottom = a.y + @as(i32, @intCast(a.height));
                if (a_bottom == b.y) {
                    const x_overlap_start = @max(a.x, b.x);
                    const x_overlap_end = @min(a.x + @as(i32, @intCast(a.width)), b.x + @as(i32, @intCast(b.width)));
                    if (x_overlap_end > x_overlap_start) {
                        if (@abs(root_y - a_bottom) <= threshold and root_x >= x_overlap_start and root_x <= x_overlap_end) {
                            return .{ .is_vertical = false, .coordinate = a_bottom };
                        }
                    }
                }
            }
        }
        return null;
    }

    // Returns the vertical and horizontal edge coordinates if the cursor is near a corner
    fn find_corner_at(self: *WM, root_x: i32, root_y: i32, threshold: i32) ?struct { v_edge: i32, h_edge: i32 } {
        const nodes = self.graph.nodes.items;
        for (nodes) |a| {
            switch (a.content) { .window => {}, else => continue }
            const a_right = a.x + @as(i32, @intCast(a.width));
            const a_bottom = a.y + @as(i32, @intCast(a.height));

            // Check if near a_right (vertical edge) and a_bottom (horizontal edge)
            if (@abs(root_x - a_right) <= threshold and @abs(root_y - a_bottom) <= threshold) {
                // Verify that these edges actually exist (i.e., there are adjacent windows)
                var has_vertical = false;
                var has_horizontal = false;
                for (nodes) |b| {
                    if (a == b) continue;
                    switch (b.content) { .window => {}, else => continue }
                    const b_x = b.x;
                    const b_y = b.y;
                    // a_right == b.x (vertical edge)
                    if (a_right == b_x) {
                        const y_overlap = @min(a_bottom, b.y + @as(i32, @intCast(b.height))) - @max(a.y, b.y);
                        if (y_overlap > 0) has_vertical = true;
                    }
                    // a_bottom == b.y (horizontal edge)
                    if (a_bottom == b_y) {
                        const x_overlap = @min(a_right, b.x + @as(i32, @intCast(b.width))) - @max(a.x, b.x);
                        if (x_overlap > 0) has_horizontal = true;
                    }
                }
                if (has_vertical and has_horizontal) {
                    return .{ .v_edge = a_right, .h_edge = a_bottom };
                }
            }
        }
        return null;
    }

    pub fn resize_vertical_edge(self: *WM, edge_x: i32, delta: i32) !bool {
        // first pass: check limits
        for (self.graph.nodes.items) |node| {
            const right: i32 = node.x + @as(i32, @intCast(node.width));
            if (right == edge_x) {
                if (@as(i32, @intCast(node.width)) + delta < 2*self.border_width + 10) return false;
            } else if (node.x == edge_x) {
                if (@as(i32, @intCast(node.width)) - delta < 2*self.border_width + 10) return false;
            }
        }
        // second pass: apply changes
        var changed = false;
        for (self.graph.nodes.items) |node| {
            const right: i32 = node.x + @as(i32, @intCast(node.width));
            if (right == edge_x) {
                node.width = @intCast(@as(i32, @intCast(node.width)) + delta);
                graph_mod.recalculate_row_weights(graph_mod.row_origin(node));
                changed = true;
            } else if (node.x == edge_x) {
                node.x += delta;
                node.width = @intCast(@as(i32, @intCast(node.width)) - delta);
                graph_mod.recalculate_row_weights(graph_mod.row_origin(node));
                changed = true;
            }
        }
        if (changed) try self.flush(&self.graph);
        return changed;
    }

    pub fn resize_horizontal_edge(self: *WM, edge_y: i32, delta: i32) !bool {
        // first pass: check limits
        for (self.graph.nodes.items) |node| {
            const bottom: i32 = node.y + @as(i32, @intCast(node.height));
            if (bottom == edge_y) {
                if (@as(i32, @intCast(node.height)) + delta < 2*self.border_width + 10) return false;
            } else if (node.y == edge_y) {
                if (@as(i32, @intCast(node.height)) - delta < 2*self.border_width + 10) return false;
            }
        }
        // second pass: apply changes
        var changed = false;
        for (self.graph.nodes.items) |node| {
            const bottom: i32 = node.y + @as(i32, @intCast(node.height));
            if (bottom == edge_y) {
                node.height = @intCast(@as(i32, @intCast(node.height)) + delta);
                graph_mod.recalculate_col_weights(graph_mod.col_origin(node));
                changed = true;
            } else if (node.y == edge_y) {
                node.y += delta;
                node.height = @intCast(@as(i32, @intCast(node.height)) - delta);
                graph_mod.recalculate_col_weights(graph_mod.col_origin(node));
                changed = true;
            }
        }
        if (changed) try self.flush(&self.graph);
        return changed;
    }

    pub fn resize_edge(self: *WM, node: *Node, dir: Direction, delta: i32) !void {
        switch (dir) {
            .Left  => if (node.left != null) { _ = try self.resize_vertical_edge(node.x, -delta);},
            .Right => if (node.right != null) { _ = try self.resize_vertical_edge(node.x + @as(i32, @intCast(node.width)), delta);},
            .Up    => if (node.up != null) { _ = try self.resize_horizontal_edge(node.y, -delta);},
            .Down  => if (node.down != null) { _ = try self.resize_horizontal_edge(node.y + @as(i32, @intCast(node.height)), delta);},
        }
    }

    pub fn resize_corner(self: *WM, node: *Node, delta_x: i32, delta_y: i32) !void {
        if (delta_x != 0) _ = try self.resize_vertical_edge(node.x + @as(i32, @intCast(node.width)), delta_x);
        if (delta_y != 0) _ = try self.resize_horizontal_edge(node.y + @as(i32, @intCast(node.height)), delta_y);
    }

    pub fn exchange(self: *WM, a: *Node, b: *Node) !void {
        const tmp = a.content;
        a.content = b.content;
        b.content = tmp;
        if (self.focused == a) self.focused = b
        else if (self.focused == b) self.focused = a;
        try self.flush(&self.graph);
    }

    pub fn exchange_left(self: *WM) anyerror!void {
        const focused = self.focused orelse return;
        if (self.find_focus_target(.Left)) |target| try self.exchange(focused, target);
    }

    pub fn exchange_right(self: *WM) anyerror!void {
        const focused = self.focused orelse return;
        if (self.find_focus_target(.Right)) |target| try self.exchange(focused, target);
    }

    pub fn exchange_up(self: *WM) anyerror!void {
        const focused = self.focused orelse return;
        if (self.find_focus_target(.Up)) |target| try self.exchange(focused, target);
    }

    pub fn exchange_down(self: *WM) anyerror!void {
        const focused = self.focused orelse return;
        if (self.find_focus_target(.Down)) |target| try self.exchange(focused, target);
    }

    pub fn spawn(self: *WM, argv: []const []const u8) !void {
        std.debug.print("Spawning: {s}\n", .{argv[0]});
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const argv_buf = try a.allocSentinel(?[*:0]const u8, argv.len, null);
        for (argv, 0..) |arg, i| argv_buf[i] = (try a.dupeZ(u8, arg)).ptr;

        const pid = c.fork();
        if (pid == 0) {
            _ = c.execvp(argv_buf[0], @ptrCast(argv_buf.ptr));
            c.exit(1);
        } else if (pid < 0) {
            return error.ForkFailed;
        }
    }

    pub fn kill_client(self: *WM) !void {
        const node = self.focused orelse return;
        switch (node.content) {
            .window => |win| {
                const wm_delete = c.XInternAtom(self.display, "WM_DELETE_WINDOW", 0);
                const wm_protocols = c.XInternAtom(self.display, "WM_PROTOCOLS", 0);
                var ev: c.XEvent = std.mem.zeroes(c.XEvent);
                ev.xclient.type = c.ClientMessage;
                ev.xclient.window = win;
                ev.xclient.message_type = wm_protocols;
                ev.xclient.format = 32;
                ev.xclient.data.l[0] = @intCast(wm_delete);
                ev.xclient.data.l[1] = c.CurrentTime;
                _ = c.XSendEvent(self.display, win, 0, c.NoEventMask, &ev);
            },
            else => {},
        }
    }

    pub fn on_button_press(self: *WM, ev: *c.XButtonEvent) void {
        // first check for corner
        if (self.find_corner_at(ev.x_root, ev.y_root, 8)) |corner| {
            self.corner_resizing = true;
            self.resize_v_edge = corner.v_edge;
            self.resize_h_edge = corner.h_edge;
            self.resize_end_x = ev.x_root;
            self.resize_end_y = ev.y_root;
            _ = c.XGrabPointer(self.display, ev.window, 1,
                c.PointerMotionMask | c.ButtonReleaseMask,
                c.GrabModeAsync, c.GrabModeAsync, c.None, c.None, c.CurrentTime);
            return;
        }
        // fallback: try to find an edge for resizing
        if (self.find_edge_at(ev.x_root, ev.y_root, 8)) |edge| {
            std.debug.print("ButtonPress: edge found, is_vertical={}, coord={}\n", .{edge.is_vertical, edge.coordinate});
            self.edge_resizing = true;
            self.edge_is_vertical = edge.is_vertical;
            if (edge.is_vertical) {
                self.edge_x = edge.coordinate;
            } else {
                self.edge_y = edge.coordinate;
            }
            self.resize_end_x = ev.x_root;
            self.resize_end_y = ev.y_root;
            // Grab pointer for motion events
            _ = c.XGrabPointer(self.display, ev.window, 1,
                c.PointerMotionMask | c.ButtonReleaseMask,
                c.GrabModeAsync, c.GrabModeAsync, c.None, c.None, c.CurrentTime);
        } else {
            std.debug.print("ButtonPress: no edge at ({}, {})\n", .{ev.x_root, ev.y_root});
        }
    }

    pub fn on_motion_notify(self: *WM, ev: *c.XMotionEvent) void {
        if (self.corner_resizing) {
            const delta_x = ev.x_root - self.resize_end_x;
            const delta_y = ev.y_root - self.resize_end_y;
            if (delta_x != 0) {
                if (try self.resize_vertical_edge(self.resize_v_edge, delta_x)) {
                    self.resize_v_edge += delta_x;
                }
                self.resize_end_x = ev.x_root;
            }
            if (delta_y != 0) {
                if (try self.resize_horizontal_edge(self.resize_h_edge, delta_y)) {
                    self.resize_h_edge += delta_y;
                }
                self.resize_end_y = ev.y_root;
            }
            return;
        }
        if (self.edge_resizing) {
            const delta_x = ev.x_root - self.resize_end_x;
            const delta_y = ev.y_root - self.resize_end_y;
            if (self.edge_is_vertical) {
                if (delta_x != 0) {
                    if (try self.resize_vertical_edge(self.edge_x, delta_x)) {
                        self.edge_x += delta_x; // edge moved
                    }
                    self.resize_end_x = ev.x_root;
                }
            } else {
                if (delta_y != 0) {
                    if (try self.resize_horizontal_edge(self.edge_y, delta_y)) {
                        self.edge_y += delta_y; // edge moved
                    }
                    self.resize_end_y = ev.y_root;
                }
            }
        }
    }

    pub fn on_button_release(self: *WM, _: *c.XButtonEvent) void {
        if (self.corner_resizing) {
            self.corner_resizing = false;
            _ = c.XUngrabPointer(self.display, c.CurrentTime);
        }
        if (self.edge_resizing) {
            self.edge_resizing = false;
            _ = c.XUngrabPointer(self.display, c.CurrentTime);
        }
    }

    pub fn print_layout(self: *WM) void {
        std.debug.print("\n=== Layout ===\n", .{});

        var origins = self.graph.get_origins() catch return;
        defer origins.deinit(self.allocator);

        var ids = std.AutoHashMap(*Node, usize).init(self.allocator);
        defer ids.deinit();

        // stable labels
        for (self.graph.nodes.items, 0..) |node, i| {
            ids.put(node, i) catch {};
        }

        for (origins.items) |origin| {
            self.print_layout_row(origin, &ids);
            std.debug.print("\n", .{});
        }

        std.debug.print("================\n", .{});
    }

    fn print_layout_row(
        self: *WM,
        start: *Node,
        ids: *std.AutoHashMap(*Node, usize),
    ) void {

        var row: ?*Node = start;

        // -------------------------
        // First line:
        // A - B - C
        // -------------------------
        while (row) |node| {
            print_node_label(node, ids);

            if (node.right != null) {
                std.debug.print(" - ", .{});
            }

            row = node.right;
        }

        std.debug.print("\n", .{});

        // -------------------------
        // Connector line:
        //         |
        // -------------------------
        var has_down = false;
        row = start;

        while (row) |node| {
            if (node.down != null) {
                has_down = true;
                break;
            }
            row = node.right;
        }

        if (!has_down) return;

        row = start;

        while (row) |node| {
            if (node.down != null) {
                std.debug.print("    |", .{});
            } else {
                std.debug.print("     ", .{});
            }

            if (node.right != null) {
                std.debug.print("    ", .{});
            }

            row = node.right;
        }

        std.debug.print("\n", .{});

        // -------------------------
        // Child rows
        // -------------------------
        row = start;

        while (row) |node| {
            if (node.down) |down| {
                self.print_layout_row(down, ids);
            }

            row = node.right;
        }
    }

    fn print_node_label(
        node: *Node,
        ids: *std.AutoHashMap(*Node, usize),
    ) void {
        const id = ids.get(node).?;

        const label: u8 = @intCast('A' + @as(u8, @intCast(id % 26)));

        switch (node.content) {
            .window => |win| {
                std.debug.print("{c}[{}]", .{ label, win });
            },
            .workspace => {
                std.debug.print("{c}[WS]", .{label});
            },
            .empty => {
                std.debug.print("{c}[ ]", .{label});
            },
        }
    }

    pub fn run(self: *WM) !void {
        wm_detected = false;
        _ = c.XSetErrorHandler(on_wm_detected);
        _ = c.XSelectInput(self.display, self.root, c.SubstructureRedirectMask | c.SubstructureNotifyMask | c.KeyPressMask |  c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask);
        _ = c.XSync(self.display, 0);
        if (wm_detected) {
            std.debug.print("Another window manager is already running. Exiting.\n", .{});
            return;
        }
        _ = c.XSetErrorHandler(on_x_error);
        while (true) {
            var e: c.XEvent = undefined;
            _ = c.XNextEvent(self.display, &e);
            switch (e.type) {
                c.CreateNotify => self.on_create_notify(&e.xcreatewindow),
                c.DestroyNotify => try self.on_destroy_notify(&e.xdestroywindow),
                c.ReparentNotify => self.on_reparent_notify(&e.xreparent),
                c.ConfigureRequest => self.on_configure_request(&e.xconfigurerequest),
                c.MapRequest => try self.on_map_request(&e.xmaprequest),
                c.KeyPress => self.on_key_press(&e.xkey),
                c.ButtonPress => self.on_button_press(&e.xbutton),
                c.MotionNotify => self.on_motion_notify(&e.xmotion),
                c.ButtonRelease => self.on_button_release(&e.xbutton),
                else => std.debug.print("Unhandled event type: {}\n", .{e.type}),
            }
        }
    }
};
