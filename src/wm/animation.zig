const std = @import("std");
const types = @import("types");
const protocol = @import("protocol");

fn sample(comptime f: fn (f32) f32) types.CurveTable {
    var out: types.CurveTable = undefined;
    for (&out, 0..) |*v, i| v.* = f(t_at(i));
    return out;
}

/// The t of table entry i.
pub fn t_at(i: usize) f32 {
    return @as(f32, @floatFromInt(i)) / types.curve_samples;
}

fn ease_out(t: f32) f32 {
    return 1 - std.math.pow(f32, 1 - t, 3);
}
fn ease_in(t: f32) f32 {
    return t * t * t;
}
fn ease_in_out(t: f32) f32 {
    return if (t < 0.5) 4 * t * t * t else 1 - std.math.pow(f32, -2 * t + 2, 3) / 2;
}

pub fn preset(p: protocol.CurvePreset) types.CurveTable {
    return switch (p) {
        .linear => types.linear_curve,
        .ease_in => sample(ease_in),
        .ease_out => sample(ease_out),
        .ease_in_out => sample(ease_in_out),
    };
}

/// One axis of a CSS cubic-bezier: endpoints fixed at 0 and 1.
fn bez(a: f32, b: f32, s: f32) f32 {
    const u = 1 - s;
    return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s;
}

pub fn bezier(x1: f32, y1: f32, x2: f32, y2: f32) !types.CurveTable {
    if (!(x1 >= 0 and x1 <= 1 and x2 >= 0 and x2 <= 1)) return error.InvalidCurve;
    var out: types.CurveTable = undefined;
    for (&out, 0..) |*v, i| {
        const t = t_at(i);
        // x(s) is monotonic for x1, x2 in [0, 1]: find s with x(s) = t.
        var lo: f32 = 0;
        var hi: f32 = 1;
        for (0..30) |_| {
            const mid = (lo + hi) / 2;
            if (bez(x1, x2, mid) < t) lo = mid else hi = mid;
        }
        v.* = bez(y1, y2, (lo + hi) / 2);
    }
    return out;
}

/// Evenly spaced values from t = 0 to 1, linearly resampled to the table.
pub fn from_samples(s: []const f32) !types.CurveTable {
    if (s.len < 2) return error.InvalidCurve;
    for (s) |v| if (!std.math.isFinite(v)) return error.InvalidCurve;
    var out: types.CurveTable = undefined;
    const last: f32 = @floatFromInt(s.len - 1);
    for (&out, 0..) |*v, i| {
        const pos = @min(t_at(i), 1) * last;
        const k: usize = @min(@as(usize, @intFromFloat(pos)), s.len - 2);
        const frac = pos - @as(f32, @floatFromInt(k));
        v.* = s[k] + (s[k + 1] - s[k]) * frac;
    }
    return out;
}
