const std = @import("std");
const ziglua = @import("ziglua");
const types = @import("types");
const util = @import("util.zig");
const Lua = ziglua.Lua;

fn sample(comptime f: fn (f32) f32) types.CurveTable {
    var out: types.CurveTable = undefined;
    for (&out, 0..) |*v, i| v.* = f(@as(f32, @floatFromInt(i)) / types.curve_samples);
    return out;
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

fn preset_curve(name: []const u8) ?types.CurveTable {
    if (std.mem.eql(u8, name, "linear")) return types.linear_curve;
    if (std.mem.eql(u8, name, "ease_out")) return sample(ease_out);
    if (std.mem.eql(u8, name, "ease_in")) return sample(ease_in);
    if (std.mem.eql(u8, name, "ease_in_out")) return sample(ease_in_out);
    return null;
}

/// One axis of a CSS cubic-bezier: endpoints fixed at 0 and 1.
fn bez(a: f32, b: f32, s: f32) f32 {
    const u = 1 - s;
    return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s;
}

fn bezier_curve(x1: f32, y1: f32, x2: f32, y2: f32) types.CurveTable {
    var out: types.CurveTable = undefined;
    for (&out, 0..) |*v, i| {
        const t = @as(f32, @floatFromInt(i)) / types.curve_samples;
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

pub fn l_set_animation(lua: *Lua) i32 {
    const ms = lua.checkInteger(1);
    if (ms < 0) return util.luaL_error_str(lua, "set_animation: duration must be >= 0");

    var curve = sample(ease_out);
    switch (lua.typeOf(2)) {
        .none, .nil => {},
        .string => curve = preset_curve(lua.checkString(2)) orelse
            return util.luaL_error_str(lua, "set_animation: unknown curve (linear, ease_in, ease_out, ease_in_out)"),
        .table => {
            var p: [4]f32 = undefined;
            for (&p, 1..) |*v, i| {
                _ = lua.getIndexRaw(2, @intCast(i));
                v.* = @floatCast(lua.toNumber(-1) catch
                    return util.luaL_error_str(lua, "set_animation: bezier needs 4 numbers {x1, y1, x2, y2}"));
                lua.pop(1);
            }
            if (p[0] < 0 or p[0] > 1 or p[2] < 0 or p[2] > 1)
                return util.luaL_error_str(lua, "set_animation: bezier x1 and x2 must be within 0..1");
            curve = bezier_curve(p[0], p[1], p[2], p[3]);
        },
        .function => {
            for (&curve, 0..) |*v, i| {
                lua.pushValue(2);
                lua.pushNumber(@as(f64, @floatFromInt(i)) / types.curve_samples);
                lua.protectedCall(.{ .args = 1, .results = 1 }) catch
                    return util.luaL_error_str(lua, "set_animation: curve function raised an error");
                v.* = @floatCast(lua.toNumber(-1) catch
                    return util.luaL_error_str(lua, "set_animation: curve function must return a number"));
                lua.pop(1);
            }
        },
        else => return util.luaL_error_str(lua, "set_animation: curve must be a name, {x1, y1, x2, y2} or a function"),
    }
    util.global_wm.backend.set_animation(.{ .duration_ms = @intCast(ms), .curve = curve });
    return 0;
}
