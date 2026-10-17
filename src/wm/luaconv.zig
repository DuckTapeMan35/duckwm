const std = @import("std");
const ziglua = @import("ziglua");
const protocol = @import("protocol");
const Lua = ziglua.Lua;
const Value = protocol.Value;
const Allocator = std.mem.Allocator;

pub const Error = error{
    ExpectedInteger,
    ExpectedNumber,
    ExpectedString,
    ExpectedTable,
    InvalidChoice,
    OutOfRange,
    Unsupported,
    OutOfMemory,
};

// ---- Zig → Lua ----
/// Push v as one Lua value.
pub fn push(lua: *Lua, comptime T: type, v: T) void {
    if (T == Value) return push_value(lua, v);
    switch (@typeInfo(T)) {
        .optional => |o| if (v) |x| push(lua, o.child, x) else lua.pushNil(),
        .bool => lua.pushBoolean(v),
        .int => lua.pushInteger(@intCast(v)),
        .float => lua.pushNumber(@floatCast(v)),
        .@"enum" => _ = lua.pushString(@tagName(v)),
        .pointer => |p| {
            if (T == []const u8) {
                _ = lua.pushString(v);
                return;
            }
            lua.createTable(@intCast(v.len), 0);
            for (v, 1..) |x, k| {
                push(lua, p.child, x);
                lua.setIndexRaw(-2, @intCast(k));
            }
        },
        .@"struct" => |s| {
            lua.createTable(0, @intCast(s.fields.len));
            set_fields(lua, T, v);
        },
        .@"union" => |u| {
            const active = std.meta.activeTag(v);
            if (comptime @hasDecl(T, "shorthand")) {
                // A Ref: a bare number for the shorthand, { key = k } otherwise.
                inline for (u.fields) |f| {
                    if (active == @field(std.meta.Tag(T), f.name)) {
                        if (comptime std.mem.eql(u8, f.name, T.shorthand)) {
                            push(lua, f.type, @field(v, f.name));
                        } else {
                            lua.createTable(0, 1);
                            push(lua, f.type, @field(v, f.name));
                            lua.setField(-2, f.name);
                        }
                    }
                }
                return;
            }
            lua.createTable(0, 4);
            _ = lua.pushString(@tagName(active));
            lua.setField(-2, "type");
            inline for (u.fields) |f| {
                if (f.type != void and active == @field(std.meta.Tag(T), f.name)) {
                    if (@typeInfo(f.type) == .@"struct") {
                        set_fields(lua, f.type, @field(v, f.name));
                    } else {
                        push(lua, f.type, @field(v, f.name));
                        lua.setField(-2, "value");
                    }
                }
            }
        },
        else => @compileError("no Lua mapping for " ++ @typeName(T)),
    }
}

/// Set each of v's fields on the table on top of the stack.
fn set_fields(lua: *Lua, comptime S: type, v: S) void {
    inline for (std.meta.fields(S)) |f| {
        push(lua, f.type, @field(v, f.name));
        lua.setField(-2, f.name);
    }
}

/// A Value as one Lua value (multi becomes a list).
pub fn push_value(lua: *Lua, v: Value) void {
    switch (v) {
        .nil => lua.pushNil(),
        .boolean => |b| lua.pushBoolean(b),
        .integer => |n| lua.pushInteger(n),
        .number => |f| lua.pushNumber(f),
        .str => |s| _ = lua.pushString(s),
        .list, .multi => |items| {
            lua.createTable(@intCast(items.len), 0);
            for (items, 1..) |item, k| {
                push_value(lua, item);
                lua.setIndexRaw(-2, @intCast(k));
            }
        },
        .map => |fields| {
            lua.createTable(0, @intCast(fields.len));
            for (fields) |f| {
                _ = lua.pushString(f.key);
                push_value(lua, f.value);
                lua.setTable(-3);
            }
        },
    }
}

