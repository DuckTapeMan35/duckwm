const c = @import("libc");
const std = @import("std");
const ziglua = @import("ziglua");
const graph_mod = @import("graph");
const focus_mod = @import("focus.zig");
const resize_mod = @import("resize.zig");
const float_mod = @import("float.zig");
const ipc_mod = @import("ipc.zig");
const preview_mod = @import("preview.zig");
const backend_mod = @import("backend.zig");
const lifecycle = @import("lifecycle.zig");
const requests = @import("requests.zig");
const types = @import("types");
const pointer = @import("pointer.zig");
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;
const Direction = graph_mod.Direction;
const Backend = backend_mod.Backend;
const Lua = ziglua.Lua;

pub fn notify_error(wm: *WM, msg: []const u8) void {
    wm.show_error(msg);
}

pub fn apply_initial_hints(node: *Node, h: types.InitialHints) void {
    if (h.fullscreen) node.wants_fullscreen = true;
    if (h.urgent) node.urgent = true;
    if (h.keep_above) node.floating = true;
    if (h.fixed_size) |s| {
        node.floating = true;
        node.width = s.width;
        node.height = s.height;
    }
    if (h.fixed_aspect) node.floating = true;
}

pub const WorkArea = types.Rect;

pub const KeybindKey = types.KeyCombo;

pub const Keybind = union(enum) {
    zig: *const fn (*WM) anyerror!void,
    lua: i32,
};

pub const SwallowPair = struct {
    terminal: []const u8,
    child: []const u8,
};

pub const WorkspaceSwitchMode = enum { none, previous };

