const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const docks_mod = @import("docks.zig");
const info_mod = @import("info.zig");
const frames_mod = @import("frames.zig");
const preview_mod = @import("preview.zig");
const util = @import("util.zig");
const bars = @import("bars.zig");
const outlines = @import("outlines.zig");
const events = @import("events.zig");
const scene = @import("scene.zig");
const input = @import("input.zig");
const ewmh = @import("ewmh.zig");
const output = @import("outputs.zig");
const now_ms = util.now_ms;
const clamp16 = util.clamp16;
const rect_eql = util.rect_eql;
const colors_eql = util.colors_eql;
const Atoms = @import("atoms.zig").Atoms;
const Size = types.Size;
const Docks = docks_mod.Docks;
const FrameOptions = types.FrameOptions;

var wm_detected: bool = false;

const root_event_mask: c_long = c.SubstructureRedirectMask | c.SubstructureNotifyMask |
    c.KeyPressMask | c.ButtonPressMask | c.ButtonReleaseMask |
    c.PointerMotionMask | c.EnterWindowMask | c.LeaveWindowMask;

fn on_wm_detected(_: ?*c.Display, _: [*c]c.XErrorEvent) callconv(.c) c_int {
    wm_detected = true;
    return 0;
}

fn on_x_error(_: ?*c.Display, e: [*c]c.XErrorEvent) callconv(.c) c_int {
    const event = e orelse return 0;
    std.debug.print("X error: type={}, serial={}, error_code={}, request_code={}, minor_code={}\n", .{
        event.*.type,
        event.*.serial,
        event.*.error_code,
        event.*.request_code,
        event.*.minor_code,
    });
    return 0;
}

comptime {
    if (types.mod.shift != c.ShiftMask or types.mod.caps_lock != c.LockMask or
        types.mod.ctrl != c.ControlMask or types.mod.alt != c.Mod1Mask or
        types.mod.num_lock != c.Mod2Mask or types.mod.mod3 != c.Mod3Mask or
        types.mod.super != c.Mod4Mask or types.mod.mod5 != c.Mod5Mask)
        @compileError("types.mod must match X11 modifier masks for identity mapping");
}

comptime {
    if (types.button.left != c.Button1 or types.button.middle != c.Button2 or
        types.button.right != c.Button3 or types.button.scroll_up != c.Button4 or
        types.button.scroll_down != c.Button5)
        @compileError("types.button must match X11 core buttons for identity mapping");
}