// ---- Lua → Zig ----
/// The Lua value at index as a T; strings are copied into a.
pub fn read(comptime T: type, lua: *Lua, index: i32, a: Allocator) Error!T {
    const i = lua.absIndex(index); // nested reads push values
    if (T == Value) return to_value(lua, i, a);
    switch (@typeInfo(T)) {
        .optional => |o| return if (lua.isNoneOrNil(i)) null else try read(o.child, lua, i, a),
        .int => return std.math.cast(T, lua.toInteger(i) catch return error.ExpectedInteger) orelse error.OutOfRange,
        .float => return @floatCast(lua.toNumber(i) catch return error.ExpectedNumber),
        .bool => return lua.toBoolean(i),
        .@"enum" => return std.meta.stringToEnum(T, lua.toString(i) catch return error.ExpectedString) orelse
            error.InvalidChoice,
        .pointer => |p| {
            if (T == []const u8) return a.dupe(u8, lua.toString(i) catch return error.ExpectedString);
            if (lua.isNoneOrNil(i)) return &.{};
            if (lua.typeOf(i) != .table) return error.ExpectedTable;
            const out = try a.alloc(p.child, @intCast(lua.lenRaw(i)));
            for (out, 1..) |*v, k| {
                _ = lua.getIndexRaw(i, @intCast(k));
                defer lua.pop(1);
                v.* = try read(p.child, lua, -1, a);
            }
            return out;
        },
        .@"struct" => |s| {
            if (lua.typeOf(i) != .table) return error.ExpectedTable;
            var out: T = undefined;
            inline for (s.fields) |f| {
                _ = lua.getField(i, f.name);
                defer lua.pop(1);
                @field(out, f.name) = try read(f.type, lua, -1, a);
            }
            return out;
        },
        .@"union" => |u| {
            if (comptime @hasDecl(T, "shorthand")) {
                if (lua.typeOf(i) == .number)
                    return @unionInit(T, T.shorthand, try read(@FieldType(T, T.shorthand), lua, i, a));
                if (lua.typeOf(i) == .table) {
                    inline for (u.fields) |f| {
                        if (f.type != void) {
                            _ = lua.getField(i, f.name);
                            defer lua.pop(1);
                            if (!lua.isNil(-1)) return @unionInit(T, f.name, try read(f.type, lua, -1, a));
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
            lua.pop(1); // the table still holds the string
            inline for (u.fields) |f| {
                if (std.mem.eql(u8, name, f.name)) {
                    if (f.type == void) return @unionInit(T, f.name, {});
                    if (@typeInfo(f.type) == .@"struct") return @unionInit(T, f.name, try read(f.type, lua, i, a));
                    _ = lua.getField(i, "value");
                    defer lua.pop(1);
                    return @unionInit(T, f.name, try read(f.type, lua, -1, a));
                }
            }
            return error.InvalidChoice;
        },
        else => @compileError("no Lua mapping for " ++ @typeName(T)),
    }
}

/// Any Lua value (but functions and userdata) as a Value: a table with an
/// array part is a list, otherwise a map of its string keys.
pub fn to_value(lua: *Lua, index: i32, a: Allocator) Error!Value {
    const i = lua.absIndex(index);
    switch (lua.typeOf(i)) {
        .none, .nil => return .nil,
        .boolean => return .{ .boolean = lua.toBoolean(i) },
        .number => return if (lua.isInteger(i))
            .{ .integer = lua.toInteger(i) catch unreachable }
        else
            .{ .number = lua.toNumber(i) catch unreachable },
        .string => return .{ .str = try a.dupe(u8, lua.toString(i) catch unreachable) },
        .table => {
            const n: usize = @intCast(lua.lenRaw(i));
            if (n > 0) {
                const items = try a.alloc(Value, n);
                for (items, 1..) |*v, k| {
                    _ = lua.getIndexRaw(i, @intCast(k));
                    defer lua.pop(1);
                    v.* = try to_value(lua, -1, a);
                }
                return .{ .list = items };
            }
            var fields: std.ArrayListUnmanaged(Value.Field) = .empty;
            lua.pushNil();
            while (lua.next(i)) {
                // key at -2, value at -1
                if (lua.typeOf(-2) == .string) {
                    const k = try a.dupe(u8, lua.toString(-2) catch unreachable);
                    try fields.append(a, .{ .key = k, .value = try to_value(lua, -1, a) });
                }
                lua.pop(1);
            }
            return .{ .map = fields.items };
        },
        else => return error.Unsupported,
    }
}
