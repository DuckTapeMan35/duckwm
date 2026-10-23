const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const Backend = @import("backend.zig").Backend;
const now_ms = @import("util.zig").now_ms;

const prompt_font = "monospace:size=11";
const prompt_bg: c_ulong = 0x1e1e2e;
const prompt_fg: u32 = 0xcdd6f4;
const prompt_pad: c_int = 4;

pub const PromptBar = struct {
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

fn render_color(rgb: u32) c.XRenderColor {
    return .{
        .red = @intCast(((rgb >> 16) & 0xff) * 0x101),
        .green = @intCast(((rgb >> 8) & 0xff) * 0x101),
        .blue = @intCast((rgb & 0xff) * 0x101),
        .alpha = 0xffff,
    };
}

// ---- error bar ----
/// Show msg in a reserved bar at the top of the screen, replacing any existing one.
pub fn show_error(self: *Backend, msg: []const u8) !void {
    _ = hide_error(self);

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

    draw_error_text(self, win, size.width, msg);

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

// ---- input bar ----
/// The input bar, holding the keyboard so every key comes back as a
/// prompt_key event. Called again after each edit to redraw.
pub fn show_prompt(self: *Backend, label: []const u8, text: []const u8, cursor: usize, block: bool) !void {
    const b = try open_bar(self);
    b.deadline = null;
    if (!b.grabbed) {
        if (c.XGrabKeyboard(self.display, self.root, 1, c.GrabModeAsync, c.GrabModeAsync, c.CurrentTime) != c.GrabSuccess) {
            hide_prompt(self);
            return error.KeyboardGrabFailed;
        }
        b.grabbed = true;
    }
    try set_bar(self, b, label, text, cursor, block);
}

/// Text in the input bar without taking the keyboard; gone after timeout_ms.
pub fn show_message(self: *Backend, text: []const u8, timeout_ms: u32) !void {
    const b = try open_bar(self);
    if (b.grabbed) {
        _ = c.XUngrabKeyboard(self.display, c.CurrentTime);
        b.grabbed = false;
    }
    b.deadline = now_ms() + timeout_ms;
    try set_bar(self, b, "", text, null, false);
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
    draw_bar(self, b);
}

pub fn draw_bar(self: *Backend, b: *PromptBar) void {
    _ = c.XClearWindow(self.display, b.win);
    const s = b.content.items;
    const y: c_int = prompt_pad + b.font.*.ascent;
    if (s.len > 0) c.XftDrawStringUtf8(b.draw, &b.fg, b.font, prompt_pad, y, s.ptr, @intCast(s.len));
    if (b.cursor) |cur| {
        const at = b.label_len + cur;
        const x = prompt_pad + text_width(self, b.font, s[0..at]);
        const h: c_uint = @intCast(b.font.*.height);
        if (b.block) {
            // A block over the character, which is drawn again in the background color.
            const end = if (at < s.len) @min(s.len, at + (std.unicode.utf8ByteSequenceLength(s[at]) catch 1)) else at;
            const ch: []const u8 = if (end > at) s[at..end] else " ";
            const w: c_uint = @intCast(@max(1, text_width(self, b.font, ch)));
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
pub fn prompt_key(ev: *c.XKeyEvent) types.Event {
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
