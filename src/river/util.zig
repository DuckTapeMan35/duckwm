const std = @import("std");
const types = @import("types");

pub fn now_ms() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    return ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
}

pub fn size_eql(a: types.Size, b: types.Size) bool {
    return a.width == b.width and a.height == b.height;
}

pub fn opt_eql(a: ?u32, b: ?u32) bool {
    if (a == null or b == null) return a == null and b == null;
    return a.? == b.?;
}

pub fn nonneg(v: i32) u32 {
    return @intCast(@max(0, v));
}
