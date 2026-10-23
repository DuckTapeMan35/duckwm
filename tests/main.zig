const std = @import("std");
const types = @import("types");
const harness = @import("harness.zig");
const Harness = harness.Harness;

fn overlaps(a: types.Rect, b: types.Rect) bool {
    const ax1 = a.x + @as(i32, @intCast(a.width));
    const ay1 = a.y + @as(i32, @intCast(a.height));
    const bx1 = b.x + @as(i32, @intCast(b.width));
    const by1 = b.y + @as(i32, @intCast(b.height));
    return a.x < bx1 and b.x < ax1 and a.y < by1 and b.y < ay1;
}

test "three windows tile without overlapping, and focus moves left" {
    var h = try Harness.init(std.testing.allocator, harness.default_config);
    defer h.deinit();

    h.map(1);
    h.map(2);
    h.map(3);

    const b = h.backend();
    try std.testing.expectEqual(@as(usize, 3), b.scene.items.len);
    const frames = [_]types.Rect{ b.frame_of(1).?, b.frame_of(2).?, b.frame_of(3).? };
    for (frames, 0..) |f, i| {
        try std.testing.expect(f.width > 0 and f.height > 0);
        for (frames[i + 1 ..]) |g| try std.testing.expect(!overlaps(f, g));
    }

    // The newest window has focus; focus_left lands on another one.
    try std.testing.expectEqual(@as(?types.WindowHandle, 3), h.focused());
    try h.wm.focus_left();
    h.step();
    try std.testing.expect(h.focused() != null and h.focused().? != 3);
    try std.testing.expectEqual(h.focused(), b.focused);
}

test "killing a nested workspace removes its node" {
    var h = try Harness.init(std.testing.allocator, harness.default_config);
    defer h.deinit();
    const M = types.mod.super;

    h.map(1);
    h.key(M, "w"); // new nested workspace, beside window 1
    h.key(M, "e"); // enter it
    h.map(2);
    h.key(M, "Escape"); // back up
    try h.wm.focus_right(); // onto the workspace's preview
    h.step();
    try std.testing.expect(h.wm.focused.?.content == .workspace);

    h.key(M | types.mod.shift, "q");

    // Only window 1 is left, and it has the whole screen again.
    for (h.wm.current_graph.nodes.items) |n| try std.testing.expect(n.content != .workspace);
    try std.testing.expectEqual(@as(usize, 1), h.backend().scene.items.len);
    const f = h.backend().frame_of(1).?;
    try std.testing.expectEqual(h.backend().screen.width, f.width);
    try std.testing.expectEqual(@as(?types.WindowHandle, 1), h.focused());
}
