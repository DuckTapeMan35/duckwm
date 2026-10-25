const std = @import("std");
const protocol = @import("protocol");
const client = @import("duckwm_client");
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

    if (std.mem.eql(u8, args[1], "repl")) return repl();
    const batch = std.mem.eql(u8, args[1], "-");
    const cmds: []const Command = if (batch)
        parse_batch(a, try read_stdin(a)) catch |err| fail(a, if (err == error.OutOfMemory) "out of memory" else parse_error)
    else blk: {
        const one = try a.alloc(Command, 1);
        one[0] = parse_command(a, args[1], args[2..]) catch |err| fail(a, if (err == error.OutOfMemory) "out of memory" else parse_error);
        break :blk one;
    };

    var c = connect(a);
    defer c.deinit();

    const results = c.run(a, cmds) catch |err| switch (err) {
        error.Rejected => fail(a, c.why),
        error.OutOfMemory => die("quack: out of memory\n"),
        else => die("quack: duckwm closed the connection\n"),
    };

    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.appendSlice(a, "{\"ok\":true,\"result\":");
    if (batch) {
        // A batch: every command's result, in order.
        try write_json(a, &out, .{ .list = results });
    } else {
        // One command, one result; a multi result prints as an array.
        try write_json(a, &out, if (results.len > 0) results[0] else .nil);
    }
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
    inline for (@typeInfo(Command).@"union".field_names, @typeInfo(Command).@"union".field_types) |f_name, f_type| {
        if (std.mem.eql(u8, name, f_name)) {
            if (f_type == void) {
                if (args.len > 0) return bad("{s} takes no arguments", .{f_name});
                return @unionInit(Command, f_name, {});
            }
            return @unionInit(Command, f_name, try parse_payload(f_type, a, f_name, args));
        }
    }
    return bad("unknown command: {s} (see quack --help)", .{name});
}

fn parse_payload(comptime T: type, a: Allocator, comptime cmd: []const u8, args: []const []const u8) !T {
    const s = @typeInfo(T).@"struct";
    var out: T = undefined;
    var i: usize = 0;
    inline for (s.field_names, s.field_types, 0..) |f_name, f_type, fi| {
        const last = fi == s.field_names.len - 1;
        if (comptime last and is_list(f_type)) {
            // The last list takes everything left: quack spawn ghostty -e htop
            const L = unwrap(f_type);
            const E = @typeInfo(L).pointer.child;
            const items = try a.alloc(E, args.len - i);
            for (args[i..], items) |arg, *item| item.* = try parse_scalar(E, a, f_name, arg);
            @field(out, f_name) = items;
            i = args.len;
        } else if (i < args.len) {
            @field(out, f_name) = try parse_arg(f_type, a, f_name, args[i]);
            i += 1;
        } else if (@typeInfo(f_type) == .optional) {
            @field(out, f_name) = null;
        } else {
            return bad("{s}: missing argument <{s}> (usage: quack {s})", .{ cmd, f_name, signature(T, cmd) });
        }
    }
    if (i < args.len) return bad("{s}: too many arguments (usage: quack {s})", .{ cmd, signature(T, cmd) });
    return out;
}

/// One command per line; see the top of the file.
fn parse_batch(a: Allocator, text: []const u8) ![]const Command {
    var cmds: std.ArrayListUnmanaged(Command) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |line| {
        line_no += 1;
        const words = split_words(a, line) catch |err| switch (err) {
            error.UnterminatedQuote => return bad("line {d}: unterminated quote", .{line_no}),
            else => |e| return e,
        };
        if (words.len == 0 or words[0][0] == '#') continue;
        const cmd = parse_command(a, words[0], words[1..]) catch |err| {
            if (err == error.InvalidArgument) parse_error = try std.fmt.allocPrint(a, "line {d}: {s}", .{ line_no, parse_error });
            return err;
        };
        try cmds.append(a, cmd);
    }
    if (cmds.items.len == 0) return bad("no commands on stdin", .{});
    return cmds.items;
}

/// Whitespace-separated words; '...' and "..." group (no escapes inside).
fn split_words(a: Allocator, line: []const u8) ![]const []const u8 {
    var words: std.ArrayListUnmanaged([]const u8) = .empty;
    var word: std.ArrayListUnmanaged(u8) = .empty;
    var in_word = false;
    var quote: ?u8 = null;
    for (line) |ch| {
        if (quote) |q| {
            if (ch == q) quote = null else try word.append(a, ch);
        } else switch (ch) {
            ' ', '\t', '\r' => if (in_word) {
                try words.append(a, try word.toOwnedSlice(a));
                in_word = false;
            },
            '\'', '"' => {
                quote = ch;
                in_word = true;
            },
            else => {
                try word.append(a, ch);
                in_word = true;
            },
        }
    }
    if (quote != null) return error.UnterminatedQuote;
    if (in_word) try words.append(a, try word.toOwnedSlice(a));
    return words.items;
}

fn read_stdin(a: Allocator) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    var buf: [4096]u8 = undefined;
    while (true) {
        const rc = linux.read(0, &buf, buf.len);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return out.items;
                try out.appendSlice(a, buf[0..rc]);
            },
            .INTR => continue,
            else => die("quack: failed to read stdin\n"),
        }
    }
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
        .@"struct", .@"union" => {
            var diag: protocol.json.Diagnostic = .{};
            return protocol.json.parse(T, a, arg, &diag) catch
                bad("<{s}>: {s}", .{ field, diag.message });
        },
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
            inline for (e.field_names, 0..) |ef_name, i| names = names ++ (if (i > 0) ", " else "") ++ ef_name;
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
        const info = @typeInfo(T).@"struct";
        for (info.field_names, info.field_types, 0..) |f_name, f_type, i| {
            const last = i == info.field_names.len - 1;
            const name = if (last and is_list(f_type)) f_name ++ "..." else f_name;
            s = s ++ if (@typeInfo(f_type) == .optional) " [" ++ name ++ "]" else " <" ++ name ++ ">";
        }
        break :blk s;
    };
}