pub const WM = struct {
    backend: Backend,
    screen_width: u32,
    screen_height: u32,
    focus_follows_mouse: bool,
    saved_focus_follows_mouse: bool,
    ffm_suspended: bool,
    click_to_focus: bool,
    argb_frames: bool,
    rgb_frame_classes: std.ArrayListUnmanaged([]const u8),
    scene: std.ArrayListUnmanaged(types.WindowState),
    preview_defaults: preview_mod.Defaults,
    preview_items: std.ArrayListUnmanaged(types.PreviewItem),
    scene_dirty: bool,
    focus_dirty: bool,
    sync_on_commit: bool,

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
    next_workspace_number: std.AutoHashMap(u32, u32),
    swallow_pairs: std.ArrayListUnmanaged(SwallowPair),
    scratch_graph: *Graph,
    focus_clock: u64,
    default_gap_inner_h: u32,
    default_gap_inner_v: u32,
    default_gap_outer_h: u32,
    default_gap_outer_v: u32,

    // misc state fields
    flushing: bool,
    pending_cleanup_graph: ?*Graph,
    autoclean: bool,

    // resize state fields
    resize_modifier: ?types.Mods,
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
    resize_window: types.WindowHandle,

    // floating state fields
    float_moving: bool,
    float_move_modifier: ?types.Mods,
    float_move_window: types.WindowHandle,
    float_move_start_x: i32,
    float_move_start_y: i32,
    float_win_start_x: i32,
    float_win_start_y: i32,
    float_move_button: types.Button,
    float_resize_button: types.Button,

    // pan state fields
    pan_dragging: bool,
    pan_drag_start_x: i32,
    pan_drag_start_y: i32,
    pan_drag_start_pan_x: i32,
    pan_drag_start_pan_y: i32,
    pan_modifier: ?types.Mods,
    pan_button: types.Button,

    // IPC state fields in WM struct
    ipc_fd: i32,
    ipc_clients: std.ArrayListUnmanaged(i32),

    // data for the lua API
    node_registry: std.AutoHashMap(u32, *Node),
    window_to_node_id: std.AutoHashMap(types.WindowHandle, u32),
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
    reload_fn: ?*const fn (*WM) void,
    pending_reload: bool,
    last_reload_time: i64,
    startup_done: bool,

    // error
    post_load_error: ?[]u8,

    // allocator
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !WM {
        const graph = Graph.init(allocator);
        var backend = try Backend.init(allocator);
        errdefer backend.deinit();
        const size = backend.screen_size();
        const wm = WM{
            .backend = backend,
            .screen_width = size.width,
            .screen_height = size.height,
            .focus_follows_mouse = true,
            .saved_focus_follows_mouse = true,
            .ffm_suspended = false,
            .click_to_focus = false,
            .argb_frames = true,
            .rgb_frame_classes = .empty,
            .scene = .empty,
            .preview_defaults = .{},
            .preview_items = .empty,
            .scene_dirty = false,
            .focus_dirty = false,
            .sync_on_commit = false,

            .keybinds = std.AutoHashMap(KeybindKey, Keybind).init(allocator),

            .graph = graph,
            .focused = null,
            .workspace_stack = .{ .items = &.{}, .capacity = 0 },
            .next_workspace_number = std.AutoHashMap(u32, u32).init(allocator),
            .current_graph = undefined,
            .visible_graph = undefined,
            .previous_graph = null,
            .workspace_switch_mode = .none,
            .default_gap_inner_h = 0,
            .swallow_pairs = .{ .items = &.{}, .capacity = 0 },
            .scratch_graph = undefined,
            .focus_clock = 0,
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
            .resize_window = 0,

            .flushing = false,
            .pending_cleanup_graph = null,
            .autoclean = true,

            .float_moving = false,
            .float_move_modifier = null,
            .float_move_window = 0,
            .float_move_start_x = 0,
            .float_move_start_y = 0,
            .float_win_start_x = 0,
            .float_win_start_y = 0,
            .float_move_button = 1, // left mouse button
            .float_resize_button = 3, // right mouse button

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
            .window_to_node_id = std.AutoHashMap(types.WindowHandle, u32).init(allocator),
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
            .startup_done = false,

            .post_load_error = null,

            .allocator = allocator,
        };

        wm.backend.publish_work_area(.{ .x = 0, .y = 0, .width = size.width, .height = size.height });
        return wm;
    }

    fn free_parked_terminal(self: *WM, term: *Node) void {
        switch (term.content) {
            .window => |win| {
                self.backend.unframe(win, true);
                self.backend.close_window(win);
                _ = self.window_to_node_id.remove(win);
            },
            else => {},
        }
        if (self.get_id_for_node(term)) |tid| _ = self.node_registry.remove(tid);
        if (self.focused == term) self.focused = null;
        if (term.owner_graph) |og| {
            if (og.fullscreen_node == term) og.fullscreen_node = null;
        }
        term.deinit(self.allocator);
        self.allocator.destroy(term);
    }

    fn free_graph(self: *WM, g: *Graph) void {
        if (g.arranger_name.len > 0) {
            self.allocator.free(g.arranger_name);
        }
        for (g.nodes.items) |node| {
            if (self.focused == node) {
                self.focused = null;
            }
            if (g.fullscreen_node == node) {
                g.fullscreen_node = null;
            }
            if (node.content == .workspace) {
                self.free_graph(node.content.workspace);
            }
            // destroy any preview window
            if (node.preview_window) |pw| self.backend.destroy_preview_window(pw);
            node.deinit(self.allocator);
            self.allocator.destroy(node);
        }
        g.nodes.deinit(self.allocator);
        g.focus_edges.deinit(self.allocator);
    }

    fn on_node_freed(ctx: *anyopaque, node: *Node) void {
        const self: *WM = @ptrCast(@alignCast(ctx));
        if (node.parked_term) |term| {
            node.parked_term = null;
            self.free_parked_terminal(term);
        }
        switch (node.content) {
            .window => |win| _ = self.window_to_node_id.remove(win),
            .workspace => if (node.preview_window) |pw| {
                _ = self.window_to_node_id.remove(pw);
            },
            .empty => {},
        }
        if (self.get_id_for_node(node)) |id| {
            _ = self.node_registry.remove(id);
        }
        if (self.focused == node) self.focused = null;
        if (node.owner_graph) |og| {
            if (og.fullscreen_node == node) og.fullscreen_node = null;
        }
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
        for (self.swallow_pairs.items) |p| {
            self.allocator.free(p.terminal);
            self.allocator.free(p.child);
        }
        self.preview_items.deinit(self.allocator);
        self.swallow_pairs.deinit(self.allocator);
        self.next_workspace_number.deinit();
        self.free_graph(&self.graph);
        self.workspace_stack.deinit(self.allocator);
        self.node_registry.deinit();
        self.window_to_node_id.deinit();
        if (self.ipc_fd >= 0) {
            _ = std.os.linux.close(self.ipc_fd);
        }
        for (self.ipc_clients.items) |fd| {
            _ = std.os.linux.close(fd);
        }
        self.ipc_clients.deinit(self.allocator);
        self.backend.deinit();
        self.clear_rgb_frame_classes();
        self.rgb_frame_classes.deinit(self.allocator);
        self.scene.deinit(self.allocator);
    }

    fn forces_rgb(self: *WM, node: *Node) bool {
        for (self.rgb_frame_classes.items) |name| {
            if (std.mem.eql(u8, name, node.info.class()) or
                std.mem.eql(u8, name, node.info.instance())) return true;
        }
        return false;
    }

    pub fn clear_rgb_frame_classes(self: *WM) void {
        for (self.rgb_frame_classes.items) |name| self.allocator.free(name);
        self.rgb_frame_classes.clearRetainingCapacity();
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

    /// Smallest node in the current graph containing p (most specific hit).
    pub fn node_at(self: *WM, p: types.Point) ?*Node {
        var best: ?*Node = null;
        var best_area: u64 = std.math.maxInt(u64);
        for (self.current_graph.nodes.items) |node| {
            if (node.width == 0 or node.height == 0) continue;
            const nw: i32 = @intCast(node.width);
            const nh: i32 = @intCast(node.height);
            if (p.x >= node.x and p.x < node.x + nw and p.y >= node.y and p.y < node.y + nh) {
                const area = @as(u64, node.width) * node.height;
                if (area < best_area) {
                    best = node;
                    best_area = area;
                }
            }
        }
        return best;
    }

    pub fn repaint_preview(self: *WM, node: *Node) void {
        if (node.content != .workspace) return;
        const pw = node.preview_window orelse return;
        const sub = node.content.workspace;
        preview_mod.layout(
            self.allocator,
            sub,
            node.width,
            node.height,
            self.preview_defaults.max_icon_size,
            &self.preview_items,
        ) catch return;
        self.backend.draw_preview(pw, .{ .width = node.width, .height = node.height }, preview_mod.style(
            &self.preview_defaults,
            sub,
        ), self.preview_items.items);
    }

    pub fn set_preview_max_icon_size(self: *WM, size: u32) void {
        self.preview_defaults.max_icon_size = if (size == 0) null else size;
    }

    pub fn set_preview_colors(self: *WM, bg: u32, win_bg: u32, border: u32, text: u32) void {
        self.preview_defaults.bg = bg;
        self.preview_defaults.win_bg = win_bg;
        self.preview_defaults.border = border;
        self.preview_defaults.text = text;
    }

    pub fn set_preview_font(self: *WM, name: []const u8) void {
        self.preview_defaults.set_font(name);
    }

    /// false if the backend could tell right away that the keymap is invalid.
    pub fn set_keyboard_layout(self: *WM, km: types.Keymap) bool {
        return self.backend.set_keymap(km);
    }

    pub fn set_keyboard_layout_index(self: *WM, index: u32) void {
        self.backend.set_layout_index(index);
    }

    pub fn end_session(self: *WM) void {
        self.backend.end_session();
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
                std.debug.print("rule error: {} {s}\n", .{ err, msg orelse "" });
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
            std.debug.print("arranger callback error: {} msg={s}\n", .{ err, lua_msg orelse "none" });
            lua.setTop(top_before);
        };
    }

    pub fn register_node(self: *WM, win: ?types.WindowHandle, node: *Node) !u32 {
        const id = self.next_node_id;
        try self.node_registry.put(id, node);
        if (win) |w| {
            try self.window_to_node_id.put(w, id);
        }
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
            node.info = .{};
        }
    }

    pub fn set_node_window(self: *WM, node_id: u32, win: types.WindowHandle) !void {
        if (self.node_registry.get(node_id)) |node| {
            switch (node.content) {
                .window => |old_win| {
                    _ = self.window_to_node_id.remove(old_win);
                },
                else => {},
            }
            node.content = .{ .window = win };
            node.info = self.backend.window_info(win);
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
        dst.info = src.info;
        src.info = .{};
    }

    pub fn bind_lua(self: *WM, mods: types.Mods, keysym: types.Keysym, ref: i32) !void {
        const k: KeybindKey = .{ .mods = mods, .keysym = keysym };
        try self.keybinds.put(k, .{ .lua = ref });
        self.backend.grab_key(k);
    }

    pub fn bind(self: *WM, mods: types.Mods, keysym: types.Keysym, action: *const fn (*WM) anyerror!void) !void {
        const k: KeybindKey = .{ .mods = mods, .keysym = keysym };
        try self.keybinds.put(k, .{ .zig = action });
        self.backend.grab_key(k);
    }

    pub fn ungrab_keys(self: *WM) void {
        self.backend.ungrab_all_keys();
    }

    /// what color each side of node's border should be right now.
    pub fn border_colors(self: *WM, node: *Node) types.BorderColors {
        const focused = self.focused == node;
        const base: u32 = if (node.urgent)
            node.border_color_focused orelse self.default_border_color_urgent
        else if (focused)
            node.border_color_focused orelse self.default_border_color_focused
        else
            node.border_color_unfocused orelse self.default_border_color_unfocused;

        const sides = !self.border_side_colors_focused_only or focused;
        return .{
            .top = if (sides) node.border_color_top orelse base else base,
            .bottom = if (sides) node.border_color_bottom orelse base else base,
            .left = if (sides) node.border_color_left orelse base else base,
            .right = if (sides) node.border_color_right orelse base else base,
        };
    }

    fn wants_borders(self: *WM, node: *Node) bool {
        if (self.border_width <= 0) return false;
        if (node.owner_graph) |og| {
            if (og.fullscreen_node == node) return false;
        }
        return true;
    }

    fn preview_visible(self: *WM, node: *Node) bool {
        if (node.hidden or node.preview_window == null) return false;
        if (node.floating) return true;
        const sub = node.content.workspace;
        if (sub == self.current_graph) return false;
        for (self.workspace_stack.items) |s| {
            if (s == sub) return false;
        }
        return true;
    }

    fn floating_rect(node: *const Node) types.Rect {
        return .{ .x = node.x, .y = node.y, .width = @max(1, node.width), .height = @max(1, node.height) };
    }

    fn tiled_rect(g: *const Graph, node: *const Node, work: WorkArea) types.Rect {
        const nw: i32 = @intCast(node.width);
        const nh: i32 = @intCast(node.height);
        const ww: i32 = @intCast(work.width);
        const wh: i32 = @intCast(work.height);

        const at_left = node.x <= work.x;
        const at_top = node.y <= work.y;
        const at_right = node.x + nw >= work.x + ww;
        const at_bottom = node.y + nh >= work.y + wh;

        const half_h = g.gap_inner_h / 2;
        const half_v = g.gap_inner_v / 2;
        const gap_left: u32 = if (at_left) g.gap_outer_h else half_h;
        const gap_right: u32 = if (at_right) g.gap_outer_h else half_h;
        const gap_top: u32 = if (at_top) g.gap_outer_v else half_v;
        const gap_bottom: u32 = if (at_bottom) g.gap_outer_v else half_v;

        return .{
            .x = node.x + @as(i32, @intCast(gap_left)) - g.pan_x,
            .y = node.y + @as(i32, @intCast(gap_top)) - g.pan_y,
            .width = @max(1, node.width -| gap_left -| gap_right),
            .height = @max(1, node.height -| gap_top -| gap_bottom),
        };
    }

    /// the desired state of every visible window in g.
    fn compute_scene(self: *WM, g: *Graph) !void {
        self.scene.clearRetainingCapacity();
        const bw: u32 = @intCast(@max(0, self.border_width));
        const work = self.get_work_area();

        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => |win| {
                    if (node.hidden) continue;
                    const is_fullscreen = self.focused == node and g.fullscreen_node == node;
                    try self.scene.append(self.allocator, .{
                        .handle = win,
                        .frame = if (node.floating) floating_rect(node) else tiled_rect(g, node, work),
                        .border_width = if (is_fullscreen) 0 else bw,
                        .borders = if (self.wants_borders(node)) self.border_colors(node) else null,
                        .tiled = !node.floating,
                        .interactive = node.floating and self.float_moving and self.float_move_window == win,
                    });
                },
                .workspace => {
                    if (!self.preview_visible(node)) continue;
                    try self.scene.append(self.allocator, .{
                        .handle = node.preview_window.?,
                        .frame = if (node.floating) floating_rect(node) else tiled_rect(g, node, work),
                        .border_width = bw,
                        .borders = if (self.wants_borders(node)) self.border_colors(node) else null,
                        .tiled = !node.floating,
                        .interactive = node.floating and self.float_moving and self.float_move_window == node.preview_window.?,
                    });
                },
                .empty => {},
            }
        }
    }

    /// Repaint node's border. Pass the frame size if known to skip a server query.
    pub fn paint_borders(self: *WM, node: *Node, size: ?types.Size) void {
        if (!self.wants_borders(node)) return;
        const h = node_window(node) orelse return;
        self.backend.draw_borders(h, self.border_colors(node), @intCast(self.border_width), size);
    }

    fn frame_options(self: *WM, node: *Node) types.FrameOptions {
        return .{
            .allow_argb = self.argb_frames and !self.forces_rgb(node),
            .border_width = @intCast(@max(0, self.border_width)),
            .border_color = if (self.focused == node)
                node.border_color_focused orelse self.default_border_color_focused
            else
                node.border_color_unfocused orelse self.default_border_color_unfocused,
            .configured_size = if (node.width > 0 and node.height > 0)
                .{ .width = node.width, .height = node.height }
            else
                null,
        };
    }

    pub fn frame(self: *WM, win: types.WindowHandle, node: *Node) !void {
        _ = try self.backend.frame_window(win, self.frame_options(node));
    }

    pub fn get_work_area(self: *WM) WorkArea {
        const r = self.backend.reserved_insets();
        return .{
            .x = @intCast(r.left),
            .y = @intCast(r.top),
            .width = self.screen_width -| r.left -| r.right,
            .height = self.screen_height -| r.top -| r.bottom,
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
        const solve_width = if (g.virtual_width > work.width) g.virtual_width else work.width;
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

        self.backend.publish_work_area(work);
    }

    pub fn rebuild_focus_edges(self: *WM) !void {
        return focus_mod.rebuild_focus_edges(self);
    }

    pub fn focus_left(self: *WM) anyerror!void {
        try focus_mod.focus_left(self);
    }
    pub fn focus_right(self: *WM) anyerror!void {
        try focus_mod.focus_right(self);
    }
    pub fn focus_up(self: *WM) anyerror!void {
        try focus_mod.focus_up(self);
    }
    pub fn focus_down(self: *WM) anyerror!void {
        try focus_mod.focus_down(self);
    }

    pub fn resize_vertical_edge(self: *WM, edge_x: i32, delta: i32, floating: bool) !bool {
        return resize_mod.resize_vertical_edge(self, edge_x, delta, floating);
    }
    pub fn resize_horizontal_edge(self: *WM, edge_y: i32, delta: i32, floating: bool) !bool {
        return resize_mod.resize_horizontal_edge(self, edge_y, delta, floating);
    }
    pub fn resize_edge(self: *WM, node: *Node, dir: Direction, delta: i32) !void {
        return resize_mod.resize_edge(self, node, dir, delta);
    }
    pub fn resize_corner(self: *WM, node: *Node, delta_x: i32, delta_y: i32) !void {
        return resize_mod.resize_corner(self, node, delta_x, delta_y);
    }

    pub fn toggle_floating(self: *WM) !void {
        return float_mod.toggle_floating(self);
    }
    pub fn toggle_fullscreen(self: *WM) !void {
        return float_mod.toggle_fullscreen(self);
    }
    pub fn center_node(self: *WM, node: *Node) void {
        float_mod.center_node(self, node);
    }

    pub fn init_ipc(self: *WM) !void {
        try ipc_mod.init(self);
    }
    pub fn accept_ipc_clients(self: *WM) void {
        ipc_mod.accept_clients(self);
    }
    pub fn handle_ipc_clients(self: *WM) void {
        ipc_mod.handle_clients(self);
    }

    pub fn node_window(node: *graph_mod.Node) ?types.WindowHandle {
        return switch (node.content) {
            .window => |w| w,
            .workspace => node.preview_window,
            .empty => null,
        };
    }

    pub fn show_scratchpad(self: *WM, node_id: u32) !void {
        const node = self.node_registry.get(node_id) orelse return;
        if (node_window(node) == null) return;

        node.floating = true;
        try self.send_to_workspace(node_id, self.current_graph);

        try self.rebuild_focus_edges();
        try self.flush(self.current_graph);
        if (node.content == .workspace) self.repaint_preview(node);
        self.focus(node);
    }

    pub fn hide_scratchpad(self: *WM, node_id: u32) !void {
        const node = self.node_registry.get(node_id) orelse return;
        if (node_window(node) == null) return;

        try self.send_to_workspace(node_id, self.scratch_graph);
        node.floating = true;

        if (focus_mod.top_left_window(self)) |n| self.focus(n);
    }

    pub fn toggle_scratchpad(self: *WM, node_id: u32) !void {
        const node = self.node_registry.get(node_id) orelse return;
        if (node_window(node) == null) return;

        if (node.owner_graph == self.scratch_graph)
            try self.show_scratchpad(node_id)
        else
            try self.hide_scratchpad(node_id);
    }

    pub fn get_id_for_node(self: *WM, node: *Node) ?u32 {
        var it = self.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == node) return entry.key_ptr.*;
        }
        return null;
    }

    /// Derive the root pointer grabs from the current modifier/button settings.
    pub fn sync_pointer_grabs(self: *WM) void {
        var grabs: [3]types.PointerGrab = undefined;
        var n: usize = 0;
        if (self.resize_modifier) |m| {
            grabs[n] = .{ .mods = m, .button = null };
            n += 1;
        }
        if (self.float_move_modifier) |m| {
            grabs[n] = .{ .mods = m, .button = null };
            n += 1;
        }
        if (self.pan_modifier) |m| {
            grabs[n] = .{ .mods = m, .button = self.pan_button };
            n += 1;
        }
        self.backend.set_pointer_grabs(grabs[0..n]);
    }

    pub fn set_click_to_focus(self: *WM, enabled: bool) void {
        self.click_to_focus = enabled;
        self.backend.set_click_to_focus(enabled);
    }

    /// Ask for g's state to be pushed to the screen at the next commit.
    pub fn flush(self: *WM, g: *Graph) !void {
        if (g == self.visible_graph) self.scene_dirty = true;
    }

    fn apply_scene(self: *WM) !void {
        const g = self.visible_graph;
        self.flushing = true;
        defer self.flushing = false;

        try self.compute_scene(g);

        const fullscreen: ?types.WindowHandle = if (g.fullscreen_node) |n| switch (n.content) {
            .window => |w| w,
            else => null,
        } else null;
        self.backend.apply_windows(self.scene.items, fullscreen);

        for (g.nodes.items) |node| {
            if (node.content == .workspace and self.preview_visible(node)) self.repaint_preview(node);
        }
    }

    /// Push everything changed during this loop iteration to the backend, once.
    pub fn commit(self: *WM) void {
        if (self.scene_dirty) {
            // Catch containers emptied by any path, not just a close.
            const g = self.visible_graph;
            const before = g.nodes.items.len;
            lifecycle.sweep_dead_containers(self);
            if (g.nodes.items.len != before) {
                self.resolve(g) catch {};
                self.rebuild_focus_edges() catch {};
            }

            self.scene_dirty = false;
            self.apply_scene() catch |err| std.debug.print("commit: {}\n", .{err});
        }
        // After the scene, so a window focused this iteration is already mapped.
        if (self.focus_dirty) {
            self.focus_dirty = false;
            if (self.focused) |n| {
                if (self.is_shown(n)) {
                    if (node_window(n)) |h| _ = self.backend.set_input_focus(h, n.content == .window);
                }
            } else {
                _ = self.backend.set_input_focus(null, false);
            }
        }
        if (self.sync_on_commit) {
            self.sync_on_commit = false;
            self.backend.sync();
        }
    }

    /// Will node be on screen after the next commit?
    pub fn is_shown(self: *WM, node: *Node) bool {
        if (node.owner_graph != self.visible_graph) return false;
        return switch (node.content) {
            .window => !node.hidden,
            .workspace => self.preview_visible(node),
            .empty => false,
        };
    }

    pub fn clear_focus(self: *WM) void {
        self.focused = null;
        self.focus_dirty = true;
    }

    pub fn focus(self: *WM, node: *Node) void {
        focus_mod.set_focus(self, node);
    }

    pub fn unmanage_as_dock(self: *WM, win: types.WindowHandle) !void {
        const node_id = self.window_to_node_id.get(win) orelse return;
        const node = self.node_registry.get(node_id) orelse return;

        self.backend.release_window(win);

        // Remove from graph and registry
        if (node.owner_graph) |graph| {
            graph.remove_node(node);
        }
        _ = self.node_registry.remove(node_id);
        _ = self.window_to_node_id.remove(win);

        // Recalculate layout
        try self.resolve(self.current_graph);
        try self.rebuild_focus_edges();
        try self.flush(self.current_graph);
    }

    pub fn exchange(self: *WM, a: *Node, b: *Node) !void {
        // Find node IDs
        var a_id: ?u32 = null;
        var b_id: ?u32 = null;
        var it = self.node_registry.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* == a) a_id = entry.key_ptr.*;
            if (entry.value_ptr.* == b) b_id = entry.key_ptr.*;
        }
        const id_a = a_id orelse return error.InvalidNode;
        const id_b = b_id orelse return error.InvalidNode;

        // Swap contents
        const content_a = a.content;
        const content_b = b.content;
        if (content_a == .empty and content_b == .empty) return;

        // Update window_to_node_id for window nodes
        switch (content_a) {
            .window => |win| _ = self.window_to_node_id.remove(win),
            else => {},
        }
        switch (content_b) {
            .window => |win| _ = self.window_to_node_id.remove(win),
            else => {},
        }

        // Swap preview_window and content
        const pw_a = a.preview_window;
        const pw_b = b.preview_window;
        a.content = content_b;
        b.content = content_a;
        a.preview_window = pw_b;
        b.preview_window = pw_a;

        const a_focused = a.border_color_focused;
        const a_unfocused = a.border_color_unfocused;
        a.border_color_focused = b.border_color_focused;
        a.border_color_unfocused = b.border_color_unfocused;
        b.border_color_focused = a_focused;
        b.border_color_unfocused = a_unfocused;

        // swap window info
        const info_a = a.info;
        a.info = b.info;
        b.info = info_a;

        // Update workspace parent_node pointers
        switch (a.content) {
            .workspace => |sub| sub.parent_node = a,
            else => {},
        }
        switch (b.content) {
            .workspace => |sub| sub.parent_node = b,
            else => {},
        }

        // Update window_to_node_id for new positions
        switch (a.content) {
            .window => |win| try self.window_to_node_id.put(win, id_a),
            else => {},
        }
        switch (b.content) {
            .window => |win| try self.window_to_node_id.put(win, id_b),
            else => {},
        }

        // Update window_to_node_id for swapped preview windows
        if (pw_a) |pw| {
            _ = self.window_to_node_id.remove(pw);
            try self.window_to_node_id.put(pw, id_b);
        }
        if (pw_b) |pw| {
            _ = self.window_to_node_id.remove(pw);
            try self.window_to_node_id.put(pw, id_a);
        }

        // Update focused pointer
        if (self.focused == a) self.focused = b else if (self.focused == b) self.focused = a;

        try self.flush(self.current_graph);
    }

    fn hide_graph_frames(self: *WM, g: *Graph) void {
        for (g.nodes.items) |node| {
            if (node_window(node)) |h| self.backend.hide_window(h);
        }
    }

    pub fn activate_window(self: *WM, node: *Node) !void {
        const target = node.owner_graph orelse return;

        // dont yank the user to the "virtual" workspace scratchpads use
        if (target == self.scratch_graph) {
            if (self.get_id_for_node(node)) |id| try self.show_scratchpad(id);
            return;
        }

        if (target != self.current_graph) {
            // get onto a shared ancestor of the target
            var target_anc = std.AutoHashMapUnmanaged(*Graph, void){};
            defer target_anc.deinit(self.allocator);
            {
                var g: *Graph = target;
                while (true) {
                    try target_anc.put(self.allocator, g, {});
                    const pn = g.parent_node orelse break;
                    g = pn.owner_graph orelse break;
                }
            }
            var guard: usize = 0;
            while (!target_anc.contains(self.current_graph) and guard < 64) : (guard += 1) {
                const before = self.current_graph;
                try self.leave_workspace();
                if (self.current_graph == before) break; // level-1 stall (common ancestor is root)
            }

            // walk down the parent_node chain into target
            var chain: std.ArrayListUnmanaged(*Node) = .{ .items = &.{}, .capacity = 0 };
            defer chain.deinit(self.allocator);
            var g: *Graph = target;
            while (g != self.current_graph) {
                const pn = g.parent_node orelse break;
                try chain.append(self.allocator, pn);
                g = pn.owner_graph orelse break;
            }
            var i = chain.items.len;
            while (i > 0) {
                i -= 1;
                try self.enter_workspace(chain.items[i]);
            }
        }

        self.focus(node);
        try self.flush(self.current_graph);
    }

    pub fn enter_workspace(self: *WM, node: *Node) !void {
        if (node.content != .workspace) return error.NotWorkspace;
        const new = node.content.workspace;

        if (new == self.current_graph) return;
        const old = self.current_graph;

        // push parent
        try self.workspace_stack.append(self.allocator, old);

        // switch
        self.current_graph = new;
        self.visible_graph = self.current_graph;

        // re-layout and paint the new graph into place first
        try self.resolve(new);
        try self.flush(new);

        // focus something
        try self.rebuild_focus_edges();
        if (focus_mod.top_left_window(self)) |n| {
            self.focus(n);
        } else {
            self.clear_focus();
        }
        self.sync_workspace_state();
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
        const old = self.current_graph;

        self.clear_focus();

        while (self.workspace_stack.items.len > target_idx + 1) {
            _ = self.workspace_stack.pop();
        }

        self.current_graph = self.workspace_stack.pop().?;
        self.visible_graph = self.current_graph;

        try self.resolve(self.current_graph);
        try self.rebuild_focus_edges();
        try self.flush(self.current_graph);
        if (old.parent_node) |pn| {
            self.repaint_preview(pn);
        }
        if (focus_mod.top_left_window(self)) |n| self.focus(n) else {
            self.clear_focus();
        }
        self.sync_workspace_state();
    }

    pub fn send_to_workspace(self: *WM, node_id: u32, target_graph: *graph_mod.Graph) !void {
        const node = self.node_registry.get(node_id) orelse return error.InvalidNode;
        const src_graph = node.owner_graph orelse return error.InvalidNode;
        if (src_graph == target_graph) return;

        // Remove from source graph
        for (src_graph.nodes.items, 0..) |n, i| {
            if (n == node) {
                _ = src_graph.nodes.swapRemove(i);
                break;
            }
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
            if (src_graph.fullscreen_node == node) src_graph.fullscreen_node = null;
            self.clear_focus();
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

        if (!node.floating) {
            self.call_arranger(target_graph, "map", node_id, target_prev_id);
        }

        // Hide frame if target is not visible
        if (target_graph != saved_graph) {
            if (node_window(node)) |h| self.backend.hide_window(h);
        } else {
            self.resolve(target_graph) catch {};
            self.rebuild_focus_edges() catch {};
            self.flush(target_graph) catch {};
        }

        self.current_graph = saved_graph;
        switch (node.content) {
            .window => |win| self.sync_window_workspace(win),
            else => {},
        }
        self.sync_workspace_state();
    }

    pub fn sync_workspace_state(self: *WM) void {
        const parent_graph: *graph_mod.Graph = if (self.current_graph.parent_node) |pn|
            pn.owner_graph orelse &self.graph
        else
            &self.graph;

        var count: u32 = 0;
        var current: u32 = 0;
        for (parent_graph.nodes.items) |node| {
            if (node.content != .workspace) continue;
            if (node.content.workspace == self.current_graph) current = count;
            count += 1;
        }
        self.backend.publish_workspaces(@max(count, 1), current);

        var client_list: std.ArrayListUnmanaged(types.WindowHandle) = .empty;
        defer client_list.deinit(self.allocator);
        var it = self.window_to_node_id.iterator();
        while (it.next()) |entry| {
            const node = self.node_registry.get(entry.value_ptr.*) orelse continue;
            if (node.content != .window) continue;
            client_list.append(self.allocator, entry.key_ptr.*) catch {};
        }
        self.backend.publish_window_list(client_list.items);
    }

    pub fn sync_window_workspace(self: *WM, win: types.WindowHandle) void {
        const node_id = self.window_to_node_id.get(win) orelse return;
        const node = self.node_registry.get(node_id) orelse return;
        const owner = node.owner_graph orelse return;

        const parent_graph: *graph_mod.Graph = if (owner.parent_node) |pn|
            pn.owner_graph orelse &self.graph
        else
            &self.graph;

        var idx: u32 = 0;
        for (parent_graph.nodes.items) |n| {
            if (n.content != .workspace) continue;
            if (n.content.workspace == owner) break;
            idx += 1;
        }
        self.backend.publish_window_workspace(win, idx);
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

    pub fn regrab_keys(self: *WM) void {
        var it = self.keybinds.keyIterator();
        while (it.next()) |k| self.backend.grab_key(k.*);
    }

    /// Run whatever is bound to combo, if anything.
    pub fn handle_key(self: *WM, combo: KeybindKey) void {
        const kb = self.keybinds.get(combo) orelse return;
        switch (kb) {
            .zig => |action| action(self) catch |err| {
                std.debug.print("Keybinding error: {}\n", .{err});
            },
            .lua => |ref| {
                const lua = self.lua orelse return;
                const top = lua.getTop();
                _ = lua.getIndexRaw(ziglua.registry_index, ref);
                lua.protectedCall(.{ .args = 0, .results = 0 }) catch |err| {
                    const msg = lua.toString(-1) catch null;
                    std.debug.print("Lua keybinding error: {} {s}\n", .{ err, msg orelse "" });
                    lua.setTop(top);
                };
            },
        }
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

    pub fn kill_graph_windows(self: *WM, g: *graph_mod.Graph) void {
        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => |win| {
                    self.backend.unframe(win, true);
                    self.backend.close_window(win);
                    if (self.window_to_node_id.get(win)) |id| {
                        _ = self.node_registry.remove(id);
                        _ = self.window_to_node_id.remove(win);
                    }
                },
                .workspace => |sub| self.kill_graph_windows(sub),
                .empty => {},
            }
        }
    }

    pub fn cleanup_left_behind(self: *WM, og: *Graph) void {
        var i: usize = 0;
        while (i < og.nodes.items.len) {
            const node = og.nodes.items[i];
            if (node.content != .workspace or node.preview_window != null) {
                i += 1;
                continue;
            }
            if (!self.graph_has_content(node.content.workspace)) {
                i += 1;
                continue;
            }
            self.kill_graph_windows(node.content.workspace);
            og.remove_node(node);
        }
    }

    pub fn set_autoclean(self: *WM, enabled: bool) void {
        self.autoclean = enabled;
    }

    pub fn kill_client(self: *WM) !void {
        const node = self.focused orelse return;
        switch (node.content) {
            .window => |win| self.backend.close_window(win),
            .workspace => {
                if (node.content.workspace == self.current_graph) {
                    try self.leave_workspace();
                }
                // Detect hidden (no-preview) sibling workspaces that still hold windows.
                var cleanup_graph: ?*Graph = null;
                if (node.owner_graph) |og| {
                    const killed_level = node.content.workspace.id.level;
                    for (og.nodes.items) |sibling| {
                        if (sibling == node) continue;
                        if (sibling.content != .workspace) continue;
                        if (sibling.content.workspace.id.level != killed_level) continue;
                        if (sibling.preview_window != null) continue;
                        if (self.graph_has_content(sibling.content.workspace)) {
                            cleanup_graph = og;
                            break;
                        }
                    }
                }

                // Kill the targeted workspace itself.
                self.kill_graph_windows(node.content.workspace);
                if (node.preview_window) |pw| {
                    self.backend.destroy_preview_window(pw);
                }

                // sweep silently when autoclean is on, else prompt.
                if (cleanup_graph) |og| {
                    if (self.autoclean) {
                        self.cleanup_left_behind(og);
                    } else {
                        self.pending_cleanup_graph = og;
                        self.notify("Windows left behind", "Hidden workspaces still have windows open");
                    }
                }
            },
            else => {},
        }
    }

    pub fn graph_has_content(self: *WM, g: *graph_mod.Graph) bool {
        for (g.nodes.items) |node| {
            switch (node.content) {
                .window => return true,
                .workspace => |sub| if (self.graph_has_content(sub)) return true,
                .empty => {},
            }
        }
        return false;
    }

    pub fn notify(self: *WM, summary: []const u8, body: []const u8) void {
        const cmd = std.fmt.allocPrint(
            self.allocator,
            "action=$(notify-send -a duckwm -t 0 --action 'default=Clean up' --wait '{s}' '{s}'); " ++
                "[ \"$action\" = default ] && quack cleanup_left_behind",
            .{ summary, body },
        ) catch return;
        defer self.allocator.free(cmd);
        const argv = [_][]const u8{ "sh", "-c", cmd };
        self.spawn(&argv) catch {};
    }

    /// Recompute and push the current layout. Becomes mark_dirty once commits land.
    pub fn relayout(self: *WM) void {
        self.resolve(self.current_graph) catch {};
        self.rebuild_focus_edges() catch {};
        self.flush(self.current_graph) catch {};
    }

    pub fn show_error(self: *WM, msg: []const u8) void {
        std.debug.print("duckwm error: {s}\n", .{msg});
        self.backend.show_error(msg) catch |err| {
            std.debug.print("duckwm: could not show error bar: {}\n", .{err});
            return;
        };
        self.relayout();
    }

    pub fn hide_error(self: *WM) void {
        if (self.backend.hide_error()) self.relayout();
    }

    pub fn sync_constraints_from_geometry(self: *WM) void {
        for (self.current_graph.nodes.items) |node| {
            if (node.floating) continue;
            for (node.constraints.items) |*con| {
                switch (con.*) {
                    .fixed_x => |*v| v.* = node.x,
                    .fixed_y => |*v| v.* = node.y,
                    .fixed_width => |*v| v.* = node.width,
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
        sub.on_node_free = on_node_freed;
        sub.on_node_free_ctx = self;
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
        const sub = try self.create_workspace_graph(owner_graph.id.level + 1);
        const node = try owner_graph.add_node(.{ .workspace = sub });
        sub.parent_node = node;
        node.floating = false;
        node.hidden = true;
        node.preview_window = try self.backend.create_preview_window(self.frame_options(node));
        self.repaint_preview(node);
        return node;
    }

    /// Create the very first workspace node in the top-level graph.
    /// This is called once in `run` so that Super+Ctrl+1 always works
    /// and the screen is never empty.
    pub fn create_initial_workspace(self: *WM) !void {
        // Root container
        const root_node = try self.current_graph.add_node(.empty);
        root_node.width = self.screen_width;
        root_node.height = self.screen_height;
        root_node.x = 0;
        root_node.y = 0;
        _ = try self.register_node(null, root_node);

        // Workspace sub-graph
        const sub = try self.create_workspace_graph(1);

        const ws_node = try self.current_graph.add_node(.{ .workspace = sub });
        sub.parent_node = ws_node;
        ws_node.floating = false;
        const pw = try self.backend.create_preview_window(self.frame_options(ws_node));
        ws_node.preview_window = pw;
        _ = try self.register_node(pw, ws_node);

        // Constraint to fill root
        const g = graph_mod.Constraint{ .grid_cell = .{
            .col = 0,
            .row = 0,
            .cols = 1,
            .rows = 1,
            .container = root_node,
        } };
        try self.current_graph.add_constraint(ws_node, g);

        // Resolve, paint, then enter
        try self.resolve(self.current_graph);
        try self.rebuild_focus_edges();
        try self.flush(self.current_graph);
        self.repaint_preview(ws_node); // paint while still on parent graph
        try self.enter_workspace(ws_node);
    }

    pub fn handle_event(self: *WM, ev: types.Event) void {
        switch (ev) {
            .key => |k| self.handle_key(k),
            .expose => |h| self.window_exposed(h),
            .keymap_changed => self.regrab_keys(),
            .reserved_area_changed => {
                const size = self.backend.screen_size();
                self.screen_width = size.width;
                self.screen_height = size.height;
                self.relayout();
            },
            .map_request => |req| lifecycle.window_mapped(self, req) catch |err|
                std.debug.print("map_request: {}\n", .{err}),
            .window_gone => |h| lifecycle.window_gone(self, h) catch |err|
                std.debug.print("window_gone: {}\n", .{err}),
            .refocus => if (self.focused) |n| self.focus(n),
            .info_changed => |h| requests.info_changed(self, h),
            .urgency_hint => |hint| requests.urgency_hint(self, hint),
            .became_dock => |h| self.unmanage_as_dock(h) catch |err|
                std.debug.print("became_dock: {}\n", .{err}),
            .activate_request => |h| requests.activate(self, h),
            .state_request => |r| requests.state_request(self, r) catch |err|
                std.debug.print("state_request: {}\n", .{err}),
            .button_press => |b| pointer.button_press(self, b),
            .button_release => pointer.button_release(self),
            .pointer_motion => |p| pointer.motion(self, p),
            .pointer_enter => |h| pointer.enter(self, h),
        }
    }

    fn window_exposed(self: *WM, h: types.WindowHandle) void {
        const id = self.window_to_node_id.get(h) orelse return;
        const node = self.node_registry.get(id) orelse return;
        self.paint_borders(node, null);
        if (node.content == .workspace) self.repaint_preview(node);
    }

    pub fn run(self: *WM) !void {
        self.current_graph = &self.graph;
        self.graph.on_node_free = on_node_freed;
        self.graph.on_node_free_ctx = self;
        self.backend.start() catch |err| {
            std.debug.print("duckwm: backend failed to start: {}\n", .{err});
            return;
        };
        try self.create_initial_workspace();
        self.scratch_graph = try self.create_workspace_graph(1);
        self.visible_graph = self.current_graph;

        if (self.post_load_error) |msg| {
            self.show_error(msg);
            self.allocator.free(msg);
            self.post_load_error = null;
        }

        self.startup_done = true;
        self.commit();

        try self.init_ipc();
        const x11_fd = self.backend.event_fd();

        while (true) {
            var fds_buf: [3]std.posix.pollfd = undefined;
            var nfds: usize = 2;
            fds_buf[0] = .{ .fd = x11_fd, .events = std.posix.POLL.IN, .revents = 0 };
            fds_buf[1] = .{ .fd = self.ipc_fd, .events = std.posix.POLL.IN, .revents = 0 };
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

            while (self.backend.next_event()) |ev| self.handle_event(ev);

            if (self.pending_reload) {
                self.pending_reload = false;
                if (self.reload_fn) |f| f(self);
            }
            self.commit();
            self.backend.flush_output();
        }
    }
};