pub const Backend = struct {
    allocator: std.mem.Allocator,
    display: *c.Display,
    root: c.Window,
    atoms: Atoms,
    docks: Docks = .{},
    error_bar: c.Window = 0,
    bar: ?bars.PromptBar = null,
    pointer_grabs: [8]types.PointerGrab = undefined,
    pointer_grab_count: usize = 0,
    check_win: c.Window = 0,
    frames: frames_mod.Frames = .{},
    click_to_focus: bool = false,
    applied: std.AutoHashMapUnmanaged(c.Window, scene.Applied) = .empty,
    apply_gen: u32 = 0,
    /// Group outlines, by core's key.
    outlines: std.AutoHashMapUnmanaged(u64, outlines.Outline) = .empty,
    outline_gen: u32 = 0,
    renderer: preview_mod.Renderer = .{},
    event_buf: c.XEvent = undefined,
    overlays: std.AutoHashMapUnmanaged(c.Window, void) = .empty,
    ignore_unmaps: std.AutoHashMapUnmanaged(c.Window, u32) = .empty,
    self_inflicted: [8]scene.SerialRange = undefined,
    self_inflicted_len: usize = 0,
    self_inflicted_next: usize = 0,
    /// XRandR's first event code, or -1 without it.
    rr_event_base: c_int = -1,

    pub const Strut = docks_mod.Strut;

    pub fn init(allocator: std.mem.Allocator) !Backend {
        const display = c.XOpenDisplay(null) orelse return error.CannotOpenDisplay;
        errdefer _ = c.XCloseDisplay(display);
        return .{
            .allocator = allocator,
            .display = display,
            .root = c.XDefaultRootWindow(display),
            .atoms = try Atoms.init(display),
        };
    }

    pub fn deinit(self: *Backend) void {
        if (self.check_win != 0) _ = c.XDestroyWindow(self.display, self.check_win);
        self.docks.deinit(self.allocator);
        self.frames.deinit(self.allocator);
        self.applied.deinit(self.allocator);
        outlines.destroy_all(self);
        self.overlays.deinit(self.allocator);
        self.ignore_unmaps.deinit(self.allocator);
        self.renderer.deinit(self.allocator, self.display);
        self.hide_prompt();
        _ = c.XCloseDisplay(self.display);
    }

    pub fn reserved_insets(self: *const Backend) types.Insets {
        return self.docks.insets(self.screen_size());
    }

    pub fn screen_size(self: *const Backend) Size {
        return .{
            .width = @intCast(c.XDisplayWidth(self.display, 0)),
            .height = @intCast(c.XDisplayHeight(self.display, 0)),
        };
    }

    pub fn close_window(self: *Backend, h: types.WindowHandle) void {
        ewmh.send_protocol(self, @intCast(h), self.atoms.WM_DELETE_WINDOW);
    }

    pub fn publish_work_area(self: *const Backend, area: types.Rect) void {
        ewmh.work_area(self, area);
    }

    pub fn publish_workspaces(self: *const Backend, count: u32, current: u32) void {
        ewmh.workspaces(self, count, current);
    }

    pub fn publish_window_list(self: *const Backend, handles: []const types.WindowHandle) void {
        ewmh.window_list(self, handles);
    }

    pub fn publish_window_workspace(self: *const Backend, h: types.WindowHandle, index: u32) void {
        ewmh.window_workspace(self, @intCast(h), index);
    }

    /// Tell the outside world whether h is fullscreen, preserving its other states.
    pub fn publish_window_fullscreen(self: *const Backend, h: types.WindowHandle, on: bool) void {
        ewmh.window_fullscreen(self, @intCast(h), on);
    }

    /// Show msg in a reserved bar at the top of the screen, replacing any existing one.
    pub fn show_error(self: *Backend, msg: []const u8) !void {
        try bars.show_error(self, msg);
    }

    /// Returns true if a bar was showing (meaning the reserved area changed).
    pub fn hide_error(self: *Backend) bool {
        return bars.hide_error(self);
    }

    /// The input bar, holding the keyboard so every key comes back as a
    /// prompt_key event. Called again after each edit to redraw.
    pub fn show_prompt(self: *Backend, label: []const u8, text: []const u8, cursor: usize, block: bool) !void {
        try bars.show_prompt(self, label, text, cursor, block);
    }

    /// Text in the input bar without taking the keyboard; gone after timeout_ms.
    pub fn show_message(self: *Backend, text: []const u8, timeout_ms: u32) !void {
        try bars.show_message(self, text, timeout_ms);
    }

    pub fn hide_prompt(self: *Backend) void {
        bars.hide_prompt(self);
    }

    pub fn window_info(self: *const Backend, h: types.WindowHandle) types.WindowInfo {
        return info_mod.read_info(self.display, &self.atoms, @intCast(h));
    }

    pub fn window_traits(self: *const Backend, h: types.WindowHandle) types.WindowTraits {
        return info_mod.read_traits(self.display, &self.atoms, self.root, @intCast(h));
    }

    pub fn window_hints(self: *const Backend, h: types.WindowHandle) types.InitialHints {
        return info_mod.read_hints(self.display, &self.atoms, @intCast(h));
    }

    pub fn read_strut(self: *const Backend, win: c.Window) ?Strut {
        return info_mod.read_strut(self.display, &self.atoms, win);
    }

    pub fn pointer_position(self: *const Backend) types.Point {
        var root_ret: c.Window = undefined;
        var child_ret: c.Window = undefined;
        var rx: c_int = 0;
        var ry: c_int = 0;
        var wx: c_int = 0;
        var wy: c_int = 0;
        var mask: c_uint = 0;
        _ = c.XQueryPointer(self.display, self.root, &root_ret, &child_ret, &rx, &ry, &wx, &wy, &mask);
        return .{ .x = rx, .y = ry };
    }

    pub fn warp_pointer(self: *const Backend, p: types.Point) void {
        _ = c.XWarpPointer(self.display, c.None, self.root, 0, 0, 0, 0, p.x, p.y);
        _ = c.XFlush(self.display);
    }

    pub fn set_cursor_theme(self: *const Backend, theme: []const u8, size: u32) void {
        var theme_buf: [256]u8 = undefined;
        const theme_z = std.mem.printSentinel(&theme_buf, "{s}", .{theme}, 0) catch return;
        _ = c.setenv("XCURSOR_THEME", theme_z.ptr, 1);

        var size_buf: [16]u8 = undefined;
        const size_z = std.mem.printSentinel(&size_buf, "{d}", .{size}, 0) catch return;
        _ = c.setenv("XCURSOR_SIZE", size_z.ptr, 1);

        var res_buf: [320]u8 = undefined;
        const res = std.fmt.bufPrint(&res_buf, "Xcursor.theme: {s}\nXcursor.size: {d}", .{ theme, size }) catch return;
        _ = c.XChangeProperty(self.display, self.root, self.atoms.RESOURCE_MANAGER, self.atoms.STRING, 8, c.PropModeReplace, res.ptr, @intCast(res.len));

        const cursor = c.XcursorLibraryLoadCursor(self.display, "left_ptr");
        if (cursor != 0) {
            _ = c.XDefineCursor(self.display, self.root, cursor);
            _ = c.XFreeCursor(self.display, cursor);
        }
        _ = c.XFlush(self.display);
    }

    pub fn keysym_from_name(_: *const Backend, name: []const u8) ?types.Keysym {
        return input.keysym_from_name(name);
    }

    pub fn keysym_name(self: *const Backend, ks: types.Keysym, buf: []u8) ?[]const u8 {
        _ = self;
        _ = buf;
        return input.keysym_name(ks);
    }

    pub fn grab_key(self: *const Backend, k: types.KeyCombo) void {
        input.grab_key(self, k);
    }

    pub fn ungrab_all_keys(self: *const Backend) void {
        input.ungrab_all_keys(self);
    }

    pub fn set_pointer_grabs(self: *Backend, grabs: []const types.PointerGrab) void {
        input.set_pointer_grabs(self, grabs);
    }

    /// Become the window manager for this display.
    pub fn start(self: *Backend) !void {
        wm_detected = false;
        _ = c.XSetErrorHandler(on_wm_detected);
        output.watch(self);
        ewmh.announce_supported(self);
        _ = c.XSync(self.display, 0);
    }

    /// fd to poll for backend events.
    pub fn event_fd(self: *const Backend) i32 {
        return c.XConnectionNumber(self.display);
    }

    /// Give keyboard focus to h, or to nothing when null.
    /// publish_active controls whether it's advertised as the active window
    /// (false for WM-internal windows like workspace previews).
    /// Returns false if h can't take focus right now (not viewable).
    pub fn set_input_focus(self: *Backend, h: ?types.WindowHandle, publish_active: bool) bool {
        const win: c.Window = if (h) |v| @intCast(v) else {
            _ = c.XSetInputFocus(self.display, self.root, c.RevertToParent, c.CurrentTime);
            ewmh.set_active_window(self, 0);
            _ = c.XFlush(self.display);
            return true;
        };

        var attrs: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(self.display, win, &attrs) == 0) return false;
        if (attrs.map_state != c.IsViewable) return false;

        const model = self.frames.focus_model(win);
        if (model.accepts_input) {
            _ = c.XSetInputFocus(self.display, win, c.RevertToParent, c.CurrentTime);
        }
        if (model.takes_focus) ewmh.send_protocol(self, win, self.atoms.WM_TAKE_FOCUS);
        ewmh.set_active_window(self, if (publish_active) win else 0);
        return true;
    }

    /// Advertise the decoration size to every framed client.
    pub fn publish_frame_extents(self: *const Backend, border_width: u32) void {
        var it = self.frames.by_client.keyIterator();
        while (it.next()) |client| frames_mod.set_extents(self, client.*, border_width);
    }

    pub fn set_click_to_focus(self: *Backend, enabled: bool) void {
        self.click_to_focus = enabled;
        var it = self.frames.by_frame.keyIterator();
        while (it.next()) |f| {
            if (enabled) frames_mod.grab_click(self, f.*) else frames_mod.ungrab_click(self, f.*);
        }
    }

    /// Reparent client into a new frame.
    pub fn frame_window(self: *Backend, h: types.WindowHandle, opts: FrameOptions) !c.Window {
        return frames_mod.create(self, @intCast(h), opts);
    }

    /// Stop framing client. With keep_client, it is reparented to the root first so it survives.
    pub fn unframe(self: *Backend, h: types.WindowHandle, keep_client: bool) void {
        frames_mod.destroy(self, @intCast(h), keep_client);
    }

    /// An override-redirect window for a workspace preview, already framed.
    pub fn create_preview_window(self: *Backend, opts: FrameOptions) !c.Window {
        var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        wa.override_redirect = 1;
        wa.background_pixel = 0x1a1a2e;
        wa.border_pixel = 0;
        const pw = c.XCreateWindow(
            self.display,
            self.root,
            0,
            0,
            200,
            150,
            0,
            c.CopyFromParent,
            c.InputOutput,
            c.CopyFromParent,
            c.CWOverrideRedirect | c.CWBackPixel | c.CWBorderPixel,
            &wa,
        );
        if (pw == 0) return error.PreviewCreateFailed;
        errdefer _ = c.XDestroyWindow(self.display, pw);

        _ = try self.frame_window(pw, opts);
        _ = c.XSelectInput(self.display, pw, c.ButtonPressMask | c.ButtonReleaseMask | c.ExposureMask);
        return pw;
    }

    pub fn destroy_preview_window(self: *Backend, h: types.WindowHandle) void {
        const pw: c.Window = @intCast(h);
        if (self.frames.frame_of(pw) != null) {
            self.unframe(pw, false); // destroying the frame destroys pw with it
        } else {
            _ = c.XDestroyWindow(self.display, pw);
        }
    }

    /// Paint the border of window handle inside its frame.
    /// size is the frame size if the caller knows it; otherwise it's queried.
    pub fn draw_borders(self: *Backend, handle: types.WindowHandle, colors: types.BorderColors, width: u32, size: ?types.Size) void {
        scene.draw_borders(self, @intCast(handle), colors, width, size);
    }

    /// Bring the screen in line with states, sending only what changed.
    pub fn apply_windows(self: *Backend, states: []const types.WindowState, fullscreen: ?types.WindowHandle) void {
        scene.apply(self, states, fullscreen);
    }

    /// The group outlines to show (before apply_windows, which stacks them);
    /// any other is destroyed.
    pub fn apply_outlines(self: *Backend, list: []const types.Outline) void {
        outlines.apply(self, list);
    }

    /// Hide h now, without waiting for the next apply.
    pub fn hide_window(self: *Backend, h: types.WindowHandle) void {
        scene.hide(self, @intCast(h));
    }

    /// Bring h above other windows (but below docks).
    pub fn raise_window(self: *Backend, h: types.WindowHandle) void {
        scene.raise(self, @intCast(h));
    }

    /// Stop managing h but leave it on screen, e.g. a window that turned out to be a dock.
    pub fn release_window(self: *Backend, h: types.WindowHandle) void {
        const client: c.Window = @intCast(h);
        if (self.frames.frame_of(client) != null) {
            if (self.ignore_unmaps.getOrPut(self.allocator, client)) |gop| {
                gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
            } else |_| {}
            _ = c.XUnmapWindow(self.display, client);
            self.unframe(client, true);
        }
        _ = c.XMapWindow(self.display, client);
        _ = c.XFlush(self.display);
    }

    /// Forget what was applied to client, forcing the next apply to resend everything.
    pub fn invalidate_window(self: *Backend, client: c.Window) void {
        _ = self.applied.remove(client);
    }

    pub fn draw_preview(self: *Backend, h: types.WindowHandle, size: types.Size, style: types.PreviewStyle, items: []const types.PreviewItem) void {
        self.renderer.draw(
            self.allocator,
            self.display,
            &self.atoms,
            @intCast(h),
            size,
            style,
            items,
        );
    }

    /// Send any buffered requests to the server.
    pub fn flush_output(self: *const Backend) void {
        _ = c.XFlush(self.display);
    }

    /// The next event that core needs to see, or null when none are pending.
    /// Events the backend fully handles itself are consumed here.
    pub fn next_event(self: *Backend) ?types.Event {
        if (self.bar) |b| if (b.deadline) |d| if (now_ms() >= d) self.hide_prompt();
        while (c.XPending(self.display) > 0) {
            _ = c.XNextEvent(self.display, &self.event_buf);
            if (events.translate(self, &self.event_buf)) |ev| return ev;
        }
        return null;
    }

    /// End any pointer grab (e.g. an interrupted drag).
    pub fn release_pointer(self: *const Backend) void {
        input.release_pointer(self);
    }

    /// Route all pointer motion and the button release to the WM (for a drag).
    pub fn capture_pointer(self: *const Backend) void {
        input.capture_pointer(self);
    }

    /// Wait until the server has processed everything sent so far.
    pub fn sync(self: *const Backend) void {
        _ = c.XSync(self.display, 0);
    }

    /// On X the session ends when the WM's process does (xinit/startx), so nothing to do.
    pub fn end_session(self: *Backend) void {
        _ = self;
    }

    /// Runs setxkbmap; the server's MappingNotify then triggers keymap_changed.
    pub fn set_keymap(self: *Backend, km: types.Keymap) bool {
        return input.set_keymap(self, km);
    }

    pub fn set_layout_index(self: *Backend, index: u32) void {
        input.set_layout_index(self, index);
    }

    /// Animations on X belong to a compositor; nothing to do here yet.
    pub fn set_animation(self: *Backend, a: types.Animation) void {
        _ = self;
        _ = a;
    }

    pub fn poll_timeout(self: *const Backend) i32 {
        const b = self.bar orelse return -1;
        const d = b.deadline orelse return -1;
        return @intCast(std.math.clamp(d - now_ms(), 0, std.math.maxInt(i32)));
    }

    pub fn outputs(self: *Backend, buf: []types.OutputInfo) []types.OutputInfo {
        return output.list(self, buf);
    }
};
