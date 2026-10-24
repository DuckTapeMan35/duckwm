const std = @import("std");
const protocol = @import("protocol.zig");
const Command = protocol.Command;
const CommandId = protocol.CommandId;
const Value = protocol.Value;
const Request = protocol.Request;
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
        const bits = std.mem.readInt(@Int(.unsigned, n * 8), r.buf[r.pos..][0..n], .little);
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
        return .{ num, @fromBackingInt(@intCast(@as(u3, @truncate(t)))) };
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
    if (T == Command) return @backingInt(@field(CommandId, name));
    return i + 1;
}

/// The protobuf default for a field that wasn't sent.
fn zero(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .bool => false,
        .int, .float => 0,
        .@"enum" => |e| @fromBackingInt(@intCast(e.field_values[0])),
        .optional => null,
        .pointer => &.{},
        .@"struct" => |s| blk: {
            var v: T = undefined;
            inline for (s.field_names, s.field_types) |f_name, f_type| @field(v, f_name) = zero(f_type);
            break :blk v;
        },
        // A oneof has no default: decode_message requires it to be sent.
        .@"union" => undefined,
        else => @compileError("no default for " ++ @typeName(T) ++ "; make the field optional or a list"),
    };
}

fn zigzag(v: i64) u64 {
    return @bitCast((v << 1) ^ (v >> 63));
}

fn unzigzag(raw: u64) i64 {
    return @bitCast((raw >> 1) ^ (0 -% (raw & 1)));
}

