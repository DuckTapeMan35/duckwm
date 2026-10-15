const std = @import("std");
const protocol = @import("protocol");
const wire = protocol.wire;
const linux = std.os.linux;
const Command = protocol.Command;
const Value = protocol.Value;
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);

    if (args.len < 2 or is_help(args[1])) {
        try write_all(if (args.len < 2) 2 else 1, try usage(a));
        std.process.exit(if (args.len < 2) 1 else 0);
    }

    const cmd = parse_command(a, args[1], args[2..]) catch |err| {
        fail(a, switch (err) {
            error.OutOfMemory => "out of memory",
            else => parse_error,
        });
    };

    const fd = connect(a);
    defer _ = linux.close(fd);

    const body = try wire.encode_request(a, &.{cmd});
    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(body.len), .little);
    write_all(fd, &len) catch die("quack: failed to send request\n");
    write_all(fd, body) catch die("quack: failed to send request\n");

    read_exact(fd, &len) catch die("quack: duckwm closed the connection\n");
    const frame = try a.alloc(u8, std.mem.readInt(u32, &len, .little));
    read_exact(fd, frame) catch die("quack: duckwm closed the connection\n");

    const resp = wire.decode_response(frame, a) catch die("quack: malformed response\n");
    if (resp.err) |msg| fail(a, msg);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.appendSlice(a, "{\"ok\":true,\"result\":");
    // One command, one result; a multi result prints as an array.
    try write_json(a, &out, if (resp.results.len > 0) resp.results[0] else .nil);
    try out.appendSlice(a, "}\n");
    try write_all(1, out.items);
}

fn is_help(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "help");
}

/// Print {"ok":false,...} and exit 1.
fn fail(a: Allocator, msg: []const u8) noreturn {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    out.appendSlice(a, "{\"ok\":false,\"error\":") catch die("quack: out of memory\n");
    write_string(a, &out, msg) catch die("quack: out of memory\n");
    out.appendSlice(a, "}\n") catch die("quack: out of memory\n");
    write_all(1, out.items) catch {};
    std.process.exit(1);
}

fn die(msg: []const u8) noreturn {
    write_all(2, msg) catch {};
    std.process.exit(1);
}

// ---- Arguments ----
var parse_error: []const u8 = "invalid arguments";

fn bad(comptime fmt: []const u8, args: anytype) error{InvalidArgument} {
    parse_error = std.fmt.allocPrint(std.heap.page_allocator, fmt, args) catch "invalid arguments";
    return error.InvalidArgument;
}

fn parse_command(a: Allocator, name: []const u8, args: []const []const u8) !Command {
    @setEvalBranchQuota(100000);
    inline for (@typeInfo(Command).@"union".fields) |f| {
        if (std.mem.eql(u8, name, f.name)) {
            if (f.type == void) {
                if (args.len > 0) return bad("{s} takes no arguments", .{f.name});
                return @unionInit(Command, f.name, {});
            }
            return @unionInit(Command, f.name, try parse_payload(f.type, a, f.name, args));
        }
    }
    return bad("unknown command: {s} (see quack --help)", .{name});
}

fn parse_payload(comptime T: type, a: Allocator, comptime cmd: []const u8, args: []const []const u8) !T {
    const fields = @typeInfo(T).@"struct".fields;
    var out: T = undefined;
    var i: usize = 0;
    inline for (fields, 0..) |f, fi| {
        const last = fi == fields.len - 1;
        if (comptime last and is_list(f.type)) {
            // The last list takes everything left: quack spawn ghostty -e htop
            const L = unwrap(f.type);
            const E = @typeInfo(L).pointer.child;
            const items = try a.alloc(E, args.len - i);
            for (args[i..], items) |arg, *item| item.* = try parse_scalar(E, a, f.name, arg);
            @field(out, f.name) = items;
            i = args.len;
        } else if (i < args.len) {
            @field(out, f.name) = try parse_arg(f.type, a, f.name, args[i]);
            i += 1;
        } else if (@typeInfo(f.type) == .optional) {
            @field(out, f.name) = null;
        } else {
            return bad("{s}: missing argument <{s}> (usage: quack {s})", .{ cmd, f.name, signature(T, cmd) });
        }
    }
    if (i < args.len) return bad("{s}: too many arguments (usage: quack {s})", .{ cmd, signature(T, cmd) });
    return out;
}

fn unwrap(comptime T: type) type {
    return if (@typeInfo(T) == .optional) @typeInfo(T).optional.child else T;
}

fn is_list(comptime T: type) bool {
    const U = unwrap(T);
    return @typeInfo(U) == .pointer and U != []const u8;
}

