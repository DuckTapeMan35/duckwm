const std = @import("std");
const protocol = @import("protocol.zig");
const Command = protocol.Command;
const CommandId = protocol.CommandId;
const Value = protocol.Value;
const Allocator = std.mem.Allocator;

pub const Error = error{
    Truncated,
    VarintTooLong,
    WireTypeMismatch,
    OutOfRange,
    InvalidEnum,
    MissingVariant,
    OutOfMemory,
};

/// A batch of commands, run as one transaction.
pub const Request = struct { commands: []const Command };

const WireType = enum(u3) { varint = 0, fixed64 = 1, len = 2, fixed32 = 5, _ };

// ---- reading ----
const Reader = struct {
    buf: []const u8,
    pos: usize = 0,

    fn done(r: *const Reader) bool {
        return r.pos >= r.buf.len;
    }

    fn varint(r: *Reader) Error!u64 {
        var result: u64 = 0;
        var shift: u32 = 0;
        while (true) {
            if (r.pos >= r.buf.len) return error.Truncated;
            if (shift >= 64) return error.VarintTooLong;
            const b = r.buf[r.pos];
            r.pos += 1;
            result |= @as(u64, b & 0x7f) << @intCast(shift);
            if (b & 0x80 == 0) return result;
            shift += 7;
        }
    }

    fn fixed(r: *Reader, comptime T: type) Error!T {
        const n = @sizeOf(T);
        if (r.buf.len - r.pos < n) return error.Truncated;
        const bits = std.mem.readInt(std.meta.Int(.unsigned, n * 8), r.buf[r.pos..][0..n], .little);
        r.pos += n;
        return @bitCast(bits);
    }

    fn bytes(r: *Reader) Error![]const u8 {
        const n = try r.varint();
        if (n > r.buf.len - r.pos) return error.Truncated;
        const s = r.buf[r.pos..][0..@intCast(n)];
        r.pos += @intCast(n);
        return s;
    }

    fn tag(r: *Reader) Error!struct { u32, WireType } {
        const t = try r.varint();
        const num = std.math.cast(u32, t >> 3) orelse return error.OutOfRange;
        return .{ num, @enumFromInt(@as(u3, @truncate(t))) };
    }

    fn skip(r: *Reader, wt: WireType) Error!void {
        switch (wt) {
            .varint => _ = try r.varint(),
            .fixed64 => _ = try r.fixed(u64),
            .fixed32 => _ = try r.fixed(u32),
            .len => _ = try r.bytes(),
            _ => return error.WireTypeMismatch, // groups: deprecated, never produced
        }
    }
};

// ---- the type mapping ----
fn wire_type(comptime T: type) WireType {
    return switch (@typeInfo(T)) {
        .bool, .int, .@"enum" => .varint,
        .float => |f| if (f.bits <= 32) .fixed32 else .fixed64,
        .optional => |o| wire_type(o.child),
        else => .len, // strings, messages, packed lists
    };
}

fn is_scalar(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum" => true,
        else => false,
    };
}

fn is_list(comptime T: type) bool {
    return @typeInfo(T) == .pointer and T != []const u8;
}

/// Commands are numbered by CommandId; everything else by declaration order.
fn field_number(comptime T: type, comptime i: usize, comptime name: []const u8) u32 {
    if (T == Command) return @intFromEnum(@field(CommandId, name));
    return i + 1;
}

/// The protobuf default for a field that wasn't sent.
fn zero(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .bool => false,
        .int, .float => 0,
        .@"enum" => |e| @enumFromInt(e.fields[0].value),
        .optional => null,
        .pointer => &.{},
        .@"struct" => |s| blk: {
            var v: T = undefined;
            inline for (s.fields) |f| @field(v, f.name) = zero(f.type);
            break :blk v;
        },
        else => @compileError("no default for " ++ @typeName(T) ++ "; make the field optional or a list"),
    };
}

