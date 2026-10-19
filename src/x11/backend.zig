const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const docks_mod = @import("docks.zig");
const info_mod = @import("info.zig");
const frames_mod = @import("frames.zig");
const preview_mod = @import("preview.zig");
const Atoms = @import("atoms.zig").Atoms;
const Size = types.Size;
const Docks = docks_mod.Docks;
const FrameOptions = types.FrameOptions;

const key_lock_masks = [_]c_uint{ 0, c.LockMask, c.Mod2Mask, c.LockMask | c.Mod2Mask };

var wm_detected: bool = false;

const NormalState: c_ulong = 1;

const root_event_mask: c_long = c.SubstructureRedirectMask | c.SubstructureNotifyMask |
    c.KeyPressMask | c.ButtonPressMask | c.ButtonReleaseMask |
    c.PointerMotionMask | c.EnterWindowMask | c.LeaveWindowMask;

const frame_event_mask: c_long = c.SubstructureRedirectMask | c.SubstructureNotifyMask |
    c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask |
    c.EnterWindowMask | c.LeaveWindowMask | c.ExposureMask;

const prompt_font = "monospace:size=11";
const prompt_bg: c_ulong = 0x1e1e2e;
const prompt_fg: u32 = 0xcdd6f4;
const prompt_pad: c_int = 4;

const PromptBar = struct {
    win: c.Window,
    draw: *c.XftDraw,
    font: [*c]c.XftFont,
    fg: c.XftColor,
    /// For the character under a block cursor.
    bg: c.XftColor,
    /// The label then the text, as drawn.
    content: std.ArrayListUnmanaged(u8) = .empty,
    label_len: usize = 0,
    /// Byte offset into the text; null for a message.
    cursor: ?usize = null,
    /// A block cursor over a character (vi normal mode) rather than a bar between two.
    block: bool = false,
    /// Holding the keyboard: a prompt rather than a message.
    grabbed: bool = false,
    /// A message hides itself once now_ms() passes this.
    deadline: ?i64 = null,
};

fn now_ms() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
}

fn render_color(rgb: u32) c.XRenderColor {
    return .{
        .red = @intCast(((rgb >> 16) & 0xff) * 0x101),
        .green = @intCast(((rgb >> 8) & 0xff) * 0x101),
        .blue = @intCast((rgb & 0xff) * 0x101),
        .alpha = 0xffff,
    };
}

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

fn argb_visual(display: *c.Display) ?*c.Visual {
    var template: c.XVisualInfo = undefined;
    template.screen = c.XDefaultScreen(display);
    template.depth = 32;
    template.class = c.TrueColor;
    var nitems: c_int = 0;
    const list = c.XGetVisualInfo(display, c.VisualScreenMask | c.VisualDepthMask | c.VisualClassMask, &template, &nitems);
    defer if (list != null) {
        _ = c.XFree(@ptrCast(list));
    };
    if (nitems > 0) return list[0].visual;
    return null;
}

fn clamp16(v: i32) i32 {
    return @max(-32768, @min(32767, v));
}

fn rect_eql(a: types.Rect, b: types.Rect) bool {
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}

fn colors_eql(a: ?types.BorderColors, b: ?types.BorderColors) bool {
    if (a == null or b == null) return a == null and b == null;
    const x = a.?;
    const y = b.?;
    return x.top == y.top and x.bottom == y.bottom and x.left == y.left and x.right == y.right;
}

comptime {
    if (types.mod.shift != c.ShiftMask or types.mod.caps_lock != c.LockMask or
        types.mod.ctrl != c.ControlMask or types.mod.alt != c.Mod1Mask or
        types.mod.num_lock != c.Mod2Mask or types.mod.mod3 != c.Mod3Mask or
        types.mod.super != c.Mod4Mask or types.mod.mod5 != c.Mod5Mask)
        @compileError("types.mod must match X11 modifier masks for identity mapping");
}

comptime {
    if (@sizeOf(c_ulong) != @sizeOf(types.WindowHandle))
        @compileError("publish_window_list assumes WindowHandle has the size of c_ulong");
}

comptime {
    if (types.button.left != c.Button1 or types.button.middle != c.Button2 or
        types.button.right != c.Button3 or types.button.scroll_up != c.Button4 or
        types.button.scroll_down != c.Button5)
        @compileError("types.button must match X11 core buttons for identity mapping");
}

const SerialRange = struct { start: c_ulong, end: c_ulong };

const Applied = struct {
    frame: types.Rect,
    configure_pending: bool,
    border_width: u32,
    borders: ?types.BorderColors,
    mapped: bool,
    gen: u32,
};