fn parse_arg(comptime T: type, a: Allocator, comptime field: []const u8, arg: []const u8) !T {
    switch (@typeInfo(T)) {
        .optional => |o| {
            if (std.mem.eql(u8, arg, "nil") or std.mem.eql(u8, arg, "null")) return null;
            return try parse_arg(o.child, a, field, arg);
        },
        .pointer => |p| {
            if (T == []const u8) return arg;
            // A list that isn't last: comma-separated.
            var items: std.ArrayListUnmanaged(p.child) = .empty;
            var it = std.mem.tokenizeScalar(u8, arg, ',');
            while (it.next()) |s| try items.append(a, try parse_scalar(p.child, a, field, s));
            return items.items;
        },
        .@"struct", .@"union" => return std.json.parseFromSliceLeaky(T, a, arg, .{}) catch |err|
            bad("<{s}>: invalid JSON ({s})", .{ field, @errorName(err) }),
        else => return parse_scalar(T, a, field, arg),
    }
}

fn parse_scalar(comptime T: type, a: Allocator, comptime field: []const u8, arg: []const u8) !T {
    switch (@typeInfo(T)) {
        .bool => {
            const yes = [_][]const u8{ "true", "on", "1", "yes" };
            const no = [_][]const u8{ "false", "off", "0", "no" };
            for (yes) |s| if (std.mem.eql(u8, arg, s)) return true;
            for (no) |s| if (std.mem.eql(u8, arg, s)) return false;
            return bad("<{s}>: expected true or false, got '{s}'", .{ field, arg });
        },
        .int => {
            // #rrggbb for colors, alongside 0x.., 0o.., 0b.. and decimal.
            if (arg.len > 1 and arg[0] == '#')
                return std.fmt.parseInt(T, arg[1..], 16) catch bad("<{s}>: invalid number '{s}'", .{ field, arg });
            return std.fmt.parseInt(T, arg, 0) catch bad("<{s}>: invalid number '{s}'", .{ field, arg });
        },
        .float => return std.fmt.parseFloat(T, arg) catch bad("<{s}>: invalid number '{s}'", .{ field, arg }),
        .@"enum" => |e| {
            if (std.meta.stringToEnum(T, arg)) |v| return v;
            comptime var names: []const u8 = "";
            inline for (e.fields, 0..) |ef, i| names = names ++ (if (i > 0) ", " else "") ++ ef.name;
            return bad("<{s}>: expected one of {s}, got '{s}'", .{ field, names, arg });
        },
        else => return parse_arg(T, a, field, arg),
    }
}

/// focus <id>, set_keyboard_layout <layout> [variant] ..., spawn <argv...>
fn signature(comptime T: type, comptime cmd: []const u8) []const u8 {
    return comptime blk: {
        var s: []const u8 = cmd;
        if (T == void) break :blk s;
        const fields = @typeInfo(T).@"struct".fields;
        for (fields, 0..) |f, i| {
            const last = i == fields.len - 1;
            const name = if (last and is_list(f.type)) f.name ++ "..." else f.name;
            s = s ++ if (@typeInfo(f.type) == .optional) " [" ++ name ++ "]" else " <" ++ name ++ ">";
        }
        break :blk s;
    };
}

fn usage(a: Allocator) ![]u8 {
    @setEvalBranchQuota(100000);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.appendSlice(a, "Usage: quack <command> [args...]\n\nCommands:\n");
    inline for (@typeInfo(Command).@"union".fields) |f| {
        try out.print(a, "  {s}\n", .{comptime signature(f.type, f.name)});
    }
    return out.items;
}

// ---- JSON output ----
fn write_json(a: Allocator, out: *std.ArrayListUnmanaged(u8), v: Value) Allocator.Error!void {
    switch (v) {
        .nil => try out.appendSlice(a, "null"),
        .boolean => |b| try out.appendSlice(a, if (b) "true" else "false"),
        .integer => |n| try out.print(a, "{d}", .{n}),
        .number => |f| if (std.math.isFinite(f)) try out.print(a, "{d}", .{f}) else try out.appendSlice(a, "null"),
        .str => |s| try write_string(a, out, s),
        .list, .multi => |items| {
            try out.append(a, '[');
            for (items, 0..) |item, i| {
                if (i > 0) try out.append(a, ',');
                try write_json(a, out, item);
            }
            try out.append(a, ']');
        },
        .map => |fields| {
            try out.append(a, '{');
            for (fields, 0..) |f, i| {
                if (i > 0) try out.append(a, ',');
                try write_string(a, out, f.key);
                try out.append(a, ':');
                try write_json(a, out, f.value);
            }
            try out.append(a, '}');
        },
    }
}

fn write_string(a: Allocator, out: *std.ArrayListUnmanaged(u8), s: []const u8) Allocator.Error!void {
    try out.append(a, '"');
    for (s) |ch| switch (ch) {
        '"' => try out.appendSlice(a, "\\\""),
        '\\' => try out.appendSlice(a, "\\\\"),
        '\n' => try out.appendSlice(a, "\\n"),
        '\r' => try out.appendSlice(a, "\\r"),
        '\t' => try out.appendSlice(a, "\\t"),
        0...8, 11, 12, 14...0x1f => try out.print(a, "\\u{x:0>4}", .{ch}),
        else => try out.append(a, ch),
    };
    try out.append(a, '"');
}

