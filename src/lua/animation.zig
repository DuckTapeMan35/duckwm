const std = @import("std");
const ziglua = @import("ziglua");
const types = @import("types");
const protocol = @import("protocol");
const util = @import("util.zig");
const bridge = @import("bridge.zig");
const Lua = ziglua.Lua;

/// t of curve-table entry i (the same spacing the WM samples at).
fn t_at(i: usize) f64 {
    return @as(f64, @floatFromInt(i)) / types.curve_samples;
}

/// set_animation(ms, curve): curve is a preset name, {x1, y1, x2, y2}, or a
/// function of t; nil for ease_out.
pub fn l_set_animation(lua: *Lua) i32 {
    const ms = std.math.cast(u32, lua.checkInteger(1)) orelse
        util.luaL_error_str(lua, "set_animation: duration must be 0 or more milliseconds");

    var buf: types.CurveTable = undefined;
    const curve: ?protocol.Curve = switch (lua.typeOf(2)) {
        .none, .nil => null,
        .string => .{ .preset = std.meta.stringToEnum(protocol.CurvePreset, lua.checkString(2)) orelse
            util.luaL_error_str(lua, "set_animation: unknown curve (linear, ease_in, ease_out, ease_in_out)") },
        .table => blk: {
            var p: [4]f32 = undefined;
            for (&p, 1..) |*v, i| {
                _ = lua.getIndexRaw(2, @intCast(i));
                v.* = @floatCast(lua.toNumber(-1) catch
                    util.luaL_error_str(lua, "set_animation: bezier needs 4 numbers {x1, y1, x2, y2}"));
                lua.pop(1);
            }
            break :blk .{ .bezier = .{ .x1 = p[0], .y1 = p[1], .x2 = p[2], .y2 = p[3] } };
        },
        .function => blk: {
            for (&buf, 0..) |*v, i| {
                lua.pushValue(2);
                lua.pushNumber(t_at(i));
                lua.protectedCall(.{ .args = 1, .results = 1 }) catch
                    util.luaL_error_str(lua, "set_animation: curve function raised an error");
                v.* = @floatCast(lua.toNumber(-1) catch
                    util.luaL_error_str(lua, "set_animation: curve function must return a number"));
                lua.pop(1);
            }
            break :blk .{ .samples = .{ .values = &buf } };
        },
        else => util.luaL_error_str(lua, "set_animation: curve must be a name, {x1, y1, x2, y2} or a function"),
    };

    var arena = std.heap.ArenaAllocator.init(util.global_wm.allocator);
    return bridge.run_and_push(lua, .set_animation, .{ .duration_ms = ms, .curve = curve }, &arena, bridge.pending_base());
}
