const c = @import("c.zig").c;
const std = @import("std");
const graph_mod = @import("graph");
const ziglua = @import("ziglua");
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;
const Lua = ziglua.Lua;
const focus_mod = @import("focus.zig");
const resize_mod = @import("resize.zig");
const events_mod = @import("events.zig");
const float_mod = @import("float.zig");

pub const Strut = struct {
    left: u32,
    right: u32,
    top: u32,
    bottom: u32,
};

pub const WorkArea = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

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
    screen_width: u32,
    screen_height: u32,
    frames: std.AutoHashMap(c.Window, c.Window),
    dock_struts: std.AutoHashMap(c.Window, Strut),
    work_x: i32,
    work_y: i32,

    // user defined keybindings
    keybinds: std.AutoHashMap(KeybindKey, Keybind),

    // internal representation of the layout
    graph: Graph,
    focused: ?*Node,

    // resize state fields
    resize_modifier: ?c_uint,
    edge_resizing: bool,
    edge_x: i32,
    edge_y: i32,
    edge_is_vertical: bool,
    resize_end_x: i32,
    resize_end_y: i32,
    corner_resizing: bool,
    resize_v_edge: i32,
    resize_h_edge: i32,
    resize_fixed_x: i32,
    resize_fixed_y: i32,

    // floating state fields
    float_moving: bool,
    float_move_modifier: ?c_uint,
    float_move_frame: c.Window,
    float_move_start_x: i32,
    float_move_start_y: i32,
    float_win_start_x: i32,
    float_win_start_y: i32,

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
            .screen_width = @intCast(c.XDisplayWidth(display, 0)),
            .screen_height = @intCast(c.XDisplayHeight(display, 0)),
            .frames = std.AutoHashMap(c.Window, c.Window).init(allocator),
            .dock_struts = std.AutoHashMap(c.Window, Strut).init(allocator),
            .work_x = 0,
            .work_y = 0,

            .keybinds = std.AutoHashMap(KeybindKey, Keybind).init(allocator),

            .graph = Graph.init(allocator),
            .focused = null,

            .resize_modifier = null,
            .edge_resizing = false,
            .edge_x = 0,
            .edge_y = 0,
            .edge_is_vertical = false,
            .resize_end_x = 0,
            .resize_end_y = 0,
            .corner_resizing = false,
            .resize_v_edge = 0,
            .resize_h_edge = 0,
            .resize_fixed_x = 0,
            .resize_fixed_y = 0,

            .float_moving = false,
            .float_move_modifier = null,
            .float_move_frame = 0,
            .float_move_start_x = 0,
            .float_move_start_y = 0,
            .float_win_start_x = 0,
            .float_win_start_y = 0,

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
        self.dock_struts.deinit();
        _ = c.XCloseDisplay(self.display);
    }

    pub fn register_node(self: *WM, win: c.Window, node: *Node) !u32 {
        const id = self.next_node_id;
        try self.node_registry.put(id, node);
        try self.window_to_node_id.put(win, id);
        self.next_node_id += 1;
        return id;
    }

    pub fn get_client_from_frame(self: *WM, win_frame: c.Window) ?c.Window {
        var it = self.frames.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == win_frame) return entry.key_ptr.*;
        }
        return null;
    }

    pub fn get_node_by_id(self: *WM, id: u32) ?*Node {
        return self.node_registry.get(id);
    }

    pub fn set_node_empty(self: *WM, node_id: u32) void {
        if (self.node_registry.get(node_id)) |node| {
            switch (node.content) {
                .window => |win| {
                    _ = self.window_to_node_id.remove(win);
                },
                else => {},
            }
            node.content = .empty;
        }
    }

    pub fn set_node_window(self: *WM, node_id: u32, win: c.Window) !void {
        if (self.node_registry.get(node_id)) |node| {
            switch (node.content) {
                .window => |old_win| {
                    _ = self.window_to_node_id.remove(old_win);
                },
                else => {},
            }
            node.content = .{ .window = win };
            try self.window_to_node_id.put(win, node_id);
        }
    }

    pub fn move_window_to_node(self: *WM, src_node_id: u32, dst_node_id: u32) !void {
        const src = self.node_registry.get(src_node_id) orelse return error.InvalidNode;
        const dst = self.node_registry.get(dst_node_id) orelse return error.InvalidNode;
        if (src.content != .window or dst.content != .empty)
            return error.InvalidState;

        const win = src.content.window;
        _ = self.window_to_node_id.remove(win);
        dst.content = .{ .window = win };
        try self.window_to_node_id.put(win, dst_node_id);
        src.content = .empty;
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

        _ = c.XSelectInput(self.display, win_frame, c.SubstructureRedirectMask | c.SubstructureNotifyMask | c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask);
        _ = c.XAddToSaveSet(self.display, win);
        _ = c.XReparentWindow(self.display, win, win_frame, self.border_width, self.border_width);
        _ = c.XMapWindow(self.display, win_frame);

        try self.frames.put(win, win_frame);
    }

    pub fn reset_root_state(self: *WM) void {
        _ = c.XSelectInput(self.display, self.root,
            c.SubstructureRedirectMask | c.SubstructureNotifyMask | c.KeyPressMask | c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask);
        _ = c.XSetInputFocus(self.display, self.root, c.RevertToParent, c.CurrentTime);
        _ = c.XSync(self.display, 0);
        _ = c.XFlush(self.display);
        _ = c.XSync(self.display, 0);
    }

    pub fn get_work_area(self: *WM) WorkArea {
        var left: u32 = 0;
        var right: u32 = 0;
        var top: u32 = 0;
        var bottom: u32 = 0;

        var it = self.dock_struts.valueIterator();
        while (it.next()) |s| {
            if (s.left   > left)   left   = s.left;
            if (s.right  > right)  right  = s.right;
            if (s.top    > top)    top    = s.top;
            if (s.bottom > bottom) bottom = s.bottom;
        }

        const x: i32 = @intCast(left);
        const y: i32 = @intCast(top);
        const w = self.screen_width - left - right;
        const h = self.screen_height - top - bottom;

        return WorkArea{
            .x = x,
            .y = y,
            .width = w,
            .height = h,
        };
    }

    pub fn resolve(self: *WM, g: *Graph) !void {
        const work = self.get_work_area();

        // Step 1: revert tiled nodes to relative coordinates
        for (g.nodes.items) |node| {
            if (node.floating) continue;
            node.x -= self.work_x;
            node.y -= self.work_y;
        }

        // Step 2: run the layout solver in the relative coordinate space
        try g.solve(work.width, work.height);

        // Step 3: apply the new offset to tiled nodes
        for (g.nodes.items) |node| {
            if (node.floating) continue;
            node.x += work.x;
            node.y += work.y;
        }

        // Step 4: remember the offset for the next call
        self.work_x = work.x;
        self.work_y = work.y;
    }

    pub fn rebuild_focus_edges(self: *WM) !void { return focus_mod.rebuild_focus_edges(self); }

    pub fn focus_left(self: *WM) anyerror!void { try focus_mod.focus_left(self); }
    pub fn focus_right(self: *WM) anyerror!void { try focus_mod.focus_right(self); }
    pub fn focus_up(self: *WM) anyerror!void { try focus_mod.focus_up(self); }
    pub fn focus_down(self: *WM) anyerror!void { try focus_mod.focus_down(self); }

    pub fn resize_vertical_edge(self: *WM, edge_x: i32, delta: i32) !bool { return resize_mod.resize_vertical_edge(self, edge_x, delta); }
    pub fn resize_horizontal_edge(self: *WM, edge_y: i32, delta: i32) !bool { return resize_mod.resize_horizontal_edge(self, edge_y, delta); }
    pub fn resize_edge(self: *WM, node: *Node, dir: Direction, delta: i32) !void { return resize_mod.resize_edge(self, node, dir, delta); }
    pub fn resize_corner(self: *WM, node: *Node, delta_x: i32, delta_y: i32) !void { return resize_mod.resize_corner(self, node, delta_x, delta_y); }

    pub fn toggle_floating(self: *WM) !void { return float_mod.toggle_floating(self); }

    pub fn flush(self: *WM, g: *Graph) !void {
        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => |win| {
                    if (node.floating) continue;
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
        float_mod.raise_floating_windows(self);
        _ = c.XFlush(self.display);
    }

    pub fn focus(self: *WM, node: *Node) void { focus_mod.set_focus(self, node); }

    pub fn unmanage_as_dock(self: *WM, win: c.Window) !void {
        const node_id = self.window_to_node_id.get(win) orelse return;
        const node = self.node_registry.get(node_id) orelse return;

        // 1. Unmap client and remove frame
        if (self.frames.get(win)) |win_frame| {
            _ = c.XUnmapWindow(self.display, win);
            _ = c.XReparentWindow(self.display, win, self.root, 0, 0);
            _ = c.XDestroyWindow(self.display, win_frame);
            _ = self.frames.remove(win);
        }

        // 2. Save strut (if any) and clean up registry / graph
        // (need to call get_strut, defined in events.zig, so we'll do it in events.zig)

        // 3. Map the client directly
        _ = c.XMapWindow(self.display, win);
        _ = c.XFlush(self.display);

        // 4. Remove from graph and registry
        self.graph.remove_node(node);
        _ = self.node_registry.remove(node_id);
        _ = self.window_to_node_id.remove(win);

        // 5. Recalculate layout
        try self.resolve(&self.graph);
        try self.rebuild_focus_edges();
        try self.flush(&self.graph);
    }

    pub fn exchange(self: *WM, a: *Node, b: *Node) !void {
        // 1. Find node IDs (needed for registry updates)
        var a_id: ?u32 = null;
        var b_id: ?u32 = null;
        var it = self.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == a) a_id = entry.key_ptr.*;
            if (entry.value_ptr.* == b) b_id = entry.key_ptr.*;
        }
        const id_a = a_id orelse return error.InvalidNode;
        const id_b = b_id orelse return error.InvalidNode;

        // 2. Remember current windows
        const win_a = switch (a.content) { .window => |w| w, else => null };
        const win_b = switch (b.content) { .window => |w| w, else => null };
        if (win_a == null and win_b == null) return;

        // 3. Clear both nodes (updates window_to_node_id)
        if (win_a != null) self.set_node_empty(id_a);
        if (win_b != null) self.set_node_empty(id_b);

        // 4. Place windows into the opposite nodes
        if (win_b) |w| try self.set_node_window(id_a, w);
        if (win_a) |w| try self.set_node_window(id_b, w);

        // 5. Update focused pointer
        if (self.focused == a) self.focused = b
        else if (self.focused == b) self.focused = a;

        // 6. Move frames to match node geometry (crucial for floating windows)
        for ([_]*Node{ a, b }) |node| {
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
                else => {},
            }
        }

        // 7. Flush (also raises floating windows and redraws borders)
        try self.flush(&self.graph);
    }

    pub fn exchange_left(self: *WM) anyerror!void {
        const focused = self.focused orelse return;
        if (focus_mod.find_focus_target(self, .Left)) |target| try self.exchange(focused, target);
    }

    pub fn exchange_right(self: *WM) anyerror!void {
        const focused = self.focused orelse return;
        if (focus_mod.find_focus_target(self, .Right)) |target| try self.exchange(focused, target);
    }

    pub fn exchange_up(self: *WM) anyerror!void {
        const focused = self.focused orelse return;
        if (focus_mod.find_focus_target(self, .Up)) |target| try self.exchange(focused, target);
    }

    pub fn exchange_down(self: *WM) anyerror!void {
        const focused = self.focused orelse return;
        if (focus_mod.find_focus_target(self, .Down)) |target| try self.exchange(focused, target);
    }

    pub fn spawn(self: *WM, argv: []const []const u8) !void {
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

    pub fn run(self: *WM) !void {
        events_mod.wm_detected = false;
        _ = c.XSetErrorHandler(events_mod.on_wm_detected);
        events_mod.announce_supported_hints(self);
        _ = c.XSelectInput(self.display, self.root, c.SubstructureRedirectMask | c.SubstructureNotifyMask | c.KeyPressMask |  c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask);
        _ = c.XSync(self.display, 0);
        if (events_mod.wm_detected) {
            std.debug.print("Another window manager is already running. Exiting.\n", .{});
            return;
        }
        _ = c.XSetErrorHandler(events_mod.on_x_error);
        while (true) {
            var e: c.XEvent = undefined;
            _ = c.XNextEvent(self.display, &e);
            switch (e.type) {
                c.CreateNotify => events_mod.on_create_notify(self, &e.xcreatewindow),
                c.DestroyNotify => try events_mod.on_destroy_notify(self, &e.xdestroywindow),
                c.ReparentNotify => events_mod.on_reparent_notify(self, &e.xreparent),
                c.ConfigureRequest => events_mod.on_configure_request(self, &e.xconfigurerequest),
                c.MapRequest => try events_mod.on_map_request(self, &e.xmaprequest),
                c.KeyPress => events_mod.on_key_press(self, &e.xkey),
                c.ButtonPress => events_mod.on_button_press(self, &e.xbutton),
                c.MotionNotify => events_mod.on_motion_notify(self, &e.xmotion),
                c.ButtonRelease => events_mod.on_button_release(self, &e.xbutton),
                c.PropertyNotify => try events_mod.on_property_notify(self, &e.xproperty),
                else => std.debug.print("Unhandled event type: {}\n", .{e.type}),
            }
        }
    }
};
