const std = @import("std");
const duckwm = @import("duckwm");
const WM = duckwm.WM;
const Config = duckwm.Config;

pub fn main() void {
    mainImpl() catch |err| {
        std.debug.print("Fatal error: {}\n", .{err});
        std.process.exit(1);
    };
}

fn mainImpl() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    
    var wm = try WM.create(da.allocator());
    wm.current_graph = &wm.graph;
    defer wm.deinit();
    
    try Config.load(&wm);
    try wm.run();
}
