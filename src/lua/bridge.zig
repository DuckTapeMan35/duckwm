const std = @import("std");
const ziglua = @import("ziglua");
const wm_mod = @import("wm");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const command = wm_mod.command;
const Command = command.Command;
const Registration = util.Registration;

fn lua_command(comptime tag: std.meta.Tag(Command)) fn (*Lua) i32 {
    return struct {
        fn call(lua: *Lua) i32 {
            const name = @tagName(tag);
            const Payload = @FieldType(Command, name);
            const args = parse_args(Payload, lua) catch |err|
                util.raise_with(lua, name ++ ": ", arg_error_text(err));
            const cmd = @unionInit(Command, name, args);

            // Nothing below may be skipped by a Lua error (no defers across raises).
            var arena = std.heap.ArenaAllocator.init(util.global_wm.allocator);
            var results: [1]command.Value = undefined;
            command.run(util.global_wm, &.{cmd}, arena.allocator(), &results) catch |err| {
                arena.deinit();
                util.raise_with(lua, name ++ " failed: ", run_error_text(err));
            };
            const n = push_value(lua, results[0]);
            arena.deinit(); // pushed values were copied into Lua
            return n;
        }
    }.call;
}

fn parse_args(comptime P: type, lua: *Lua) !P {
    if (P == void) return {};
    var out: P = undefined;
    inline for (std.meta.fields(P), 1..) |f, i| {
        @field(out, f.name) = try read_arg(f.type, lua, @intCast(i));
    }
    return out;
}

fn read_arg(comptime T: type, lua: *Lua, i: i32) !T {
    return switch (@typeInfo(T)) {
        .optional => |o| if (lua.isNoneOrNil(i)) null else try read_arg(o.child, lua, i),
        .int => std.math.cast(T, lua.toInteger(i) catch return error.ExpectedInteger) orelse error.OutOfRange,
        .float => @floatCast(lua.toNumber(i) catch return error.ExpectedNumber),
        .bool => lua.toBoolean(i),
        .@"enum" => std.meta.stringToEnum(T, lua.toString(i) catch return error.ExpectedString) orelse
            error.InvalidChoice,
        .pointer => if (T == []const u8)
            lua.toString(i) catch error.ExpectedString
        else
            @compileError("unsupported command argument type " ++ @typeName(T)),
        else => @compileError("unsupported command argument type " ++ @typeName(T)),
    };
}

/// Push a result; nil pushes nothing, which Lua also reads as nil.
fn push_value(lua: *Lua, v: command.Value) i32 {
    switch (v) {
        .nil => return 0,
        .boolean => |b| lua.pushBoolean(b),
        .integer => |n| lua.pushInteger(n),
        .number => |f| lua.pushNumber(f),
        .string => |s| _ = lua.pushString(s),
        .list => |items| {
            lua.createTable(@intCast(items.len), 0);
            for (items, 1..) |item, k| {
                if (push_value(lua, item) == 0) lua.pushNil();
                lua.setIndexRaw(-2, @intCast(k));
            }
        },
        .map => |fields| {
            lua.createTable(0, @intCast(fields.len));
            for (fields) |f| {
                _ = lua.pushString(f.key);
                if (push_value(lua, f.value) == 0) lua.pushNil();
                lua.setTable(-3);
            }
        },
    }
    return 1;
}

fn arg_error_text(err: anyerror) []const u8 {
    return switch (err) {
        error.ExpectedInteger => "expected an integer argument",
        error.ExpectedNumber => "expected a number argument",
        error.ExpectedString => "expected a string argument",
        error.OutOfRange => "argument out of range",
        error.InvalidChoice => "argument is not one of the allowed names",
        else => "invalid argument",
    };
}

fn run_error_text(err: anyerror) []const u8 {
    return switch (err) {
        error.Rejected => "the result was invalid, so nothing was changed",
        error.InvalidNode => "no such node",
        else => @errorName(err),
    };
}

/// One wm.<name> per Command variant.
pub const registrations = blk: {
    const fields = std.meta.fields(Command);
    var regs: [fields.len]Registration = undefined;
    for (fields, 0..) |f, i| {
        regs[i] = .{ .func = ziglua.wrap(lua_command(@field(std.meta.Tag(Command), f.name))), .name = f.name };
    }
    break :blk regs;
};
