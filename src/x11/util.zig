const std = @import("std");
const types = @import("types");

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
