const std = @import("std");
const linux = std.os.linux;
const protocol = @import("protocol");
const wire = protocol.wire;
const core = @import("core.zig");
const command = @import("command.zig");
const WM = core.WM;

/// Run the commands file, if there is one. Problems show in the error bar:
/// a broken file shouldn't stop the WM from starting.
pub fn run_commands_file(wm: *WM) void {
    const path = wm.commands_path orelse return;

    var arena = std.heap.ArenaAllocator.init(wm.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = read_file(a, path) catch |err| {
        return report(wm, a, "cannot read {s}: {s}", .{ path, @errorName(err) });
    };
    const cmds = wire.decode_request(bytes, a) catch |err| {
        return report(wm, a, "{s} is not a valid duckwm.Request: {s}", .{ path, @errorName(err) });
    };
    const results = a.alloc(protocol.Value, cmds.len) catch return;
    command.run(wm, cmds, a, results) catch |err| {
        return report(wm, a, "{s}: {s} (nothing in it was applied)", .{ path, command.error_text(err) });
    };
}

fn report(wm: *WM, a: std.mem.Allocator, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(a, "commands file: " ++ fmt, args) catch return;
    wm.show_error(msg);
}

fn read_file(a: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = try a.dupeZ(u8, path);
    const rc = linux.open(path_z, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return error.OpenFailed;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    var buf: [16 * 1024]u8 = undefined;
    while (true) {
        const n = linux.read(fd, &buf, buf.len);
        switch (linux.errno(n)) {
            .SUCCESS => {
                if (n == 0) return out.items;
                try out.appendSlice(a, buf[0..n]);
            },
            .INTR => continue,
            else => return error.ReadFailed,
        }
    }
}
