const std = @import("std");
const graph_mod = @import("graph");
const core = @import("core.zig");
const output = @import("output.zig");
const WM = core.WM;
const Node = graph_mod.Node;
const Output = output.Output;

/// Something with a name in a path: a node, or an output.
pub const Elem = union(enum) {
    node: *Node,
    output: *Output,

    pub fn name(e: Elem) []const u8 {
        return switch (e) {
            .node => |n| n.name,
            .output => |o| o.name.slice(),
        };
    }
};

/// The most segments a path can have.
pub const max_depth = 32;

/// What e is directly in, named or not.
pub fn parent(wm: *WM, e: Elem) ?Elem {
    const n = switch (e) {
        .node => |n| n,
        .output => return null,
    };
    if (graph_mod.get_container(n)) |c| return .{ .node = c };
    const g = n.owner_graph orelse return null;
    if (g.parent_node) |p| return .{ .node = p };
    return if (output.of(wm, g)) |o| .{ .output = o } else null;
}

/// The nearest named thing e is in.
pub fn named_parent(wm: *WM, e: Elem) ?Elem {
    var cur = parent(wm, e);
    while (cur) |c| : (cur = parent(wm, c)) {
        if (c.name().len > 0) return c;
    }
    return null;
}

/// The path segments of s; error.InvalidPath for "", "a//b", "/a" or "a/".
pub fn split(s: []const u8, buf: *[max_depth][]const u8) ![]const []const u8 {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, s, '/');
    while (it.next()) |seg| {
        if (seg.len == 0) return error.InvalidPath;
        if (n == max_depth) return error.PathTooDeep;
        buf[n] = seg;
        n += 1;
    }
    return buf[0..n];
}

/// Does e's path end in segs? e itself must be named segs' last.
pub fn ends_in(wm: *WM, e: Elem, segs: []const []const u8) bool {
    if (segs.len == 0) return false;
    if (!std.mem.eql(u8, e.name(), segs[segs.len - 1])) return false;
    var cur = e;
    var i = segs.len - 1;
    while (i > 0) {
        i -= 1;
        cur = named_parent(wm, cur) orelse return false;
        if (!std.mem.eql(u8, cur.name(), segs[i])) return false;
    }
    return true;
}

/// How far up from start (0: start itself) the nearest thing whose path ends
/// in segs is; null if start isn't in one.
pub fn depth_under(wm: *WM, start: Elem, segs: []const []const u8) ?usize {
    var cur: ?Elem = start;
    var depth: usize = 0;
    while (cur) |e| : ({
        cur = parent(wm, e);
        depth += 1;
    }) {
        if (e.name().len > 0 and ends_in(wm, e, segs)) return depth;
    }
    return null;
}

/// The one node or output whose path ends in path; null for none,
/// error.Ambiguous for several.
pub fn find(wm: *WM, path: []const u8) !?Elem {
    var buf: [max_depth][]const u8 = undefined;
    const segs = try split(path, &buf);
    var found: ?Elem = null;
    for (wm.outputs.items) |o| {
        if (!ends_in(wm, .{ .output = o }, segs)) continue;
        if (found != null) return error.Ambiguous;
        found = .{ .output = o };
    }
    var it = wm.node_registry.valueIterator();
    while (it.next()) |np| {
        const n = np.*;
        if (n.dead or !ends_in(wm, .{ .node = n }, segs)) continue;
        if (found) |f| if (!std.meta.eql(f, Elem{ .node = n })) return error.Ambiguous;
        found = .{ .node = n };
    }
    return found;
}

/// e's whole path: its name (if it has one) after those of the named
/// things it's in. "" when none of them is named.
pub fn path_of(wm: *WM, e: Elem, a: std.mem.Allocator) ![]u8 {
    var names: [max_depth][]const u8 = undefined;
    var count: usize = 0;
    var cur: ?Elem = if (e.name().len > 0) e else named_parent(wm, e);
    while (cur) |c| : (cur = named_parent(wm, c)) {
        if (count == max_depth) return error.PathTooDeep;
        names[count] = c.name();
        count += 1;
    }
    std.mem.reverse([]const u8, names[0..count]);
    return std.mem.join(a, "/", names[0..count]);
}

/// Can n be called name? Not if something in the same named place already
/// is, so that its whole path stays unique.
pub fn check_name(wm: *WM, n: *Node, name: []const u8) !void {
    if (name.len == 0) return;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return error.InvalidName;
    const place = named_parent(wm, .{ .node = n });
    for (wm.outputs.items) |o| {
        if (place == null and std.mem.eql(u8, o.name.slice(), name)) return error.NameTaken;
    }
    var it = wm.node_registry.valueIterator();
    while (it.next()) |mp| {
        const m = mp.*;
        if (m == n or m.dead or !std.mem.eql(u8, m.name, name)) continue;
        const other = named_parent(wm, .{ .node = m });
        if (std.meta.eql(place, other)) return error.NameTaken;
    }
}
