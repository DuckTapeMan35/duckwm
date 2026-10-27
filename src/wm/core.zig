const std = @import("std");
const ziglua = @import("ziglua");
const graph = @import("graph");
const protocol = @import("protocol");
const focus = @import("focus.zig");
const resize = @import("resize.zig");
const float = @import("float.zig");
const ipc = @import("ipc.zig");
const preview = @import("preview.zig");
const backend_mod = @import("backend.zig");
const types = @import("types");
const tx = @import("tx.zig");
const scene = @import("scene.zig");
const registry = @import("registry.zig");
const navigation = @import("navigation.zig");
const window_ops = @import("window_ops.zig");
const callbacks = @import("callbacks.zig");
const settings = @import("settings.zig");
const events = @import("events.zig");
const loop = @import("loop.zig");
const swallow = @import("swallow.zig");
const startup = @import("startup.zig");
const prompt = @import("prompt.zig");
const input_bar = @import("input_bar.zig");
const output_mod = @import("output.zig");
const scopes = @import("scopes.zig");
const workspace_settings = @import("workspace_settings.zig");

const Graph = graph.Graph;
const Node = graph.Node;
const Direction = graph.Direction;
const Backend = backend_mod.Backend;
const Lua = ziglua.Lua;
const Tx = tx.Tx;
const Effect = tx.Effect;

