const std = @import("std");
const duckwm = @import("duckwm");
const WM = duckwm.WM;
const Config = duckwm.Config;

var global_display_ptr: usize = 0; // store as usize to avoid X11 type dependency

fn signal_handler(sig: i32) callconv(.c) void {
    _ = sig;
    std.process.exit(1);
}

fn mainImpl() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();

    var wm = try WM.create(da.allocator());
    wm.current_graph = &wm.graph;
    defer wm.deinit();

    const handler = std.os.linux.Sigaction{
        .handler = .{ .handler = @ptrCast(&signal_handler) },
        .mask = std.mem.zeroes(std.os.linux.sigset_t),
        .flags = 0,
    };

    _ = std.os.linux.sigaction(std.os.linux.SIG.SEGV, &handler, null);
    _ = std.os.linux.sigaction(std.os.linux.SIG.ABRT, &handler, null);
    _ = std.os.linux.sigaction(std.os.linux.SIG.FPE,  &handler, null);
    _ = std.os.linux.sigaction(std.os.linux.SIG.ILL,  &handler, null);
    _ = std.os.linux.sigaction(std.os.linux.SIG.BUS,  &handler, null);

    try Config.load(&wm);
    try wm.run();
}

pub fn main() void {
    mainImpl() catch |err| {
        std.debug.print("Fatal error: {}\n", .{err});
        std.process.exit(1);
    };
}
