const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        _ = std.os.linux.write(2, "Usage: quack <command> [args...]\n", 33);
        std.process.exit(1);
    }

    var cmd: std.ArrayListUnmanaged(u8) = .empty;
    for (args[1..], 0..) |arg, i| {
        if (i > 0) try cmd.append(allocator, ' ');
        try cmd.appendSlice(allocator, arg);
    }
    try cmd.append(allocator, '\n');

    const sock_path = try get_sock_path(allocator);

    const fd: i32 = blk: {
        const rc: isize = @bitCast(std.os.linux.socket(
            std.os.linux.AF.UNIX,
            std.os.linux.SOCK.STREAM,
            0,
        ));
        if (rc < 0) {
            _ = std.os.linux.write(2, "quack: failed to create socket\n", 31);
            std.process.exit(1);
        }
        break :blk @intCast(rc);
    };
    defer _ = std.os.linux.close(fd);

    var addr = std.mem.zeroes(std.os.linux.sockaddr.un);
    addr.family = std.os.linux.AF.UNIX;
    if (sock_path.len >= addr.path.len) {
        _ = std.os.linux.write(2, "quack: socket path too long\n", 28);
        std.process.exit(1);
    }
    @memcpy(addr.path[0..sock_path.len], sock_path);

    const connect_rc: isize = @bitCast(std.os.linux.connect(
        fd,
        @ptrCast(&addr),
        @sizeOf(std.os.linux.sockaddr.un),
    ));
    if (connect_rc < 0) {
        _ = std.os.linux.write(2, "quack: could not connect to duckwm (is it running?)\n", 52);
        std.process.exit(1);
    }

    _ = std.os.linux.write(fd, cmd.items.ptr, cmd.items.len);

    var buf: [65536]u8 = undefined;
    const n: isize = @bitCast(std.os.linux.read(fd, &buf, buf.len));
    if (n > 0) {
        _ = std.os.linux.write(1, &buf, @intCast(n));
    }
}

fn get_sock_path(allocator: std.mem.Allocator) ![]u8 {
    if (std.c.getenv("XDG_RUNTIME_DIR")) |dir| {
        return std.fmt.allocPrint(allocator, "{s}/duckwm.sock", .{std.mem.span(dir)});
    }
    return std.fmt.allocPrint(allocator, "/tmp/duckwm-{d}.sock", .{std.os.linux.getuid()});
}
