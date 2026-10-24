const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{ InvalidJson, OutOfMemory };

/// Where the last error happened and what was wrong, e.g.
/// "commands[3].set_gaps: missing field 'outer_v'". Owned by the arena given to parse.
pub const Diagnostic = struct { message: []const u8 = "" };

pub fn parse(comptime T: type, a: Allocator, text: []const u8, diag: *Diagnostic) Error!T {
    const root = std.json.parseFromSliceLeaky(std.json.Value, a, text, .{}) catch |err| {
        diag.message = try std.fmt.allocPrint(a, "not valid JSON: {s}", .{@errorName(err)});
        return error.InvalidJson;
    };
    var path: std.ArrayListUnmanaged(u8) = .empty;
    return convert(T, a, root, &path, diag);
}

fn fail(a: Allocator, path: *std.ArrayListUnmanaged(u8), diag: *Diagnostic, comptime fmt: []const u8, args: anytype) Error {
    const what = try std.fmt.allocPrint(a, fmt, args);
    diag.message = if (path.items.len == 0)
        what
    else
        try std.fmt.allocPrint(a, "{s}: {s}", .{ path.items, what });
    return error.InvalidJson;
}

/// Append .name (or [i]) to the path; returns the old length to restore.
fn push(a: Allocator, path: *std.ArrayListUnmanaged(u8), comptime fmt: []const u8, args: anytype) Error!usize {
    const len = path.items.len;
    if (len > 0 and fmt[0] != '[') try path.append(a, '.');
    try path.print(a, fmt, args);
    return len;
}

fn convert(comptime T: type, a: Allocator, v: std.json.Value, path: *std.ArrayListUnmanaged(u8), diag: *Diagnostic) Error!T {
    switch (@typeInfo(T)) {
        .bool => return switch (v) {
            .bool => |b| b,
            else => fail(a, path, diag, "expected true or false", .{}),
        },
        .int => {
            const n: i128 = switch (v) {
                .integer => |n| n,
                .number_string => |s| std.fmt.parseInt(i128, s, 10) catch return fail(
                    a,
                    path,
                    diag,
                    "number out of range",
                    .{},
                ),
                else => return fail(a, path, diag, "expected an integer", .{}),
            };
            return std.math.cast(T, n) orelse fail(a, path, diag, "{d} is out of range for {s}", .{ n, @typeName(T) });
        },
        .float => return switch (v) {
            .float => |f| @floatCast(f),
            .integer => |n| @floatFromInt(n),
            else => fail(a, path, diag, "expected a number", .{}),
        },
        .@"enum" => |e| {
            const s = switch (v) {
                .string => |s| s,
                else => return fail(a, path, diag, "expected a string", .{}),
            };
            if (std.meta.stringToEnum(T, s)) |x| return x;
            comptime var names: []const u8 = "";
            inline for (e.field_names, 0..) |f_name, i| names = names ++ (if (i > 0) ", " else "") ++ f_name;
            return fail(a, path, diag, "'{s}' is not one of {s}", .{ s, names });
        },
        .optional => |o| return if (v == .null) null else try convert(o.child, a, v, path, diag),
        .pointer => |p| {
            if (T == []const u8) return switch (v) {
                .string => |s| s,
                else => fail(a, path, diag, "expected a string", .{}),
            };
            const items = switch (v) {
                .array => |arr| arr.items,
                else => return fail(a, path, diag, "expected a list", .{}),
            };
            const out = try a.alloc(p.child, items.len);
            for (items, out, 0..) |item, *dst, i| {
                const saved = try push(a, path, "[{d}]", .{i});
                defer path.shrinkRetainingCapacity(saved);
                dst.* = try convert(p.child, a, item, path, diag);
            }
            return out;
        },
        .@"struct" => |s| {
            const obj = switch (v) {
                .object => |o| o,
                else => return fail(a, path, diag, "expected an object", .{}),
            };
            var it = obj.iterator();
            while (it.next()) |e| {
                const known = inline for (s.field_names) |f_name| {
                    if (std.mem.eql(u8, e.key_ptr.*, f_name)) break true;
                } else false;
                if (!known) return fail(a, path, diag, "unknown field '{s}'", .{e.key_ptr.*});
            }
            var out: T = undefined;
            inline for (s.field_names, s.field_types) |f_name, f_type| {
                if (obj.get(f_name)) |fv| {
                    const saved = try push(a, path, "{s}", .{f_name});
                    defer path.shrinkRetainingCapacity(saved);
                    @field(out, f_name) = try convert(f_type, a, fv, path, diag);
                } else switch (@typeInfo(f_type)) {
                    .optional => @field(out, f_name) = null,
                    .pointer => if (f_type != []const u8) {
                        @field(out, f_name) = &.{};
                    } else return fail(a, path, diag, "missing field '{s}'", .{f_name}),
                    else => return fail(a, path, diag, "missing field '{s}'", .{f_name}),
                }
            }
            return out;
        },
        .@"union" => |u| {
            if (comptime @hasDecl(T, "shorthand")) {
                if (v == .integer or v == .number_string) {
                    return @unionInit(T, T.shorthand, try convert(
                        @FieldType(T, T.shorthand),
                        a,
                        v,
                        path,
                        diag,
                    ));
                }
            }
            const obj = switch (v) {
                .object => |o| o,
                else => return fail(a, path, diag, "expected an object with one key", .{}),
            };
            if (obj.count() != 1) return fail(a, path, diag, "expected exactly one key, got {d}", .{obj.count()});
            var it = obj.iterator();
            const e = it.next().?;
            inline for (u.field_names, u.field_types) |f_name, f_type| {
                if (std.mem.eql(u8, e.key_ptr.*, f_name)) {
                    const saved = try push(a, path, "{s}", .{f_name});
                    defer path.shrinkRetainingCapacity(saved);
                    if (f_type == void) {
                        // No arguments: {} (or null) as the value.
                        const empty = switch (e.value_ptr.*) {
                            .null => true,
                            .object => |o| o.count() == 0,
                            else => false,
                        };
                        if (!empty) return fail(a, path, diag, "takes no arguments; use {{}}", .{});
                        return @unionInit(T, f_name, {});
                    }
                    return @unionInit(T, f_name, try convert(f_type, a, e.value_ptr.*, path, diag));
                }
            }
            return fail(a, path, diag, "unknown '{s}'", .{e.key_ptr.*});
        },
        else => @compileError("no JSON mapping for " ++ @typeName(T)),
    }
}

