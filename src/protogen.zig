const std = @import("std");
const protocol = @import("protocol.zig");
const Command = protocol.Command;
const CommandId = protocol.CommandId;

const Gen = struct {
    a: std.mem.Allocator,
    out: std.ArrayListUnmanaged(u8) = .empty,

    fn print(self: *Gen, comptime fmt: []const u8, args: anytype) !void {
        try self.out.print(self.a, fmt, args);
    }
};

/// snake_case -> PascalCase.
fn pascal(comptime s: []const u8) []const u8 {
    @setEvalBranchQuota(100000);
    comptime {
        var out: []const u8 = "";
        var upper = true;
        for (s) |ch| {
            if (ch == '_') {
                upper = true;
                continue;
            }
            out = out ++ [_]u8{if (upper) std.ascii.toUpper(ch) else ch};
            upper = false;
        }
        return out;
    }
}

/// PascalCase or snake_case -> SCREAMING_SNAKE, for enum value names.
fn screaming(comptime s: []const u8) []const u8 {
    comptime {
        var out: []const u8 = "";
        for (s, 0..) |ch, i| {
            if (std.ascii.isUpper(ch) and i > 0) out = out ++ "_";
            out = out ++ [_]u8{std.ascii.toUpper(ch)};
        }
        return out;
    }
}

/// A named type keeps its Zig name; an anonymous one is named from its context.
fn type_name(comptime T: type, comptime fallback: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(100000);
        const full = @typeName(T);
        if (std.mem.indexOf(u8, full, "__") != null) return fallback; // anonymous
        const dot = std.mem.lastIndexOfScalar(u8, full, '.') orelse return full;
        const name = full[dot + 1 ..];
        for (name) |ch| {
            if (!std.ascii.isAlphanumeric(ch) and ch != '_')
                @compileError("type " ++ full ++ " has no usable protobuf name; declare it with a name");
        }
        return name;
    }
}

fn is_list(comptime T: type) bool {
    return @typeInfo(T) == .pointer and T != []const u8;
}

/// The name of a single (non-list, non-optional) type.
fn scalar_name(comptime T: type, comptime ctx: []const u8) []const u8 {
    return switch (@typeInfo(T)) {
        .bool => "bool",
        .int => |i| switch (i.signedness) {
            .signed => if (i.bits <= 32) "sint32" else "sint64",
            .unsigned => if (i.bits <= 32) "uint32" else "uint64",
        },
        .float => |f| if (f.bits <= 32) "float" else "double",
        .pointer => if (T == []const u8) "string" else @compileError("nested lists are not supported"),
        .@"enum", .@"struct", .@"union" => type_name(T, ctx),
        else => @compileError("no protobuf mapping for " ++ @typeName(T)),
    };
}

/// The field type for T: a name, with repeated or optional as needed.
fn field_type(comptime T: type, comptime ctx: []const u8) []const u8 {
    return switch (@typeInfo(T)) {
        // An absent list and an empty one are the same thing on the wire.
        .optional => |o| if (is_list(o.child)) field_type(o.child, ctx) else "optional " ++ scalar_name(o.child, ctx),
        .pointer => |p| if (T == []const u8) "string" else "repeated " ++ scalar_name(p.child, ctx),
        else => scalar_name(T, ctx),
    };
}

/// An enum or message to write, with its protobuf name.
const Named = struct { T: type, name: []const u8 };

/// The enums and messages T needs, added to acc after what they refer to.
/// Command is written separately, so a payload holding commands stops there.
fn collect(comptime T: type, comptime ctx: []const u8, comptime acc: []const Named) []const Named {
    switch (@typeInfo(T)) {
        .optional => |o| return collect(o.child, ctx, acc),
        .pointer => |p| return if (T == []const u8) acc else collect(p.child, ctx, acc),
        .@"enum", .@"struct", .@"union" => {},
        else => return acc,
    }
    if (T == Command) return acc;
    for (acc) |n| if (n.T == T) return acc;
    const name = type_name(T, ctx);
    var out = acc;
    switch (@typeInfo(T)) {
        .@"struct" => |s| for (s.fields) |f| {
            out = collect(f.type, name ++ pascal(f.name), out);
        },
        .@"union" => |u| for (u.fields) |f| {
            if (f.type != void) out = collect(f.type, name ++ pascal(f.name), out);
        },
        else => {},
    }
    return out ++ [_]Named{.{ .T = T, .name = name }};
}

