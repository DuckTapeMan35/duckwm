const std = @import("std");
const types = @import("types");

/// One client window the test made up.
pub const Window = struct {
    info: types.WindowInfo = .{},
    traits: types.WindowTraits = .{},
    hints: types.InitialHints = .{},
    framed: bool = false,
    closed: bool = false,
};

pub const Backend = struct {
    allocator: std.mem.Allocator,
    screen: types.Size = .{ .width = 1920, .height = 1080 },

    /// Events for core, oldest first.
    events: std.ArrayListUnmanaged(types.Event) = .empty,
    event_head: usize = 0,

    windows: std.AutoHashMapUnmanaged(types.WindowHandle, Window) = .empty,
    /// Previews get handles far from the ones tests pick for windows.
    next_preview: types.WindowHandle = 1 << 32,

    // What core asked for most recently.
    scene: std.ArrayListUnmanaged(types.WindowState) = .empty,
    fullscreen: ?types.WindowHandle = null,
    outlines: std.ArrayListUnmanaged(types.Outline) = .empty,
    focused: ?types.WindowHandle = null,
    error_shown: bool = false,

    /// The one output's connector name (tests rename it).
    output_name: []const u8 = "FAKE-1",

    // ---- what tests use ----
    /// Queue an event for core's next next_event.
    pub fn push(self: *Backend, ev: types.Event) void {
        self.events.append(self.allocator, ev) catch @panic("OOM");
    }

    /// A new client window: remembered, and its map request queued.
    pub fn map(self: *Backend, h: types.WindowHandle, w: Window) void {
        self.windows.put(self.allocator, h, w) catch @panic("OOM");
        self.push(.{ .map_request = .{
            .window = h,
            .size = .{ .width = 640, .height = 480 },
            .traits = w.traits,
        } });
    }

    /// The keysym keysym_from_name gives name: made up, but always the same.
    pub fn keysym(name: []const u8) types.Keysym {
        return @truncate(std.hash.Wyhash.hash(0, name));
    }

    /// The window's frame in the last scene, if it's in it.
    pub fn frame_of(self: *const Backend, h: types.WindowHandle) ?types.Rect {
        for (self.scene.items) |st| {
            if (st.handle == h) return st.frame;
        }
        return null;
    }

    // ---- lifecycle ----
    pub fn init(allocator: std.mem.Allocator) !Backend {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Backend) void {
        self.events.deinit(self.allocator);
        self.windows.deinit(self.allocator);
        self.scene.deinit(self.allocator);
        self.outlines.deinit(self.allocator);
    }

    pub fn start(self: *Backend) !void {
        _ = self;
    }

    /// Never polled: tests drive the loop themselves.
    pub fn event_fd(self: *const Backend) i32 {
        _ = self;
        return -1;
    }

    pub fn next_event(self: *Backend) ?types.Event {
        if (self.event_head == self.events.items.len) {
            self.events.clearRetainingCapacity();
            self.event_head = 0;
            return null;
        }
        defer self.event_head += 1;
        return self.events.items[self.event_head];
    }

    pub fn flush_output(self: *const Backend) void {
        _ = self;
    }

    pub fn sync(self: *const Backend) void {
        _ = self;
    }

    pub fn end_session(self: *Backend) void {
        _ = self;
    }

    pub fn poll_timeout(self: *const Backend) i32 {
        _ = self;
        return -1;
    }

    // ---- screen ----
    pub fn screen_size(self: *const Backend) types.Size {
        return self.screen;
    }

    pub fn reserved_insets(self: *const Backend) types.Insets {
        _ = self;
        return .{};
    }

    /// One monitor, the whole screen.
    pub fn outputs(self: *Backend, buf: []types.OutputInfo) []types.OutputInfo {
        const r: types.Rect = .{ .x = 0, .y = 0, .width = self.screen.width, .height = self.screen.height };
        buf[0] = .{ .id = 1, .rect = r, .usable = r, .name = .init(self.output_name) };
        return buf[0..1];
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
        return if (self.windows.get(h)) |w| w.info else .{};
    }

    pub fn window_traits(self: *const Backend, h: types.WindowHandle) types.WindowTraits {
        return if (self.windows.get(h)) |w| w.traits else .{};
    }

    pub fn window_hints(self: *const Backend, h: types.WindowHandle) types.InitialHints {
        return if (self.windows.get(h)) |w| w.hints else .{};
    }

    pub fn frame_window(self: *Backend, h: types.WindowHandle, opts: types.FrameOptions) !void {
        _ = opts;
        if (self.windows.getPtr(h)) |w| w.framed = true;
    }

    pub fn unframe(self: *Backend, h: types.WindowHandle, keep: bool) void {
        _ = keep;
        if (self.windows.getPtr(h)) |w| w.framed = false;
    }

    /// Recorded; the test decides whether the client goes (push window_gone).
    pub fn close_window(self: *Backend, h: types.WindowHandle) void {
        if (self.windows.getPtr(h)) |w| w.closed = true;
    }

    pub fn release_window(self: *Backend, h: types.WindowHandle) void {
        _ = self.windows.remove(h);
    }

    pub fn apply_windows(self: *Backend, states: []const types.WindowState, fullscreen: ?types.WindowHandle) void {
        self.scene.clearRetainingCapacity();
        self.scene.appendSlice(self.allocator, states) catch @panic("OOM");
        self.fullscreen = fullscreen;
    }

    pub fn apply_outlines(self: *Backend, list: []const types.Outline) void {
        self.outlines.clearRetainingCapacity();
        self.outlines.appendSlice(self.allocator, list) catch @panic("OOM");
    }

    pub fn hide_window(self: *Backend, h: types.WindowHandle) void {
        for (self.scene.items, 0..) |st, i| {
            if (st.handle == h) {
                _ = self.scene.orderedRemove(i);
                return;
            }
        }
    }

    pub fn raise_window(self: *Backend, h: types.WindowHandle) void {
        _ = self;
        _ = h;
    }

    pub fn draw_borders(self: *Backend, h: types.WindowHandle, colors: types.BorderColors, width: u32, size: ?types.Size) void {
        _ = self;
        _ = h;
        _ = colors;
        _ = width;
        _ = size;
    }

    pub fn set_input_focus(self: *Backend, h: ?types.WindowHandle, publish: bool) bool {
        _ = publish;
        self.focused = h;
        return true;
    }

    // ---- WM-owned windows ----
    pub fn create_preview_window(self: *Backend, opts: types.FrameOptions) !types.WindowHandle {
        _ = opts;
        defer self.next_preview += 1;
        return self.next_preview;
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
        std.debug.print("duckwm error: {s}\n", .{msg});
        self.error_shown = true;
    }

    pub fn hide_error(self: *Backend) bool {
        defer self.error_shown = false;
        return self.error_shown;
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

    // ---- input: nothing to grab ----

    /// Any name is a key: tests press keys by the names the config binds.
    pub fn keysym_from_name(self: *const Backend, name: []const u8) ?types.Keysym {
        _ = self;
        return keysym(name);
    }

    /// Hashed keysyms can't be turned back into names.
    pub fn keysym_name(self: *const Backend, ks: types.Keysym, buf: []u8) ?[]const u8 {
        _ = self;
        _ = ks;
        _ = buf;
        return null;
    }

    pub fn grab_key(self: *const Backend, k: types.KeyCombo) void {
        _ = self;
        _ = k;
    }

    pub fn ungrab_all_keys(self: *const Backend) void {
        _ = self;
    }

    pub fn set_pointer_grabs(self: *Backend, grabs: []const types.PointerGrab) void {
        _ = self;
        _ = grabs;
    }

    pub fn set_click_to_focus(self: *Backend, enabled: bool) void {
        _ = self;
        _ = enabled;
    }

    pub fn capture_pointer(self: *const Backend) void {
        _ = self;
    }

    pub fn release_pointer(self: *const Backend) void {
        _ = self;
    }

    pub fn pointer_position(self: *const Backend) types.Point {
        _ = self;
        return .{ .x = 0, .y = 0 };
    }

    pub fn warp_pointer(self: *const Backend, p: types.Point) void {
        _ = self;
        _ = p;
    }

    pub fn set_cursor_theme(self: *const Backend, theme: []const u8, size: u32) void {
        _ = self;
        _ = theme;
        _ = size;
    }

    pub fn set_keymap(self: *Backend, km: types.Keymap) bool {
        _ = self;
        _ = km;
        return true;
    }

    pub fn set_layout_index(self: *Backend, index: u32) void {
        _ = self;
        _ = index;
    }

    pub fn offer_workspaces(self: *Backend, offers: []const types.WorkspaceOffer) void {
        _ = self;
        _ = offers;
    }

    pub fn set_animation(self: *Backend, a: types.Animation) void {
        _ = self;
        _ = a;
    }
};
