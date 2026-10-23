const std = @import("std");
const types = @import("types");
const c = @import("xlib");

pub fn now_ms() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
}

/// X11 coordinates are 16-bit: keep v inside them.
pub fn clamp16(v: i32) i32 {
    return @max(-32768, @min(32767, v));
}

pub fn rect_eql(a: types.Rect, b: types.Rect) bool {
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}

pub fn colors_eql(a: ?types.BorderColors, b: ?types.BorderColors) bool {
    if (a == null or b == null) return a == null and b == null;
    const x = a.?;
    const y = b.?;
    return x.top == y.top and x.bottom == y.bottom and x.left == y.left and x.right == y.right;
}

/// Replace win's property prop with vals, as a list of 32-bit items of the
/// given type (CARDINAL, ATOM, WINDOW...). Xlib passes them as longs.
pub fn set_prop32(display: *c.Display, win: c.Window, prop: c.Atom, kind: c.Atom, vals: []const c_ulong) void {
    _ = c.XChangeProperty(display, win, prop, kind, 32, c.PropModeReplace, @ptrCast(vals.ptr), @intCast(vals.len));
}

/// An Xft color for 0xRRGGBB on the default visual and colormap, or null.
/// Free it with free_color.
pub fn alloc_color(display: *c.Display, rgb: u32) ?c.XftColor {
    const screen = c.XDefaultScreen(display);
    var rc: c.XRenderColor = .{
        .red = @intCast(((rgb >> 16) & 0xff) * 0x101),
        .green = @intCast(((rgb >> 8) & 0xff) * 0x101),
        .blue = @intCast((rgb & 0xff) * 0x101),
        .alpha = 0xffff,
    };
    var col: c.XftColor = undefined;
    if (c.XftColorAllocValue(
        display,
        c.XDefaultVisual(display, screen),
        c.XDefaultColormap(display, screen),
        &rc,
        &col,
    ) == 0) return null;
    return col;
}

pub fn free_color(display: *c.Display, col: *c.XftColor) void {
    const screen = c.XDefaultScreen(display);
    c.XftColorFree(display, c.XDefaultVisual(display, screen), c.XDefaultColormap(display, screen), col);
}
