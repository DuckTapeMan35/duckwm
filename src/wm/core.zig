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
            .screen_width = @intCast(c.XDisplayWidth(display, 0)),
            .screen_height = @intCast(c.XDisplayHeight(display, 0)),
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

        _ = c.XSelectInput(self.display, win_frame, c.SubstructureRedirectMask | c.SubstructureNotifyMask);
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

    pub fn resolve(self: *WM, g: *Graph) !void {
        const w = @as(u32, @intCast(c.XDisplayWidth(self.display, 0)));
        const h = @as(u32, @intCast(c.XDisplayHeight(self.display, 0)));
        try g.solve(w, h);
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

    pub fn focus(self: *WM, node: *Node) void { focus_mod.set_focus(self, node); }

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
                else => std.debug.print("Unhandled event type: {}\n", .{e.type}),
            }
        }
    }
};