/// Everything the Command payloads need, each once.
const payload_types = blk: {
    @setEvalBranchQuota(1_000_000);
    var acc: []const Named = &.{};
    for (std.meta.fields(Command)) |f| {
        if (f.type != void) acc = collect(f.type, pascal(f.name), acc);
    }
    // The framed messages (ServerMessage is in the header: it holds Response).
    acc = collect(protocol.ClientMessage, "ClientMessage", acc);
    acc = collect(protocol.Call, "Call", acc);
    break :blk acc;
};

fn emit(g: *Gen, comptime n: Named) !void {
    @setEvalBranchQuota(100000);
    switch (@typeInfo(n.T)) {
        .@"enum" => |e| {
            try g.print("enum {s} {{\n", .{n.name});
            inline for (e.fields) |f| {
                try g.print("  {s}_{s} = {d};\n", .{ comptime screaming(n.name), comptime screaming(f.name), f.value });
            }
            try g.print("}}\n\n", .{});
        },
        .@"struct" => |s| {
            try g.print("message {s} {{\n", .{n.name});
            inline for (s.fields, 1..) |f, i| {
                try g.print("  {s} {s} = {d};\n", .{ comptime field_type(f.type, n.name ++ pascal(f.name)), f.name, i });
            }
            try g.print("}}\n\n", .{});
        },
        .@"union" => |u| {
            try g.print("message {s} {{\n  oneof kind {{\n", .{n.name});
            inline for (u.fields, 1..) |f, i| {
                const t = comptime if (f.type == void) "Empty" else field_type(f.type, n.name ++ pascal(f.name));
                try g.print("    {s} {s} = {d};\n", .{ t, f.name, i });
            }
            try g.print("  }}\n}}\n\n", .{});
        },
        else => unreachable,
    }
}

const header =
    \\// Generated by `zig build proto` from src/protocol.zig. Do not edit.
    \\//
    \\// Framing: every message on the socket is a little-endian u32 length
    \\// followed by that many bytes of ClientMessage (client) or
    \\// ServerMessage (duckwm).
    \\syntax = "proto3";
    \\
    \\package duckwm.v1;
    \\
    \\message Empty {}
    \\
    \\// What duckwm sends: the answer to a Request, or a Call to one of the
    \\// client's callbacks.
    \\message ServerMessage {
    \\  oneof kind {
    \\    Response response = 1;
    \\    Call call = 2;
    \\  }
    \\}
    \\
    \\// One result per command, in order, if the batch committed;
    \\// otherwise `error` says why and nothing changed.
    \\message Response {
    \\  repeated Value results = 1;
    \\  string error = 2;
    \\}
    \\
    \\message Value {
    \\  oneof kind {
    \\    Empty nil = 1;
    \\    bool boolean = 2;
    \\    sint64 integer = 3;
    \\    double number = 4;
    \\    string str = 5;
    \\    ValueList list = 6;
    \\    ValueMap map = 7;
    \\    ValueList multi = 8; // several return values
    \\  }
    \\}
    \\
    \\message ValueList {
    \\  repeated Value items = 1;
    \\}
    \\
    \\message ValueMap {
    \\  repeated ValueField fields = 1;
    \\}
    \\
    \\message ValueField {
    \\  string key = 1;
    \\  Value value = 2;
    \\}
    \\
    \\
;

/// The schema, as text. Allocated in a.
pub fn generate(a: std.mem.Allocator) ![]u8 {
    @setEvalBranchQuota(100000);
    var g: Gen = .{ .a = a };
    try g.out.appendSlice(a, header);
    inline for (payload_types) |n| try emit(&g, n);

    // Command: one oneof member per CommandId, numbered by it.
    try g.print("message Command {{\n  oneof kind {{\n", .{});
    inline for (std.meta.fields(Command)) |f| {
        const t = comptime if (f.type == void) "Empty" else field_type(f.type, pascal(f.name));
        try g.print("    {s} {s} = {d};\n", .{ t, f.name, @intFromEnum(@field(CommandId, f.name)) });
    }
    try g.print("  }}\n}}\n", .{});

    return g.out.items;
}