pub const WM = struct {
    // ---- platform ----
    allocator: std.mem.Allocator,
    /// X11 or river, chosen at build time.
    backend: Backend,
    /// Output size, refreshed when the reserved area changes.
    screen_width: u32,
    screen_height: u32,

    // ---- graphs and workspaces ----
    /// Every output; each has its own workspaces.
    outputs: std.ArrayListUnmanaged(*output_mod.Output) = .empty,
    /// The output commands, new windows and arrangers act on; the navigation
    /// fields below are its.
    output: *output_mod.Output = undefined,
    /// The focused output's root graph: its workspaces.
    root: *Graph = undefined,
    /// The workspace commands and arrangers act on.
    current_graph: *Graph = undefined,
    /// The workspace on screen. Differs from current_graph only while an
    /// operation temporarily works in another workspace.
    visible_graph: *Graph = undefined,
    /// Where switch mode "previous" goes back to.
    previous_graph: ?*Graph = null,
    workspace_switch_mode: navigation.WorkspaceSwitchMode = .none,
    /// The workspaces entered on the way to the current one, outermost first.
    workspace_stack: std.ArrayListUnmanaged(*Graph) = .empty,
    /// Next workspace number per nesting level.
    next_workspace_number: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    /// Hidden workspace that holds scratchpad windows.
    scratch_graph: *Graph = undefined,
    /// Undo log for transactions.
    journal: graph.Journal,

    // ---- node ids ----
    /// The ids the APIs use. Entries are removed when a node is freed at commit.
    node_registry: std.AutoHashMapUnmanaged(u32, *Node) = .empty,
    /// Window (or preview window) to node id.
    window_to_node_id: std.AutoHashMapUnmanaged(types.WindowHandle, u32) = .empty,
    next_node_id: u32 = 1,

    // ---- focus ----
    focused: ?*Node = null,
    /// Ticks on every focus change; orders nodes by when they were last focused.
    focus_clock: u64 = 0,
    focus_follows_mouse: bool = true,
    /// The setting to restore once a drag ends; drags suspend focus-follows-mouse.
    saved_focus_follows_mouse: bool = true,
    ffm_suspended: bool = false,
    click_to_focus: bool = false,
    /// > 0 while an arranger or rule runs: focus can't move to another output
    /// then, as that would swap workspaces out from under the code that called it.
    hold_output: u32 = 0,

    // ---- commit ----
    /// The scene from the last commit: the desired state of every visible window.
    scene: std.ArrayListUnmanaged(types.WindowState) = .empty,
    /// How many scenes have gone to the backend: get_scene's serial.
    scene_serial: u64 = 0,
    /// The fullscreen window of the last scene, if any.
    scene_fullscreen: ?types.WindowHandle = null,
    /// Recompute and apply the scene at the next commit.
    scene_dirty: bool = false,
    /// Group outlines to draw, rebuilt with the scene.
    outlines: std.ArrayListUnmanaged(types.Outline) = .empty,
    /// Send input focus at the next commit.
    focus_dirty: bool = false,
    /// Round-trip with the display server at the next commit.
    sync_on_commit: bool = false,
    /// Set while the scene is being applied.
    flushing: bool = false,
    /// Side effects deferred until the outermost transaction commits.
    effects: std.ArrayListUnmanaged(Effect) = .empty,

    // ---- appearance ----
    border_width: i32 = 2,
    default_border_color_focused: u32 = 0x5294e2,
    default_border_color_unfocused: u32 = 0x333333,
    default_border_color_urgent: u32 = 0xe53935,
    /// Color of every node's indicator side.
    indicator_color: u32 = 0xf9e2af,
    /// Per-side border colors only on the focused window.
    border_side_colors_focused_only: bool = true,
    /// Gaps given to new workspaces.
    default_gap_inner_h: u32 = 0,
    default_gap_inner_v: u32 = 0,
    default_gap_outer_h: u32 = 0,
    default_gap_outer_v: u32 = 0,
    /// Use 32-bit (ARGB) frames where the client supports it.
    argb_frames: bool = true,
    /// Window classes that always get RGB frames.
    rgb_frame_classes: std.ArrayListUnmanaged([]const u8) = .empty,
    preview_defaults: preview.Defaults = .{},
    /// Scratch buffer for laying out previews, reused across repaints.
    preview_items: std.ArrayListUnmanaged(types.PreviewItem) = .empty,
    /// Outline drawn around every group (width 0: none), unless the group sets its own.
    group_outline_width: u32 = 0,
    /// Group border color when unfocused; 0: not drawn (the room is still kept).
    group_outline_color: u32 = 0,

    // ---- config state ----
    lua: ?*Lua = null,
    keybinds: std.AutoHashMapUnmanaged(settings.BindKey, settings.Keybind) = .empty,
    /// While a factory runs: the workspace its binds belong to.
    bind_owner: ?*Graph = null,
    /// Every path a bind was made within (scopes.zig), once each.
    scope_paths: std.ArrayListUnmanaged([]const u8) = .empty,
    /// The Lua config's scope, inside wm.within.
    lua_scope: u32 = 0,
    /// Gaps and preview settings made within a path (workspace_settings.zig).
    workspace_settings: std.ArrayListUnmanaged(workspace_settings.Entry) = .empty,
    /// Rules, in the order they were added.
    rules: std.ArrayListUnmanaged(callbacks.Rule) = .empty,
    next_rule_id: u32 = 1,
    /// Factory for the arranger of workspaces that don't set their own (0: none).
    default_arranger: ?types.Callback = null,
    default_arranger_name: []const u8 = "",
    /// an encoded Request run after the Lua config.
    commands_path: ?[]const u8 = null,
    /// True until the first config load and the commands file have run: exec_once spawns only then.
    initial_load: bool = true,
    /// Set while Lua runs a command; command.Callback ids are Lua refs then.
    callback_source: types.CallbackSource = .none,
    prompt: prompt.Editor = .{},
    /// read_line's callback while the bar is open.
    prompt_cb: ?types.Callback = null,

    // ---- window behavior ----
    /// Terminal/child class pairs for swallowing.
    swallow_pairs: std.ArrayListUnmanaged(swallow.SwallowPair) = .empty,
    /// Silently close windows left in hidden workspaces when their parent is closed.
    autoclean: bool = true,
    /// Workspace whose hidden children still hold windows, awaiting
    /// cleanup_left_behind (when autoclean is off).
    pending_cleanup_graph: ?*Graph = null,

    // ---- pointer drags: edge and corner resize ----
    resize_modifier: ?types.Mods = null,
    edge_resizing: bool = false,
    edge_is_vertical: bool = false,
    /// The edge being dragged.
    edge_x: i32 = 0,
    edge_y: i32 = 0,
    /// Pointer position at the last processed motion.
    resize_end_x: i32 = 0,
    resize_end_y: i32 = 0,
    corner_resizing: bool = false,
    /// The two edges a corner resize moves.
    resize_v_edge: i32 = 0,
    resize_h_edge: i32 = 0,
    /// The corner that stays put during a corner resize.
    resize_fixed_x: i32 = 0,
    resize_fixed_y: i32 = 0,
    /// The window being resized.
    resize_window: types.WindowHandle = 0,
    /// Throttle: time and edge position of the last update pushed to the screen.
    last_resize_flush: i64 = 0,
    resize_refresh_interval: i64 = 16, // ms
    last_flushed_edge_x: i32 = -1,
    last_flushed_edge_y: i32 = -1,

    // ---- pointer drags: moving and resizing floats ----
    float_move_modifier: ?types.Mods = null,
    float_move_button: types.Button = 1, // left
    float_resize_button: types.Button = 3, // right
    float_moving: bool = false,
    float_move_window: types.WindowHandle = 0,
    /// Pointer position and window position when the drag started.
    float_move_start_x: i32 = 0,
    float_move_start_y: i32 = 0,
    float_win_start_x: i32 = 0,
    float_win_start_y: i32 = 0,
    /// The node a mod+drag moves or resizes (a floating window, or a floating
    /// group around the window clicked), by id.
    float_target: ?u32 = null,

    // ---- pointer drags: panning ----
    pan_modifier: ?types.Mods = null,
    pan_button: types.Button = 2, // middle
    pan_dragging: bool = false,
    /// Pointer position and pan offset when the drag started.
    pan_drag_start_x: i32 = 0,
    pan_drag_start_y: i32 = 0,
    pan_drag_start_pan_x: i32 = 0,
    pan_drag_start_pan_y: i32 = 0,

    // ---- IPC ----
    ipc_state: ipc.State = .{},

    // ---- config loading and reloading ----
    /// Watches the config directory (-1: not watching).
    inotify_fd: i32 = -1,
    inotify_wd: i32 = -1,
    /// Reloads the config; set by the Lua frontend once a config has loaded.
    reload_fn: ?*const fn (*WM) void = null,
    /// Set by the Lua module: runs the eval command.
    eval_fn: ?*const fn (*WM, []const u8, std.mem.Allocator) anyerror!protocol.Value = null,
    /// A reload requested from Lua, run after the current event.
    pending_reload: bool = false,
    /// Debounce for file-change reloads.
    last_reload_time: i64 = 0,
    /// Set after the first config load; exec_once is skipped afterwards.
    startup_done: bool = false,
    /// An error from loading the config, shown once the WM is up.
    post_load_error: ?[]u8 = null,

    pub fn create(allocator: std.mem.Allocator) !WM {
        var backend = try Backend.init(allocator);
        errdefer backend.deinit();
        const size = backend.screen_size();
        backend.publish_work_area(.{ .x = 0, .y = 0, .width = size.width, .height = size.height });
        return .{
            .backend = backend,
            .allocator = allocator,
            .screen_width = size.width,
            .screen_height = size.height,
            .journal = graph.Journal.init(allocator),
        };
    }

    pub fn deinit(self: *WM) void {
        self.rules.deinit(self.allocator);
        for (self.effects.items) |e| tx.drop_effect(self, e);
        var kb_it = self.keybinds.valueIterator();
        while (kb_it.next()) |kb| self.free_keybind(kb.*);
        self.keybinds.deinit(self.allocator);
        self.keybinds = .empty;
        scopes.deinit(self);
        workspace_settings.deinit(self);
        if (self.lua) |lua| lua.deinit();
        self.lua = null;
        if (self.default_arranger_name.len > 0) {
            self.allocator.free(self.default_arranger_name);
        }
        swallow.clear_pairs(self);
        self.prompt.deinit(self.allocator);
        self.preview_items.deinit(self.allocator);
        self.swallow_pairs.deinit(self.allocator);
        self.next_workspace_number.deinit(self.allocator);
        self.effects.deinit(self.allocator);
        self.journal.deinit();
        output_mod.deinit_all(self);
        if (self.startup_done) {
            navigation.free_graph(self, self.scratch_graph);
            self.allocator.destroy(self.scratch_graph);
        }
        self.workspace_stack.deinit(self.allocator);
        self.node_registry.deinit(self.allocator);
        self.window_to_node_id.deinit(self.allocator);
        ipc.deinit(self);
        self.unwatch_file();
        self.backend.deinit();
        self.clear_rgb_frame_classes();
        self.rgb_frame_classes.deinit(self.allocator);
        self.outlines.deinit(self.allocator);
        self.scene.deinit(self.allocator);
    }

    // focus.zig
    pub fn rebuild_focus_edges(self: *WM) !void {
        return focus.rebuild_focus_edges(self);
    }
    pub fn set_focus(self: *WM, node: *Node) void {
        focus.set_focus(self, node);
    }
    pub fn focus_left(self: *WM) anyerror!void {
        try focus.focus_left(self);
    }
    pub fn focus_right(self: *WM) anyerror!void {
        try focus.focus_right(self);
    }
    pub fn focus_up(self: *WM) anyerror!void {
        try focus.focus_up(self);
    }
    pub fn focus_down(self: *WM) anyerror!void {
        try focus.focus_down(self);
    }
    pub fn clear_focus(self: *WM) void {
        focus.clear_focus(self);
    }

    // resize.zig
    pub fn resize_vertical_edge(self: *WM, edge_x: i32, delta: i32, floating: bool) !bool {
        return resize.resize_vertical_edge(self, edge_x, delta, floating);
    }
    pub fn resize_horizontal_edge(self: *WM, edge_y: i32, delta: i32, floating: bool) !bool {
        return resize.resize_horizontal_edge(self, edge_y, delta, floating);
    }
    pub fn resize_edge(self: *WM, node: *Node, dir: Direction, delta: i32) !void {
        return resize.resize_edge(self, node, dir, delta);
    }
    pub fn resize_corner(self: *WM, node: *Node, delta_x: i32, delta_y: i32) !void {
        return resize.resize_corner(self, node, delta_x, delta_y);
    }

    // float.zig
    pub fn toggle_floating(self: *WM) !void {
        return float.toggle_floating(self);
    }
    pub fn set_floating(self: *WM, node: *Node, val: bool) !void {
        return float.set_floating(self, node, val);
    }
    pub fn toggle_fullscreen(self: *WM) !void {
        return float.toggle_fullscreen(self);
    }
    pub fn center_node(self: *WM, node: *Node) void {
        float.center_node(self, node);
    }

    // ipc.zig
    pub fn init_ipc(self: *WM) !void {
        try ipc.init(self);
    }

    // tx.zig
    pub fn tx_begin(self: *WM) Tx {
        return tx.tx_begin(self);
    }
    pub fn tx_end(self: *WM, t: Tx, ok: bool) void {
        tx.tx_end(self, t, ok);
    }
    pub fn tx_finish(self: *WM, t: Tx, ok: bool) bool {
        return tx.tx_finish(self, t, ok);
    }
    pub fn effect(self: *WM, e: Effect) void {
        tx.effect(self, e);
    }
    pub fn spawn(self: *WM, argv: []const []const u8) !void {
        return tx.spawn(self, argv);
    }

    // events.zig
    pub fn handle_event(self: *WM, ev: types.Event) void {
        events.handle_event(self, ev);
    }

    // scene.zig
    pub fn commit(self: *WM) void {
        scene.commit(self);
    }
    pub fn flush(self: *WM, g: *Graph) !void {
        return scene.flush(self, g);
    }
    pub fn relayout(self: *WM) void {
        scene.relayout(self);
    }
    pub fn resolve(self: *WM, g: *Graph) !void {
        return scene.resolve(self, g);
    }
    pub fn get_work_area(self: *WM) types.Rect {
        return scene.get_work_area(self);
    }
    pub fn border_colors(self: *WM, node: *Node) types.BorderColors {
        return scene.border_colors(self, node);
    }
    pub fn paint_borders(self: *WM, node: *Node, size: ?types.Size) void {
        scene.paint_borders(self, node, size);
    }
    pub fn frame(self: *WM, win: types.WindowHandle, node: *Node) !void {
        return scene.frame(self, win, node);
    }
    pub fn frame_options(self: *WM, node: *Node) types.FrameOptions {
        return scene.frame_options(self, node);
    }
    pub fn is_shown(self: *WM, node: *Node) bool {
        return scene.is_shown(self, node);
    }
    pub fn preview_visible(self: *WM, node: *Node) bool {
        return scene.preview_visible(self, node);
    }
    pub fn node_at(self: *WM, p: types.Point) ?*Node {
        return scene.node_at(self, p);
    }

    // registry.zig
    pub fn register_node(self: *WM, win: ?types.WindowHandle, node: *Node) !u32 {
        return registry.register_node(self, win, node);
    }
    pub fn get_node_by_id(self: *WM, id: u32) ?*Node {
        return registry.get_node_by_id(self, id);
    }
    pub fn get_id_for_node(self: *WM, node: *Node) ?u32 {
        return registry.get_id_for_node(self, node);
    }
    pub fn set_node_empty(self: *WM, node_id: u32) void {
        registry.set_node_empty(self, node_id);
    }
    pub fn set_node_window(self: *WM, node_id: u32, win: types.WindowHandle) !void {
        return registry.set_node_window(self, node_id, win);
    }
    pub fn move_window_to_node(self: *WM, src_node_id: u32, dst_node_id: u32) !void {
        return registry.move_window_to_node(self, src_node_id, dst_node_id);
    }

    // navigation.zig
    pub fn enter_workspace(self: *WM, node: *Node) !void {
        return navigation.enter_workspace(self, node);
    }
    pub fn leave_workspace(self: *WM) !void {
        return navigation.leave_workspace(self);
    }
    pub fn activate_window(self: *WM, node: *Node) !void {
        return navigation.activate_window(self, node);
    }
    pub fn send_to_workspace(self: *WM, node_id: u32, target: *Graph) !void {
        return navigation.send_to_workspace(self, node_id, target);
    }
    pub fn sync_workspace_state(self: *WM) void {
        navigation.sync_workspace_state(self);
    }
    pub fn sync_window_workspace(self: *WM, win: types.WindowHandle) void {
        navigation.sync_window_workspace(self, win);
    }
    pub fn create_workspace_graph(self: *WM, level: u32) !*Graph {
        return navigation.create_workspace_graph(self, level);
    }
    pub fn create_workspace_node_with_preview(self: *WM, owner: *Graph) !*Node {
        return navigation.create_workspace_node_with_preview(self, owner);
    }
    pub fn add_workspace_node(self: *WM, parent: *Graph) !*Node {
        return navigation.add_workspace_node(self, parent);
    }
    pub fn create_initial_workspace(self: *WM) !void {
        return navigation.create_initial_workspace(self);
    }

    // window_ops.zig
    pub fn exchange(self: *WM, a: *Node, b: *Node) !void {
        return window_ops.exchange(self, a, b);
    }
    pub fn exchange_left(self: *WM) anyerror!void {
        return window_ops.exchange_left(self);
    }
    pub fn exchange_right(self: *WM) anyerror!void {
        return window_ops.exchange_right(self);
    }
    pub fn exchange_up(self: *WM) anyerror!void {
        return window_ops.exchange_up(self);
    }
    pub fn exchange_down(self: *WM) anyerror!void {
        return window_ops.exchange_down(self);
    }
    pub fn kill_client(self: *WM) !void {
        return window_ops.kill_client(self);
    }
    pub fn kill_graph_windows(self: *WM, g: *Graph) void {
        window_ops.kill_graph_windows(self, g);
    }
    pub fn cleanup_left_behind(self: *WM, og: *Graph) void {
        window_ops.cleanup_left_behind(self, og);
    }
    pub fn graph_has_content(self: *WM, g: *Graph) bool {
        return window_ops.graph_has_content(self, g);
    }
    pub fn show_scratchpad(self: *WM, node_id: u32) !void {
        return window_ops.show_scratchpad(self, node_id);
    }
    pub fn hide_scratchpad(self: *WM, node_id: u32) !void {
        return window_ops.hide_scratchpad(self, node_id);
    }
    pub fn toggle_scratchpad(self: *WM, node_id: u32) !void {
        return window_ops.toggle_scratchpad(self, node_id);
    }
    pub fn unmanage_as_dock(self: *WM, win: types.WindowHandle) !void {
        return window_ops.unmanage_as_dock(self, win);
    }
    pub fn notify(self: *WM, summary: []const u8, body: []const u8) void {
        window_ops.notify(self, summary, body);
    }

    // callbacks.zig
    pub fn call_rules(self: *WM, event_str: [:0]const u8, node_id: u32) void {
        callbacks.call_rules(self, event_str, node_id);
    }
    pub fn call_arranger(self: *WM, g: *Graph, event: protocol.ArrangerEvent, node_id: u32, prev_id: ?u32) void {
        callbacks.call_arranger(self, g, event, node_id, prev_id);
    }
    pub fn handle_key(self: *WM, combo: types.KeyCombo) void {
        callbacks.handle_key(self, combo);
    }
    pub fn release_callback(self: *WM, cb: types.Callback) void {
        callbacks.release(self, cb);
    }
    pub fn instantiate_callback(self: *WM, factory: types.Callback, owner: *Graph) !types.Callback {
        return callbacks.instantiate(self, factory, owner);
    }
    pub fn drop_client_callbacks(self: *WM, client: u32) void {
        callbacks.drop_client(self, client);
    }

    // settings.zig
    pub fn set_preview_max_icon_size(self: *WM, size: u32) void {
        settings.set_preview_max_icon_size(self, size);
    }
    pub fn set_preview_colors(self: *WM, bg: u32, win_bg: u32, border: u32, text: u32) void {
        settings.set_preview_colors(self, bg, win_bg, border, text);
    }
    pub fn set_preview_font(self: *WM, name: []const u8) void {
        settings.set_preview_font(self, name);
    }
    pub fn set_keyboard_layout(self: *WM, km: types.Keymap) bool {
        return settings.set_keyboard_layout(self, km);
    }
    pub fn set_keyboard_layout_index(self: *WM, index: u32) void {
        settings.set_keyboard_layout_index(self, index);
    }
    pub fn end_session(self: *WM) void {
        settings.end_session(self);
    }
    pub fn set_autoclean(self: *WM, enabled: bool) void {
        settings.set_autoclean(self, enabled);
    }
    pub fn watch_file(self: *WM, path: [:0]const u8) void {
        settings.watch_file(self, path);
    }
    pub fn watch_config_dir(self: *WM, dir_path: [:0]const u8) void {
        settings.watch_config_dir(self, dir_path);
    }
    pub fn unwatch_file(self: *WM) void {
        settings.unwatch_file(self);
    }
    pub fn set_click_to_focus(self: *WM, enabled: bool) void {
        settings.set_click_to_focus(self, enabled);
    }
    pub fn sync_pointer_grabs(self: *WM) void {
        settings.sync_pointer_grabs(self);
    }
    pub fn bind(self: *WM, mods: types.Mods, keysym: types.Keysym, action: *const fn (*WM) anyerror!void) !void {
        return settings.bind(self, mods, keysym, action);
    }
    pub fn bind_callback(self: *WM, mods: types.Mods, keysym: types.Keysym, cb: types.Callback) void {
        settings.bind_callback(self, mods, keysym, cb);
    }
    pub fn ungrab_keys(self: *WM) void {
        settings.ungrab_keys(self);
    }
    pub fn regrab_keys(self: *WM) void {
        settings.regrab_keys(self);
    }
    pub fn clear_rgb_frame_classes(self: *WM) void {
        settings.clear_rgb_frame_classes(self);
    }
    pub fn reset_arrangers(self: *WM, g: *Graph) void {
        settings.reset_arrangers(self, g);
    }
    pub fn show_error(self: *WM, msg: []const u8) void {
        settings.show_error(self, msg);
    }
    pub fn hide_error(self: *WM) void {
        settings.hide_error(self);
    }
    pub fn put_keybind(self: *WM, key: settings.BindKey, kb: settings.Keybind) void {
        settings.put_keybind(self, key, kb);
    }
    pub fn remove_keybind(self: *WM, key: settings.BindKey) void {
        settings.remove_keybind(self, key);
    }
    pub fn drop_owned_binds(self: *WM, g: *Graph) void {
        settings.drop_owned_binds(self, g);
    }
    pub fn free_keybind(self: *WM, kb: settings.Keybind) void {
        settings.free_keybind(self, kb);
    }
    pub fn clear_config_binds(self: *WM) void {
        settings.clear_config_binds(self);
    }
    pub fn bind_commands(self: *WM, key: types.KeyCombo, encoded: []const u8) void {
        settings.bind_commands(self, key, encoded);
    }
    pub fn unbind(self: *WM, key: types.KeyCombo) void {
        settings.unbind(self, key);
    }

    // startup.zig
    pub fn run_commands_file(self: *WM) void {
        startup.run_commands_file(self);
    }

    /// Set up without entering the event loop (backend already started).
    pub fn start(self: *WM) !void {
        return loop.start(self);
    }

    // swallow.zig
    pub fn clear_swallow_pairs(self: *WM) void {
        swallow.clear_pairs(self);
    }

    // preview.zig
    pub fn repaint_preview(self: *WM, node: *Node) void {
        preview.repaint_preview(self, node);
    }

    // resize.zig
    pub fn sync_constraints_from_geometry(self: *WM) void {
        resize.sync_constraints_from_geometry(self);
    }

    // loop.zig
    pub fn run(self: *WM) !void {
        return loop.run(self);
    }

    // input_bar.zig
    pub fn cancel_prompt(self: *WM) void {
        input_bar.cancel(self);
    }
};
