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
            // Nothing below may be skipped by a Lua error (no defers across raises).
            var arena = std.heap.ArenaAllocator.init(util.global_wm.allocator);
            const args = parse_args(@FieldType(Command, name), lua, arena.allocator()) catch |err| {
                arena.deinit();
                util.raise_with(lua, name ++ ": ", arg_error_text(err));
            };
            return run_and_push(lua, tag, args, &arena);
        }
    }.call;
}

/// Run one command and push its result. Frees arena on every path.
pub fn run_and_push(
    lua: *Lua,
    comptime tag: std.meta.Tag(Command),
    args: @FieldType(Command, @tagName(tag)),
    arena: *std.heap.ArenaAllocator,
) i32 {
    const name = @tagName(tag);
    var results: [1]command.Value = undefined;
    command.run(util.global_wm, &.{@unionInit(Command, name, args)}, arena.allocator(), &results) catch |err| {
        arena.deinit();
        util.raise_with(lua, name ++ " failed: ", command.error_text(err));
    };
    const n = push_value(lua, results[0]);
    arena.deinit(); // pushed values were copied into Lua
    return n;
}

fn parse_args(comptime P: type, lua: *Lua, a: std.mem.Allocator) !P {
    if (P == void) return {};
    var out: P = undefined;
    inline for (std.meta.fields(P), 1..) |f, i| {
        @field(out, f.name) = try read_arg(f.type, lua, @intCast(i), a);
    }
    return out;
}

fn read_arg(comptime T: type, lua: *Lua, index: i32, a: std.mem.Allocator) !T {
    const i = lua.absIndex(index); // nested reads push values; a relative index would shift
    switch (@typeInfo(T)) {
        .optional => |o| return if (lua.isNoneOrNil(i)) null else try read_arg(o.child, lua, i, a),
        .int => return std.math.cast(T, lua.toInteger(i) catch return error.ExpectedInteger) orelse error.OutOfRange,
        .float => return @floatCast(lua.toNumber(i) catch return error.ExpectedNumber),
        .bool => return lua.toBoolean(i),
        .@"enum" => return std.meta.stringToEnum(T, lua.toString(i) catch return error.ExpectedString) orelse
            error.InvalidChoice,
        .pointer => |p| {
            if (T == []const u8) return lua.toString(i) catch error.ExpectedString;
            if (p.size != .slice) @compileError("unsupported command argument type " ++ @typeName(T));
            if (lua.typeOf(i) != .table) return error.ExpectedTable;
            const out = try a.alloc(p.child, @intCast(lua.lenRaw(i)));
            for (out, 1..) |*v, k| {
                _ = lua.getIndexRaw(i, @intCast(k));
                defer lua.pop(1);
                v.* = try read_arg(p.child, lua, -1, a);
            }
            return out;
        },
        // A table, read field by field by name. Keys the struct doesn't have are ignored.
        .@"struct" => |s| {
            if (lua.typeOf(i) != .table) return error.ExpectedTable;
            var out: T = undefined;
            inline for (s.fields) |f| {
                _ = lua.getField(i, f.name);
                defer lua.pop(1);
                @field(out, f.name) = try read_arg(f.type, lua, -1, a);
            }
            return out;
        },
        // A table whose type field names the variant; the payload's fields are read from the same table.
        .@"union" => |u| {
            if (u.tag_type == null) @compileError("command arguments need tagged unions: " ++ @typeName(T));
            if (lua.typeOf(i) != .table) return error.ExpectedTable;
            _ = lua.getField(i, "type");
            const name = lua.toString(-1) catch {
                lua.pop(1);
                return error.ExpectedString;
            };
            lua.pop(1); // the table still holds the string, so name stays valid
            inline for (u.fields) |f| {
                if (std.mem.eql(u8, name, f.name)) {
                    if (f.type == void) return @unionInit(T, f.name, {});
                    return @unionInit(T, f.name, try read_arg(f.type, lua, i, a));
                }
            }
            return error.InvalidChoice;
        },
        else => @compileError("unsupported command argument type " ++ @typeName(T)),
    }
}

/// Push a result; nil pushes nothing, which Lua also reads as nil.
fn push_value(lua: *Lua, v: command.Value) i32 {
    switch (v) {
        .nil => return 0,
        .boolean => |b| lua.pushBoolean(b),
        .integer => |n| lua.pushInteger(n),
        .number => |f| lua.pushNumber(f),
        .str => |s| _ = lua.pushString(s),
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
        .multi => |vals| {
            for (vals) |item| {
                if (push_value(lua, item) == 0) lua.pushNil();
            }
            return @intCast(vals.len);
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
        error.ExpectedTable => "expected a table argument",
        else => "invalid argument",
    };
}

/// Commands whose Lua function is a hand-written wrapper.
const wrapped_in_lua = [_][]const u8{"get_layout"};

/// Commands with no wm.<name> in Lua, because Lua has a better way to do them:
/// wm.bind takes a function (lua/input.zig), not a list of commands.
const not_in_lua = [_]std.meta.Tag(Command){.bind};

fn skipped(comptime name: []const u8) bool {
    for (wrapped_in_lua) |w| if (std.mem.eql(u8, w, name)) return true;
    for (not_in_lua) |t| if (std.mem.eql(u8, @tagName(t), name)) return true;
    return false;
}

/// One wm.<name> per Command variant, except the skipped ones.
pub const registrations = blk: {
    @setEvalBranchQuota(100000);
    var regs: []const Registration = &.{};
    for (std.meta.fields(Command)) |f| {
        if (skipped(f.name)) continue;
        const tag = @field(std.meta.Tag(Command), f.name);
        regs = regs ++ [_]Registration{.{ .func = ziglua.wrap(lua_command(tag)), .name = f.name }};
    }
    break :blk regs;
};