fn zigzag(v: i64) u64 {
    return @bitCast((v << 1) ^ (v >> 63));
}

fn unzigzag(raw: u64) i64 {
    return @bitCast((raw >> 1) ^ (0 -% (raw & 1)));
}

/// The enum value with this number, if T declares one.
fn to_enum(comptime T: type, raw: u64) ?T {
    inline for (@typeInfo(T).@"enum".fields) |f| {
        if (raw == f.value) return @enumFromInt(f.value);
    }
    return null;
}

// ---- decoding ----
fn read_scalar(comptime T: type, r: *Reader, wt: WireType) Error!T {
    if (wt != wire_type(T)) return error.WireTypeMismatch;
    return switch (@typeInfo(T)) {
        .bool => (try r.varint()) != 0,
        .int => |i| if (i.signedness == .signed)
            std.math.cast(T, unzigzag(try r.varint())) orelse error.OutOfRange
        else
            std.math.cast(T, try r.varint()) orelse error.OutOfRange,
        .float => try r.fixed(T),
        .@"enum" => to_enum(T, try r.varint()) orelse error.InvalidEnum,
        else => unreachable,
    };
}

fn read_value(comptime T: type, r: *Reader, wt: WireType, a: Allocator) Error!T {
    switch (@typeInfo(T)) {
        .optional => |o| return try read_value(o.child, r, wt, a),
        .pointer => {
            if (T != []const u8) @compileError("lists are read by read_list");
            if (wt != .len) return error.WireTypeMismatch;
            // Copied: the request buffer is reused once the request is answered.
            return try a.dupe(u8, try r.bytes());
        },
        .@"struct", .@"union" => {
            if (wt != .len) return error.WireTypeMismatch;
            return decode_message(T, try r.bytes(), a);
        },
        else => return read_scalar(T, r, wt),
    }
}

fn append(comptime E: type, a: Allocator, s: []const E, v: E) Error![]const E {
    const out = try a.alloc(E, s.len + 1);
    @memcpy(out[0..s.len], s);
    out[s.len] = v;
    return out;
}

/// One occurrence of a repeated field: a single element, or a packed run of scalars.
fn read_list(comptime L: type, dst: *L, r: *Reader, wt: WireType, a: Allocator) Error!void {
    const E = @typeInfo(L).pointer.child;
    if (comptime is_scalar(E)) {
        if (wt == .len) {
            var sub: Reader = .{ .buf = try r.bytes() };
            while (!sub.done()) dst.* = try append(E, a, dst.*, try read_scalar(E, &sub, wire_type(E)));
            return;
        }
    }
    dst.* = try append(E, a, dst.*, try read_value(E, r, wt, a));
}

fn read_field(comptime F: type, dst: *F, r: *Reader, wt: WireType, a: Allocator) Error!void {
    if (comptime is_list(F)) return read_list(F, dst, r, wt, a);
    if (@typeInfo(F) == .optional) {
        const C = @typeInfo(F).optional.child;
        if (comptime is_list(C)) {
            // An optional list: absent and empty are the same thing on the wire.
            var list: C = dst.* orelse &.{};
            try read_list(C, &list, r, wt, a);
            dst.* = list;
            return;
        }
    }
    dst.* = try read_value(F, r, wt, a);
}

