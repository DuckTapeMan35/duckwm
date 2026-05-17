const c = @import("c").c;
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

pub fn notify_error(wm: *WM, msg: []const u8) void {
    wm.show_error_bar(msg);
}

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
    focus_follows_mouse: bool,

    // user defined keybindings
    keybinds: std.AutoHashMap(KeybindKey, Keybind),

    // internal representation of the layout
    graph: Graph,
    focused: ?*Node,
    current_graph: *Graph,
    work_x: i32,
    work_y: i32,
    workspace_stack: std.ArrayListUnmanaged(*Graph),
    workspace_previews: std.AutoHashMap(c.Window, void),
    default_gap_inner_h: u32,
    default_gap_inner_v: u32,
    default_gap_outer_h: u32,
    default_gap_outer_v: u32,

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
    last_resize_flush: i64,
    resize_refresh_interval: i64,
    last_flushed_edge_x: i32,
    last_flushed_edge_y: i32,

    // floating state fields
    float_moving: bool,
    float_move_modifier: ?c_uint,
    float_move_frame: c.Window,
    float_move_start_x: i32,
    float_move_start_y: i32,
    float_win_start_x: i32,
    float_win_start_y: i32,
    float_move_button: c_uint,
    float_resize_button: c_uint,

    // fullscreen state fields
    fullscreen_node: ?*Node,
    fullscreen_saved_x: i32,
    fullscreen_saved_y: i32,
    fullscreen_saved_w: u32,
    fullscreen_saved_h: u32,


    // data for the lua API
    node_registry: std.AutoHashMap(u32, *Node),
    window_to_node_id: std.AutoHashMap(c.Window, u32),
    next_node_id: u32,
    lua: ?*Lua,
    default_arranger_ref: i32,
    border_width: i32,
    default_border_color_focused: u32,
    default_border_color_unfocused: u32,
    default_border_color_urgent: u32,
    inotify_fd: i32,
    inotify_wd: i32,
    reload_fn: ?*const fn(*WM) void,
    config_error_count: u32,
    last_reload_time: i64,
    error_bar_win: c.Window,
    startup_done: bool,

    // error
    post_load_error: ?[]u8,

    // allocator
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !WM {
        const display = c.XOpenDisplay(null) orelse return error.CannotOpenDisplay;
        const graph = Graph.init(allocator);
        const wm =  WM{
            .display = display,
            .root = c.XDefaultRootWindow(display),
            .screen_width = @intCast(c.XDisplayWidth(display, 0)),
            .screen_height = @intCast(c.XDisplayHeight(display, 0)),
            .frames = std.AutoHashMap(c.Window, c.Window).init(allocator),
            .dock_struts = std.AutoHashMap(c.Window, Strut).init(allocator),
            .focus_follows_mouse = true,

            .keybinds = std.AutoHashMap(KeybindKey, Keybind).init(allocator),

            .graph = graph,
            .focused = null,
            .work_x = 0,
            .work_y = 0,
            .workspace_stack = .{ .items = &.{}, .capacity = 0},
            .workspace_previews = std.AutoHashMap(c.Window, void).init(allocator),
            .current_graph = undefined,
            .default_gap_inner_h = 0,
            .default_gap_inner_v = 0,
            .default_gap_outer_h = 0,
            .default_gap_outer_v = 0,

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
            .last_resize_flush = 0,
            .resize_refresh_interval = 16, // ms
            .last_flushed_edge_x = -1,
            .last_flushed_edge_y = -1,

            .float_moving = false,
            .float_move_modifier = null,
            .float_move_frame = 0,
            .float_move_start_x = 0,
            .float_move_start_y = 0,
            .float_win_start_x = 0,
            .float_win_start_y = 0,
            .float_move_button = 1, // left mouse button
            .float_resize_button = 3, // right mouse button

            .fullscreen_node = null,
            .fullscreen_saved_x = 0,
            .fullscreen_saved_y = 0,
            .fullscreen_saved_w = 0,
            .fullscreen_saved_h = 0,

            .node_registry = std.AutoHashMap(u32, *Node).init(allocator),
            .window_to_node_id = std.AutoHashMap(c.Window, u32).init(allocator),
            .next_node_id = 1,
            .lua = null,
            .default_arranger_ref = 0,
            .border_width = 2,
            .default_border_color_focused = 0x0000FF,
            .default_border_color_unfocused = 0x00FF00,
            .default_border_color_urgent = 0xFF0000,
            .inotify_fd = -1,
            .inotify_wd = -1,
            .reload_fn = null,
            .config_error_count = 0,
            .last_reload_time = 0,
            .error_bar_win = 0,
            .startup_done = false,

            .post_load_error = null,

            .allocator = allocator,
        };

        // Seed _NET_WORKAREA so bars that start before any MapRequest see a valid value
        const workarea_atom = c.XInternAtom(display, "_NET_WORKAREA", 0);
        const XA_CARDINAL = c.XInternAtom(display, "CARDINAL", 0);
        const w: c_ulong = @intCast(c.XDisplayWidth(display, 0));
        const h: c_ulong = @intCast(c.XDisplayHeight(display, 0));
        const vals = [4]c_ulong{ 0, 0, w, h };
        _ = c.XChangeProperty(display, c.XDefaultRootWindow(display),
            workarea_atom, XA_CARDINAL, 32, c.PropModeReplace,
            @ptrCast(&vals), 4);
        
        return wm;
    }

    fn free_graph(self: *WM, g: *Graph) void {
        for (g.nodes.items) |node| {
            if (node.content == .workspace) {
                self.free_graph(node.content.workspace);
            }
            // destroy any preview window
            if (node.preview_window) |pw| {
                if (self.frames.get(pw)) |win_frame| {
                    _ = c.XDestroyWindow(self.display, win_frame);
                    _ = self.frames.remove(pw);
                }
                _ = c.XDestroyWindow(self.display, pw);
            }
            node.deinit(self.allocator);
            self.allocator.destroy(node);
        }
        g.nodes.deinit(self.allocator);
        g.focus_edges.deinit(self.allocator);
    }

    pub fn deinit(self: *WM) void {
        if (self.lua) |lua| lua.deinit();
        self.keybinds.deinit();
        self.free_graph(&self.graph);
        self.workspace_stack.deinit(self.allocator);
        self.workspace_previews.deinit();
        self.frames.deinit();
        self.node_registry.deinit();
        self.window_to_node_id.deinit();
        self.dock_struts.deinit();
        _ = c.XCloseDisplay(self.display);
    }

    pub fn reset_arranger_refs(self: *WM, g: *graph_mod.Graph) void {
        g.arranger_ref = 0;
        for (g.nodes.items) |node| {
            if (node.content == .workspace) {
                self.reset_arranger_refs(node.content.workspace);
            }
        }
    }

    pub fn watch_file(self: *WM, path: [:0]const u8) void {
        if (self.inotify_fd < 0) {
            self.inotify_fd = @intCast(std.os.linux.inotify_init1(std.os.linux.IN.CLOEXEC) catch return);
        }
        if (self.inotify_wd >= 0) {
            _ = std.os.linux.inotify_rm_watch(self.inotify_fd, self.inotify_wd);
        }
        self.inotify_wd = @intCast(std.os.linux.inotify_add_watch(
            self.inotify_fd,
            path,
            std.os.linux.IN.CLOSE_WRITE | std.os.linux.IN.MOVED_TO,
        ));
    }

    pub fn watch_config_dir(self: *WM, dir_path: [:0]const u8) void {
        if (self.inotify_fd < 0) {
            const fd = std.os.linux.inotify_init1(std.os.linux.IN.CLOEXEC);
            if (fd < 0) return;
            self.inotify_fd = @intCast(fd);
        }
        if (self.inotify_wd >= 0) {
            _ = std.os.linux.inotify_rm_watch(self.inotify_fd, self.inotify_wd);
        }
        const wd = std.os.linux.inotify_add_watch(
            self.inotify_fd,
            dir_path,
            std.os.linux.IN.CLOSE_WRITE | std.os.linux.IN.MOVED_TO,
        );
        if (wd >= 0) self.inotify_wd = @intCast(wd);
    }

    pub fn unwatch_file(self: *WM) void {
        if (self.inotify_fd >= 0) {
            if (self.inotify_wd >= 0) {
                _ = std.os.linux.inotify_rm_watch(self.inotify_fd, self.inotify_wd);
                self.inotify_wd = -1;
            }
            std.posix.close(self.inotify_fd);
            self.inotify_fd = -1;
        }
    }

    // Call the arranger for `graph` (or the default) with the given event.
    pub fn call_arranger(
        self: *WM,
        graph: *graph_mod.Graph,
        event_str: [:0]const u8,
        node_id: u32,
        prev_id: ?u32,
    ) void {
        const lua = self.lua orelse return;
        const top_before = lua.getTop();

        if (graph.arranger_ref == 0) {
            if (self.default_arranger_ref == 0) return;
            _ = lua.getIndexRaw(ziglua.registry_index, self.default_arranger_ref);
            lua.protectedCall(.{ .args = 0, .results = 1 }) catch |err| {
                std.debug.print("arranger factory error: {}\n", .{err});
                lua.setTop(top_before);
                return;
            };
            if (lua.typeOf(-1) != .function) {
                std.debug.print("arranger factory did not return a function (got {})\n", .{lua.typeOf(-1)});
                lua.setTop(top_before);
                return;
            }
            graph.arranger_ref = lua.ref(ziglua.registry_index);
        }

        _ = lua.getIndexRaw(ziglua.registry_index, graph.arranger_ref);
        _ = lua.pushString(event_str);
        lua.pushInteger(@intCast(node_id));
        if (prev_id) |pid| lua.pushInteger(@intCast(pid)) else lua.pushNil();
        lua.protectedCall(.{ .args = 3, .results = 0 }) catch |err| {
            const lua_msg = lua.toString(-1) catch null;
            std.debug.print("arranger callback error: {} msg={s}\n",
                .{ err, lua_msg orelse "none" });
            lua.setTop(top_before);
        };
    }


    pub fn register_node(self: *WM, win: ?c.Window, node: *Node) !u32 {
        const id = self.next_node_id;
        try self.node_registry.put(id, node);
        if (win) |w| {
            try self.window_to_node_id.put(w, id);
        }
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

    fn set_border_color(self: *WM, win_frame: c.Window, color: u32) void {
        _ = c.XSetWindowBorder(self.display, win_frame, color);
    }

    pub fn frame(self: *WM, win: c.Window, node: *Node) !void {
        // Choose the correct border color based on whether this node is focused
        const border_color = if (self.focused == node)
            node.border_color_focused orelse self.default_border_color_focused
        else
            node.border_color_unfocused orelse self.default_border_color_unfocused;

        var attrs: c.XWindowAttributes = undefined;
        _ = c.XGetWindowAttributes(self.display, win, &attrs);

        const win_frame = c.XCreateSimpleWindow(
            self.display,
            self.root,
            attrs.x,
            attrs.y,
            @intCast(attrs.width),
            @intCast(attrs.height),
            @intCast(self.border_width),
            border_color,
            c.None,
        );
        var swa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        swa.backing_store = c.WhenMapped;
        swa.bit_gravity = c.NorthWestGravity;
        swa.win_gravity = c.NorthWestGravity;
        _ = c.XChangeWindowAttributes(self.display, win_frame,
            c.CWBackingStore | c.CWBitGravity | c.CWWinGravity, &swa);

        _ = c.XSelectInput(self.display, win_frame,
            c.SubstructureRedirectMask | c.SubstructureNotifyMask |
            c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask | c.EnterWindowMask | c.LeaveWindowMask);
        _ = c.XAddToSaveSet(self.display, win);
        _ = c.XReparentWindow(self.display, win, win_frame, 0, 0);
        _ = c.XSetWindowBorderWidth(self.display, win, 0);
        _ = c.XMoveResizeWindow(self.display, win, self.border_width, self.border_width, node.width, node.height);

        try self.frames.put(win, win_frame);
        _ = c.XSelectInput(self.display, win, c.PropertyChangeMask);

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
        var max_top: i32    = 0;
        var max_bottom: i32 = 0;
        var max_left: i32   = 0;
        var max_right: i32  = 0;

        var it = self.dock_struts.iterator();
        while (it.next()) |entry| {
            const win = entry.key_ptr.*;
            const s   = entry.value_ptr.*;
            var attrs: c.XWindowAttributes = undefined;
            if (c.XGetWindowAttributes(self.display, win, &attrs) == 0) continue;
            const x: i32 = attrs.x;
            const y: i32 = attrs.y;
            const w: i32 = @intCast(attrs.width);
            const h: i32 = @intCast(attrs.height);

            if      (s.top    > 0) { if (y + h > max_top)    max_top    = y + h; }
            else if (s.bottom > 0) { const fb = @as(i32, @intCast(self.screen_height)) - y;
                                    if (fb > max_bottom) max_bottom = fb; }
            else if (s.left   > 0) { if (x + w > max_left)   max_left   = x + w; }
            else if (s.right  > 0) { const fr = @as(i32, @intCast(self.screen_width))  - x;
                                    if (fr > max_right)  max_right  = fr; }
        }

        return WorkArea{
            .x      = max_left,
            .y      = max_top,
            .width  = @intCast(@as(i32, @intCast(self.screen_width))  - max_left - max_right),
            .height = @intCast(@as(i32, @intCast(self.screen_height)) - max_top  - max_bottom),
        };
    }

    pub fn resolve(self: *WM, g: *Graph) !void {
        const work = self.get_work_area();
        for (g.nodes.items) |node| {
            if (node.floating) continue;
            switch (node.content) {
                .empty => { // Only update "container/root" nodes
                    node.x = 0;
                    node.y = 0;
                    node.width = work.width;
                    node.height = work.height;
                },
                else => {},
            }
        }

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

        const workarea_atom = c.XInternAtom(self.display, "_NET_WORKAREA", 0);
        const XA_CARDINAL = c.XInternAtom(self.display, "CARDINAL", 0);
        const vals = [4]c_ulong{
            @intCast(work.x),
            @intCast(work.y),
            @intCast(work.width),
            @intCast(work.height),
        };
        _ = c.XChangeProperty(self.display, self.root, workarea_atom,
            XA_CARDINAL, 32, c.PropModeReplace,
            @ptrCast(&vals), 4);
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
    pub fn toggle_fullscreen(self: *WM) !void { return float_mod.toggle_fullscreen(self); }
    pub fn center_node(self: *WM, node: *Node) void { float_mod.center_node(self, node); }

    pub fn get_id_for_node(self: *WM, node: *Node) ?u32 {
        var it = self.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == node) return entry.key_ptr.*;
        }
        return null;
    }

    pub fn flush(self: *WM, g: *Graph) !void {
        const bw: u32 = @intCast(@max(0, self.border_width));
        const work = self.get_work_area();
        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => |win| {
                    if (node.floating) {
                        if (self.frames.get(win)) |win_frame| {
                            _ = c.XMapWindow(self.display, win);
                            _ = c.XMapWindow(self.display, win_frame);
                        }
                        continue;
                    }
                    if (self.frames.get(win)) |win_frame| {
                        const at_left   = node.x <= work.x;
                        const at_top    = node.y <= work.y;
                        const at_right  = node.x + @as(i32, @intCast(node.width))  >= work.x + @as(i32, @intCast(work.width));
                        const at_bottom = node.y + @as(i32, @intCast(node.height)) >= work.y + @as(i32, @intCast(work.height));

                        const half_h = g.gap_inner_h / 2;
                        const half_v = g.gap_inner_v / 2;
                        const gap_left:   u32 = if (at_left)   g.gap_outer_h else half_h;
                        const gap_right:  u32 = if (at_right)  g.gap_outer_h else half_h;
                        const gap_top:    u32 = if (at_top)    g.gap_outer_v else half_v;
                        const gap_bottom: u32 = if (at_bottom) g.gap_outer_v else half_v;

                        const x = node.x + @as(i32, @intCast(gap_left));
                        const y = node.y + @as(i32, @intCast(gap_top));
                        const w = @max(1, node.width  -| gap_left -| gap_right  -| 2 * bw);
                        const h = @max(1, node.height -| gap_top  -| gap_bottom -| 2 * bw);

                        _ = c.XMoveResizeWindow(self.display, win_frame, x, y, w, h);
                        _ = c.XMoveResizeWindow(self.display, win, 0, 0, w, h);
                        _ = c.XSetWindowBorderWidth(self.display, win, 0);
                        _ = c.XMapWindow(self.display, win);
                        _ = c.XMapWindow(self.display, win_frame);
                    }
                },
                .workspace => {
                    const sub = node.content.workspace;
                    var is_active = (sub == self.current_graph);
                    if (!is_active) {
                        for (self.workspace_stack.items) |stacked| {
                            if (stacked == sub) { is_active = true; break; }
                        }
                    }
                    if (is_active) continue;

                    if (node.preview_window) |pw| {
                        if (self.frames.get(pw)) |win_frame| {
                            const at_left   = node.x <= work.x;
                            const at_top    = node.y <= work.y;
                            const at_right  = node.x + @as(i32, @intCast(node.width))  >= work.x + @as(i32, @intCast(work.width));
                            const at_bottom = node.y + @as(i32, @intCast(node.height)) >= work.y + @as(i32, @intCast(work.height));

                            const half_h = g.gap_inner_h / 2;
                            const half_v = g.gap_inner_v / 2;
                            const gap_left:   u32 = if (at_left)   g.gap_outer_h else half_h;
                            const gap_right:  u32 = if (at_right)  g.gap_outer_h else half_h;
                            const gap_top:    u32 = if (at_top)    g.gap_outer_v else half_v;
                            const gap_bottom: u32 = if (at_bottom) g.gap_outer_v else half_v;

                            const x = node.x + @as(i32, @intCast(gap_left));
                            const y = node.y + @as(i32, @intCast(gap_top));
                            const w = @max(1, node.width  -| gap_left -| gap_right  -| 2 * bw);
                            const h = @max(1, node.height -| gap_top  -| gap_bottom -| 2 * bw);

                            _ = c.XMoveResizeWindow(self.display, win_frame, x, y, w, h);
                            _ = c.XMoveResizeWindow(self.display, pw, 0, 0, w, h);
                            _ = c.XResizeWindow(self.display, pw, w, h);
                            _ = c.XMapWindow(self.display, pw);
                            _ = c.XMapWindow(self.display, win_frame);
                        }
                    }
                },
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

        // 2. Map the client directly
        _ = c.XMapWindow(self.display, win);
        _ = c.XFlush(self.display);

        // 3. Remove from graph and registry
        if (node.owner_graph) |graph| {
            graph.remove_node(node);
        }
        _ = self.node_registry.remove(node_id);
        _ = self.window_to_node_id.remove(win);

        // 4. Recalculate layout
        try self.resolve(self.current_graph);
        try self.rebuild_focus_edges();
        try self.flush(self.current_graph);
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
                        const client_w = node.width;
                        const client_h = node.height;
                        _ = c.XResizeWindow(self.display, win, client_w, client_h);
                    }
                },
                else => {},
            }
        }

        // 7. Flush (also raises floating windows and redraws borders)
        try self.flush(self.current_graph);
    }

    fn hide_graph_frames(self: *WM, g: *Graph) void {
        for (g.nodes.items) |node| {
            const win = switch (node.content) {
                .window => |w| w,
                .workspace => if (node.preview_window) |pw| pw else continue,
                .empty => continue,
            };
            if (self.frames.get(win)) |win_frame| {
                _ = c.XUnmapWindow(self.display, win_frame);
            }
        }
    }

    fn show_graph_frames(self: *WM, g: *Graph) void {
        for (g.nodes.items) |node| {
            const win = switch (node.content) {
                .window => |w| w,
                .workspace => if (node.preview_window) |pw| pw else continue,
                .empty => continue,
            };
            if (self.frames.get(win)) |win_frame| {
                _ = c.XMapWindow(self.display, win_frame);
            }
        }
    }

    pub fn enter_workspace(self: *WM, node: *Node) !void {
        if (node.content != .workspace) return error.NotWorkspace;
        const sub = node.content.workspace;

        // hide current graph
        hide_graph_frames(self, self.current_graph);
        // push parent
        try self.workspace_stack.append(self.allocator, self.current_graph);
        // switch
        self.current_graph = sub;
        // show new graph
        show_graph_frames(self, sub);
        // Reset work offset so struts are applied cleanly on next resolve
        self.work_x = 0;
        self.work_y = 0;
        // re-layout and refresh
        try self.resolve(sub);
        try self.rebuild_focus_edges();
        try self.flush(sub);
        // focus something
        if (focus_mod.top_left_window(self)) |n| {
            self.focus(n);
        } else {
            self.focused = null;
        }
    }

    pub fn leave_workspace(self: *WM) !void {
        if (self.workspace_stack.items.len == 0) return;
        hide_graph_frames(self, self.current_graph);
        self.focused = null;
        focus_mod.clear_active_window(self);
        self.current_graph = self.workspace_stack.pop().?;
        show_graph_frames(self, self.current_graph);
        // Reset work offset so struts are applied cleanly on next resolve
        self.work_x = 0;
        self.work_y = 0;
        try self.resolve(self.current_graph);
        try self.rebuild_focus_edges();
        try self.flush(self.current_graph);
        if (focus_mod.top_left_window(self)) |n| self.focus(n);
    }

    pub fn send_to_workspace(self: *WM, node_id: u32, target_graph: *graph_mod.Graph) !void {
        const node = self.node_registry.get(node_id) orelse return error.InvalidNode;
        const src_graph = node.owner_graph orelse return error.InvalidNode;
        if (src_graph == target_graph) return;

        // Remove from source graph
        for (src_graph.nodes.items, 0..) |n, i| {
            if (n == node) { _ = src_graph.nodes.swapRemove(i); break; }
        }
        for (src_graph.nodes.items) |n| {
            var i: usize = 0;
            while (i < n.constraints.items.len) {
                if (graph_mod.Graph.constraint_involves_node(n.constraints.items[i], node)) {
                    _ = n.constraints.swapRemove(i);
                } else i += 1;
            }
        }
        node.constraints.clearRetainingCapacity();
        node.owner_graph = target_graph;
        try target_graph.nodes.append(self.allocator, node);

        if (self.focused == node) {
            self.focused = null;
            focus_mod.clear_active_window(self);
            _ = c.XSetInputFocus(self.display, self.root, c.RevertToParent, c.CurrentTime);
        }

        // Call source arranger in source graph context
        const saved_graph = self.current_graph;
        self.current_graph = src_graph;
        if (!node.floating) {
            self.call_arranger(src_graph, "unmap", node_id, null);
        }
        self.work_x = 0;
        self.work_y = 0;
        self.resolve(src_graph) catch {};
        self.rebuild_focus_edges() catch {};
        self.flush(src_graph) catch {};

        // Call target arranger in target graph context
        self.current_graph = target_graph;
        var target_prev_id: ?u32 = null;
        for (target_graph.nodes.items) |n| {
            if (n == node) continue;
            if (n.content == .window or n.content == .workspace) {
                if (self.get_id_for_node(n)) |id| {
                    target_prev_id = id;
                    break;
                }
            }
        }
        self.call_arranger(target_graph, "map", node_id, target_prev_id);

        // Hide frame if target is not visible
        if (target_graph != saved_graph) {
            switch (node.content) {
                .window => |win| {
                    if (self.frames.get(win)) |win_frame| {
                        _ = c.XUnmapWindow(self.display, win_frame);
                    }
                },
                else => {},
            }
        } else {
            self.work_x = 0;
            self.work_y = 0;
            self.resolve(target_graph) catch {};
            self.rebuild_focus_edges() catch {};
            self.flush(target_graph) catch {};
        }

        self.current_graph = saved_graph;
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
            .workspace => {
                 // If we're currently inside this workspace, leave it first.
                if (node.content.workspace == self.current_graph) {
                    try self.leave_workspace();
                }
                // Destroying the preview window will trigger DestroyNotify,
                // which handles all cleanup (frame, Lua callback, graph removal).
                if (node.preview_window) |pw| {
                    _ = c.XDestroyWindow(self.display, pw);
                }
            },
            else => {},
        }
    }

    pub fn show_error_bar(self: *WM, msg: []const u8) void {
        std.debug.print("duckwm error: {s}\n", .{msg});

        // Destroy any existing error bar first
        if (self.error_bar_win != 0) {
            _ = c.XDestroyWindow(self.display, self.error_bar_win);
            self.error_bar_win = 0;
        }

        const bar_height: c_uint = 20;
        const win = c.XCreateSimpleWindow(
            self.display, self.root,
            0, 0,
            self.screen_width, bar_height,
            0, 0, 0xCC0000,
        );

        const net_wm_window_type = c.XInternAtom(self.display, "_NET_WM_WINDOW_TYPE", 0);
        const net_wm_window_type_dock = c.XInternAtom(self.display, "_NET_WM_WINDOW_TYPE_DOCK", 0);
        const xa_atom = c.XInternAtom(self.display, "ATOM", 0);
        _ = c.XChangeProperty(self.display, win,
            net_wm_window_type, xa_atom, 32, c.PropModeReplace,
            @ptrCast(&net_wm_window_type_dock), 1);

        const strut_partial = c.XInternAtom(self.display, "_NET_WM_STRUT_PARTIAL", 0);
        const XA_CARDINAL = c.XInternAtom(self.display, "CARDINAL", 0);
        const strut = [12]c_ulong{ 0, 0, bar_height, 0,
            0, 0, 0, 0,
            0, self.screen_width, 0, 0 };
        _ = c.XChangeProperty(self.display, win,
            strut_partial, XA_CARDINAL, 32, c.PropModeReplace,
            @ptrCast(&strut), 12);

        var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        wa.override_redirect = 1;
        _ = c.XChangeWindowAttributes(self.display, win, c.CWOverrideRedirect, &wa);

        _ = c.XSelectInput(self.display, win, c.ButtonPressMask);
        _ = c.XMapRaised(self.display, win);

        const gc = c.XCreateGC(self.display, win, 0, null);
        defer _ = c.XFreeGC(self.display, gc);
        _ = c.XSetForeground(self.display, gc, 0xFFFFFF);
        const font = c.XLoadQueryFont(self.display, "fixed");
        if (font) |f| {
            _ = c.XSetFont(self.display, gc, f.*.fid);
            defer _ = c.XFreeFont(self.display, f);
        }

        const prefix = "duckwm: ";
        const full_len = @min(prefix.len + msg.len, 200);
        var buf: [200]u8 = undefined;
        @memcpy(buf[0..prefix.len], prefix);
        @memcpy(buf[prefix.len..full_len], msg[0..full_len - prefix.len]);
        _ = c.XDrawString(self.display, win, gc, 4, 14,
            buf[0..full_len].ptr, @intCast(full_len));

        const x_label = "[x]";
        _ = c.XDrawString(self.display, win, gc,
            @intCast(self.screen_width - 30), 14,
            x_label.ptr, x_label.len);

        _ = c.XFlush(self.display);

        self.dock_struts.put(win, .{
            .left = 0, .right = 0,
            .top = @intCast(bar_height), .bottom = 0,
        }) catch {};
        self.resolve(self.current_graph) catch {};
        self.rebuild_focus_edges() catch {};
        self.flush(self.current_graph) catch {};

        self.error_bar_win = win;
        _ = c.XGrabButton(self.display, 1, c.AnyModifier, win, 0,
            c.ButtonPressMask,
            c.GrabModeAsync, c.GrabModeAsync, c.None, c.None);
    }

    pub fn create_workspace_graph(self: *WM) !*graph_mod.Graph {
        const sub = try self.allocator.create(graph_mod.Graph);
        sub.* = graph_mod.Graph.init(self.allocator);
        return sub;
    }

    pub fn create_workspace_node_with_preview(self: *WM, owner_graph: *graph_mod.Graph) !*Node {
        const sub = try self.create_workspace_graph();
        const pw = c.XCreateSimpleWindow(
            self.display, self.root,
            0, 0, 200, 150, 0, 0, 0x4488ff
        );
        var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        wa.override_redirect = 1;
        _ = c.XChangeWindowAttributes(self.display, pw, c.CWOverrideRedirect, &wa);

        const node = try owner_graph.add_node(.{ .workspace = sub });
        sub.parent_node = node;
        node.preview_window = pw;
        node.floating = false;

        try self.frame(pw, node);
        _ = c.XSelectInput(self.display, pw, c.ButtonPressMask | c.ButtonReleaseMask);

        return node;
    }

    /// Create the very first workspace node in the top-level graph.
    /// This is called once in `run` so that Super+Ctrl+1 always works
    /// and the screen is never empty.
    pub fn create_initial_workspace(self: *WM) !void {
        // 1. Ensure the top-level graph has a root container that fills the screen.
        const root_node = self.current_graph.add_node(.empty) catch return error.OutOfMemory;
        root_node.width = self.screen_width;
        root_node.height = self.screen_height;
        root_node.x = 0;
        root_node.y = 0;
        _ = self.register_node(null, root_node) catch return error.OutOfMemory;

        // 2. Create the workspace sub‑graph and its preview window.
        const sub = self.allocator.create(graph_mod.Graph) catch return error.OutOfMemory;
        sub.* = graph_mod.Graph.init(self.allocator);

        const pw = c.XCreateSimpleWindow(
            self.display, self.root,
            0, 0, 200, 150, 0, 0, 0x4488ff
        );
        var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        wa.override_redirect = 1;
        _ = c.XChangeWindowAttributes(self.display, pw, c.CWOverrideRedirect, &wa);

        const ws_node = self.current_graph.add_node(.{ .workspace = sub }) catch return error.OutOfMemory;
        sub.parent_node = ws_node;
        ws_node.preview_window = pw;
        ws_node.floating = false;

        // 3. Frame and map the preview.
        self.frame(pw, ws_node) catch return error.OutOfMemory;
        _ = c.XMapWindow(self.display, pw);
        _ = c.XSelectInput(self.display, pw, c.ButtonPressMask | c.ButtonReleaseMask);

        // 4. Register the workspace node (keyed on the preview window).
        _ = self.register_node(pw, ws_node) catch return error.OutOfMemory;

        // 5. Constrain the workspace node to fill the entire root container.
        const g = graph_mod.Constraint{ .grid_cell = .{
            .col = 0,
            .row = 0,
            .cols = 1,
            .rows = 1,
            .container = root_node,
        } };
        self.current_graph.add_constraint(ws_node, g) catch return error.OutOfMemory;

        sub.gap_inner_h = self.default_gap_inner_h;
        sub.gap_inner_v = self.default_gap_inner_v;
        sub.gap_outer_h = self.default_gap_outer_h;
        sub.gap_outer_v = self.default_gap_outer_v;

        // 6. Apply the constraint and enter the workspace.
        self.resolve(self.current_graph) catch return error.OutOfMemory;
        self.rebuild_focus_edges() catch {};
        self.flush(self.current_graph) catch {};
        try self.enter_workspace(ws_node);
    }

    pub fn run(self: *WM) !void {
        self.current_graph = &self.graph;
        events_mod.wm_detected = false;
        _ = c.XSetErrorHandler(events_mod.on_wm_detected);
        events_mod.announce_supported_hints(self);
        _ = c.XSelectInput(self.display, self.root,
            c.SubstructureRedirectMask | c.SubstructureNotifyMask |
            c.KeyPressMask | c.ButtonPressMask | c.ButtonReleaseMask |
            c.PointerMotionMask | c.EnterWindowMask | c.LeaveWindowMask);
        _ = c.XSync(self.display, 0);
        if (events_mod.wm_detected) {
            std.debug.print("Another window manager is already running. Exiting.\n", .{});
            return;
        }
        _ = c.XSetErrorHandler(events_mod.on_x_error);
        try self.create_initial_workspace();

        if (self.post_load_error) |msg| {
            self.show_error_bar(msg);
            self.allocator.free(msg);
            self.post_load_error = null;
        }

        self.startup_done = true;

        const x11_fd = c.XConnectionNumber(self.display);

        while (true) {
            var fds_buf: [2]std.posix.pollfd = undefined;
            fds_buf[0] = .{ .fd = x11_fd, .events = std.posix.POLL.IN, .revents = 0 };

            const fds: []std.posix.pollfd = if (self.inotify_fd >= 0) blk: {
                fds_buf[1] = .{ .fd = self.inotify_fd, .events = std.posix.POLL.IN, .revents = 0 };
                break :blk fds_buf[0..2];
            } else fds_buf[0..1];

            _ = std.posix.poll(fds, -1) catch continue;

            // Handle inotify events
            if (self.inotify_fd >= 0 and fds_buf[1].revents & std.posix.POLL.IN != 0) {
                var ibuf: [4096]u8 align(@alignOf(std.os.linux.inotify_event)) = undefined;
                while (true) {
                    const n = std.posix.read(self.inotify_fd, &ibuf) catch break;
                    if (n == 0) break;
                    var drain_fds = [1]std.posix.pollfd{.{
                        .fd = self.inotify_fd,
                        .events = std.posix.POLL.IN,
                        .revents = 0,
                    }};
                    const ready = std.posix.poll(&drain_fds, 0) catch break;
                    if (ready == 0 or drain_fds[0].revents & std.posix.POLL.IN == 0) break;
                }
                var ts: std.os.linux.timespec = undefined;
                _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
                const now_ms: i64 = ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
                if (now_ms - self.last_reload_time > 200) {
                    self.last_reload_time = now_ms;
                    if (self.reload_fn) |f| f(self);
                }
            }

            // Handle X11 events
            while (c.XPending(self.display) > 0) {
                var e: c.XEvent = undefined;
                _ = c.XNextEvent(self.display, &e);
                switch (e.type) {
                    c.CreateNotify     => events_mod.on_create_notify(self, &e.xcreatewindow),
                    c.DestroyNotify    => try events_mod.on_destroy_notify(self, &e.xdestroywindow),
                    c.ReparentNotify   => events_mod.on_reparent_notify(self, &e.xreparent),
                    c.ConfigureRequest => events_mod.on_configure_request(self, &e.xconfigurerequest),
                    c.MapRequest       => try events_mod.on_map_request(self, &e.xmaprequest),
                    c.KeyPress         => events_mod.on_key_press(self, &e.xkey),
                    c.ButtonPress      => events_mod.on_button_press(self, &e.xbutton),
                    c.MotionNotify     => events_mod.on_motion_notify(self, &e.xmotion),
                    c.ButtonRelease    => events_mod.on_button_release(self, &e.xbutton),
                    c.ConfigureNotify  => {},
                    c.EnterNotify      => events_mod.on_enter_notify(self, &e.xcrossing),
                    c.LeaveNotify      => {}, // just to silence prints
                    c.ClientMessage => try events_mod.on_client_message(self, &e.xclient),
                    c.PropertyNotify => try events_mod.on_property_notify(self, &e.xproperty),
                    else => std.debug.print("Unhandled event type: {}\n", .{e.type}),
                }
            }
        }
    }
};
