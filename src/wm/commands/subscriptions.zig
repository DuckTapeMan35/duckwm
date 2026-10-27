const std = @import("std");
const core = @import("../core.zig");
const command = @import("../command.zig");
const util = @import("util.zig");
const subscriptions = @import("../subscriptions.zig");
const WM = core.WM;
const Value = command.Value;
const Args = util.Args;
const Allocator = std.mem.Allocator;

pub fn subscribe(wm: *WM, args: Args(.subscribe), _: Allocator) !Value {
    const cb = try util.callback(wm, args.callback);
    return .{ .integer = try subscriptions.add(wm, args.topic, cb) };
}

pub fn unsubscribe(wm: *WM, args: Args(.unsubscribe), _: Allocator) !Value {
    try subscriptions.remove(wm, args.id);
    return .nil;
}