/// Decode a message of type T. Everything it points to is allocated in a.
pub fn decode_message(comptime T: type, buf: []const u8, a: Allocator) Error!T {
    @setEvalBranchQuota(100000);
    var r: Reader = .{ .buf = buf };
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            var out = zero(T);
            while (!r.done()) {
                const num, const wt = try r.tag();
                var matched = false;
                inline for (s.fields, 0..) |f, i| {
                    if (!matched and num == field_number(T, i, f.name)) {
                        matched = true;
                        try read_field(f.type, &@field(out, f.name), &r, wt, a);
                    }
                }
                if (!matched) try r.skip(wt); // a newer client's field
            }
            return out;
        },
        .@"union" => |u| {
            var out: ?T = null;
            while (!r.done()) {
                const num, const wt = try r.tag();
                var matched = false;
                inline for (u.fields, 0..) |f, i| {
                    if (!matched and num == field_number(T, i, f.name)) {
                        matched = true;
                        if (f.type == void) {
                            if (wt != .len) return error.WireTypeMismatch;
                            _ = try r.bytes(); // Empty
                            out = @unionInit(T, f.name, {});
                        } else {
                            out = @unionInit(T, f.name, try read_value(f.type, &r, wt, a));
                        }
                    }
                }
                if (!matched) try r.skip(wt);
            }
            // An unknown variant (a newer client's command) also ends up here.
            return out orelse error.MissingVariant;
        },
        else => @compileError("not a message: " ++ @typeName(T)),
    }
}

pub fn decode_request(buf: []const u8, a: Allocator) Error![]const Command {
    return (try decode_message(Request, buf, a)).commands;
}

// ---- encoding ----
const Writer = struct {
    a: Allocator,
    out: std.ArrayListUnmanaged(u8) = .empty,

    fn varint(w: *Writer, v: u64) Error!void {
        var x = v;
        while (x >= 0x80) : (x >>= 7) try w.out.append(w.a, @as(u8, @truncate(x)) | 0x80);
        try w.out.append(w.a, @truncate(x));
    }

    fn tag(w: *Writer, num: u32, wt: WireType) Error!void {
        try w.varint((@as(u64, num) << 3) | @intFromEnum(wt));
    }

    fn fixed(w: *Writer, v: anytype) Error!void {
        const T = @TypeOf(v);
        var b: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(std.meta.Int(.unsigned, @bitSizeOf(T)), &b, @bitCast(v), .little);
        try w.out.appendSlice(w.a, &b);
    }

    fn bytes(w: *Writer, num: u32, s: []const u8) Error!void {
        try w.tag(num, .len);
        try w.varint(s.len);
        try w.out.appendSlice(w.a, s);
    }
};

fn write_field(w: *Writer, num: u32, comptime F: type, v: F, a: Allocator) Error!void {
    switch (@typeInfo(F)) {
        .optional => |o| if (v) |x| try write_field(w, num, o.child, x, a),
        .pointer => |p| if (F == []const u8)
            try w.bytes(num, v)
        else for (v) |x| try write_field(w, num, p.child, x, a),
        .@"struct", .@"union" => try w.bytes(num, try encode_message(F, v, a)),
        .bool => {
            try w.tag(num, .varint);
            try w.varint(@intFromBool(v));
        },
        .int => |i| {
            try w.tag(num, .varint);
            try w.varint(if (i.signedness == .signed) zigzag(v) else v);
        },
        .float => {
            try w.tag(num, wire_type(F));
            try w.fixed(v);
        },
        .@"enum" => {
            try w.tag(num, .varint);
            try w.varint(@intCast(@intFromEnum(v)));
        },
        else => @compileError("no protobuf mapping for " ++ @typeName(F)),
    }
}

/// Encode a message of type T (a struct, or a tagged union as a oneof).
pub fn encode_message(comptime T: type, v: T, a: Allocator) Error![]u8 {
    var w: Writer = .{ .a = a };
    switch (@typeInfo(T)) {
        .@"struct" => |s| inline for (s.fields, 0..) |f, i| {
            try write_field(&w, field_number(T, i, f.name), f.type, @field(v, f.name), a);
        },
        .@"union" => |u| {
            @setEvalBranchQuota(100000);
            const active = std.meta.activeTag(v);
            inline for (u.fields, 0..) |f, i| {
                if (active == @field(std.meta.Tag(T), f.name)) {
                    const num = field_number(T, i, f.name);
                    if (f.type == void) try w.bytes(num, "") else try write_field(&w, num, f.type, @field(v, f.name), a);
                }
            }
        },
        else => @compileError("not a message: " ++ @typeName(T)),
    }
    return w.out.items;
}

