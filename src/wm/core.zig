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
const ipc_mod = @import("ipc.zig");
const preview_mod = @import("preview.zig");

pub fn notify_error(wm: *WM, msg: []const u8) void {
    wm.show_error_bar(msg);
}

fn get_argb_visual(display: *c.Display) ?*c.Visual {
    var template: c.XVisualInfo = undefined;
    template.screen = c.XDefaultScreen(display);
    template.depth = 32;
    template.@"class" = c.TrueColor;   // ← correct field name
    var nitems: c_int = 0;
    const list = c.XGetVisualInfo(display, c.VisualScreenMask | c.VisualDepthMask | c.VisualClassMask, &template, &nitems);
    defer if (list != null) {_ = c.XFree(@ptrCast(list));};
    if (nitems > 0) return list[0].visual;
    return null;
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

pub const WorkspaceSwitchMode = enum { none, previous };

pub const WM = struct {
    // X11 data
    display: *c.Display,
    root: c.Window,
    screen_width: u32,
    screen_height: u32,
    frames: std.AutoHashMap(c.Window, c.Window),
    dock_struts: std.AutoHashMap(c.Window, Strut),
    overlay_windows: std.AutoHashMap(c.Window, void),
    focus_follows_mouse: bool,
    click_to_focus: bool,
    check_win: c.Window,

    // user defined keybindings
    keybinds: std.AutoHashMap(KeybindKey, Keybind),

    // internal representation of the layout
    graph: Graph,
    focused: ?*Node,
    current_graph: *Graph,
    visible_graph: *Graph,
    previous_graph: ?*Graph,
    workspace_switch_mode: WorkspaceSwitchMode,
    workspace_stack: std.ArrayListUnmanaged(*Graph),
    workspace_previews: std.AutoHashMap(c.Window, void),
    next_workspace_number: std.AutoHashMap(u32, u32),
    default_gap_inner_h: u32,
    default_gap_inner_v: u32,
    default_gap_outer_h: u32,
    default_gap_outer_v: u32,

    // flushing state
    flushing: bool,

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
    float_move_saved_ffm: bool,

    // fullscreen state fields
    fullscreen_node: ?*Node,
    fullscreen_saved_x: i32,
    fullscreen_saved_y: i32,
    fullscreen_saved_w: u32,
    fullscreen_saved_h: u32,

    // pan state fields
    pan_dragging: bool,
    pan_drag_start_x: i32,
    pan_drag_start_y: i32,
    pan_drag_start_pan_x: i32,
    pan_drag_start_pan_y: i32,
    pan_modifier: ?c_uint,
    pan_button: c_uint,

    // IPC state fields in WM struct
    ipc_fd: i32,
    ipc_clients: std.ArrayListUnmanaged(i32),


    // data for the lua API
    node_registry: std.AutoHashMap(u32, *Node),
    window_to_node_id: std.AutoHashMap(c.Window, u32),
    next_node_id: u32,
    rules: std.ArrayListUnmanaged(i32),
    lua: ?*Lua,
    default_arranger_ref: i32,
    default_arranger_name: []const u8,
    border_width: i32,
    border_side_colors_focused_only: bool,
    default_border_color_focused: u32,
    default_border_color_unfocused: u32,
    default_border_color_urgent: u32,
    inotify_fd: i32,
    inotify_wd: i32,
    reload_fn: ?*const fn(*WM) void,
    pending_reload: bool,
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
            .overlay_windows = std.AutoHashMap(c.Window, void).init(allocator),
            .focus_follows_mouse = true,
            .click_to_focus = false,
            .check_win = 0,

            .keybinds = std.AutoHashMap(KeybindKey, Keybind).init(allocator),

            .graph = graph,
            .focused = null,
            .workspace_stack = .{ .items = &.{}, .capacity = 0},
            .workspace_previews = std.AutoHashMap(c.Window, void).init(allocator),
            .next_workspace_number = std.AutoHashMap(u32, u32).init(allocator),
            .current_graph = undefined,
            .visible_graph = undefined,
            .previous_graph = null,
            .workspace_switch_mode = .none,
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

            .flushing = false,

            .float_moving = false,
            .float_move_modifier = null,
            .float_move_frame = 0,
            .float_move_start_x = 0,
            .float_move_start_y = 0,
            .float_win_start_x = 0,
            .float_win_start_y = 0,
            .float_move_button = 1, // left mouse button
            .float_resize_button = 3, // right mouse button
            .float_move_saved_ffm = false,

            .fullscreen_node = null,
            .fullscreen_saved_x = 0,
            .fullscreen_saved_y = 0,
            .fullscreen_saved_w = 0,
            .fullscreen_saved_h = 0,

            .pan_dragging = false,
            .pan_drag_start_x = 0,
            .pan_drag_start_y = 0,
            .pan_drag_start_pan_x = 0,
            .pan_drag_start_pan_y = 0,
            .pan_modifier = null,
            .pan_button = 2, // middle click by default

            .ipc_fd = -1,
            .ipc_clients = .{ .items = &.{}, .capacity = 0 },

            .node_registry = std.AutoHashMap(u32, *Node).init(allocator),
            .window_to_node_id = std.AutoHashMap(c.Window, u32).init(allocator),
            .next_node_id = 1,
            .lua = null,
            .rules = .{ .items = &.{}, .capacity = 0 },
            .default_arranger_ref = 0,
            .default_arranger_name = "",
            .border_width = 2,
            .border_side_colors_focused_only = true,
            .default_border_color_focused = 0x5294e2,
            .default_border_color_unfocused = 0x333333,
            .default_border_color_urgent = 0xe53935,
            .inotify_fd = -1,
            .inotify_wd = -1,
            .reload_fn = null,
            .pending_reload = false,
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
        if (g.arranger_name.len > 0) {
            self.allocator.free(g.arranger_name);
        }
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
        for (self.rules.items) |ref| {
            if (self.lua) |lua| lua.unref(ziglua.registry_index, ref);
        }
        self.rules.deinit(self.allocator);
        if (self.lua) |lua| lua.deinit();
        self.keybinds.deinit();
        if (self.default_arranger_name.len > 0) {
            self.allocator.free(self.default_arranger_name);
        }
        self.next_workspace_number.deinit();
        self.free_graph(&self.graph);
        self.workspace_stack.deinit(self.allocator);
        self.workspace_previews.deinit();
        self.frames.deinit();
        self.node_registry.deinit();
        self.window_to_node_id.deinit();
        self.dock_struts.deinit();
        if(self.check_win != 0) {
            _ = c.XDestroyWindow(self.display, self.check_win);
        }
        if (self.ipc_fd >= 0) {
            _ = std.os.linux.close(self.ipc_fd);
        }
        for (self.ipc_clients.items) |fd| {
            _ = std.os.linux.close(fd);
        }
        self.ipc_clients.deinit(self.allocator);
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

    pub fn repaint_preview(self: *WM, node: *Node) void {
        if (node.content != .workspace) return;
        const sub = node.content.workspace;
        const pw = node.preview_window orelse return;
        preview_mod.draw_preview(
            self.display, pw, sub,
            node.width, node.height,
        );
    }

    pub fn set_preview_colors(self: *WM, bg: u32, win_bg: u32, border: u32, text: u32) void {
        _ = self;
        preview_mod.preview_colors.bg     = bg;
        preview_mod.preview_colors.win_bg = win_bg;
        preview_mod.preview_colors.border = border;
        preview_mod.preview_colors.text   = text;
    }

    pub fn alloc_workspace_id(self: *WM, level: u32) !graph_mod.GraphId {
        const entry = try self.next_workspace_number.getOrPut(level);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        const number = entry.value_ptr.*;
        entry.value_ptr.* += 1;
        return .{ .level = level, .number = number };
    }

    pub fn call_rules(self: *WM, event_str: [:0]const u8, node_id: u32) void {
        const lua = self.lua orelse return;
        for (self.rules.items) |ref| {
            const top = lua.getTop();
            _ = lua.getIndexRaw(ziglua.registry_index, ref);
            _ = lua.pushString(event_str);
            lua.pushInteger(@intCast(node_id));
            lua.protectedCall(.{ .args = 2, .results = 0 }) catch |err| {
                const msg = lua.toString(-1) catch null;
                std.debug.print("rule error: {} {s}\n", .{err, msg orelse ""});
                lua.setTop(top);
            };
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

    pub fn draw_frame_borders(self: *WM, win_frame: c.Window, node: *Node) void {
        const bw = self.border_width;
        if (bw <= 0) return;

        var root_ret: c.Window = undefined;
        var x: c_int = 0; var y: c_int = 0;
        var w: c_uint = 0; var h: c_uint = 0;
        var bw_ret: c_uint = 0; var depth: c_uint = 0;
        _ = c.XGetGeometry(self.display, win_frame, &root_ret,
            &x, &y, &w, &h, &bw_ret, &depth);

        const gc = c.XCreateGC(self.display, win_frame, 0, null);
        defer _ = c.XFreeGC(self.display, gc);

        const focused = (self.focused == node);
        const base_color: u32 = if (node.urgent)
            node.border_color_focused orelse self.default_border_color_urgent
        else if (focused)
            node.border_color_focused orelse self.default_border_color_focused
        else
            node.border_color_unfocused orelse self.default_border_color_unfocused;

        const show_sides = !self.border_side_colors_focused_only or focused;
        const top_color    = if (show_sides) node.border_color_top    orelse base_color else base_color;
        const bottom_color = if (show_sides) node.border_color_bottom orelse base_color else base_color;
        const left_color   = if (show_sides) node.border_color_left   orelse base_color else base_color;
        const right_color  = if (show_sides) node.border_color_right  orelse base_color else base_color;

        const ibw: c_int = @intCast(bw);
        const iw: c_int  = @intCast(w);
        const ih: c_int  = @intCast(h);

        _ = c.XSetForeground(self.display, gc, top_color);
        _ = c.XFillRectangle(self.display, win_frame, gc,
            0, 0, w, @intCast(bw));

        _ = c.XSetForeground(self.display, gc, bottom_color);
        _ = c.XFillRectangle(self.display, win_frame, gc,
            0, ih - ibw, w, @intCast(bw));

        _ = c.XSetForeground(self.display, gc, left_color);
        _ = c.XFillRectangle(self.display, win_frame, gc,
            0, 0, @intCast(bw), h);

        _ = c.XSetForeground(self.display, gc, right_color);
        _ = c.XFillRectangle(self.display, win_frame, gc,
            iw - ibw, 0, @intCast(bw), h);
    }

    pub fn frame(self: *WM, win: c.Window, node: *Node) !void {
        const border_color = if (self.focused == node)
            node.border_color_focused orelse self.default_border_color_focused
        else
            node.border_color_unfocused orelse self.default_border_color_unfocused;

        var attrs: c.XWindowAttributes = undefined;
        _ = c.XGetWindowAttributes(self.display, win, &attrs);

        const needs_alpha = (attrs.depth == 32);
        const visual = if (needs_alpha) get_argb_visual(self.display) else c.XDefaultVisual(self.display, 0);
        const depth = if (needs_alpha) 32 else c.XDefaultDepth(self.display, 0);

        var swa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        swa.backing_store = c.WhenMapped;
        swa.bit_gravity = c.NorthWestGravity;
        swa.win_gravity = c.NorthWestGravity;
        swa.border_pixel = border_color;
        swa.background_pixel = if (needs_alpha) 0x00000000 else c.None;
        swa.colormap = if (needs_alpha)
            c.XCreateColormap(self.display, self.root, visual, c.AllocNone)
        else
            c.XDefaultColormap(self.display, 0);

        const mask: c_ulong = c.CWBackingStore | c.CWBitGravity | c.CWWinGravity |
                            c.CWBorderPixel | c.CWBackPixel | c.CWColormap;

        const win_frame = c.XCreateWindow(
            self.display,
            self.root,
            attrs.x,
            attrs.y,
            @intCast(attrs.width),
            @intCast(attrs.height),
            0,
            depth,
            c.InputOutput,
            visual,
            mask,
            &swa
        );

        if (needs_alpha) {
            _ = c.XSetWindowBackgroundPixmap(self.display, win_frame, c.None);
        }

        // Move offscreen temporarily
        _ = c.XMoveWindow(self.display, win_frame, -10000, -10000);

        if (self.click_to_focus) {
            _ = c.XGrabButton(self.display, 1, c.AnyModifier, win_frame, 0,
                c.ButtonPressMask | c.ButtonReleaseMask,
                c.GrabModeSync, c.GrabModeAsync, c.None, c.None);
        }

        _ = c.XSelectInput(self.display, win_frame,
            c.SubstructureRedirectMask | c.SubstructureNotifyMask |
            c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask |
            c.EnterWindowMask | c.LeaveWindowMask | c.ExposureMask);

        _ = c.XAddToSaveSet(self.display, win);
        _ = c.XReparentWindow(self.display, win, win_frame, self.border_width, self.border_width);
        _ = c.XSetWindowBorderWidth(self.display, win, 0);

        // Send synthetic ConfigureNotify
        var ce: c.XEvent = std.mem.zeroes(c.XEvent);
        ce.xconfigure.type = c.ConfigureNotify;
        ce.xconfigure.display = self.display;
        ce.xconfigure.event = win;
        ce.xconfigure.window = win;
        ce.xconfigure.x = attrs.x;
        ce.xconfigure.y = attrs.y;
        ce.xconfigure.width = @intCast(node.width);
        ce.xconfigure.height = @intCast(node.height);
        ce.xconfigure.border_width = 0;
        ce.xconfigure.above = c.None;
        ce.xconfigure.override_redirect = 0;
        _ = c.XSendEvent(self.display, win, 0, c.StructureNotifyMask, &ce);

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
        const solve_width  = if (g.virtual_width  > work.width)  g.virtual_width  else work.width;
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

    pub fn init_ipc(self: *WM) !void { try ipc_mod.init(self); }
    pub fn accept_ipc_clients(self: *WM) void { ipc_mod.accept_clients(self); }
    pub fn handle_ipc_clients(self: *WM) void { ipc_mod.handle_clients(self); }

    pub fn get_id_for_node(self: *WM, node: *Node) ?u32 {
        var it = self.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == node) return entry.key_ptr.*;
        }
        return null;
    }

    pub fn flush(self: *WM, g: *Graph) !void {
        if (g != self.visible_graph) {
            std.debug.print("flush: skipping non-current graph level={} number={}\n", 
            .{ g.id.level, g.id.number });
            return;
        }
        self.flushing = true;
        defer self.flushing = false;
        const bw: u32 = @intCast(@max(0, self.border_width));
        const work = self.get_work_area();
        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => |win| {
                    if (node.hidden) continue;
                    if (node.floating) {
                        if (self.frames.get(win)) |win_frame| {
                            const fw: u32 = node.width;
                            const fh: u32 = node.height;
                            const cw: u32 = fw -| @as(u32, @intCast(@max(0, 2 * @as(i32, @intCast(bw)))));
                            const ch: u32 = fh -| @as(u32, @intCast(@max(0, 2 * @as(i32, @intCast(bw)))));
                            _ = c.XMoveResizeWindow(self.display, win_frame, node.x, node.y, @max(1, fw), @max(1, fh));
                            _ = c.XMoveResizeWindow(self.display, win, @intCast(bw), @intCast(bw), @max(1, cw), @max(1, ch));
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

                        const raw_x = node.x + @as(i32, @intCast(gap_left)) - g.pan_x;
                        const raw_y = node.y + @as(i32, @intCast(gap_top))  - g.pan_y;

                        const x = @max(-32768, @min(32767, raw_x));
                        const y = @max(-32768, @min(32767, raw_y));
                        const fw = @max(1, node.width  -| gap_left -| gap_right);
                        const fh = @max(1, node.height -| gap_top  -| gap_bottom);
                        const cw = fw -| 2 * bw;
                        const ch = fh -| 2 * bw;

                        _ = c.XMoveResizeWindow(self.display, win_frame, x, y, fw, fh);
                        _ = c.XMoveResizeWindow(self.display, win, @intCast(bw), @intCast(bw), @max(1, cw), @max(1, ch));
                        _ = c.XSetWindowBorderWidth(self.display, win, 0);
                        _ = c.XMapWindow(self.display, win);
                        _ = c.XMapWindow(self.display, win_frame);

                        var ce: c.XEvent = std.mem.zeroes(c.XEvent);
                        ce.xconfigure.type = c.ConfigureNotify;
                        ce.xconfigure.display = self.display;
                        ce.xconfigure.event = win;
                        ce.xconfigure.window = win;
                        ce.xconfigure.x = x;
                        ce.xconfigure.y = y;
                        ce.xconfigure.width = @intCast(@max(1, cw));
                        ce.xconfigure.height = @intCast(@max(1, ch));
                        ce.xconfigure.border_width = 0;
                        ce.xconfigure.above = c.None;
                        ce.xconfigure.override_redirect = 0;
                        _ = c.XSendEvent(self.display, win, 0, c.StructureNotifyMask, &ce);
                    }
                },
                .workspace => {
                    const sub = node.content.workspace;
                    if (node.floating) {
                        if (!node.hidden) {
                            if (node.preview_window) |pw| {
                                if (self.frames.get(pw)) |win_frame| {
                                    const fw: u32 = node.width;
                                    const fh: u32 = node.height;
                                    const cw: u32 = fw -| @as(u32, @intCast(@max(0, 2 * @as(i32, @intCast(bw)))));
                                    const ch: u32 = fh -| @as(u32, @intCast(@max(0, 2 * @as(i32, @intCast(bw)))));
                                    _ = c.XMoveResizeWindow(self.display, win_frame, node.x, node.y, @max(1, fw), @max(1, fh));
                                    _ = c.XMoveResizeWindow(self.display, pw, @intCast(bw), @intCast(bw), @max(1, cw), @max(1, ch));
                                    _ = c.XMapWindow(self.display, pw);
                                    _ = c.XMapWindow(self.display, win_frame);
                                }
                            }
                        }
                        continue;
                    }
                    var is_active = (sub == self.current_graph);
                    if (!is_active) {
                        for (self.workspace_stack.items) |stacked| {
                            if (stacked == sub) { is_active = true; break; }
                        }
                    }
                    if (is_active) continue;
                    if (node.hidden) continue;

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

                            const raw_x = node.x + @as(i32, @intCast(gap_left)) - g.pan_x;
                            const raw_y = node.y + @as(i32, @intCast(gap_top))  - g.pan_y;

                            const x = @max(-32768, @min(32767, raw_x));
                            const y = @max(-32768, @min(32767, raw_y));
                            const pfw = @max(1, node.width  -| gap_left -| gap_right);
                            const pfh = @max(1, node.height -| gap_top  -| gap_bottom);
                            const pcw = pfw -| 2 * bw;
                            const pch = pfh -| 2 * bw;

                            _ = c.XMoveResizeWindow(self.display, win_frame, x, y, pfw, pfh);
                            _ = c.XMoveResizeWindow(self.display, pw, @intCast(bw), @intCast(bw), @max(1, pcw), @max(1, pch));
                            _ = c.XResizeWindow(self.display, pw, @max(1, pcw), @max(1, pch));
                            _ = c.XMapWindow(self.display, win_frame);
                            _ = c.XMapWindow(self.display, pw);
                            self.repaint_preview(node);
                        }
                    }
                },
                .empty => {},
            }
        }
        // lower all tiled frames
        for (g.nodes.items) |node| {
            if (node.floating) continue;
            switch (node.content) {
                .window => |win| {
                    if (self.frames.get(win)) |win_frame| _ = c.XLowerWindow(self.display, win_frame);
                },
                .workspace => {
                    if (node.preview_window) |pw| {
                        if (self.frames.get(pw)) |pw_frame| _ = c.XLowerWindow(self.display, pw_frame);
                    }
                },
                else => {},
            }
        }
        var dead_docks = std.ArrayListUnmanaged(c.Window){ .items = &.{}, .capacity = 0 };
        defer dead_docks.deinit(self.allocator);
        var dock_it = self.dock_struts.keyIterator();
        while (dock_it.next()) |win| {
            var attrs: c.XWindowAttributes = undefined;
            if (c.XGetWindowAttributes(self.display, win.*, &attrs) == 0) {
                dead_docks.append(self.allocator, win.*) catch {};
                continue;
            }
            _ = c.XRaiseWindow(self.display, win.*);
        }
        for (dead_docks.items) |win| {
            _ = self.dock_struts.remove(win);
        }
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
        // 1. Find node IDs
        var a_id: ?u32 = null;
        var b_id: ?u32 = null;
        var it = self.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == a) a_id = entry.key_ptr.*;
            if (entry.value_ptr.* == b) b_id = entry.key_ptr.*;
        }
        const id_a = a_id orelse return error.InvalidNode;
        const id_b = b_id orelse return error.InvalidNode;

        // 2. Swap contents
        const content_a = a.content;
        const content_b = b.content;
        if (content_a == .empty and content_b == .empty) return;

        // 3. Update window_to_node_id for window nodes
        switch (content_a) {
            .window => |win| _ = self.window_to_node_id.remove(win),
            else => {},
        }
        switch (content_b) {
            .window => |win| _ = self.window_to_node_id.remove(win),
            else => {},
        }

        // 4. Swap preview_window and content
        const pw_a = a.preview_window;
        const pw_b = b.preview_window;
        a.content = content_b;
        b.content = content_a;
        a.preview_window = pw_b;
        b.preview_window = pw_a;

        // 5. Update workspace parent_node pointers
        switch (a.content) {
            .workspace => |sub| sub.parent_node = a,
            else => {},
        }
        switch (b.content) {
            .workspace => |sub| sub.parent_node = b,
            else => {},
        }

        // 6. Update window_to_node_id for new positions
        switch (a.content) {
            .window => |win| try self.window_to_node_id.put(win, id_a),
            else => {},
        }
        switch (b.content) {
            .window => |win| try self.window_to_node_id.put(win, id_b),
            else => {},
        }

        // 7. Update window_to_node_id for swapped preview windows
        if (pw_a) |pw| {
            _ = self.window_to_node_id.remove(pw);
            try self.window_to_node_id.put(pw, id_b);
        }
        if (pw_b) |pw| {
            _ = self.window_to_node_id.remove(pw);
            try self.window_to_node_id.put(pw, id_a);
        }

        // 8. Update focused pointer
        if (self.focused == a) self.focused = b
        else if (self.focused == b) self.focused = a;

        // 9. Move frames to match new geometry
        for ([_]*Node{ a, b }) |node| {
            const win_for_frame = switch (node.content) {
                .window => |win| win,
                .workspace => node.preview_window orelse continue,
                .empty => continue,
            };
            if (self.frames.get(win_for_frame)) |win_frame| {
                _ = c.XMoveResizeWindow(self.display, win_frame,
                    node.x, node.y, node.width, node.height);
                switch (node.content) {
                    .window => |win| _ = c.XResizeWindow(self.display, win, node.width, node.height),
                    else => {},
                }
            }
        }

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
        std.debug.print("show_graph_frames: level={} number={} current_level={} current_number={}\n",
        .{ g.id.level, g.id.number, 
           self.current_graph.id.level, self.current_graph.id.number });
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

        if (sub == self.current_graph) return;

        // hide current graph
        hide_graph_frames(self, self.current_graph);
        // push parent
        try self.workspace_stack.append(self.allocator, self.current_graph);
        // switch
        self.current_graph = sub;
        self.visible_graph = self.current_graph;
        // show new graph
        show_graph_frames(self, sub);
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
        self.update_ewmh();
    }

    fn find_leave_target(self: *WM) ?usize {
        const current_level = self.current_graph.id.level;
        var i = self.workspace_stack.items.len;
        while (i > 0) {
            i -= 1;
            const g = self.workspace_stack.items[i];
            if (g == &self.graph) break;
            if (g.id.level < current_level) return i;
        }
        return null;
    }

    pub fn leave_workspace(self: *WM) !void {
        if (self.workspace_stack.items.len == 0) return;
        const target_idx = self.find_leave_target() orelse return;

        hide_graph_frames(self, self.current_graph);
        self.focused = null;
        focus_mod.clear_active_window(self);

        while (self.workspace_stack.items.len > target_idx + 1) {
            _ = self.workspace_stack.pop();
        }
        self.current_graph = self.workspace_stack.pop().?;
        self.visible_graph = self.current_graph;

        show_graph_frames(self, self.current_graph);
        try self.resolve(self.current_graph);
        try self.rebuild_focus_edges();
        try self.flush(self.current_graph);
        if (focus_mod.top_left_window(self)) |n| self.focus(n);
        self.update_ewmh();
    }

    pub fn leave_workspace_silent(self: *WM) !void {
        if (self.workspace_stack.items.len == 0) return;
        const target_idx = self.find_leave_target() orelse return;

        hide_graph_frames(self, self.current_graph);
        self.focused = null;
        focus_mod.clear_active_window(self);

        while (self.workspace_stack.items.len > target_idx + 1) {
            _ = self.workspace_stack.pop();
        }
        self.current_graph = self.workspace_stack.pop().?;
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
            self.resolve(target_graph) catch {};
            self.rebuild_focus_edges() catch {};
            self.flush(target_graph) catch {};
        }

        self.current_graph = saved_graph;
        switch (node.content) {
            .window => |win| self.update_net_wm_desktop(win),
            else => {},
        }
        self.update_ewmh();
    }

    pub fn update_ewmh(self: *WM) void {
        const XA_CARDINAL = c.XInternAtom(self.display, "CARDINAL", 0);
        const XA_WINDOW   = c.XInternAtom(self.display, "WINDOW", 0);

        const parent_graph: *graph_mod.Graph = if (self.current_graph.parent_node) |pn|
            pn.owner_graph orelse &self.graph
        else
            &self.graph;

        // _NET_NUMBER_OF_DESKTOPS
        var n_desktops: c_ulong = 0;
        for (parent_graph.nodes.items) |node| {
            if (node.content == .workspace) n_desktops += 1;
        }
        if (n_desktops == 0) n_desktops = 1;
        _ = c.XChangeProperty(self.display, self.root,
            c.XInternAtom(self.display, "_NET_NUMBER_OF_DESKTOPS", 0),
            XA_CARDINAL, 32, c.PropModeReplace,
            @ptrCast(&n_desktops), 1);

        // _NET_CURRENT_DESKTOP
        var current_idx: c_ulong = 0;
        var idx: c_ulong = 0;
        for (parent_graph.nodes.items) |node| {
            if (node.content != .workspace) continue;
            if (node.content.workspace == self.current_graph) {
                current_idx = idx;
                break;
            }
            idx += 1;
        }
        _ = c.XChangeProperty(self.display, self.root,
            c.XInternAtom(self.display, "_NET_CURRENT_DESKTOP", 0),
            XA_CARDINAL, 32, c.PropModeReplace,
            @ptrCast(&current_idx), 1);

        // _NET_CLIENT_LIST
        var client_list: std.ArrayListUnmanaged(c.Window) = .{ .items = &.{}, .capacity = 0 };
        defer client_list.deinit(self.allocator);
        var it = self.window_to_node_id.iterator();
        while (it.next()) |entry| {
            const win = entry.key_ptr.*;
            if (self.workspace_previews.contains(win)) continue;
            client_list.append(self.allocator, win) catch {};
        }
        if (client_list.items.len > 0) {
            _ = c.XChangeProperty(self.display, self.root,
                c.XInternAtom(self.display, "_NET_CLIENT_LIST", 0),
                XA_WINDOW, 32, c.PropModeReplace,
                @ptrCast(client_list.items.ptr),
                @intCast(client_list.items.len));
        } else {
            _ = c.XDeleteProperty(self.display, self.root,
                c.XInternAtom(self.display, "_NET_CLIENT_LIST", 0));
        }
    }

    pub fn update_net_wm_desktop(self: *WM, win: c.Window) void {
        const XA_CARDINAL = c.XInternAtom(self.display, "CARDINAL", 0);
        const node_id = self.window_to_node_id.get(win) orelse return;
        const node = self.node_registry.get(node_id) orelse return;
        const owner = node.owner_graph orelse return;

        const parent_graph: *graph_mod.Graph = if (owner.parent_node) |pn|
            pn.owner_graph orelse &self.graph
        else
            &self.graph;

        var desktop_idx: c_ulong = 0;
        var idx: c_ulong = 0;
        for (parent_graph.nodes.items) |n| {
            if (n.content != .workspace) continue;
            if (n.content.workspace == owner) {
                desktop_idx = idx;
                break;
            }
            idx += 1;
        }
        _ = c.XChangeProperty(self.display, win,
            c.XInternAtom(self.display, "_NET_WM_DESKTOP", 0),
            XA_CARDINAL, 32, c.PropModeReplace,
            @ptrCast(&desktop_idx), 1);
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

    pub fn ungrab_keyboard(self: *WM) void {
        _ = c.XUngrabKeyboard(self.display, c.CurrentTime);
        _ = c.XSync(self.display, 0);
    }

    pub fn grab_keyboard(self: *WM) void {
        _ = c.XGrabKeyboard(self.display, self.root, 0,
            c.GrabModeAsync, c.GrabModeAsync, c.CurrentTime);
        _ = c.XSync(self.display, 0);
    }

    pub fn regrab_keys(self: *WM) void {
        var it = self.keybinds.iterator();
        while (it.next()) |entry| {
            const keycode = c.XKeysymToKeycode(self.display, entry.key_ptr.*.keysym);
            if (keycode != 0) {
                _ = c.XGrabKey(self.display, keycode, entry.key_ptr.*.modifiers,
                    self.root, 1, c.GrabModeAsync, c.GrabModeAsync);
            }
        }
        _ = c.XSync(self.display, 0);
    }

    pub fn spawn(self: *WM, argv: []const []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const argv_buf = try a.allocSentinel(?[*:0]const u8, argv.len, null);
        for (argv, 0..) |arg, i| argv_buf[i] = (try a.dupeZ(u8, arg)).ptr;

        const pid = c.fork();
        if (pid == 0) {
            _ = c.setsid();
            const pid2 = c.fork();
            if (pid2 == 0) {
                _ = c.execvp(argv_buf[0], @ptrCast(argv_buf.ptr));
                c.exit(1);
            }
            c.exit(0);
        } else if (pid < 0) {
            return error.ForkFailed;
        }
        var status: u32 = 0;
        _ = std.os.linux.waitpid(pid, &status, 0);
    }

    fn kill_graph_windows(self: *WM, g: *graph_mod.Graph) void {
        const wm_delete = c.XInternAtom(self.display, "WM_DELETE_WINDOW", 0);
        const wm_protocols = c.XInternAtom(self.display, "WM_PROTOCOLS", 0);
        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => |win| {
                    // Send close request FIRST so the client receives it
                    var ev: c.XEvent = std.mem.zeroes(c.XEvent);
                    ev.xclient.type = c.ClientMessage;
                    ev.xclient.window = win;
                    ev.xclient.message_type = wm_protocols;
                    ev.xclient.format = 32;
                    ev.xclient.data.l[0] = @intCast(wm_delete);
                    ev.xclient.data.l[1] = c.CurrentTime;
                    _ = c.XSendEvent(self.display, win, 0, c.NoEventMask, &ev);
                    // Remove from registry so DestroyNotify is ignored
                    if (self.window_to_node_id.get(win)) |id| {
                        _ = self.node_registry.remove(id);
                        _ = self.window_to_node_id.remove(win);
                    }
                    // Don't destroy frame — let client die naturally
                },
                .workspace => |sub| self.kill_graph_windows(sub),
                .empty => {},
            }
        }
        _ = c.XFlush(self.display);
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
                if (node.content.workspace == self.current_graph) {
                    try self.leave_workspace();
                }
                // Check for siblings with content at the same level
                if (node.owner_graph) |og| {
                    const killed_level = node.content.workspace.id.level;
                    for (og.nodes.items) |sibling| {
                        if (sibling == node) continue;
                        if (sibling.content != .workspace) continue;
                        if (sibling.content.workspace.id.level != killed_level) continue;
                        if (graph_has_content(sibling.content.workspace)) {
                            self.notify("Windows left behind", "Other workspaces at this level still have windows open");
                            break;
                        }
                    }
                }
                // Clean up children first — removes from registry so their
                // DestroyNotify events are ignored
                self.kill_graph_windows(node.content.workspace);
                // Destroy preview — triggers normal on_destroy_notify path
                // which calls arranger unmap, remove_node (frees sub-graph), resolve/flush
                if (node.preview_window) |pw| {
                    _ = c.XDestroyWindow(self.display, pw);
                }
            },
            else => {},
        }
    }

    fn graph_has_content(g: *graph_mod.Graph) bool {
        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => return true,
                .workspace => |sub| if (graph_has_content(sub)) return true,
                .empty => {},
            }
        }
        return false;
    }

    pub fn notify(self: *WM, summary: []const u8, body: []const u8) void {
        const argv = [_][]const u8{ "notify-send", "-a", "duckwm", summary, body };
        self.spawn(&argv) catch {};
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

    pub fn sync_constraints_from_geometry(self: *WM) void {
        for (self.current_graph.nodes.items) |node| {
            if (node.floating) continue;
            for (node.constraints.items) |*con| {
                switch (con.*) {
                    .fixed_x      => |*v| v.* = node.x,
                    .fixed_y      => |*v| v.* = node.y,
                    .fixed_width  => |*v| v.* = node.width,
                    .fixed_height => |*v| v.* = node.height,
                    .split => |*s| {
                        const cont = s.container;
                        if (cont.width == 0 and cont.height == 0) continue;
                        var ratio_sum: f32 = 0;
                        for (0..s.count) |i| {
                            const child = s.children[i];
                            const ratio: f32 = if (s.axis == .horizontal)
                                @as(f32, @floatFromInt(child.width)) /
                                @as(f32, @floatFromInt(cont.width))
                            else
                                @as(f32, @floatFromInt(child.height)) /
                                @as(f32, @floatFromInt(cont.height));
                            s.ratios[i] = @max(0.01, ratio);
                            ratio_sum += s.ratios[i];
                        }
                        if (ratio_sum > 0) {
                            for (0..s.count) |i| s.ratios[i] /= ratio_sum;
                        }
                    },
                    else => {},
                }
            }
        }
    }

    pub fn create_workspace_graph(self: *WM, level: u32) !*graph_mod.Graph {
        const sub = try self.allocator.create(graph_mod.Graph);
        sub.* = graph_mod.Graph.init(self.allocator);
        sub.id = try self.alloc_workspace_id(level);
        sub.gap_inner_h = self.default_gap_inner_h;
        sub.gap_inner_v = self.default_gap_inner_v;
        sub.gap_outer_h = self.default_gap_outer_h;
        sub.gap_outer_v = self.default_gap_outer_v;
        if (self.default_arranger_name.len > 0 and sub.arranger_name.len == 0) {
            sub.arranger_name = try self.allocator.dupe(u8, self.default_arranger_name);
        }
        return sub;
    }

    pub fn create_workspace_node_with_preview(self: *WM, owner_graph: *graph_mod.Graph) !*Node {
        const level = owner_graph.id.level + 1;
        const sub = try self.create_workspace_graph(level);
        const pw = c.XCreateSimpleWindow(
            self.display, self.root,
            0, 0, 200, 150, 0, 0, 0x1a1a2e
        );
        var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        wa.override_redirect = 1;
        _ = c.XChangeWindowAttributes(self.display, pw, c.CWOverrideRedirect, &wa);
        const node = try owner_graph.add_node(.{ .workspace = sub });
        sub.parent_node = node;
        node.preview_window = pw;
        node.floating = false;
        node.hidden = true;
        try self.frame(pw, node);
        _ = c.XSelectInput(self.display, pw, c.ButtonPressMask | c.ButtonReleaseMask | c.ExposureMask);
        self.repaint_preview(node);
        return node;
    }

    /// Create the very first workspace node in the top-level graph.
    /// This is called once in `run` so that Super+Ctrl+1 always works
    /// and the screen is never empty.
    pub fn create_initial_workspace(self: *WM) !void {
        // 1. Root container
        const root_node = try self.current_graph.add_node(.empty);
        root_node.width = self.screen_width;
        root_node.height = self.screen_height;
        root_node.x = 0;
        root_node.y = 0;
        _ = try self.register_node(null, root_node);

        // 2. Workspace sub-graph
        const sub = try self.create_workspace_graph(1);

        const pw = c.XCreateSimpleWindow(
            self.display, self.root,
            0, 0, 200, 150, 0, 0, 0x1a1a2e
        );
        var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        wa.override_redirect = 1;
        _ = c.XChangeWindowAttributes(self.display, pw, c.CWOverrideRedirect, &wa);

        const ws_node = try self.current_graph.add_node(.{ .workspace = sub });
        sub.parent_node = ws_node;
        ws_node.preview_window = pw;
        ws_node.floating = false;

        try self.frame(pw, ws_node);
        _ = c.XSelectInput(self.display, pw, c.ButtonPressMask | c.ButtonReleaseMask | c.ExposureMask);
        _ = try self.register_node(pw, ws_node);

        // 3. Constraint to fill root
        const g = graph_mod.Constraint{ .grid_cell = .{
            .col = 0, .row = 0, .cols = 1, .rows = 1, .container = root_node,
        } };
        try self.current_graph.add_constraint(ws_node, g);

        // 4. Resolve, paint, then enter
        try self.resolve(self.current_graph);
        try self.rebuild_focus_edges();
        try self.flush(self.current_graph);
        self.repaint_preview(ws_node);  // paint while still on parent graph
        try self.enter_workspace(ws_node);
    }

    pub fn run(self: *WM) !void {
        self.current_graph = &self.graph;
        events_mod.wm_detected = false;
        _ = c.XSetErrorHandler(events_mod.on_wm_detected);
        events_mod.announce_supported_hints(self);
        _ = c.XSync(self.display, 0);
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
        self.visible_graph = self.current_graph;

        if (self.post_load_error) |msg| {
            self.show_error_bar(msg);
            self.allocator.free(msg);
            self.post_load_error = null;
        }

        self.startup_done = true;

        try self.init_ipc();
        const x11_fd = c.XConnectionNumber(self.display);

        while (true) {
            var fds_buf: [3]std.posix.pollfd = undefined;
            var nfds: usize = 2;
            fds_buf[0] = .{ .fd = x11_fd,      .events = std.posix.POLL.IN, .revents = 0 };
            fds_buf[1] = .{ .fd = self.ipc_fd,  .events = std.posix.POLL.IN, .revents = 0 };
            if (self.inotify_fd >= 0) {
                fds_buf[2] = .{ .fd = self.inotify_fd, .events = std.posix.POLL.IN, .revents = 0 };
                nfds = 3;
            }

            _ = std.posix.poll(fds_buf[0..nfds], -1) catch continue;

            if (fds_buf[1].revents & std.posix.POLL.IN != 0) {
                self.accept_ipc_clients();
            }
            self.handle_ipc_clients();

            // Handle inotify events
            if (self.inotify_fd >= 0 and nfds == 3 and fds_buf[2].revents & std.posix.POLL.IN != 0) {
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
                    c.ButtonPress      => try events_mod.on_button_press(self, &e.xbutton),
                    c.MotionNotify     => events_mod.on_motion_notify(self, &e.xmotion),
                    c.ButtonRelease    => events_mod.on_button_release(self, &e.xbutton),
                    c.ConfigureNotify  => {},
                    c.EnterNotify      => events_mod.on_enter_notify(self, &e.xcrossing),
                    c.LeaveNotify      => events_mod.on_leave_notify(self, &e.xcrossing),
                    c.ClientMessage    => try events_mod.on_client_message(self, &e.xclient),
                    c.PropertyNotify   => try events_mod.on_property_notify(self, &e.xproperty),
                    c.UnmapNotify      => try events_mod.on_unmap_notify(self, &e.xunmap),
                    c.MapNotify        => events_mod.on_map_notify(self, &e.xmap),
                    c.Expose           => events_mod.on_expose(self, &e.xexpose),
                    else => std.debug.print("Unhandled event type: {}\n", .{e.type}),
                }
            }
            if (self.pending_reload) {
                self.pending_reload = false;
                if (self.reload_fn) |f| f(self);
            }
        }
    }
};
