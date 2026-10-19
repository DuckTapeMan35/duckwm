const std = @import("std");
const ziglua = @import("ziglua");
const wm_mod = @import("wm");
const protocol = @import("protocol");
const util = @import("util.zig");
const Lua = ziglua.Lua;
const command = wm_mod.command;
const Command = command.Command;
const Registration = util.Registration;

/// Refs made for the command being parsed: released if it fails, owned by
/// duckwm once it succeeds.
var pending_refs: [8]i32 = undefined;
var pending_count: usize = 0;

fn lua_command(comptime tag: std.meta.Tag(Command)) fn (*Lua) i32 {
    return struct {
        fn call(lua: *Lua) i32 {
            const name = @tagName(tag);
            // Nothing below may be skipped by a Lua error (no defers across raises).
            const base = pending_count;
            var arena = std.heap.ArenaAllocator.init(util.global_wm.allocator);
            const args = parse_args(@FieldType(Command, name), lua, arena.allocator()) catch |err| {
                release_pending(lua, base);
                arena.deinit();
                util.raise_with(lua, name ++ ": ", arg_error_text(err));
            };
            return run_and_push(lua, tag, args, &arena, base);
        }
    }.call;
}

/// Run one command and push its result. Frees arena on every path.
pub fn run_and_push(
    lua: *Lua,
    comptime tag: std.meta.Tag(Command),
    args: @FieldType(Command, @tagName(tag)),
    arena: *std.heap.ArenaAllocator,
    base: usize,
) i32 {
    const name = @tagName(tag);
    var results: [1]command.Value = undefined;
    const wm = util.global_wm;
    const saved_source = wm.callback_source;
    wm.callback_source = .lua;
    command.run(
        wm,
        &.{@unionInit(Command, name, args)},
        arena.allocator(),
        &results,
    ) catch |err| {
        wm.callback_source = saved_source;
        release_pending(lua, base);
        arena.deinit();
        util.raise_with(lua, name ++ " failed: ", command.error_text(err));
    };
    wm.callback_source = saved_source;
    pending_count = base; // the command owns them now
    const n = push_value(lua, results[0]);
    arena.deinit(); // pushed values were copied into Lua
    return n;
}

pub fn pending_base() usize {
    return pending_count;
}

fn parse_args(comptime P: type, lua: *Lua, a: std.mem.Allocator) !P {
    if (P == void) return {};
    var out: P = undefined;
    inline for (std.meta.fields(P), 1..) |f, i| {
        @field(out, f.name) = try read_arg(f.type, lua, @intCast(i), a);
    }
    return out;
}

fn release_pending(lua: *Lua, base: usize) void {
    for (pending_refs[base..pending_count]) |ref| lua.unref(ziglua.registry_index, ref);
    pending_count = base;
}

fn read_arg(comptime T: type, lua: *Lua, index: i32, a: std.mem.Allocator) !T {
    const i = lua.absIndex(index); // nested reads push values; a relative index would shift
    if (T == protocol.Callback) {
        if (lua.typeOf(i) != .function) return error.ExpectedFunction;
        if (pending_count == pending_refs.len) return error.TooManyFunctions;
        lua.pushValue(i);
        const ref = lua.ref(ziglua.registry_index);
        pending_refs[pending_count] = ref;
        pending_count += 1;
        return .{ .id = @intCast(ref) };
    }
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
        // A union with a shorthand (protocol.Ref) also takes a bare number, and a table with
        // the variant as its only key: 5, { id = 5 }, { key = 0 }.
        .@"union" => |u| {
            if (u.tag_type == null) @compileError("command arguments need tagged unions: " ++ @typeName(T));
            if (comptime @hasDecl(T, "shorthand")) {
                if (lua.typeOf(i) == .number) {
                    return @unionInit(T, T.shorthand, try read_arg(
                        @FieldType(T, T.shorthand),
                        lua,
                        i,
                        a,
                    ));
                }
                if (lua.typeOf(i) == .table) {
                    inline for (u.fields) |f| {
                        if (f.type != void) {
                            _ = lua.getField(i, f.name);
                            defer lua.pop(1);
                            if (!lua.isNil(-1)) return @unionInit(T, f.name, try read_arg(f.type, lua, -1, a));
                        }
                    }
                }
            }
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
        error.ExpectedFunction => "expected a function argument",
        error.TooManyFunctions => "too many function arguments",
        else => "invalid argument",
    };
}

/// Commands whose Lua function is a hand-written wrapper.
const wrapped_in_lua = [_][]const u8{ "get_layout", "set_animation" };

/// Commands with no wm.<name> in Lua, because Lua has a better way to do them:
/// wm.bind takes a function (lua/input.zig), not a list of commands.
const not_in_lua = [_]std.meta.Tag(Command){ .bind_commands, .eval };

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
