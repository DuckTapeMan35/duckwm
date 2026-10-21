const std = @import("std");
const duckwm = @import("duckwm");
const types = @import("types");
const output = @import("wm").output;
const build_options = @import("build_options");
const WM = duckwm.WM;
const Config = duckwm.Config;

const usage =
    \\Usage: duckwm [--commands <file>]
    \\
    \\  --commands <file>  an encoded duckwm.Request (proto/duckwm.proto),
    \\                     run after the Lua config and after every reload
    \\  --no-lua           don't load a Lua config: the commands file and
    \\                     socket clients configure everything
    \\  --check <file>     check a commands file and exit (status 0: valid)
    \\
;

fn signal_handler(sig: i32) callconv(.c) void {
    _ = sig;
    std.process.exit(1);
}

fn mainImpl(init: std.process.Init) !void {
    // Arguments live in the process arena, so commands_path stays valid for the WM's lifetime.
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var commands_path: ?[]const u8 = null;
    var no_lua = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--commands") and i + 1 < args.len) {
            i += 1;
            commands_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--no-lua")) {
            no_lua = true;
        } else if (std.mem.eql(u8, args[i], "--check") and i + 1 < args.len) {
            std.process.exit(duckwm.check_commands_file(args[i + 1]));
        } else {
            std.debug.print("{s}", .{usage});
            std.process.exit(if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) 0 else 2);
        }
    }

    // Debug builds check for leaks and misuse; release builds use a fast allocator.
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer if (build_options.allocator == .debug) {
        _ = debug_allocator.deinit();
    };
    const gpa = switch (build_options.allocator) {
        .debug => debug_allocator.allocator(),
        .smp => std.heap.smp_allocator,
        .c => std.heap.c_allocator,
    };

    var wm = try WM.create(gpa);
    defer wm.deinit();
    try output.init_all(&wm);
    wm.commands_path = commands_path;

    const handler = std.os.linux.Sigaction{
        .handler = .{ .handler = @ptrCast(&signal_handler) },
        .mask = std.mem.zeroes(std.os.linux.sigset_t),
        .flags = 0,
    };

    _ = std.os.linux.sigaction(std.os.linux.SIG.SEGV, &handler, null);
    _ = std.os.linux.sigaction(std.os.linux.SIG.ABRT, &handler, null);
    _ = std.os.linux.sigaction(std.os.linux.SIG.FPE, &handler, null);
    _ = std.os.linux.sigaction(std.os.linux.SIG.ILL, &handler, null);
    _ = std.os.linux.sigaction(std.os.linux.SIG.BUS, &handler, null);

    if (no_lua) {
        // A reload (reload_config) re-applies the commands file, the only config there is.
        wm.reload_fn = duckwm.reload_commands_only;
    } else {
        try Config.load(&wm);
    }
    try wm.run();
}

pub fn main(init: std.process.Init) void {
    mainImpl(init) catch |err| {
        std.debug.print("Fatal error: {}\n", .{err});
        std.process.exit(1);
    };
}