// Value has its own schema (lists are wrapped, so they fit in a oneof).
fn encode_list(a: Allocator, items: []const Value) Error![]u8 {
    var w: Writer = .{ .a = a };
    for (items) |item| try w.bytes(1, try encode_value(a, item));
    return w.out.items;
}

fn encode_value(a: Allocator, v: Value) Error![]u8 {
    var w: Writer = .{ .a = a };
    switch (v) {
        .nil => try w.bytes(1, ""),
        .boolean => |b| {
            try w.tag(2, .varint);
            try w.varint(@intFromBool(b));
        },
        .integer => |n| {
            try w.tag(3, .varint);
            try w.varint(zigzag(n));
        },
        .number => |f| {
            try w.tag(4, .fixed64);
            try w.fixed(f);
        },
        .string => |s| try w.bytes(5, s),
        .list => |items| try w.bytes(6, try encode_list(a, items)),
        .map => |fields| {
            var m: Writer = .{ .a = a };
            for (fields) |f| {
                var fw: Writer = .{ .a = a };
                try fw.bytes(1, f.key);
                try fw.bytes(2, try encode_value(a, f.value));
                try m.bytes(1, fw.out.items);
            }
            try w.bytes(7, m.out.items);
        },
        .multi => |items| try w.bytes(8, try encode_list(a, items)),
    }
    return w.out.items;
}

/// A Response: the results if the batch committed, otherwise the error.
pub fn encode_response(a: Allocator, results: []const Value, err: ?[]const u8) Error![]u8 {
    var w: Writer = .{ .a = a };
    for (results) |v| try w.bytes(1, try encode_value(a, v));
    if (err) |e| try w.bytes(2, e);
    return w.out.items;
}

// ---- tests ----
test "request round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cmds = [_]Command{
        .focus_left,
        .{ .focus = .{ .id = 42 } },
        .{ .set_pan = .{ .x = -10, .y = 3 } },
        .{ .spawn = .{ .argv = &.{ "ghostty", "-e", "htop" } } },
        .{ .split = .{ .container = 1, .axis = .v, .ratios = &.{ 0.25, 0.75 }, .children = &.{ 2, 3 } } },
    };
    const bytes = try encode_message(Request, .{ .commands = &cmds }, a);
    const back = try decode_request(bytes, a);

    try std.testing.expectEqual(cmds.len, back.len);
    try std.testing.expect(back[0] == .focus_left);
    try std.testing.expectEqual(@as(u32, 42), back[1].focus.id);
    try std.testing.expectEqual(@as(i32, -10), back[2].set_pan.x);
    try std.testing.expectEqualStrings("htop", back[3].spawn.argv[2]);
    try std.testing.expectEqual(protocol.Axis.v, back[4].split.axis);
    try std.testing.expectEqual(@as(f64, 0.75), back[4].split.ratios[1]);
}

test "packed and unknown fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Split { container = 7; ratios = packed [0.5, 0.5]; children = packed [1, 2]; field 99 = 5 }
    var w: Writer = .{ .a = a };
    try w.tag(1, .varint);
    try w.varint(7);
    var ratios: Writer = .{ .a = a };
    try ratios.fixed(@as(f64, 0.5));
    try ratios.fixed(@as(f64, 0.5));
    try w.bytes(3, ratios.out.items);
    try w.bytes(4, &.{ 1, 2 });
    try w.tag(99, .varint);
    try w.varint(5);

    const S = @FieldType(Command, "split");
    const s = try decode_message(S, w.out.items, a);
    try std.testing.expectEqual(@as(u32, 7), s.container);
    try std.testing.expectEqual(@as(usize, 2), s.ratios.len);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2 }, s.children);
}