test "commands from JSON" {
    const protocol = @import("protocol.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: Diagnostic = .{};

    const req = try parse(protocol.Request, a,
        \\{"commands":[
        \\ {"set_gaps":{"inner_h":0,"inner_v":0,"outer_h":8,"outer_v":8}},
        \\ {"exchange_left":{}},
        \\ {"set_workspace_switch_mode":{"mode":"previous"}},
        \\ {"set_reparent_strategy":{"id":3}},
        \\ {"split":{"container":1,"axis":"v","ratios":[0.25,0.75],"children":[2,3]}},
        \\ {"spawn":{"argv":["ghostty","-e","htop"]}},
        \\ {"set_keyboard_layout":{"layout":"us","variant":"intl"}}
        \\]}
    , &d);
    try std.testing.expectEqual(@as(usize, 7), req.commands.len);
    try std.testing.expect(req.commands[1] == .exchange_left);
    try std.testing.expectEqual(protocol.WorkspaceSwitchMode.previous, req.commands[2].set_workspace_switch_mode.mode);
    try std.testing.expect(req.commands[3].set_reparent_strategy.strategy == null);
    try std.testing.expectEqual(@as(f64, 0.75), req.commands[4].split.ratios[1]);
    try std.testing.expectEqualStrings("htop", req.commands[5].spawn.argv[2]);
    try std.testing.expect(req.commands[6].set_keyboard_layout.options == null);

    const cases = .{
        .{ "{\"commands\":[{\"set_gapz\":{}}]}", "commands[0]: unknown 'set_gapz'" },
        .{ "{\"commands\":[{\"set_gaps\":{\"inner_h\":1}}]}", "commands[0].set_gaps: missing field 'inner_v'" },
        .{ "{\"commands\":[{\"set_workspace_switch_mode\":{\"mode\":\"prev\"}}]}", "commands[0].set_workspace_switch_mode.mode: 'prev' is not one of none, previous" },
        .{ "{\"commands\":[{\"focus\":{\"id\":-1}}]}", "commands[0].focus.id: -1 is out of range for u32" },
        .{ "{\"commands\":[{\"focus\":{\"id\":1,\"x\":2}}]}", "commands[0].focus: unknown field 'x'" },
        .{ "{\"commands\":[{\"quit\":{\"now\":true}}]}", "commands[0].quit: takes no arguments; use {}" },
        .{ "{\"commands\":[{\"quit\":{},\"focus_left\":{}}]}", "commands[0]: expected exactly one key, got 2" },
    };
    inline for (cases) |c| {
        try std.testing.expectError(error.InvalidJson, parse(protocol.Request, a, c[0], &d));
        try std.testing.expectEqualStrings(c[1], d.message);
    }
}

test "ref shorthand" {
    const protocol = @import("protocol.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: Diagnostic = .{};
    const refs = try parse([]const protocol.Ref, arena.allocator(), "[5, {\"id\": 6}, {\"key\": 1}]", &diag);
    try std.testing.expectEqual(@as(u32, 5), refs[0].id);
    try std.testing.expectEqual(@as(u32, 6), refs[1].id);
    try std.testing.expectEqual(@as(u32, 1), refs[2].key);
}
