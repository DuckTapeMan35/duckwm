const std = @import("std");
const core = @import("core.zig");
const paths = @import("paths.zig");
const WM = core.WM;

pub const Scope = u32;
pub const everywhere: Scope = 0;

/// The scope for path, made the first time it's asked for.
pub fn intern(wm: *WM, path: []const u8) !Scope {
    var buf: [paths.max_depth][]const u8 = undefined;
    _ = try paths.split(path, &buf);
    for (wm.scope_paths.items, 1..) |p, i| {
        if (std.mem.eql(u8, p, path)) return @intCast(i);
    }
    try wm.scope_paths.ensureUnusedCapacity(wm.allocator, 1);
    wm.scope_paths.appendAssumeCapacity(try wm.allocator.dupe(u8, path));
    return @intCast(wm.scope_paths.items.len);
}

/// s's path ("" for everywhere).
pub fn path_of(wm: *const WM, s: Scope) []const u8 {
    return if (s == everywhere) "" else wm.scope_paths.items[s - 1];
}

/// The scope binds made right now go into: the Lua config's, inside wm.within.
pub fn current(wm: *const WM) Scope {
    return switch (wm.callback_source) {
        .lua => wm.lua_scope,
        else => everywhere,
    };
}

pub fn deinit(wm: *WM) void {
    for (wm.scope_paths.items) |p| wm.allocator.free(p);
    wm.scope_paths.deinit(wm.allocator);
}

/// Where focus is: the focused node, or with nothing focused, the current
/// workspace (or group), or else the output.
pub fn focus_elem(wm: *WM) paths.Elem {
    if (wm.focused) |f| return .{ .node = f };
    if (wm.current_graph.parent_node) |p| return .{ .node = p };
    return .{ .output = wm.output };
}

/// Is e in s's path (or is it the thing the path names)? Everywhere is everything.
pub fn contains(wm: *WM, s: Scope, e: paths.Elem) bool {
    if (s == everywhere) return true;
    var buf: [paths.max_depth][]const u8 = undefined;
    const segs = paths.split(path_of(wm, s), &buf) catch return false;
    return paths.depth_under(wm, e, segs) != null;
}

const Match = struct { scope: Scope, depth: usize, len: usize };

/// The scopes focus is in, the innermost first; out is cleared first.
pub fn active(wm: *WM, out: *std.ArrayListUnmanaged(Scope)) !void {
    out.clearRetainingCapacity();
    var matches: std.ArrayListUnmanaged(Match) = .empty;
    defer matches.deinit(wm.allocator);
    const start = focus_elem(wm);
    for (wm.scope_paths.items, 1..) |p, i| {
        var buf: [paths.max_depth][]const u8 = undefined;
        const segs = paths.split(p, &buf) catch continue;
        const depth = paths.depth_under(wm, start, segs) orelse continue;
        try matches.append(wm.allocator, .{ .scope = @intCast(i), .depth = depth, .len = segs.len });
    }
    // Nearest the focus first; for the same place, the longer path.
    std.mem.sort(Match, matches.items, {}, struct {
        fn lt(_: void, a: Match, b: Match) bool {
            return if (a.depth != b.depth) a.depth < b.depth else a.len > b.len;
        }
    }.lt);
    try out.ensureTotalCapacity(wm.allocator, matches.items.len);
    for (matches.items) |m| out.appendAssumeCapacity(m.scope);
}
