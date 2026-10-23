const std = @import("std");
const surface = @import("surface.zig");
const util = @import("util.zig");
const output = @import("outputs.zig");
const windows = @import("windows.zig");
const bars = @import("bars.zig");
const previews = @import("previews.zig");
const outlines = @import("outlines.zig");
const input = @import("input.zig");
const keyboard = @import("keyboard.zig");
const sequence = @import("sequence.zig");
const globals = @import("globals.zig");
const types = @import("types");
const wayland = @import("wayland");
const c = @import("rc");
const wl = wayland.client.wl;
const river = wayland.client.river;
const State = @import("state.zig").State;

const frame_interval_ms: i64 = 16;

// The backend interface core uses (see wm/backend.zig's required).
pub const Backend = struct {
    allocator: std.mem.Allocator,
    state: *State,

    // ---- lifecycle ----

    pub fn init(allocator: std.mem.Allocator) !Backend {
        surface.init();
        const display = wl.Display.connect(null) catch return error.CannotOpenDisplay;
        errdefer display.disconnect();
        const registry = try display.getRegistry();

        const s = try allocator.create(State);
        errdefer allocator.destroy(s);
        s.* = .{ .allocator = allocator, .display = display, .registry = registry };

        // Bind the globals now rather than in start(): core reads the screen
        // size in WM.create, and that comes from the first output.
        registry.setListener(*State, globals.registry_listener, s);
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        const wm = s.wm orelse return error.NotRunningUnderRiver;
        wm.setListener(*State, globals.wm_listener, s);
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        if (s.unavailable) return error.AnotherWmRunning;

        return .{ .allocator = allocator, .state = s };
    }

    pub fn deinit(self: *Backend) void {
        const s = self.state;
        self.ungrab_all_keys();
        self.set_pointer_grabs(&.{});
        var it = s.windows.valueIterator();
        while (it.next()) |wp| {
            if (wp.*.ind) |*ind| ind.destroy();
            s.allocator.destroy(wp.*);
        }
        s.windows.deinit(s.allocator);
        s.by_obj.deinit(s.allocator);
        for (s.outputs.items) |o| s.allocator.destroy(o);
        s.outputs.deinit(s.allocator);
        s.fresh.deinit(s.allocator);
        s.dead.deinit(s.allocator);
        s.events.deinit(s.allocator);
        s.order.deinit(s.allocator);
        s.closes.deinit(s.allocator);
        s.scratch.deinit(s.allocator);
        s.keys.deinit(s.allocator);
        s.buttons.deinit(s.allocator);
        if (s.cursor_theme) |t| s.allocator.free(t);
        previews.destroy_all(s);
        s.previews.deinit(s.allocator);
        outlines.destroy_all(s);
        _ = bars.hide_error(s);
        _ = bars.hide_prompt(s);
        keyboard.deinit(s);
        s.fonts.deinit(s.allocator);
        surface.deinit();
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
        if (!s.pumped) {
            s.pump();
            s.pumped = true;
        }
        if (s.prompt_bar) |b| if (b.deadline) |d| if (util.now_ms() >= d) {
            _ = bars.hide_prompt(s);
        };
        keyboard.repeat_due(s);
        if (s.render_pending) {
            s.render_pending = false;
            sequence.send_render(s);
        }
        if (s.event_head < s.events.items.len) {
            const ev = s.events.items[s.event_head];
            s.event_head += 1;
            return ev;
        }
        s.events.clearRetainingCapacity();
        s.event_head = 0;
        return null;
    }

    /// End of the loop iteration: close the manage sequence, or ask for one.
    pub fn flush_output(self: *const Backend) void {
        const s = self.state;
        if ((s.settle or (s.animating and util.now_ms() - s.last_frame_ms >= frame_interval_ms)) and !s.in_manage) {
            s.want_manage = true;
        }
        if (s.wm) |wm| {
            if (s.in_manage) {
                sequence.send_manage(s);
                wm.manageFinish();
                s.in_manage = false;
                s.want_manage = false;
            } else if (s.want_manage and !s.dirty_sent) {
                wm.manageDirty();
                s.dirty_sent = true;
                s.want_manage = false;
            }
        }
        _ = s.display.flush();
        s.pumped = false;
    }

    /// river renders frame-perfectly on its own; nothing to wait for.
    pub fn sync(self: *const Backend) void {
        _ = self;
    }

    /// End the whole Wayland session: river exits, and every client with it.
    pub fn end_session(self: *Backend) void {
        const s = self.state;
        if (s.wm) |wm| wm.exitSession();
        _ = s.display.flush();
    }

    // ---- screen ----

    pub fn screen_size(self: *const Backend) types.Size {
        const o = self.state.primary orelse return .{ .width = 1920, .height = 1080 };
        return .{ .width = util.nonneg(o.width), .height = util.nonneg(o.height) };
    }

    pub fn reserved_insets(self: *const Backend) types.Insets {
        const s = self.state;
        var r: types.Insets = .{};
        if (s.primary) |o| if (o.usable) |a| {
            const aw: i32 = @intCast(a.width);
            const ah: i32 = @intCast(a.height);
            r = .{
                .left = util.nonneg(a.x - o.x),
                .top = util.nonneg(a.y - o.y),
                .right = util.nonneg((o.x + o.width) - (a.x + aw)),
                .bottom = util.nonneg((o.y + o.height) - (a.y + ah)),
            };
        };
        if (s.error_bar) |bar| r.top += bar.height;
        return r;
    }

    // ---- publishing (EWMH on X; river runs foreign-toplevel itself) ----

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
        const w = self.state.windows.get(h) orelse return .{};
        return windows.traits_of(w);
    }

    pub fn window_hints(self: *const Backend, h: types.WindowHandle) types.InitialHints {
        const w = self.state.windows.get(h) orelse return .{};
        return .{
            .fullscreen = w.wants_fullscreen,
            .fixed_size = windows.fixed_size(w),
        };
    }

    /// No frames on Wayland: river draws borders around the window itself.
    pub fn frame_window(self: *Backend, h: types.WindowHandle, opts: types.FrameOptions) !void {
        _ = self;
        _ = h;
        _ = opts;
    }

    /// Window objects are destroyed when river reports them closed.
    pub fn unframe(self: *Backend, h: types.WindowHandle, keep: bool) void {
        _ = self;
        _ = h;
        _ = keep;
    }

    pub fn close_window(self: *Backend, h: types.WindowHandle) void {
        const s = self.state;
        if (s.live(h) == null) return;
        s.closes.append(s.allocator, h) catch return;
        s.mark();
    }

    /// Docks are layer-shell surfaces on Wayland and never become windows.
    pub fn release_window(self: *Backend, h: types.WindowHandle) void {
        _ = self;
        _ = h;
    }

    pub fn apply_windows(self: *Backend, states: []const types.WindowState, fullscreen: ?types.WindowHandle) void {
        const s = self.state;

        var it = s.windows.valueIterator();
        while (it.next()) |wp| wp.*.in_scene = false;
        s.order.clearRetainingCapacity();

        var pit = s.previews.valueIterator();
        while (pit.next()) |pp| pp.*.in_scene = false;

        for (states) |st| {
            if (s.previews.get(st.handle)) |p| {
                previews.apply(p, st);
                s.order.append(s.allocator, st.handle) catch {};
                continue;
            }
            const w = s.live(st.handle) orelse continue; // e.g. preview placeholders
            const bw = st.border_width;
            // core's rect is the whole footprint; river's geometry is the
            // content, with borders drawn outside it.
            w.in_scene = true;
            const new_pos: types.Point = .{
                .x = st.frame.x + @as(i32, @intCast(bw)),
                .y = st.frame.y + @as(i32, @intCast(bw)),
            };
            const new_size: types.Size = .{
                .width = @max(1, st.frame.width -| 2 * bw),
                .height = @max(1, st.frame.height -| 2 * bw),
            };
            const changed = new_pos.x != w.want_pos.x or new_pos.y != w.want_pos.y or !util.size_eql(new_size, w.want_size);
            if (changed and s.anim.duration_ms > 0 and w.pos != null and w.shown and
                !w.fullscreen and !st.interactive and !s.op_active)
            {
                const cur = windows.displayed(s, w, util.now_ms()); // mid-flight retargets start from where it is
                w.anim_from_pos = cur.pos;
                w.anim_from_size = cur.size;
                w.anim_start_ms = 0;
                w.anim_active = true;
            } else if (changed) {
                w.anim_active = false;
            }
            w.want_border_color = if (st.borders) |b| windows.base_color(b) else null;
            w.want_odd = if (st.borders) |b| windows.odd_side(b) else null;
            w.want_pos = new_pos;
            w.want_size = new_size;
            w.want_tiled = st.tiled;
            w.want_out = st.clip;
            w.want_border_width = bw;
            s.order.append(s.allocator, st.handle) catch {};
        }
        s.fullscreen = fullscreen;
        s.mark();
    }

    /// The group outlines to show; any other goes at the next render.
    pub fn apply_outlines(self: *Backend, list: []const types.Outline) void {
        outlines.apply(self.state, list);
    }

    pub fn hide_window(self: *Backend, h: types.WindowHandle) void {
        const s = self.state;
        if (s.previews.get(h)) |p| {
            p.in_scene = false;
            s.mark();
            return;
        }
        const w = s.live(h) orelse return;
        w.in_scene = false;
        s.mark();
    }

    pub fn raise_window(self: *Backend, h: types.WindowHandle) void {
        const s = self.state;
        if (s.previews.get(h)) |p| {
            s.raise_clock += 1;
            p.raise_serial = s.raise_clock;
            s.mark();
            return;
        }
        const w = s.live(h) orelse return;
        s.raise_clock += 1;
        w.raise_serial = s.raise_clock;
        s.mark();
    }

    /// One color for all edges: river's borders don't do per-side colors.
    pub fn draw_borders(self: *Backend, h: types.WindowHandle, colors: types.BorderColors, width: u32, size: ?types.Size) void {
        _ = size;
        const s = self.state;
        if (s.previews.get(h)) |p| {
            p.want_border_color = windows.base_color(colors);
            p.want_border_width = width;
            s.mark();
            return;
        }
        const w = s.live(h) orelse return;
        w.want_border_color = windows.base_color(colors);
        w.want_odd = windows.odd_side(colors);
        w.want_border_width = width;
        s.mark();
    }

    pub fn set_input_focus(self: *Backend, h: ?types.WindowHandle, publish: bool) bool {
        _ = publish; // river publishes the activated toplevel itself
        const s = self.state;
        if (h) |win| if (s.live(win) == null and !s.previews.contains(win)) return false;
        s.focus = h;
        s.focus_dirty = true;
        s.mark();
        return true;
    }

    // ---- WM-owned surfaces (previews, error bar): shell surfaces, later ----
    pub fn create_preview_window(self: *Backend, opts: types.FrameOptions) !types.WindowHandle {
        _ = opts;
        return previews.create(self.state);
    }

    pub fn destroy_preview_window(self: *Backend, h: types.WindowHandle) void {
        previews.destroy(self.state, h);
    }

    /// Copies the content; the buffer itself follows the scene rect at render time.
    pub fn draw_preview(self: *Backend, h: types.WindowHandle, size: types.Size, style: types.PreviewStyle, items: []const types.PreviewItem) void {
        _ = size;
        previews.set_content(self.state, h, style, items);
    }

    pub fn show_error(self: *Backend, msg: []const u8) !void {
        try bars.show_error(self.state, msg);
    }

    pub fn hide_error(self: *Backend) bool {
        return bars.hide_error(self.state);
    }

    /// The input bar, taking the keyboard: keys come back as prompt_key events.
    pub fn show_prompt(self: *Backend, label: []const u8, text: []const u8, cursor: usize, block: bool) !void {
        try bars.show_prompt(self.state, label, text, cursor, block);
    }

    /// Text in the input bar without taking the keyboard; gone after timeout_ms.
    pub fn show_message(self: *Backend, text: []const u8, timeout_ms: u32) !void {
        try bars.show_message(self.state, text, timeout_ms);
    }

    pub fn hide_prompt(self: *Backend) void {
        _ = bars.hide_prompt(self.state);
    }

    // ---- input ----

    pub fn keysym_from_name(_: *const Backend, name: []const u8) ?types.Keysym {
        return keyboard.keysym_from_name(name);
    }

    /// Bindings are created and enabled in the next manage sequence.
    pub fn grab_key(self: *const Backend, k: types.KeyCombo) void {
        input.grab_key(self.state, k);
    }

    pub fn ungrab_all_keys(self: *const Backend) void {
        input.ungrab_all_keys(self.state);
    }

    /// A grab with no button covers left, middle and right, like X's AnyButton
    /// for the buttons that matter here.
    pub fn set_pointer_grabs(self: *Backend, grabs: []const types.PointerGrab) void {
        input.set_pointer_grabs(self.state, grabs);
    }

    /// river reports clicks on windows as window_interaction; whether they
    /// focus is decided here rather than by a grab.
    pub fn set_click_to_focus(self: *Backend, enabled: bool) void {
        self.state.click_to_focus = enabled;
    }

    /// Start an interactive pointer op: motion arrives as op_delta.
    pub fn capture_pointer(self: *const Backend) void {
        input.capture_pointer(self.state);
    }

    pub fn release_pointer(self: *const Backend) void {
        input.release_pointer(self.state);
    }

    pub fn pointer_position(self: *const Backend) types.Point {
        return self.state.pointer_pos;
    }

    pub fn warp_pointer(self: *const Backend, p: types.Point) void {
        const s = self.state;
        s.warp = p;
        s.mark();
    }

    pub fn set_cursor_theme(self: *const Backend, theme: []const u8, size: u32) void {
        const s = self.state;
        const owned = s.allocator.dupeZ(u8, theme) catch return;
        if (s.cursor_theme) |old| s.allocator.free(old);
        s.cursor_theme = owned;
        s.cursor_size = size;
        if (s.seat) |seat| seat.setXcursorTheme(owned.ptr, size);
    }

    pub fn set_keymap(self: *Backend, km: types.Keymap) bool {
        return keyboard.set_keymap(self.state, km);
    }

    pub fn set_layout_index(self: *Backend, index: u32) void {
        keyboard.set_layout_index(self.state, index);
    }

    pub fn set_animation(self: *Backend, a: types.Animation) void {
        const s = self.state;
        s.anim = a;
        if (a.duration_ms == 0) {
            var it = s.windows.valueIterator();
            while (it.next()) |wp| wp.*.anim_active = false;
        }
    }

    /// While animating, wake up in time for the next frame.
    pub fn poll_timeout(self: *const Backend) i32 {
        const s = self.state;
        const now = util.now_ms();
        var wait: ?i64 = null;
        if (s.animating) wait = s.last_frame_ms + frame_interval_ms - now;
        if (s.repeat_key != null) {
            const w = s.repeat_next_ms - now;
            wait = if (wait) |x| @min(x, w) else w;
        }
        if (s.prompt_bar) |b| if (b.deadline) |d| {
            wait = if (wait) |x| @min(x, d - now) else d - now;
        };
        const w = wait orelse return -1;
        return @intCast(std.math.clamp(w, 0, std.math.maxInt(i32)));
    }

    pub fn outputs(self: *Backend, buf: []types.OutputInfo) []types.OutputInfo {
        return output.list(self.state, buf);
    }
};
