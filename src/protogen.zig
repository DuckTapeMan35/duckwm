const std = @import("std");
const protocol = @import("protocol.zig");
const Command = protocol.Command;
const CommandId = protocol.CommandId;

const Gen = struct {
    a: std.mem.Allocator,
    out: std.ArrayListUnmanaged(u8) = .empty,
    seen: std.StringHashMapUnmanaged(void) = .empty,

    fn print(self: *Gen, comptime fmt: []const u8, args: anytype) !void {
        try self.out.print(self.a, fmt, args);
    }

    /// Mark a named type as emitted; false if it already was.
    fn claim(self: *Gen, name: []const u8) !bool {
        const gop = try self.seen.getOrPut(self.a, name);
        return !gop.found_existing;
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

/// The field type for T, emitting any message or enum it needs.
fn field_type(g: *Gen, comptime T: type, comptime ctx: []const u8) ![]const u8 {
    switch (@typeInfo(T)) {
        .optional => |o| {
            // An absent list and an empty one are the same thing on the wire.
            if (comptime is_list(o.child)) return field_type(g, o.child, ctx);
            try ensure(g, o.child, ctx);
            return "optional " ++ comptime scalar_name(o.child, ctx);
        },
        .pointer => |p| {
            if (T == []const u8) return "string";
            try ensure(g, p.child, ctx);
            return "repeated " ++ comptime scalar_name(p.child, ctx);
        },
        else => {
            try ensure(g, T, ctx);
            return comptime scalar_name(T, ctx);
        },
    }
}

/// Emit the message or enum for T (and everything it refers to), once.
fn ensure(g: *Gen, comptime T: type, comptime ctx: []const u8) !void {
    switch (@typeInfo(T)) {
        .@"enum" => |e| {
            const name = comptime type_name(T, ctx);
            if (!try g.claim(name)) return;
            try g.print("enum {s} {{\n", .{name});
            inline for (e.fields) |f| {
                try g.print("  {s}_{s} = {d};\n", .{ comptime screaming(name), comptime screaming(f.name), f.value });
            }
            try g.print("}}\n\n", .{});
        },
        .@"struct" => |s| {
            const name = comptime type_name(T, ctx);
            if (!try g.claim(name)) return;
            // Nested types first, so this message is written in one piece.
            var types: [s.fields.len][]const u8 = undefined;
            inline for (s.fields, 0..) |f, i| types[i] = try field_type(g, f.type, name ++ comptime pascal(f.name));
            try g.print("message {s} {{\n", .{name});
            inline for (s.fields, 0..) |f, i| try g.print("  {s} {s} = {d};\n", .{ types[i], f.name, i + 1 });
            try g.print("}}\n\n", .{});
        },
        .@"union" => |u| {
            const name = comptime type_name(T, ctx);
            if (!try g.claim(name)) return;
            var types: [u.fields.len][]const u8 = undefined;
            inline for (u.fields, 0..) |f, i| {
                types[i] = if (f.type == void) "Empty" else try field_type(g, f.type, name ++ comptime pascal(f.name));
            }
            try g.print("message {s} {{\n  oneof kind {{\n", .{name});
            inline for (u.fields, 0..) |f, i| try g.print("    {s} {s} = {d};\n", .{ types[i], f.name, i + 1 });
            try g.print("  }}\n}}\n\n", .{});
        },
        else => {},
    }
}

const header =
    \\// Generated by `zig build proto` from src/protocol.zig. Do not edit.
    \\//
    \\// Framing: every message on the socket is a little-endian u32 length
    \\// followed by that many bytes of Request (client) or Response (duckwm).
    \\syntax = "proto3";
    \\
    \\package duckwm.v1;
    \\
    \\message Empty {}
    \\
    \\// A batch of commands, run as one transaction: all of them take
    \\// effect, or none do.
    \\message Request {
    \\  repeated Command commands = 1;
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

/// The schema, as text. Allocated in a
pub fn generate(a: std.mem.Allocator) ![]u8 {
    var g: Gen = .{ .a = a };
    try g.out.appendSlice(a, header);

    // Command: one oneof member per CommandId, numbered by it.
    const fields = std.meta.fields(Command);
    var types: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |f, i| {
        types[i] = if (f.type == void) "Empty" else try field_type(&g, f.type, comptime pascal(f.name));
    }
    try g.print("message Command {{\n  oneof kind {{\n", .{});
    inline for (fields, 0..) |f, i| {
        try g.print("    {s} {s} = {d};\n", .{ types[i], f.name, @intFromEnum(@field(CommandId, f.name)) });
    }
    try g.print("  }}\n}}\n", .{});

    return g.out.items;
}