// ---- decoding ----
/// The enum value with this number, if T declares one.
fn to_enum(comptime T: type, raw: u64) ?T {
    inline for (@typeInfo(T).@"enum".field_values) |value| {
        if (raw == value) return @fromBackingInt(@intCast(value));
    }
    return null;
}

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
    if (T == Value) {
        if (wt != .len) return error.WireTypeMismatch;
        return decode_value(try r.bytes(), a);
    }
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
            var seen: [s.field_names.len]bool = @splat(false);
            while (!r.done()) {
                const num, const wt = try r.tag();
                var matched = false;
                inline for (s.field_names, s.field_types, 0..) |f_name, f_type, i| {
                    if (!matched and num == field_number(T, i, f_name)) {
                        matched = true;
                        seen[i] = true;
                        try read_field(f_type, &@field(out, f_name), &r, wt, a);
                    }
                }
                if (!matched) try r.skip(wt); // a newer client's field
            }
            // A union field (a oneof message) has no default, so it must have been sent.
            inline for (s.field_types, 0..) |f_type, i| {
                if (@typeInfo(f_type) == .@"union" and !seen[i]) return error.MissingVariant;
            }
            return out;
        },
        .@"union" => |u| {
            var out: ?T = null;
            while (!r.done()) {
                const num, const wt = try r.tag();
                var matched = false;
                inline for (u.field_names, u.field_types, 0..) |f_name, f_type, i| {
                    if (!matched and num == field_number(T, i, f_name)) {
                        matched = true;
                        if (f_type == void) {
                            if (wt != .len) return error.WireTypeMismatch;
                            _ = try r.bytes(); // Empty
                            out = @unionInit(T, f_name, {});
                        } else {
                            out = @unionInit(T, f_name, try read_value(f_type, &r, wt, a));
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
        try w.varint((@as(u64, num) << 3) | @backingInt(wt));
    }

    fn fixed(w: *Writer, v: anytype) Error!void {
        const T = @TypeOf(v);
        var b: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(@Int(.unsigned, @bitSizeOf(T)), &b, @bitCast(v), .little);
        try w.out.appendSlice(w.a, &b);
    }

    fn bytes(w: *Writer, num: u32, s: []const u8) Error!void {
        try w.tag(num, .len);
        try w.varint(s.len);
        try w.out.appendSlice(w.a, s);
    }
};

fn write_field(w: *Writer, num: u32, comptime F: type, v: F, a: Allocator) Error!void {
    if (F == Value) return w.bytes(num, try encode_value(a, v));
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
            try w.varint(@intCast(@backingInt(v)));
        },
        else => @compileError("no protobuf mapping for " ++ @typeName(F)),
    }
}

/// Encode a message of type T (a struct, or a tagged union as a oneof).
pub fn encode_message(comptime T: type, v: T, a: Allocator) Error![]u8 {
    var w: Writer = .{ .a = a };
    switch (@typeInfo(T)) {
        .@"struct" => |s| inline for (s.field_names, s.field_types, 0..) |f_name, f_type, i| {
            try write_field(&w, field_number(T, i, f_name), f_type, @field(v, f_name), a);
        },
        .@"union" => |u| {
            @setEvalBranchQuota(100000);
            const active = std.meta.activeTag(v);
            inline for (u.field_names, u.field_types, 0..) |f_name, f_type, i| {
                if (active == @field(std.meta.Tag(T), f_name)) {
                    const num = field_number(T, i, f_name);
                    if (f_type == void) try w.bytes(num, "") else try write_field(&w, num, f_type, @field(v, f_name), a);
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

pub fn encode_value(a: Allocator, v: Value) Error![]u8 {
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
        .str => |s| try w.bytes(5, s),
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

// ---- decoding responses (for clients) ----
/// What a Response decodes to: the results if the batch committed, otherwise the error.
pub const Response = struct {
    results: []const Value,
    err: ?[]const u8,
};

/// A len-delimited field's contents, checking it is one.
fn len_field(r: *Reader, wt: WireType) Error![]const u8 {
    if (wt != .len) return error.WireTypeMismatch;
    return r.bytes();
}

/// A ValueList: repeated Value values = 1.
fn decode_list(buf: []const u8, a: Allocator) Error![]const Value {
    var r: Reader = .{ .buf = buf };
    var items: std.ArrayListUnmanaged(Value) = .empty;
    while (!r.done()) {
        const num, const wt = try r.tag();
        if (num == 1) try items.append(a, try decode_value(try len_field(&r, wt), a)) else try r.skip(wt);
    }
    return items.items;
}

/// A ValueField: string key = 1; Value value = 2.
fn decode_field(buf: []const u8, a: Allocator) Error!Value.Field {
    var r: Reader = .{ .buf = buf };
    var f: Value.Field = .{ .key = "", .value = .nil };
    while (!r.done()) {
        const num, const wt = try r.tag();
        switch (num) {
            1 => f.key = try a.dupe(u8, try len_field(&r, wt)),
            2 => f.value = try decode_value(try len_field(&r, wt), a),
            else => try r.skip(wt),
        }
    }
    return f;
}

/// A ValueMap: repeated ValueField fields = 1.
fn decode_map(buf: []const u8, a: Allocator) Error![]const Value.Field {
    var r: Reader = .{ .buf = buf };
    var fields: std.ArrayListUnmanaged(Value.Field) = .empty;
    while (!r.done()) {
        const num, const wt = try r.tag();
        if (num == 1) try fields.append(a, try decode_field(try len_field(&r, wt), a)) else try r.skip(wt);
    }
    return fields.items;
}

/// A Value: a oneof, so the last variant on the wire wins; none at all is nil.
pub fn decode_value(buf: []const u8, a: Allocator) Error!Value {
    var r: Reader = .{ .buf = buf };
    var v: Value = .nil;
    while (!r.done()) {
        const num, const wt = try r.tag();
        switch (num) {
            1 => {
                _ = try len_field(&r, wt); // Empty
                v = .nil;
            },
            2 => v = .{ .boolean = try read_scalar(bool, &r, wt) },
            3 => v = .{ .integer = try read_scalar(i64, &r, wt) },
            4 => v = .{ .number = try read_scalar(f64, &r, wt) },
            5 => v = .{ .str = try a.dupe(u8, try len_field(&r, wt)) },
            6 => v = .{ .list = try decode_list(try len_field(&r, wt), a) },
            7 => v = .{ .map = try decode_map(try len_field(&r, wt), a) },
            8 => v = .{ .multi = try decode_list(try len_field(&r, wt), a) },
            else => try r.skip(wt),
        }
    }
    return v;
}

/// Decode a Response. Everything it points to is allocated in a.
pub fn decode_response(buf: []const u8, a: Allocator) Error!Response {
    var r: Reader = .{ .buf = buf };
    var results: std.ArrayListUnmanaged(Value) = .empty;
    var err: ?[]const u8 = null;
    while (!r.done()) {
        const num, const wt = try r.tag();
        switch (num) {
            1 => try results.append(a, try decode_value(try len_field(&r, wt), a)),
            2 => err = try a.dupe(u8, try len_field(&r, wt)),
            else => try r.skip(wt),
        }
    }
    return .{ .results = results.items, .err = err };
}

/// Encode a Request: one batch of commands, run as one transaction.
pub fn encode_request(a: Allocator, commands: []const Command) Error![]u8 {
    return encode_message(Request, .{ .commands = commands }, a);
}

// ---- the framed messages ----
pub fn decode_client_message(buf: []const u8, a: Allocator) Error!protocol.ClientMessage {
    return decode_message(protocol.ClientMessage, buf, a);
}

pub fn encode_client_message(a: Allocator, m: protocol.ClientMessage) Error![]u8 {
    return encode_message(protocol.ClientMessage, m, a);
}

/// What duckwm sends: the answer to a request, or a call to a callback.
pub const ServerMessage = union(enum) {
    response: Response,
    call: protocol.Call,
};

/// A ServerMessage holding a Response.
pub fn encode_server_response(a: Allocator, results: []const Value, err: ?[]const u8) Error![]u8 {
    var w: Writer = .{ .a = a };
    try w.bytes(1, try encode_response(a, results, err));
    return w.out.items;
}

/// A ServerMessage holding a Call.
pub fn encode_server_call(a: Allocator, call: protocol.Call) Error![]u8 {
    var w: Writer = .{ .a = a };
    try w.bytes(2, try encode_message(protocol.Call, call, a));
    return w.out.items;
}

pub fn decode_server_message(buf: []const u8, a: Allocator) Error!ServerMessage {
    var r: Reader = .{ .buf = buf };
    var out: ?ServerMessage = null;
    while (!r.done()) {
        const num, const wt = try r.tag();
        switch (num) {
            1 => out = .{ .response = try decode_response(try len_field(&r, wt), a) },
            2 => out = .{ .call = try decode_message(protocol.Call, try len_field(&r, wt), a) },
            else => try r.skip(wt),
        }
    }
    return out orelse error.MissingVariant;
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

test "response round trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fields = [_]Value.Field{
        .{ .key = "x", .value = .{ .integer = -3 } },
        .{ .key = "name", .value = .{ .str = "kitty" } },
    };
    const results = [_]Value{
        .nil,
        .{ .boolean = true },
        .{ .number = 0.5 },
        .{ .list = &.{ .{ .integer = 1 }, .{ .integer = 2 } } },
        .{ .map = &fields },
        .{ .multi = &.{ .{ .integer = 7 }, .nil } },
    };
    const ok = try decode_response(try encode_response(a, &results, null), a);
    try std.testing.expect(ok.err == null);
    try std.testing.expectEqual(results.len, ok.results.len);
    try std.testing.expect(ok.results[0] == .nil);
    try std.testing.expect(ok.results[1].boolean);
    try std.testing.expectEqual(@as(f64, 0.5), ok.results[2].number);
    try std.testing.expectEqual(@as(i64, 2), ok.results[3].list[1].integer);
    try std.testing.expectEqual(@as(i64, -3), ok.results[4].map[0].value.integer);
    try std.testing.expectEqualStrings("kitty", ok.results[4].map[1].value.str);
    try std.testing.expect(ok.results[5].multi[1] == .nil);

    const failed = try decode_response(try encode_response(a, &.{}, "no such node"), a);
    try std.testing.expectEqual(@as(usize, 0), failed.results.len);
    try std.testing.expectEqualStrings("no such node", failed.err.?);
}

test "client and server messages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ret = try decode_client_message(try encode_client_message(a, .{ .ret = .{
        .commands = &.{.{ .focus = .{ .id = 3 } }},
        .err = null,
        .callback = 9,
        .layout = null,
        .state = null,
    } }), a);
    try std.testing.expectEqual(@as(u32, 3), ret.ret.commands[0].focus.id);
    try std.testing.expectEqual(@as(?u64, 9), ret.ret.callback);

    const call = try decode_server_message(try encode_server_call(a, .{
        .callback = 17,
        .args = .{ .arranger = .{
            .event = .map,
            .id = 42,
            .prev_id = null,
            .work_area = .{ .x = 0, .y = 30, .width = 1920, .height = 1050 },
            .cursor_dx = -5,
            .cursor_dy = 3,
            .focused = 7,
            .windows = &.{.{ .id = 7, .geometry = .{ .x = 0, .y = 30, .width = 1920, .height = 1050 } }},
            .layout = .{ .nodes = &.{} },
            .state = .{ .integer = 1 },
        } },
    }), a);
    const args = call.call.args.arranger;
    try std.testing.expectEqual(protocol.ArrangerEvent.map, args.event);
    try std.testing.expectEqual(@as(i32, -5), args.cursor_dx);
    try std.testing.expectEqual(@as(?u32, 7), args.focused);
    try std.testing.expectEqual(@as(u32, 1050), args.windows[0].geometry.height);
    try std.testing.expectEqual(@as(i64, 1), args.state.?.integer);

    // A Call without its args is rejected rather than decoded with garbage.
    var w: Writer = .{ .a = a };
    try w.tag(1, .varint);
    try w.varint(17);
    try std.testing.expectError(error.MissingVariant, decode_message(protocol.Call, w.out.items, a));

    const resp = try decode_server_message(try encode_server_response(a, &.{.{ .integer = 5 }}, null), a);
    try std.testing.expectEqual(@as(i64, 5), resp.response.results[0].integer);
}

test "return with layout and state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fields = [_]Value.Field{.{ .key = "next_h", .value = .{ .boolean = true } }};
    const children = [_]protocol.Ref{ .{ .id = 5 }, .{ .key = 1 } };
    const cons = [_]protocol.ConstraintSpec{.{ .split = .{
        .container = .{ .key = 0 },
        .axis = .h,
        .ratios = &.{ 0.5, 0.5 },
        .children = &children,
    } }};
    const nodes = [_]protocol.NodeSpec{.{ .id = .{ .key = 0 }, .constraints = &cons }};
    const msg: protocol.ClientMessage = .{ .ret = .{
        .commands = &.{},
        .err = null,
        .callback = null,
        .layout = .{ .nodes = &nodes },
        .state = .{ .map = &fields },
    } };

    const back = try decode_client_message(try encode_client_message(a, msg), a);
    const r = back.ret;
    try std.testing.expect(r.state.?.map[0].value.boolean);
    const s = r.layout.?.nodes[0].constraints.?[0].split;
    try std.testing.expectEqual(@as(u32, 0), s.container.key);
    try std.testing.expectEqual(@as(u32, 5), s.children[0].id);
    try std.testing.expectEqual(@as(u32, 1), s.children[1].key);
}