pub const Backend = struct {
    allocator: std.mem.Allocator,
    display: *c.Display,
    root: c.Window,
    atoms: Atoms,
    docks: Docks = .{},
    error_bar: c.Window = 0,
    bar: ?PromptBar = null,
    pointer_grabs: [8]types.PointerGrab = undefined,
    pointer_grab_count: usize = 0,
    check_win: c.Window = 0,
    frames: frames_mod.Frames = .{},
    click_to_focus: bool = false,
    applied: std.AutoHashMapUnmanaged(c.Window, Applied) = .empty,
    apply_gen: u32 = 0,
    renderer: preview_mod.Renderer = .{},
    event_buf: c.XEvent = undefined,
    overlays: std.AutoHashMapUnmanaged(c.Window, void) = .empty,
    ignore_unmaps: std.AutoHashMapUnmanaged(c.Window, u32) = .empty,
    self_inflicted: [8]SerialRange = undefined,
    self_inflicted_len: usize = 0,
    self_inflicted_next: usize = 0,

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
        self.overlays.deinit(self.allocator);
        self.ignore_unmaps.deinit(self.allocator);
        self.renderer.deinit(self.allocator, self.display);
        self.hide_prompt();
        _ = c.XCloseDisplay(self.display);
    }

    pub fn reserved_insets(self: *const Backend) types.Insets {
        return self.docks.insets(self.screen_size());
    }

    pub fn is_dock(self: *const Backend, win: c.Window) bool {
        return self.docks.contains(win);
    }

    /// Start tracking a dock. Reads its geometry once.
    pub fn dock_add(self: *Backend, win: c.Window, strut: Strut) !void {
        var attrs: c.XWindowAttributes = undefined;
        const rect: types.Rect = if (c.XGetWindowAttributes(self.display, win, &attrs) != 0) .{
            .x = attrs.x,
            .y = attrs.y,
            .width = @intCast(attrs.width),
            .height = @intCast(attrs.height),
        } else .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        try self.docks.put(self.allocator, win, strut, rect);
    }

    pub fn dock_remove(self: *Backend, win: c.Window) bool {
        return self.docks.remove(win);
    }

    /// Returns true if win is a dock. A null strut stops tracking it.
    pub fn dock_set_strut(self: *Backend, win: c.Window, strut: ?Strut) bool {
        if (!self.docks.contains(win)) return false;
        if (strut) |s| {
            _ = self.docks.set_strut(win, s);
        } else {
            _ = self.docks.remove(win);
        }
        return true;
    }

    /// Feed ConfigureNotify here. True means a dock's geometry changed.
    pub fn dock_configured(self: *Backend, win: c.Window, rect: types.Rect) bool {
        return self.docks.set_rect(win, rect);
    }

    pub fn dock_restack(self: *Backend) void {
        const size = self.screen_size();
        var top: i32 = 0;
        var bottom: i32 = 0;
        var left: i32 = 0;
        var right: i32 = 0;
        var it = self.docks.map.iterator();
        while (it.next()) |e| {
            const win = e.key_ptr.*;
            const d = e.value_ptr;
            const s = d.strut;
            if (s.top > 0) {
                d.rect.x = 0;
                d.rect.y = top;
                top += @intCast(s.top);
            } else if (s.bottom > 0) {
                bottom += @intCast(s.bottom);
                d.rect.x = 0;
                d.rect.y = @as(i32, @intCast(size.height)) - bottom;
            } else if (s.left > 0) {
                d.rect.x = left;
                d.rect.y = 0;
                left += @intCast(s.left);
            } else if (s.right > 0) {
                right += @intCast(s.right);
                d.rect.x = @as(i32, @intCast(size.width)) - right;
                d.rect.y = 0;
            } else continue;
            _ = c.XMoveWindow(self.display, win, d.rect.x, d.rect.y);
        }
        _ = c.XFlush(self.display);
    }

    pub fn raise_docks(self: *const Backend) void {
        var it = self.docks.map.keyIterator();
        while (it.next()) |win| _ = c.XRaiseWindow(self.display, win.*);
    }

    fn stack_below_docks(self: *const Backend, frame: c.Window) void {
        var lowest: ?c.Window = null;
        var it = self.docks.map.keyIterator();
        while (it.next()) |win| {
            _ = c.XRaiseWindow(self.display, win.*);
            if (lowest == null) lowest = win.*;
        }
        if (lowest) |d| {
            var changes: c.XWindowChanges = std.mem.zeroes(c.XWindowChanges);
            changes.sibling = d;
            changes.stack_mode = c.Below;
            _ = c.XConfigureWindow(self.display, frame, c.CWSibling | c.CWStackMode, &changes);
        } else {
            _ = c.XRaiseWindow(self.display, frame);
        }
    }

    pub fn screen_size(self: *const Backend) Size {
        return .{
            .width = @intCast(c.XDisplayWidth(self.display, 0)),
            .height = @intCast(c.XDisplayHeight(self.display, 0)),
        };
    }

    fn send_protocol(self: *const Backend, win: c.Window, proto: c.Atom) void {
        var ev: c.XEvent = std.mem.zeroes(c.XEvent);
        ev.xclient.type = c.ClientMessage;
        ev.xclient.window = win;
        ev.xclient.message_type = self.atoms.WM_PROTOCOLS;
        ev.xclient.format = 32;
        ev.xclient.data.l[0] = @intCast(proto);
        ev.xclient.data.l[1] = c.CurrentTime;
        _ = c.XSendEvent(self.display, win, 0, c.NoEventMask, &ev);
    }

    pub fn close_window(self: *Backend, h: types.WindowHandle) void {
        self.send_protocol(@intCast(h), self.atoms.WM_DELETE_WINDOW);
    }

    pub fn publish_work_area(self: *const Backend, area: types.Rect) void {
        const vals = [4]c_ulong{
            @intCast(area.x), @intCast(area.y), area.width, area.height,
        };
        _ = c.XChangeProperty(
            self.display,
            self.root,
            self.atoms._NET_WORKAREA,
            self.atoms.CARDINAL,
            32,
            c.PropModeReplace,
            @ptrCast(&vals),
            4,
        );
    }

    pub fn publish_workspaces(self: *const Backend, count: u32, current: u32) void {
        const n: c_ulong = count;
        const cur: c_ulong = current;
        _ = c.XChangeProperty(
            self.display,
            self.root,
            self.atoms._NET_NUMBER_OF_DESKTOPS,
            self.atoms.CARDINAL,
            32,
            c.PropModeReplace,
            @ptrCast(&n),
            1,
        );
        _ = c.XChangeProperty(
            self.display,
            self.root,
            self.atoms._NET_CURRENT_DESKTOP,
            self.atoms.CARDINAL,
            32,
            c.PropModeReplace,
            @ptrCast(&cur),
            1,
        );
    }

    pub fn publish_window_list(self: *const Backend, handles: []const types.WindowHandle) void {
        if (handles.len == 0) {
            _ = c.XDeleteProperty(self.display, self.root, self.atoms._NET_CLIENT_LIST);
            return;
        }
        _ = c.XChangeProperty(
            self.display,
            self.root,
            self.atoms._NET_CLIENT_LIST,
            self.atoms.WINDOW,
            32,
            c.PropModeReplace,
            @ptrCast(handles.ptr),
            @intCast(handles.len),
        );
    }

    pub fn publish_window_workspace(self: *const Backend, h: types.WindowHandle, index: u32) void {
        const idx: c_ulong = index;
        _ = c.XChangeProperty(
            self.display,
            @intCast(h),
            self.atoms._NET_WM_DESKTOP,
            self.atoms.CARDINAL,
            32,
            c.PropModeReplace,
            @ptrCast(&idx),
            1,
        );
    }

    /// Show msg in a reserved bar at the top of the screen, replacing any existing one.
    pub fn show_error(self: *Backend, msg: []const u8) !void {
        _ = self.hide_error();

        const size = self.screen_size();
        const bar_height: u32 = 20;

        const win = c.XCreateSimpleWindow(self.display, self.root, 0, 0, size.width, bar_height, 0, 0, 0xCC0000);
        if (win == 0) return error.ErrorBarCreateFailed;
        errdefer _ = c.XDestroyWindow(self.display, win);

        _ = c.XChangeProperty(self.display, win, self.atoms._NET_WM_WINDOW_TYPE, self.atoms.ATOM, 32, c.PropModeReplace, @ptrCast(&self.atoms._NET_WM_WINDOW_TYPE_DOCK), 1);

        const strut = [12]c_ulong{ 0, 0, bar_height, 0, 0, 0, 0, 0, 0, size.width, 0, 0 };
        _ = c.XChangeProperty(self.display, win, self.atoms._NET_WM_STRUT_PARTIAL, self.atoms.CARDINAL, 32, c.PropModeReplace, @ptrCast(&strut), 12);

        var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        wa.override_redirect = 1;
        _ = c.XChangeWindowAttributes(self.display, win, c.CWOverrideRedirect, &wa);
        _ = c.XSelectInput(self.display, win, c.ButtonPressMask);
        _ = c.XMapRaised(self.display, win);

        self.draw_error_text(win, size.width, msg);

        // Geometry is known, so no need to query it back like dock_add does.
        try self.docks.put(self.allocator, win, .{ .top = bar_height }, .{
            .x = 0,
            .y = 0,
            .width = size.width,
            .height = bar_height,
        });

        _ = c.XGrabButton(self.display, 1, c.AnyModifier, win, 0, c.ButtonPressMask, c.GrabModeAsync, c.GrabModeAsync, c.None, c.None);
        _ = c.XFlush(self.display);
        self.error_bar = win;
    }

    /// Returns true if a bar was showing (meaning the reserved area changed).
    pub fn hide_error(self: *Backend) bool {
        if (self.error_bar == 0) return false;
        _ = self.docks.remove(self.error_bar);
        _ = c.XDestroyWindow(self.display, self.error_bar);
        _ = c.XFlush(self.display);
        self.error_bar = 0;
        return true;
    }

    pub fn is_error_bar(self: *const Backend, win: c.Window) bool {
        return self.error_bar != 0 and win == self.error_bar;
    }

    fn draw_error_text(self: *const Backend, win: c.Window, width: u32, msg: []const u8) void {
        const gc = c.XCreateGC(self.display, win, 0, null);
        defer _ = c.XFreeGC(self.display, gc);
        _ = c.XSetForeground(self.display, gc, 0xFFFFFF);

        const font = c.XLoadQueryFont(self.display, "fixed");
        defer if (font) |f| {
            _ = c.XFreeFont(self.display, f);
        };
        if (font) |f| _ = c.XSetFont(self.display, gc, f.*.fid);

        const prefix = "duckwm: ";
        var buf: [200]u8 = undefined;
        const full_len = @min(prefix.len + msg.len, buf.len);
        @memcpy(buf[0..prefix.len], prefix);
        @memcpy(buf[prefix.len..full_len], msg[0 .. full_len - prefix.len]);
        _ = c.XDrawString(self.display, win, gc, 4, 14, &buf, @intCast(full_len));

        const x_label = "[x]";
        _ = c.XDrawString(self.display, win, gc, @intCast(width - 30), 14, x_label.ptr, x_label.len);
    }

    /// The input bar, holding the keyboard so every key comes back as a
    /// prompt_key event. Called again after each edit to redraw.
    pub fn show_prompt(self: *Backend, label: []const u8, text: []const u8, cursor: usize, block: bool) !void {
        const b = try self.open_bar();
        b.deadline = null;
        if (!b.grabbed) {
            if (c.XGrabKeyboard(self.display, self.root, 1, c.GrabModeAsync, c.GrabModeAsync, c.CurrentTime) != c.GrabSuccess) {
                self.hide_prompt();
                return error.KeyboardGrabFailed;
            }
            b.grabbed = true;
        }
        try self.set_bar(b, label, text, cursor, block);
    }

    /// Text in the input bar without taking the keyboard; gone after timeout_ms.
    pub fn show_message(self: *Backend, text: []const u8, timeout_ms: u32) !void {
        const b = try self.open_bar();
        if (b.grabbed) {
            _ = c.XUngrabKeyboard(self.display, c.CurrentTime);
            b.grabbed = false;
        }
        b.deadline = now_ms() + timeout_ms;
        try self.set_bar(b, "", text, null, false);
    }

    pub fn hide_prompt(self: *Backend) void {
        var b = self.bar orelse return;
        self.bar = null;
        if (b.grabbed) _ = c.XUngrabKeyboard(self.display, c.CurrentTime);
        const screen = c.XDefaultScreen(self.display);
        const visual = c.XDefaultVisual(self.display, screen);
        const cmap = c.XDefaultColormap(self.display, screen);
        c.XftColorFree(self.display, visual, cmap, &b.fg);
        c.XftColorFree(self.display, visual, cmap, &b.bg);
        c.XftDrawDestroy(b.draw);
        c.XftFontClose(self.display, b.font);
        _ = c.XDestroyWindow(self.display, b.win);
        b.content.deinit(self.allocator);
        _ = c.XFlush(self.display);
    }

    fn open_bar(self: *Backend) !*PromptBar {
        if (self.bar != null) return &self.bar.?;
        const screen = c.XDefaultScreen(self.display);
        const visual = c.XDefaultVisual(self.display, screen);
        const cmap = c.XDefaultColormap(self.display, screen);

        const font = c.XftFontOpenName(self.display, screen, prompt_font);
        if (font == null) return error.PromptFontFailed;
        errdefer c.XftFontClose(self.display, font);

        const width = self.screen_size().width;
        const height: c_uint = @intCast(font.*.height + 2 * prompt_pad);
        var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        wa.override_redirect = 1;
        wa.background_pixel = prompt_bg;
        const win = c.XCreateWindow(
            self.display,
            self.root,
            0,
            0,
            width,
            height,
            0,
            c.CopyFromParent,
            c.InputOutput,
            c.CopyFromParent,
            c.CWOverrideRedirect | c.CWBackPixel,
            &wa,
        );
        if (win == 0) return error.PromptCreateFailed;
        errdefer _ = c.XDestroyWindow(self.display, win);

        const draw = c.XftDrawCreate(self.display, win, visual, cmap) orelse return error.PromptCreateFailed;
        var fg: c.XftColor = undefined;
        var bg: c.XftColor = undefined;
        _ = c.XftColorAllocValue(self.display, visual, cmap, &render_color(prompt_fg), &fg);
        _ = c.XftColorAllocValue(self.display, visual, cmap, &render_color(@intCast(prompt_bg)), &bg);

        _ = c.XSelectInput(self.display, win, c.ExposureMask);
        _ = c.XMapRaised(self.display, win);
        self.bar = .{ .win = win, .draw = draw, .font = font, .fg = fg, .bg = bg };
        return &self.bar.?;
    }

    fn set_bar(self: *Backend, b: *PromptBar, label: []const u8, text: []const u8, cursor: ?usize, block: bool) !void {
        b.content.clearRetainingCapacity();
        try b.content.appendSlice(self.allocator, label);
        try b.content.appendSlice(self.allocator, text);
        b.label_len = label.len;
        b.cursor = cursor;
        b.block = block;
        self.draw_bar(b);
    }

    fn draw_bar(self: *Backend, b: *PromptBar) void {
        _ = c.XClearWindow(self.display, b.win);
        const s = b.content.items;
        const y: c_int = prompt_pad + b.font.*.ascent;
        if (s.len > 0) c.XftDrawStringUtf8(b.draw, &b.fg, b.font, prompt_pad, y, s.ptr, @intCast(s.len));
        if (b.cursor) |cur| {
            const at = b.label_len + cur;
            const x = prompt_pad + self.text_width(b.font, s[0..at]);
            const h: c_uint = @intCast(b.font.*.height);
            if (b.block) {
                // A block over the character, which is drawn again in the background color.
                const end = if (at < s.len) @min(s.len, at + (std.unicode.utf8ByteSequenceLength(s[at]) catch 1)) else at;
                const ch: []const u8 = if (end > at) s[at..end] else " ";
                const w: c_uint = @intCast(@max(1, self.text_width(b.font, ch)));
                c.XftDrawRect(b.draw, &b.fg, x, prompt_pad, w, h);
                c.XftDrawStringUtf8(b.draw, &b.bg, b.font, x, y, ch.ptr, @intCast(ch.len));
            } else {
                c.XftDrawRect(b.draw, &b.fg, x, prompt_pad, 2, h);
            }
        }
        _ = c.XRaiseWindow(self.display, b.win);
        _ = c.XFlush(self.display);
    }

    fn text_width(self: *const Backend, font: [*c]c.XftFont, s: []const u8) c_int {
        if (s.len == 0) return 0;
        var gi: c.XGlyphInfo = undefined;
        c.XftTextExtentsUtf8(self.display, font, s.ptr, @intCast(s.len), &gi);
        return gi.xOff;
    }

    /// A key typed into the bar: its keysym and the UTF-8 text it types.
    fn prompt_key(ev: *c.XKeyEvent) types.Event {
        var latin1: [8]u8 = undefined;
        var sym: c.KeySym = 0;
        const n: usize = @intCast(@max(0, c.XLookupString(ev, &latin1, latin1.len, &sym, null)));
        var k: types.PromptKey = .{
            .keysym = @intCast(sym),
            .mods = @intCast(ev.state & ~@as(c_uint, c.LockMask | c.Mod2Mask)),
        };
        // XLookupString speaks Latin-1; core wants UTF-8.
        for (latin1[0..n]) |ch| {
            const len = std.unicode.utf8Encode(ch, k.text_buf[k.text_len..]) catch break;
            k.text_len += len;
        }
        // Keysyms past Latin-1 that carry their code point (0x01000000 | cp).
        if (n == 0 and sym >= 0x01000100 and sym <= 0x0110ffff) {
            k.text_len = std.unicode.utf8Encode(@intCast(sym - 0x01000000), &k.text_buf) catch 0;
        }
        return .{ .prompt_key = k };
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
        const theme_z = std.fmt.bufPrintZ(&theme_buf, "{s}", .{theme}) catch return;
        _ = c.setenv("XCURSOR_THEME", theme_z.ptr, 1);

        var size_buf: [16]u8 = undefined;
        const size_z = std.fmt.bufPrintZ(&size_buf, "{d}", .{size}) catch return;
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

    pub fn keysym_from_name(self: *const Backend, name: []const u8) ?types.Keysym {
        _ = self;
        var buf: [64]u8 = undefined;
        const z = std.fmt.bufPrintZ(&buf, "{s}", .{name}) catch return null;
        const ks = c.XStringToKeysym(z.ptr);
        if (ks == c.NoSymbol) return null;
        return @intCast(ks);
    }

    pub fn grab_key(self: *const Backend, k: types.KeyCombo) void {
        const keycode = c.XKeysymToKeycode(self.display, k.keysym);
        if (keycode == 0) return;
        const mods: c_uint = k.mods;
        for (key_lock_masks) |lock| {
            _ = c.XGrabKey(self.display, keycode, mods | lock, self.root, 1, c.GrabModeAsync, c.GrabModeAsync);
        }
    }

    pub fn ungrab_all_keys(self: *const Backend) void {
        _ = c.XUngrabKey(self.display, c.AnyKey, c.AnyModifier, self.root);
        _ = c.XSync(self.display, 0);
    }

    pub fn release_keyboard_grab(self: *const Backend) void {
        if (self.bar) |b| if (b.grabbed) return; // the input bar holds it
        _ = c.XUngrabKeyboard(self.display, c.CurrentTime);
        _ = c.XSync(self.display, 0);
    }

    pub fn set_pointer_grabs(self: *Backend, grabs: []const types.PointerGrab) void {
        for (self.pointer_grabs[0..self.pointer_grab_count]) |g| {
            const btn: c_uint = if (g.button) |b| b else c.AnyButton;
            const mods: c_uint = g.mods;
            for (key_lock_masks) |lock| {
                _ = c.XUngrabButton(self.display, btn, mods | lock, self.root);
            }
        }

        const n = @min(grabs.len, self.pointer_grabs.len);
        for (grabs[0..n], 0..) |g, i| {
            self.pointer_grabs[i] = g;
            const btn: c_uint = if (g.button) |b| b else c.AnyButton;
            const mods: c_uint = g.mods;
            for (key_lock_masks) |lock| {
                _ = c.XGrabButton(
                    self.display,
                    btn,
                    mods | lock,
                    self.root,
                    0,
                    c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
                    c.GrabModeAsync,
                    c.GrabModeAsync,
                    c.None,
                    c.None,
                );
            }
        }
        self.pointer_grab_count = n;
        _ = c.XFlush(self.display);
    }

    /// Become the window manager for this display.
    pub fn start(self: *Backend) !void {
        wm_detected = false;
        _ = c.XSetErrorHandler(on_wm_detected);
        _ = c.XSelectInput(self.display, self.root, root_event_mask);
        _ = c.XSync(self.display, 0);
        if (wm_detected) return error.AnotherWmRunning;

        _ = c.XSetErrorHandler(on_x_error);
        self.announce_supported();
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
            self.set_active_window(0);
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
        if (model.takes_focus) self.send_protocol(win, self.atoms.WM_TAKE_FOCUS);
        self.set_active_window(if (publish_active) win else 0);
        return true;
    }

    fn set_active_window(self: *const Backend, win: c.Window) void {
        _ = c.XChangeProperty(self.display, self.root, self.atoms._NET_ACTIVE_WINDOW, self.atoms.WINDOW, 32, c.PropModeReplace, @ptrCast(&win), 1);
    }

    /// Crossing events caused by our own reconfiguration arrive as NotifyGrab
    /// while this is active, so focus-follows-mouse ignores them.
    pub fn begin_ignore_crossing(self: *const Backend) void {
        _ = c.XGrabPointer(
            self.display,
            self.root,
            0,
            c.PointerMotionMask | c.ButtonPressMask | c.ButtonReleaseMask,
            c.GrabModeAsync,
            c.GrabModeAsync,
            c.None,
            c.None,
            c.CurrentTime,
        );
    }

    pub fn end_ignore_crossing(self: *const Backend) void {
        _ = c.XUngrabPointer(self.display, c.CurrentTime);
    }

    fn announce_supported(self: *Backend) void {
        const a = &self.atoms;
        const supported = [_]c.Atom{
            a._NET_WM_STATE,            a._NET_WM_STATE_FULLSCREEN, a._NET_WM_STATE_DEMANDS_ATTENTION,
            a._NET_WM_WINDOW_TYPE,      a._NET_WM_WINDOW_TYPE_DOCK, a._NET_WM_WINDOW_TYPE_TOOLBAR,
            a._NET_WM_STRUT_PARTIAL,    a._NET_WORKAREA,            a._NET_ACTIVE_WINDOW,
            a._NET_NUMBER_OF_DESKTOPS,  a._NET_CURRENT_DESKTOP,     a._NET_CLIENT_LIST,
            a._NET_WM_DESKTOP,          a.WM_HINTS,                 a._NET_FRAME_EXTENTS,
            a._NET_SUPPORTING_WM_CHECK, a._NET_WM_NAME,
        };
        _ = c.XChangeProperty(self.display, self.root, a._NET_SUPPORTED, a.ATOM, 32, c.PropModeReplace, @ptrCast(&supported), supported.len);

        self.check_win = c.XCreateSimpleWindow(self.display, self.root, -1, -1, 1, 1, 0, 0, 0);
        _ = c.XChangeProperty(self.display, self.root, a._NET_SUPPORTING_WM_CHECK, a.WINDOW, 32, c.PropModeReplace, @ptrCast(&self.check_win), 1);
        _ = c.XChangeProperty(self.display, self.check_win, a._NET_SUPPORTING_WM_CHECK, a.WINDOW, 32, c.PropModeReplace, @ptrCast(&self.check_win), 1);
        _ = c.XChangeProperty(self.display, self.check_win, a._NET_WM_NAME, a.UTF8_STRING, 8, c.PropModeReplace, "duckwm", 6);
    }

    /// Tell the outside world whether h is fullscreen, preserving its other states.
    pub fn publish_window_fullscreen(self: *const Backend, h: types.WindowHandle, on: bool) void {
        const win: c.Window = @intCast(h);
        const a = &self.atoms;

        var current: [32]c.Atom = undefined;
        var next: [33]c.Atom = undefined;
        var n: usize = 0;
        for (info_mod.read_atoms(self.display, win, a._NET_WM_STATE, &current)) |s| {
            if (s == a._NET_WM_STATE_FULLSCREEN) continue;
            next[n] = s;
            n += 1;
        }
        if (on) {
            next[n] = a._NET_WM_STATE_FULLSCREEN;
            n += 1;
        }
        _ = c.XChangeProperty(self.display, win, a._NET_WM_STATE, a.ATOM, 32, c.PropModeReplace, @ptrCast(&next), @intCast(n));
    }

    /// Advertise the decoration size to every framed client.
    pub fn publish_frame_extents(self: *const Backend, border_width: u32) void {
        var it = self.frames.by_client.keyIterator();
        while (it.next()) |client| self.set_frame_extents(client.*, border_width);
    }

    pub fn set_click_to_focus(self: *Backend, enabled: bool) void {
        self.click_to_focus = enabled;
        var it = self.frames.by_frame.keyIterator();
        while (it.next()) |f| {
            if (enabled) self.grab_click_to_focus(f.*) else self.ungrab_click_to_focus(f.*);
        }
    }

    pub fn frame_of(self: *const Backend, client: c.Window) ?c.Window {
        return self.frames.frame_of(client);
    }

    pub fn client_of(self: *const Backend, frame: c.Window) ?c.Window {
        return self.frames.client_of(frame);
    }

    pub fn is_frame(self: *const Backend, win: c.Window) bool {
        return self.frames.client_of(win) != null;
    }

    fn set_wm_state(self: *const Backend, client: c.Window, state: c_ulong) void {
        const data = [2]c_ulong{ state, c.None }; // state, icon window
        _ = c.XChangeProperty(self.display, client, self.atoms.WM_STATE, self.atoms.WM_STATE, 32, c.PropModeReplace, @ptrCast(&data), 2);
    }

    /// Reparent client into a new frame.
    pub fn frame_window(self: *Backend, h: types.WindowHandle, opts: FrameOptions) !c.Window {
        const client: c.Window = @intCast(h);
        try self.frames.reserve(self.allocator); // nothing below this line can fail

        var attrs: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(self.display, client, &attrs) == 0) return error.WindowGone;

        const argb = if (opts.allow_argb and attrs.depth == 32) argb_visual(self.display) else null;
        const use_alpha = argb != null;
        const visual = argb orelse c.XDefaultVisual(self.display, 0);
        const depth = if (use_alpha) @as(c_int, 32) else c.XDefaultDepth(self.display, 0);
        const colormap = if (use_alpha)
            c.XCreateColormap(self.display, self.root, visual, c.AllocNone)
        else
            c.XDefaultColormap(self.display, 0);

        var swa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
        swa.backing_store = c.WhenMapped;
        swa.bit_gravity = c.NorthWestGravity;
        swa.win_gravity = c.NorthWestGravity;
        swa.border_pixel = opts.border_color;
        swa.background_pixel = if (use_alpha) 0x00000000 else c.None;
        swa.colormap = colormap;
        const mask: c_ulong = c.CWBackingStore | c.CWBitGravity | c.CWWinGravity |
            c.CWBorderPixel | c.CWBackPixel | c.CWColormap;

        const frame = c.XCreateWindow(
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
            &swa,
        );
        if (frame == 0) {
            if (use_alpha) _ = c.XFreeColormap(self.display, colormap);
            return error.FrameCreationFailed;
        }

        const xdnd_version: c_ulong = 5;
        _ = c.XChangeProperty(self.display, frame, self.atoms.XdndAware, self.atoms.ATOM, 32, c.PropModeReplace, @ptrCast(&xdnd_version), 1);
        _ = c.XChangeProperty(self.display, client, self.atoms.XdndAware, self.atoms.ATOM, 32, c.PropModeReplace, @ptrCast(&xdnd_version), 1);

        if (use_alpha) _ = c.XSetWindowBackgroundPixmap(self.display, frame, c.None);

        // Offscreen until the first flush positions it.
        _ = c.XMoveWindow(self.display, frame, -10000, -10000);

        if (self.click_to_focus) self.grab_click_to_focus(frame);

        _ = c.XSelectInput(self.display, frame, frame_event_mask);

        const bw: c_int = @intCast(opts.border_width);
        _ = c.XAddToSaveSet(self.display, client);
        _ = c.XReparentWindow(self.display, client, frame, bw, bw);
        _ = c.XSetWindowBorderWidth(self.display, client, 0);
        _ = c.XSync(self.display, 0);

        if (opts.configured_size) |s| {
            var ce: c.XEvent = std.mem.zeroes(c.XEvent);
            ce.xconfigure.type = c.ConfigureNotify;
            ce.xconfigure.display = self.display;
            ce.xconfigure.event = client;
            ce.xconfigure.window = client;
            ce.xconfigure.x = attrs.x;
            ce.xconfigure.y = attrs.y;
            ce.xconfigure.width = @intCast(s.width);
            ce.xconfigure.height = @intCast(s.height);
            ce.xconfigure.above = c.None;
            _ = c.XSendEvent(self.display, client, 0, c.StructureNotifyMask, &ce);
        }

        self.set_frame_extents(client, opts.border_width);
        const model = info_mod.read_focus_model(self.display, &self.atoms, client);
        self.frames.put_reserved(client, frame, use_alpha, model);
        _ = c.XSelectInput(self.display, client, c.PropertyChangeMask);
        self.set_wm_state(client, NormalState);
        return frame;
    }

    /// Stop framing client. With keep_client, it is reparented to the root first so it survives.
    pub fn unframe(self: *Backend, h: types.WindowHandle, keep_client: bool) void {
        const client: c.Window = @intCast(h);
        const frame = self.frames.remove(client) orelse return;
        _ = self.applied.remove(client);
        if (keep_client) {
            _ = c.XReparentWindow(self.display, client, self.root, 0, 0);
            _ = c.XRemoveFromSaveSet(self.display, client);
            _ = c.XDeleteProperty(self.display, client, self.atoms.WM_STATE);
        }
        self.renderer.forget_icon(self.allocator, client);
        self.destroy_frame_window(frame);
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

    fn destroy_frame_window(self: *Backend, frame: c.Window) void {
        var attrs: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(self.display, frame, &attrs) != 0) {
            const default_cmap = c.XDefaultColormap(self.display, 0);
            if (attrs.colormap != 0 and attrs.colormap != default_cmap) {
                _ = c.XFreeColormap(self.display, attrs.colormap);
            }
        }
        _ = c.XDestroyWindow(self.display, frame);
    }

    fn set_frame_extents(self: *const Backend, client: c.Window, bw: u32) void {
        const v: c_ulong = bw;
        const vals = [4]c_ulong{ v, v, v, v };
        _ = c.XChangeProperty(self.display, client, self.atoms._NET_FRAME_EXTENTS, self.atoms.CARDINAL, 32, c.PropModeReplace, @ptrCast(&vals), 4);
    }

    fn grab_click_to_focus(self: *const Backend, frame: c.Window) void {
        _ = c.XGrabButton(self.display, c.Button1, c.AnyModifier, frame, 0, c.ButtonPressMask | c.ButtonReleaseMask, c.GrabModeSync, c.GrabModeAsync, c.None, c.None);
    }

    fn ungrab_click_to_focus(self: *const Backend, frame: c.Window) void {
        _ = c.XUngrabButton(self.display, c.Button1, c.AnyModifier, frame);
    }

    /// Paint the border of window handle inside its frame.
    /// size is the frame size if the caller knows it; otherwise it's queried.
    pub fn draw_borders(self: *Backend, handle: types.WindowHandle, colors: types.BorderColors, width: u32, size: ?types.Size) void {
        if (width == 0) return;
        const client: c.Window = @intCast(handle);
        const frame = self.frames.frame_of(client) orelse return;

        const sz: types.Size = if (size) |s| s else if (self.applied.get(client)) |a|
            .{ .width = a.frame.width, .height = a.frame.height }
        else
            (self.frame_size(frame) orelse return);

        self.paint(frame, colors, width, sz);
        if (self.applied.getPtr(client)) |a| a.borders = colors;
    }

    fn paint(self: *const Backend, frame: c.Window, colors: types.BorderColors, width: u32, sz: types.Size) void {
        if (width == 0) return;
        const gc = c.XCreateGC(self.display, frame, 0, null);
        defer _ = c.XFreeGC(self.display, gc);

        const bw: c_uint = width;
        const w: c_uint = sz.width;
        const h: c_uint = sz.height;
        const ibw: c_int = @intCast(width);
        const iw: c_int = @intCast(sz.width);
        const ih: c_int = @intCast(sz.height);

        _ = c.XSetForeground(self.display, gc, self.pixel(frame, colors.top));
        _ = c.XFillRectangle(self.display, frame, gc, 0, 0, w, bw);
        _ = c.XSetForeground(self.display, gc, self.pixel(frame, colors.bottom));
        _ = c.XFillRectangle(self.display, frame, gc, 0, ih - ibw, w, bw);
        _ = c.XSetForeground(self.display, gc, self.pixel(frame, colors.left));
        _ = c.XFillRectangle(self.display, frame, gc, 0, 0, bw, h);
        _ = c.XSetForeground(self.display, gc, self.pixel(frame, colors.right));
        _ = c.XFillRectangle(self.display, frame, gc, iw - ibw, 0, bw, h);
    }

    /// ARGB frames need an alpha byte; colors given without one are opaque.
    fn pixel(self: *const Backend, frame: c.Window, rgb: u32) c_ulong {
        if (self.frames.is_argb(frame) and (rgb >> 24) == 0) return rgb | 0xFF000000;
        return rgb;
    }

    fn frame_size(self: *const Backend, frame: c.Window) ?types.Size {
        var root_ret: c.Window = undefined;
        var x: c_int = 0;
        var y: c_int = 0;
        var w: c_uint = 0;
        var h: c_uint = 0;
        var bw: c_uint = 0;
        var depth: c_uint = 0;
        if (c.XGetGeometry(self.display, frame, &root_ret, &x, &y, &w, &h, &bw, &depth) == 0) return null;
        return .{ .width = w, .height = h };
    }

    /// Bring the screen in line with states, sending only what changed.
    pub fn apply_windows(self: *Backend, states: []const types.WindowState, fullscreen: ?types.WindowHandle) void {
        const batch = self.begin_batch();
        self.apply_gen +%= 1;
        for (states) |s| self.apply_one(s);

        // Shown before but not in this scene: hide. Runs after the maps, so
        // switching workspaces never flashes an empty screen.
        var it = self.applied.iterator();
        while (it.next()) |e| {
            const a = e.value_ptr;
            if (a.gen == self.apply_gen or !a.mapped) continue;
            if (self.frames.frame_of(e.key_ptr.*)) |f| _ = c.XUnmapWindow(self.display, f);
            a.mapped = false;
        }

        // Stacking: docks on top, tiled frames at the bottom, fullscreen above everything.
        self.raise_docks();
        for (states) |s| {
            if (!s.tiled) continue;
            if (self.frames.frame_of(@intCast(s.handle))) |f| _ = c.XLowerWindow(self.display, f);
        }
        if (fullscreen) |h| {
            if (self.frames.frame_of(@intCast(h))) |f| _ = c.XRaiseWindow(self.display, f);
        }
        self.end_batch(batch);
        _ = c.XFlush(self.display);
    }

    fn apply_one(self: *Backend, s: types.WindowState) void {
        const client: c.Window = @intCast(s.handle);
        const frame = self.frames.frame_of(client) orelse return;
        const prev = self.applied.get(client);

        const geometry_changed = if (prev) |p|
            !rect_eql(p.frame, s.frame) or p.border_width != s.border_width
        else
            true;
        const colors_changed = if (prev) |p| !colors_eql(p.borders, s.borders) else true;

        const bw = s.border_width;
        const ibw: i32 = @intCast(bw);
        const cw: u32 = @max(1, s.frame.width -| 2 * bw);
        const ch: u32 = @max(1, s.frame.height -| 2 * bw);

        // X coordinates are 16-bit; panned layouts can exceed that.
        const x = clamp16(s.frame.x);
        const y = clamp16(s.frame.y);
        var configure_pending = if (prev) |p| p.configure_pending else false;
        if (geometry_changed) {
            _ = c.XMoveResizeWindow(self.display, frame, x, y, s.frame.width, s.frame.height);
            _ = c.XMoveResizeWindow(self.display, client, ibw, ibw, cw, ch);
            _ = c.XSetWindowBorderWidth(self.display, client, 0);
            configure_pending = true;
        }
        if (configure_pending and !s.interactive) {
            self.send_configure(client, x + ibw, y + ibw, cw, ch);
            configure_pending = false;
        }

        const was_mapped = if (prev) |p| p.mapped else false;
        if (!was_mapped) {
            _ = c.XMapWindow(self.display, client);
            _ = c.XMapWindow(self.display, frame);
        }

        if (s.borders) |colors| {
            if (geometry_changed or colors_changed) {
                self.paint(frame, colors, bw, .{ .width = s.frame.width, .height = s.frame.height });
            }
        }

        self.applied.put(self.allocator, client, .{
            .frame = s.frame,
            .configure_pending = configure_pending,
            .border_width = bw,
            .borders = s.borders,
            .mapped = true,
            .gen = self.apply_gen,
        }) catch {};
    }

    /// Hide h now, without waiting for the next apply.
    pub fn hide_window(self: *Backend, h: types.WindowHandle) void {
        const client: c.Window = @intCast(h);
        const frame = self.frames.frame_of(client) orelse return;
        if (self.applied.getPtr(client)) |a| {
            if (!a.mapped) return;
            a.mapped = false;
        }
        const batch = self.begin_batch();
        _ = c.XUnmapWindow(self.display, frame);
        self.end_batch(batch);
    }

    /// Bring h above other windows (but below docks).
    pub fn raise_window(self: *Backend, h: types.WindowHandle) void {
        const f = self.frames.frame_of(@intCast(h)) orelse return;
        const batch = self.begin_batch();
        _ = c.XSelectInput(self.display, f, frame_event_mask & ~@as(c_long, c.EnterWindowMask | c.LeaveWindowMask));
        self.stack_below_docks(f);
        _ = c.XSelectInput(self.display, f, frame_event_mask);
        self.end_batch(batch);
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

    /// Tell the client its real root-relative geometry (ICCCM 4.1.5).
    fn send_configure(self: *const Backend, client: c.Window, x: i32, y: i32, w: u32, h: u32) void {
        var ce: c.XEvent = std.mem.zeroes(c.XEvent);
        ce.xconfigure.type = c.ConfigureNotify;
        ce.xconfigure.display = self.display;
        ce.xconfigure.event = client;
        ce.xconfigure.window = client;
        ce.xconfigure.x = x;
        ce.xconfigure.y = y;
        ce.xconfigure.width = @intCast(w);
        ce.xconfigure.height = @intCast(h);
        ce.xconfigure.border_width = 0;
        ce.xconfigure.above = c.None;
        ce.xconfigure.override_redirect = 0;
        _ = c.XSendEvent(self.display, client, 0, c.StructureNotifyMask, &ce);
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
            if (self.translate(&self.event_buf)) |ev| return ev;
        }
        return null;
    }

    fn translate(self: *Backend, e: *c.XEvent) ?types.Event {
        switch (e.type) {
            c.KeyPress => {
                if (self.bar) |b| if (b.grabbed) return prompt_key(&e.xkey);
                const keysym = c.XkbKeycodeToKeysym(self.display, @as(u8, @truncate(e.xkey.keycode)), 0, 0);
                const mods = e.xkey.state & ~@as(c_uint, c.LockMask | c.Mod2Mask);
                return .{ .key = .{ .mods = @intCast(mods), .keysym = @intCast(keysym) } };
            },
            c.Expose => {
                if (e.xexpose.count != 0) return null;
                if (self.bar) |*b| if (e.xexpose.window == b.win) {
                    self.draw_bar(b);
                    return null;
                };
                const client = self.frames.client_of(e.xexpose.window) orelse return null;
                return .{ .expose = client };
            },
            c.MappingNotify => {
                _ = c.XRefreshKeyboardMapping(&e.xmapping);
                if (e.xmapping.request == c.MappingKeyboard or e.xmapping.request == c.MappingModifier) {
                    self.ungrab_all_keys();
                    return .keymap_changed;
                }
                return null;
            },
            c.ConfigureRequest => {
                self.handle_configure_request(&e.xconfigurerequest);
                return null;
            },
            c.ConfigureNotify => {
                const rect: types.Rect = .{
                    .x = e.xconfigure.x,
                    .y = e.xconfigure.y,
                    .width = @intCast(e.xconfigure.width),
                    .height = @intCast(e.xconfigure.height),
                };
                return if (self.docks.set_rect(e.xconfigure.window, rect)) .reserved_area_changed else null;
            },
            c.CreateNotify, c.ReparentNotify => return null,
            c.MapRequest => return self.translate_map_request(&e.xmaprequest),
            c.MapNotify => {
                if (self.overlays.contains(e.xmap.window)) {
                    _ = c.XSetInputFocus(self.display, e.xmap.window, c.RevertToParent, c.CurrentTime);
                }
                return null;
            },
            c.UnmapNotify => return self.translate_unmap(&e.xunmap),
            c.DestroyNotify => return self.translate_destroy(&e.xdestroywindow),
            c.PropertyNotify => return self.translate_property(&e.xproperty),
            c.ClientMessage => {
                if (self.forward_xdnd(&e.xclient)) return null;
                return self.translate_client_message(&e.xclient);
            },
            c.ButtonPress => return self.translate_button(&e.xbutton, true),
            c.ButtonRelease => return self.translate_button(&e.xbutton, false),
            c.MotionNotify => {
                // Only the latest position matters; drop the queued backlog.
                var latest = e.xmotion;
                var next: c.XEvent = undefined;
                while (c.XCheckTypedEvent(self.display, c.MotionNotify, &next) != 0) latest = next.xmotion;
                return .{ .pointer_motion = .{ .x = latest.x_root, .y = latest.y_root } };
            },
            c.EnterNotify => return self.translate_enter(&e.xcrossing),
            c.LeaveNotify => return null,
            else => return null,
        }
    }

    fn translate_map_request(self: *Backend, req: *c.XMapRequestEvent) ?types.Event {
        const win = req.window;
        var attrs: c.XWindowAttributes = undefined;
        if (c.XGetWindowAttributes(self.display, win, &attrs) == 0) return null; // already gone
        if (attrs.override_redirect != 0) return null;

        // Already ours (e.g. remapped after being hidden): just map the client.
        if (self.frames.frame_of(win) != null) {
            _ = c.XMapWindow(self.display, win);
            return null;
        }

        const traits = info_mod.read_traits(self.display, &self.atoms, self.root, win);
        if (traits.kind == .dock) {
            _ = c.XMapWindow(self.display, win);
            self.dock_add(win, self.read_strut(win) orelse Strut{}) catch return null;
            self.dock_restack();
            if (traits.focusable_dock) self.overlays.put(self.allocator, win, {}) catch {};
            return .reserved_area_changed;
        }

        return .{ .map_request = .{
            .window = win,
            .size = .{ .width = @intCast(attrs.width), .height = @intCast(attrs.height) },
            .traits = traits,
        } };
    }

    fn translate_unmap(self: *Backend, ev: *c.XUnmapEvent) ?types.Event {
        const win = ev.window;

        if (self.ignore_unmaps.getPtr(win)) |n| {
            n.* -= 1;
            if (n.* == 0) _ = self.ignore_unmaps.remove(win);
            return null;
        }
        if (self.overlays.contains(win)) return .refocus;
        if (self.docks.remove(win)) {
            self.dock_restack();
            return .reserved_area_changed;
        }
        if (self.is_frame(win)) return null; // our own frame being hidden
        if (self.frames.frame_of(win) == null) return null; // not a managed client
        if (ev.send_event != 0) return null; // synthetic, from reparenting

        // The client withdrew itself: rescue it from the frame before the frame goes.
        self.unframe(win, true);
        return .{ .window_gone = win };
    }

    fn translate_destroy(self: *Backend, ev: *c.XDestroyWindowEvent) ?types.Event {
        const win = ev.window;
        _ = self.overlays.remove(win);
        _ = self.ignore_unmaps.remove(win);
        if (self.docks.remove(win)) {
            self.dock_restack();
            return .reserved_area_changed;
        }
        if (self.is_frame(win)) return null;
        self.unframe(win, false);
        return .{ .window_gone = win };
    }

    fn translate_property(self: *Backend, ev: *c.XPropertyEvent) ?types.Event {
        const a = &self.atoms;
        const win = ev.window;
        const atom = ev.atom;

        if (atom == a._NET_WM_ICON) {
            self.renderer.forget_icon(self.allocator, win);
            return null;
        }
        if (atom == a.WM_CLASS or atom == a.WM_NAME or atom == a._NET_WM_NAME) {
            return .{ .info_changed = win };
        }
        if (atom == a.WM_PROTOCOLS) {
            self.refresh_focus_model(win);
            return null;
        }
        if (atom == a.WM_HINTS) {
            if (self.frames.frame_of(win) == null) return null;
            self.refresh_focus_model(win);
            const hints = c.XGetWMHints(self.display, win);
            // A cleared hint (null) still counts: xterm drops it right after setting it.
            const urgent = if (hints != null) blk: {
                defer _ = c.XFree(hints);
                break :blk (hints.*.flags & c.XUrgencyHint) != 0;
            } else true;
            return .{ .urgency_hint = .{ .window = win, .urgent = urgent } };
        }
        if (atom == a._NET_WM_WINDOW_TYPE) {
            if (self.frames.frame_of(win) == null) return null;
            if (info_mod.read_traits(self.display, &self.atoms, self.root, win).kind != .dock) return null;
            if (self.read_strut(win)) |s| self.dock_add(win, s) catch {};
            return .{ .became_dock = win };
        }
        if (atom == a._NET_WM_STRUT_PARTIAL) {
            return if (self.dock_set_strut(win, self.read_strut(win))) .reserved_area_changed else null;
        }
        return null;
    }

    fn translate_client_message(self: *Backend, ev: *c.XClientMessageEvent) ?types.Event {
        const a = &self.atoms;

        if (ev.message_type == a._NET_ACTIVE_WINDOW) {
            return .{ .activate_request = ev.window };
        }

        if (ev.message_type == a._NET_WM_STATE) {
            const action: types.StateAction = switch (ev.data.l[0]) {
                0 => .remove,
                1 => .add,
                2 => .toggle,
                else => return null,
            };
            const p1: c.Atom = @bitCast(ev.data.l[1]);
            const p2: c.Atom = @bitCast(ev.data.l[2]);
            const fullscreen = p1 == a._NET_WM_STATE_FULLSCREEN or p2 == a._NET_WM_STATE_FULLSCREEN;
            const attention = p1 == a._NET_WM_STATE_DEMANDS_ATTENTION or p2 == a._NET_WM_STATE_DEMANDS_ATTENTION;
            if (!fullscreen and !attention) return null;
            return .{ .state_request = .{
                .window = ev.window,
                .action = action,
                .fullscreen = fullscreen,
                .attention = attention,
            } };
        }
        return null;
    }

    fn translate_button(self: *Backend, ev: *c.XButtonEvent, pressed: bool) ?types.Event {
        if (pressed and self.is_error_bar(ev.window)) {
            return if (self.hide_error()) .reserved_area_changed else null;
        }

        const mods: types.Mods = @intCast(ev.state &
            ~@as(c_uint, c.LockMask | c.Mod2Mask | c.Mod3Mask | c.Mod5Mask));
        const lookup = if (ev.window == self.root) ev.subwindow else ev.window;
        const window: ?types.WindowHandle = if (lookup != 0) self.frames.client_of(lookup) else null;

        // A click caught by the click-to-focus grab freezes the pointer until we
        // decide: keep it if it starts a WM drag, otherwise pass it to the client.
        if (pressed and self.click_to_focus and self.is_frame(ev.window)) {
            const mode = if (self.is_drag_modifier(mods)) c.AsyncPointer else c.ReplayPointer;
            _ = c.XAllowEvents(self.display, mode, c.CurrentTime);
        }

        const b: types.PointerButton = .{
            .window = window,
            .button = @intCast(ev.button),
            .mods = mods,
            .pos = .{ .x = ev.x_root, .y = ev.y_root },
        };
        return if (pressed) .{ .button_press = b } else .{ .button_release = b };
    }

    fn is_drag_modifier(self: *const Backend, mods: types.Mods) bool {
        for (self.pointer_grabs[0..self.pointer_grab_count]) |g| {
            if (mods & g.mods != 0) return true;
        }
        return false;
    }

    fn translate_enter(self: *Backend, ev: *c.XCrossingEvent) ?types.Event {
        // Grab/ungrab crossings and moves into a child aren't real "entering".
        if (ev.mode != c.NotifyNormal or ev.detail == c.NotifyInferior) return null;
        if (self.caused_by_us(ev.serial)) return null;
        const lookup = if (ev.window == self.root) ev.subwindow else ev.window;
        if (lookup == 0) return null;
        if (self.frames.client_of(lookup)) |client| return .{ .pointer_enter = client };
        if (self.frames.frame_of(lookup) != null) return null; // a client itself: nothing to do
        self.release_keyboard_grab(); // over something unmanaged
        return null;
    }

    fn refresh_focus_model(self: *Backend, win: c.Window) void {
        if (self.frames.focus_models.getPtr(win)) |m| {
            m.* = info_mod.read_focus_model(self.display, &self.atoms, win);
        }
    }

    fn handle_configure_request(self: *Backend, req: *c.XConfigureRequestEvent) void {
        var mask = req.value_mask;
        if (self.docks.contains(req.window)) mask &= ~@as(c_ulong, c.CWX | c.CWY);
        var changes = c.XWindowChanges{
            .x = req.x,
            .y = req.y,
            .width = req.width,
            .height = req.height,
            .border_width = req.border_width,
            .sibling = req.above,
            .stack_mode = req.detail,
        };
        _ = c.XConfigureWindow(self.display, req.window, @intCast(mask), &changes);
        if (self.frames.frame_of(req.window) != null) self.invalidate_window(req.window);
    }

    /// XDND messages that duckwm relays between drag sources and framed clients.
    /// Returns true if the message was XDND and has been handled.
    fn forward_xdnd(self: *Backend, ev: *c.XClientMessageEvent) bool {
        const a = &self.atoms;
        const mt = ev.message_type;

        // Replies from a client back to the drag source.
        if (mt == a.XdndStatus or mt == a.XdndFinished) {
            const source: c.Window = @intCast(ev.data.l[0]);
            if (source == 0) return false;
            var fwd = ev.*;
            fwd.window = source;
            _ = c.XSendEvent(self.display, source, 0, c.NoEventMask, @ptrCast(&fwd));
            return true;
        }

        // Messages from a drag source to one of our frames.
        if (mt != a.XdndEnter and mt != a.XdndPosition and mt != a.XdndLeave and mt != a.XdndDrop) return false;
        const client = self.frames.client_of(ev.window) orelse return false;
        const source: c.Window = @intCast(ev.data.l[0]);

        var fwd = ev.*;
        fwd.window = client;
        _ = c.XSendEvent(self.display, client, 0, c.NoEventMask, @ptrCast(&fwd));

        if (mt == a.XdndEnter or mt == a.XdndPosition) {
            var status: c.XEvent = std.mem.zeroes(c.XEvent);
            status.xclient.type = c.ClientMessage;
            status.xclient.display = self.display;
            status.xclient.window = source;
            status.xclient.message_type = a.XdndStatus;
            status.xclient.format = 32;
            status.xclient.data.l[0] = @intCast(ev.window);
            status.xclient.data.l[1] = 1;
            status.xclient.data.l[4] = @intCast(a.XdndActionCopy);
            _ = c.XSendEvent(self.display, source, 0, c.NoEventMask, &status);
        }
        return true;
    }

    /// End any pointer grab (e.g. an interrupted drag).
    pub fn release_pointer(self: *const Backend) void {
        _ = c.XUngrabPointer(self.display, c.CurrentTime);
    }

    /// Route all pointer motion and the button release to the WM (for a drag).
    pub fn capture_pointer(self: *const Backend) void {
        _ = c.XGrabPointer(
            self.display,
            self.root,
            0,
            c.PointerMotionMask | c.ButtonReleaseMask,
            c.GrabModeAsync,
            c.GrabModeAsync,
            c.None,
            c.None,
            c.CurrentTime,
        );
    }

    /// Wait until the server has processed everything sent so far.
    pub fn sync(self: *const Backend) void {
        _ = c.XSync(self.display, 0);
    }

    /// Start of a batch of requests whose side-effect crossings should be ignored.
    fn begin_batch(self: *const Backend) c_ulong {
        return c.XNextRequest(self.display);
    }

    /// End of the batch: remember its serial range, then send a no-op so that
    /// later, genuine events carry a serial outside of it.
    fn end_batch(self: *Backend, batch_start: c_ulong) void {
        const end = c.XNextRequest(self.display);
        if (end == batch_start) return; // nothing was sent
        _ = c.XNoOp(self.display);
        self.self_inflicted[self.self_inflicted_next] = .{ .start = batch_start, .end = end };
        self.self_inflicted_next = (self.self_inflicted_next + 1) % self.self_inflicted.len;
        self.self_inflicted_len = @min(self.self_inflicted_len + 1, self.self_inflicted.len);
    }

    fn caused_by_us(self: *const Backend, serial: c_ulong) bool {
        for (self.self_inflicted[0..self.self_inflicted_len]) |r| {
            if (serial >= r.start and serial < r.end) return true;
        }
        return false;
    }

    /// On X the session ends when the WM's process does (xinit/startx), so nothing to do.
    pub fn end_session(self: *Backend) void {
        _ = self;
    }

    /// Runs setxkbmap; the server's MappingNotify then triggers keymap_changed.
    pub fn set_keymap(self: *Backend, km: types.Keymap) bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var argv: std.ArrayListUnmanaged(?[*:0]const u8) = .empty;
        const add = struct {
            fn f(al: std.mem.Allocator, list: *std.ArrayListUnmanaged(?[*:0]const u8), s: []const u8) void {
                const zs = al.dupeZ(u8, s) catch return;
                list.append(al, zs.ptr) catch {};
            }
        }.f;
        add(a, &argv, "setxkbmap");
        add(a, &argv, "-layout");
        add(a, &argv, km.layout);
        if (km.variant.len > 0) {
            add(a, &argv, "-variant");
            add(a, &argv, km.variant);
        }
        if (km.model.len > 0) {
            add(a, &argv, "-model");
            add(a, &argv, km.model);
        }
        // An empty -option clears what's set; setxkbmap otherwise appends.
        add(a, &argv, "-option");
        add(a, &argv, "");
        if (km.options.len > 0) {
            add(a, &argv, "-option");
            add(a, &argv, km.options);
        }
        argv.append(a, null) catch return false;

        const pid = c.fork();
        if (pid < 0) return false;
        if (pid == 0) {
            _ = c.execvp("setxkbmap", @ptrCast(argv.items.ptr));
            c._exit(127);
        }
        var status: c_int = 0;
        _ = c.waitpid(pid, &status, 0);
        return true;
    }

    pub fn set_layout_index(self: *Backend, index: u32) void {
        _ = c.XkbLockGroup(self.display, c.XkbUseCoreKbd, index);
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
};
