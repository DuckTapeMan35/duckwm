const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const pointer = @import("pointer.zig");
const windows = @import("windows.zig");
const outputs_ = @import("outputs.zig");
const keys = @import("keys.zig");

const wl = wayland.client.wl;
const wayluck = wayland.client.wayluck;

const State = @import("state.zig").State;

const manager_version = 1;

pub const Backend = struct {
    allocator: std.mem.Allocator,
    state: *State,

    // ---- lifecycle ----
    /// Connect, bind the manager, and wait for what wayluck has (outputs,
    /// windows) before core starts.
    pub fn init(allocator: std.mem.Allocator) !Backend {
        const display = wl.Display.connect(null) catch return error.CannotOpenDisplay;
        errdefer display.disconnect();
        const registry = try display.getRegistry();

        const s = try allocator.create(State);
        errdefer allocator.destroy(s);
        s.* = .{ .allocator = allocator, .display = display, .registry = registry };

        registry.setListener(*State, registry_listener, s);
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        const manager = s.manager orelse return error.NotRunningUnderWayluck;
        manager.setListener(*State, manager_listener, s);
        while (!s.ready and !s.unavailable) {
            if (display.dispatch() != .SUCCESS) return error.RoundtripFailed;
        }
        if (s.unavailable) return error.AnotherWmRunning;

        return .{ .allocator = allocator, .state = s };
    }

    pub fn deinit(self: *Backend) void {
        const s = self.state;
        for (s.outputs.items) |o| {
            o.obj.destroy();
            s.allocator.destroy(o);
        }
        s.outputs.deinit(s.allocator);
        var it = s.windows.valueIterator();
        while (it.next()) |w| {
            w.*.obj.destroy();
            s.allocator.destroy(w.*);
        }
        s.windows.deinit(s.allocator);
        s.fresh.deinit(s.allocator);
        s.scene.deinit(s.allocator);
        keys.ungrab_all(s);
        s.bindings.deinit(s.allocator);
        pointer.ungrab_all(s);
        s.buttons.deinit(s.allocator);
        s.events.deinit(s.allocator);
        if (s.manager) |m| m.destroy();
        s.display.disconnect();
        self.allocator.destroy(s);
    }

    pub fn start(self: *Backend) !void {
        _ = self; // everything happens in init
    }

    pub fn event_fd(self: *const Backend) i32 {
        return self.state.display.getFd();
    }

    pub fn next_event(self: *Backend) ?types.Event {
        const s = self.state;
        if (s.event_head == s.events.items.len) s.pump();
        if (s.event_head < s.events.items.len) {
            defer s.event_head += 1;
            return s.events.items[s.event_head];
        }
        s.events.clearRetainingCapacity();
        s.event_head = 0;
        return null;
    }

    /// End of core's turn: what it asked for goes to wayluck as one transaction.
    pub fn flush_output(self: *const Backend) void {
        windows.commit(self.state);
        _ = self.state.display.flush();
    }

    pub fn sync(self: *const Backend) void {
        _ = self;
    }

    /// Nothing to ask wayluck for yet; it ends when it's closed.
    pub fn end_session(self: *Backend) void {
        _ = self;
    }

    pub fn poll_timeout(self: *const Backend) i32 {
        _ = self;
        return -1;
    }

    // ---- screen ----
    /// The first output's size (core asks before it reads outputs).
    pub fn screen_size(self: *const Backend) types.Size {
        const s = self.state;
        if (s.outputs.items.len == 0) return .{ .width = 1920, .height = 1080 };
        const r = s.outputs.items[0].rect;
        return .{ .width = r.width, .height = r.height };
    }

    pub fn reserved_insets(self: *const Backend) types.Insets {
        _ = self;
        return .{};
    }

    pub fn outputs(self: *Backend, buf: []types.OutputInfo) []types.OutputInfo {
        return outputs_.list(self.state, buf);
    }

    // ---- publishing: nothing listens ----
    pub fn publish_work_area(self: *const Backend, r: types.Rect) void {
        _ = self;
        _ = r;
    }

    pub fn publish_workspaces(self: *const Backend, count: u32, current: u32) void {
        _ = self;
        _ = count;
        _ = current;
    }

    pub fn publish_window_list(self: *const Backend, hs: []const types.WindowHandle) void {
        _ = self;
        _ = hs;
    }

    pub fn publish_window_workspace(self: *const Backend, h: types.WindowHandle, i: u32) void {
        _ = self;
        _ = h;
        _ = i;
    }

    pub fn publish_window_fullscreen(self: *const Backend, h: types.WindowHandle, on: bool) void {
        _ = self;
        _ = h;
        _ = on;
    }

    pub fn publish_frame_extents(self: *const Backend, bw: u32) void {
        _ = self;
        _ = bw;
    }

    // ---- windows ----
    pub fn window_info(self: *const Backend, h: types.WindowHandle) types.WindowInfo {
        const w = self.state.windows.get(h) orelse return .{};
        return w.info;
    }

    pub fn window_traits(self: *const Backend, h: types.WindowHandle) types.WindowTraits {
        _ = self;
        _ = h;
        return .{};
    }

    /// What its client asked for before core knew it.
    pub fn window_hints(self: *const Backend, h: types.WindowHandle) types.InitialHints {
        const w = self.state.windows.get(h) orelse return .{};
        return .{ .fullscreen = w.wants_fullscreen };
    }

    pub fn frame_window(self: *Backend, h: types.WindowHandle, opts: types.FrameOptions) !void {
        _ = self;
        _ = h;
        _ = opts;
    }

    pub fn unframe(self: *Backend, h: types.WindowHandle, keep: bool) void {
        _ = self;
        _ = h;
        _ = keep;
    }

    /// Recorded; the test decides whether the client goes (push window_gone).
    pub fn close_window(self: *Backend, h: types.WindowHandle) void {
        const w = self.state.windows.get(h) orelse return;
        w.obj.close();
    }

    pub fn release_window(self: *Backend, h: types.WindowHandle) void {
        _ = self;
        _ = h;
    }

    pub fn apply_windows(self: *Backend, states: []const types.WindowState, fullscreen: ?types.WindowHandle) void {
        windows.apply(self.state, states, fullscreen);
    }

    pub fn apply_outlines(self: *Backend, list: []const types.Outline) void {
        _ = self;
        _ = list;
    }

    pub fn hide_window(self: *Backend, h: types.WindowHandle) void {
        windows.hide(self.state, h);
    }

    pub fn raise_window(self: *Backend, h: types.WindowHandle) void {
        windows.raise(self.state, h);
    }

    pub fn draw_borders(self: *Backend, h: types.WindowHandle, colors: types.BorderColors, width: u32, size: ?types.Size) void {
        _ = size;
        windows.border(self.state, h, colors, width);
    }

    pub fn set_input_focus(self: *Backend, h: ?types.WindowHandle, publish: bool) bool {
        _ = publish; // nothing to publish to yet
        return windows.focus(self.state, h);
    }

    // ---- WM-owned windows ----
    /// A handle core can keep; nothing is drawn yet.
    pub fn create_preview_window(self: *Backend, opts: types.FrameOptions) !types.WindowHandle {
        _ = opts;
        defer self.state.next_preview += 1;
        return self.state.next_preview;
    }

    pub fn destroy_preview_window(self: *Backend, h: types.WindowHandle) void {
        _ = self;
        _ = h;
    }

    pub fn draw_preview(self: *Backend, h: types.WindowHandle, size: types.Size, style: types.PreviewStyle, items: []const types.PreviewItem) void {
        _ = self;
        _ = h;
        _ = size;
        _ = style;
        _ = items;
    }

    pub fn show_error(self: *Backend, msg: []const u8) !void {
        _ = self;
        std.debug.print("duckwm error: {s}\n", .{msg});
    }

    pub fn hide_error(self: *Backend) bool {
        _ = self;
        return false;
    }

    pub fn show_prompt(self: *Backend, label: []const u8, text: []const u8, cursor: usize, block: bool) !void {
        _ = self;
        _ = label;
        _ = text;
        _ = cursor;
        _ = block;
    }

    pub fn show_message(self: *Backend, text: []const u8, timeout_ms: u32) !void {
        _ = self;
        _ = text;
        _ = timeout_ms;
    }

    pub fn hide_prompt(self: *Backend) void {
        _ = self;
    }

    // ---- input: wayluck doesn't hand any to the window manager yet ----
    pub fn keysym_from_name(self: *const Backend, name: []const u8) ?types.Keysym {
        _ = self;
        return keys.keysym_from_name(name);
    }

    pub fn keysym_name(self: *const Backend, ks: types.Keysym, buf: []u8) ?[]const u8 {
        _ = self;
        return keys.keysym_name(ks, buf);
    }

    pub fn grab_key(self: *const Backend, k: types.KeyCombo) void {
        keys.grab(self.state, k);
    }

    pub fn ungrab_all_keys(self: *const Backend) void {
        keys.ungrab_all(self.state);
    }

    pub fn set_pointer_grabs(self: *Backend, grabs: []const types.PointerGrab) void {
        pointer.set_grabs(self.state, grabs);
    }

    pub fn set_click_to_focus(self: *Backend, enabled: bool) void {
        self.state.click_to_focus = enabled;
    }

    /// A drag starts: motion reaches core as pointer_motion until release.
    pub fn capture_pointer(self: *const Backend) void {
        pointer.capture(self.state);
    }

    pub fn release_pointer(self: *const Backend) void {
        pointer.release(self.state);
    }

    pub fn pointer_position(self: *const Backend) types.Point {
        return self.state.pointer_pos;
    }

    pub fn warp_pointer(self: *const Backend, p: types.Point) void {
        const s = self.state;
        s.pointer_pos = p;
        if (s.manager) |m| m.warpPointer(p.x, p.y);
    }

    pub fn set_cursor_theme(self: *const Backend, theme: []const u8, size: u32) void {
        _ = self;
        _ = theme;
        _ = size;
    }

    pub fn set_keymap(self: *Backend, km: types.Keymap) bool {
        return keys.set_keymap(self.state, km);
    }

    pub fn set_layout_index(self: *Backend, index: u32) void {
        keys.set_layout(self.state, index);
    }

    pub fn set_animation(self: *Backend, a: types.Animation) void {
        _ = self;
        _ = a;
    }
};

/// Bind the manager when the registry announces it.
fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, s: *State) void {
    switch (event) {
        .global => |g| {
            if (std.mem.orderZ(u8, g.interface, wayluck.WmManagerV1.interface.name) == .eq) {
                s.manager = registry.bind(g.name, wayluck.WmManagerV1, @min(g.version, manager_version)) catch null;
            }
        },
        .global_remove => {},
    }
}

fn manager_listener(_: *wayluck.WmManagerV1, event: wayluck.WmManagerV1.Event, s: *State) void {
    switch (event) {
        .unavailable => s.unavailable = true,
        .output => |e| outputs_.add(s, e.id),
        .window => |e| windows.add(s, e.id),
        .ready => s.ready = true,
        .pointer_position => |e| pointer.moved(s, .{ .x = e.x, .y = e.y }),
    }
}
