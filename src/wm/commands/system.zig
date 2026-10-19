const std = @import("std");
const c = @import("libc");
const core = @import("../core.zig");
const command = @import("../command.zig");
const util = @import("util.zig");
const WM = core.WM;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

pub fn spawn(wm: *WM, args: Args(.spawn), _: Allocator) !Value {
    if (args.argv.len == 0) return error.EmptyArgv;
    try wm.spawn(args.argv); // queued: runs at commit, dropped on rollback
    return .nil;
}

pub fn exec_once(wm: *WM, args: Args(.exec_once), arena: Allocator) !Value {
    if (!wm.initial_load) return .nil;
    return spawn(wm, .{ .argv = args.argv }, arena);
}

pub fn reload_config(wm: *WM, _: Args(.reload_config), _: Allocator) !Value {
    wm.pending_reload = true;
    return .nil;
}

pub fn setenv(_: *WM, args: Args(.setenv), arena: Allocator) !Value {
    // setenv needs NUL-terminated strings; Lua's are, but the slices don't say so.
    const key = try arena.dupeZ(u8, args.key);
    const value = try arena.dupeZ(u8, args.value);
    if (c.setenv(key.ptr, value.ptr, 1) != 0) return error.SetenvFailed;
    return .nil;
}

pub fn quit(wm: *WM, _: void, _: Allocator) !Value {
    wm.end_session();
    std.process.exit(0);
}

pub fn eval(wm: *WM, args: Args(.eval), arena: Allocator) !Value {
    const run = wm.eval_fn orelse return error.NoLua;
    return run(wm, args.source, arena);
}