fn usage(a: Allocator) ![]u8 {
    @setEvalBranchQuota(100000);
    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.appendSlice(a,
        \\Usage: quack <command> [args...]
        \\       quack -       commands from stdin, as one batch
        \\       quack repl    Lua, evaluated inside duckwm
        \\
        \\Commands:
        \\
    );
    inline for (@typeInfo(Command).@"union".field_names, @typeInfo(Command).@"union".field_types) |f_name, f_type| {
        try out.print(a, "  {s}\n", .{comptime signature(f_type, f_name)});
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

fn connect(a: Allocator) client.Client {
    return client.Client.connect(a) catch |err| switch (err) {
        error.OutOfMemory => die("quack: out of memory\n"),
        error.PathTooLong => die("quack: socket path too long\n"),
        else => die("quack: could not connect to duckwm (is it running?)\n"),
    };
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

// ---- REPL ----
/// quack repl: read Lua, run it inside duckwm, print what it printed and
/// returned. A line that leaves a block open (for ... do, function f())
/// keeps reading until the block is complete. Line editing: run it under rlwrap.
fn repl() !void {
    const gpa = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var c = connect(gpa);
    defer c.deinit();

    var src: std.ArrayListUnmanaged(u8) = .empty;
    defer src.deinit(gpa);
    while (true) {
        _ = arena.reset(.retain_capacity);
        const a = arena.allocator();
        try write_all(1, if (src.items.len == 0) "lua> " else "...> ");
        const line = (try read_line(a)) orelse {
            try write_all(1, "\n");
            return;
        };
        if (src.items.len == 0 and std.mem.trim(u8, line, " \t\r").len == 0) continue;
        if (src.items.len > 0) try src.append(gpa, '\n');
        try src.appendSlice(gpa, line);

        const cmd = [_]Command{.{ .eval = .{ .source = src.items } }};
        if (c.run(a, &cmd)) |results| {
            const r: Value = if (results.len > 0) results[0] else .nil;
            if (std.mem.eql(u8, map_str(r, "status"), "incomplete")) continue;
            try write_all(1, map_str(r, "output"));
        } else |err| switch (err) {
            error.Rejected => try write_all(1, try std.fmt.allocPrint(a, "duckwm: {s}\n", .{c.why})),
            else => return err,
        }
        src.clearRetainingCapacity();
    }
}

/// One line of stdin without its newline; null at end of input.
fn read_line(a: Allocator) !?[]const u8 {
    var line: std.ArrayListUnmanaged(u8) = .empty;
    var ch: [1]u8 = undefined;
    while (true) {
        const rc = linux.read(0, &ch, 1);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return if (line.items.len > 0) line.items else null;
                if (ch[0] == '\n') return line.items;
                try line.append(a, ch[0]);
            },
            .INTR => continue,
            else => die("quack: failed to read stdin\n"),
        }
    }
}

fn map_str(v: Value, key: []const u8) []const u8 {
    if (v != .map) return "";
    for (v.map) |f| {
        if (std.mem.eql(u8, f.key, key) and f.value == .str) return f.value.str;
    }
    return "";
}

// ---- Tests ----
test "arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expect(try parse_command(a, "cleanup_left_behind", &.{}) == .cleanup_left_behind);
    try std.testing.expectEqual(@as(u32, 42), (try parse_command(a, "focus", &.{"42"})).focus.id);
    try std.testing.expectEqual(@as(i32, -5), (try parse_command(a, "pan_by", &.{ "-5", "3" })).pan_by.dx);
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

test "batch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cmds = try parse_batch(a,
        \\# theme
        \\set_default_focused_border_color #89b4fa
        \\
        \\  set_preview_font 'FiraCode Nerd Font:pixelsize=25'
        \\spawn notify-send "theme applied"
    );
    try std.testing.expectEqual(@as(usize, 3), cmds.len);
    try std.testing.expectEqual(@as(u32, 0x89b4fa), cmds[0].set_default_focused_border_color.color);
    try std.testing.expectEqualStrings("FiraCode Nerd Font:pixelsize=25", cmds[1].set_preview_font.name);
    try std.testing.expectEqualStrings("theme applied", cmds[2].spawn.argv[1]);

    try std.testing.expectError(error.InvalidArgument, parse_batch(a, "focus 1\nfocus"));
    try std.testing.expectEqualStrings("line 2: focus: missing argument <id> (usage: quack focus <id>)", parse_error);
    try std.testing.expectError(error.InvalidArgument, parse_batch(a, "spawn 'oops"));
    try std.testing.expectError(error.InvalidArgument, parse_batch(a, "# nothing\n"));
}

test "json" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var out: std.ArrayListUnmanaged(u8) = .empty;
    const fields = [_]Value.Field{
        .{ .key = "x", .value = .{ .integer = 1 } },
        .{ .key = "s", .value = .{ .str = "a\"b\n" } },
    };
    try write_json(a, &out, .{
        .multi = &.{
            .{ .map = &fields },
            .{ .number = 0.5 },
            .nil,
            .{ .boolean = false },
        },
    });
    try std.testing.expectEqualStrings("[{\"x\":1,\"s\":\"a\\\"b\\n\"},0.5,null,false]", out.items);
}