// ---- Socket ----
fn get_sock_path(a: Allocator) ![]u8 {
    if (std.c.getenv("XDG_RUNTIME_DIR")) |dir| {
        return std.fmt.allocPrint(a, "{s}/duckwm.sock", .{std.mem.span(dir)});
    }
    return std.fmt.allocPrint(a, "/tmp/duckwm-{d}.sock", .{linux.getuid()});
}

fn connect(a: Allocator) i32 {
    const path = get_sock_path(a) catch die("quack: out of memory\n");

    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(rc) != .SUCCESS) die("quack: failed to create socket\n");
    const fd: i32 = @intCast(rc);

    var addr = std.mem.zeroes(linux.sockaddr.un);
    addr.family = linux.AF.UNIX;
    if (path.len >= addr.path.len) die("quack: socket path too long\n");
    @memcpy(addr.path[0..path.len], path);

    if (linux.errno(linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un))) != .SUCCESS)
        die("quack: could not connect to duckwm (is it running?)\n");
    return fd;
}

fn write_all(fd: i32, buf: []const u8) !void {
    var done: usize = 0;
    while (done < buf.len) {
        const rc = linux.write(fd, buf[done..].ptr, buf.len - done);
        switch (linux.errno(rc)) {
            .SUCCESS => done += rc,
            .INTR => continue,
            else => return error.WriteFailed,
        }
    }
}

fn read_exact(fd: i32, buf: []u8) !void {
    var done: usize = 0;
    while (done < buf.len) {
        const rc = linux.read(fd, buf[done..].ptr, buf.len - done);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return error.EndOfStream;
                done += rc;
            },
            .INTR => continue,
            else => return error.ReadFailed,
        }
    }
}

// ---- Tests ----
test "arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expect(try parse_command(a, "cleanup_left_behind", &.{}) == .cleanup_left_behind);
    try std.testing.expectEqual(
        @as(u32, 42),
        (try parse_command(a, "focus", &.{"42"})).focus.id,
    );
    try std.testing.expectEqual(
        @as(i32, -5),
        (try parse_command(a, "pan_by", &.{ "-5", "3" })).pan_by.dx,
    );
    try std.testing.expectEqual(
        @as(u32, 0x1e1e2e),
        (try parse_command(a, "set_border_width", &.{"#1e1e2e"})).set_border_width.width,
    );
    try std.testing.expectEqual(
        protocol.Dir.up,
        (try parse_command(a, "resize_focused_edge", &.{ "up", "10" })).resize_focused_edge.direction,
    );

    const spawn = (try parse_command(a, "spawn", &.{ "ghostty", "-e", "htop" })).spawn;
    try std.testing.expectEqual(@as(usize, 3), spawn.argv.len);
    try std.testing.expectEqualStrings("htop", spawn.argv[2]);

    const kb = (try parse_command(a, "set_keyboard_layout", &.{ "us", "intl" })).set_keyboard_layout;
    try std.testing.expectEqualStrings("intl", kb.variant.?);
    try std.testing.expect(kb.options == null);

    const strat = (try parse_command(a, "set_reparent_strategy", &.{ "3", "nil" })).set_reparent_strategy;
    try std.testing.expect(strat.strategy == null);

    // Not last: comma-separated. Last: the remaining arguments.
    const split = (try parse_command(a, "split", &.{ "1", "v", "0.25,0.75", "2", "3" })).split;
    try std.testing.expectEqual(@as(f64, 0.75), split.ratios[1]);
    try std.testing.expectEqualSlices(u32, &.{ 2, 3 }, split.children);

    const layout = (try parse_command(a, "set_layout", &.{
        \\{"nodes":[{"id":1,"constraints":[{"left_of":{"other":2}}]},{"id":2,"constraints":null}]}
    })).set_layout.layout;
    try std.testing.expectEqual(@as(u32, 2), layout.nodes[0].constraints.?[0].left_of.other);

    try std.testing.expectError(error.InvalidArgument, parse_command(a, "nope", &.{}));
    try std.testing.expectError(error.InvalidArgument, parse_command(a, "focus", &.{}));
    try std.testing.expectError(error.InvalidArgument, parse_command(a, "focus", &.{ "1", "2" }));
    try std.testing.expectError(error.InvalidArgument, parse_command(a, "set_floating", &.{ "1", "maybe" }));
    try std.testing.expectError(error.InvalidArgument, parse_command(a, "quit", &.{"now"}));
}

test "json" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var out: std.ArrayListUnmanaged(u8) = .empty;
    const fields = [_]Value.Field{ .{ .key = "x", .value = .{ .integer = 1 } }, .{ .key = "s", .value = .{ .str = "a\"b\n" } } };
    try write_json(a, &out, .{ .multi = &.{ .{ .map = &fields }, .{ .number = 0.5 }, .nil, .{ .boolean = false } } });
    try std.testing.expectEqualStrings("[{\"x\":1,\"s\":\"a\\\"b\\n\"},0.5,null,false]", out.items);
}
