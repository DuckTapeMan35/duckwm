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

// ---- wm.arrange (src/lua/arrange.lua) ----

test "wm.arrange: tile puts a new window after the focused one, 55/45" {
    var h = try Harness.init(std.testing.allocator,
        \\wm.arrange.set_default(wm.arrange.tile)
    );
    defer h.deinit();
    h.map(1);
    h.map(2);
    h.map(3);
    const b = h.backend();
    const W = b.screen.width;
    // Master 1 on the left, the stack 2, 3 on the right.
    try std.testing.expectEqual(@as(u32, @intFromFloat(@round(@as(f64, @floatFromInt(W)) * 0.55))), b.frame_of(1).?.width);
    try std.testing.expect(b.frame_of(2).?.y < b.frame_of(3).?.y);

    // Focus 1 and open 4: it goes second, the master's old place in the
    // order being just after it, so it heads the stack.
    h.wm.set_focus(h.wm.node_registry.get(h.wm.window_to_node_id.get(1).?).?);
    h.step();
    h.map(4);
    try std.testing.expect(b.frame_of(4).?.x > b.frame_of(1).?.x);
    try std.testing.expect(b.frame_of(4).?.y < b.frame_of(2).?.y);
}

test "wm.arrange: rows, columns and rectangles in a config's own arranger" {
    var h = try Harness.init(std.testing.allocator,
        \\local A = wm.arrange
        \\local left, rest = A.area({ work_area = { width = 1000, height = 500 } }):cut("left", 0.25)
        \\assert(left.width == 250 and rest.x == 250 and rest.width == 750)
        \\assert(#A.rect(0, 0, 100, 10):split("h", 3) == 3)
        \\A.set_default(A.arranger("columns", function(s)
        \\    return A.reply(s, A.row(table.unpack(A.windows(s))))
        \\end))
    );
    defer h.deinit();
    h.map(1);
    h.map(2);
    const b = h.backend();
    try std.testing.expectEqual(b.frame_of(1).?.y, b.frame_of(2).?.y);
    try std.testing.expect(b.frame_of(1).?.x < b.frame_of(2).?.x);
}

test "wm.arrange: a failing arranger is reported, and falls back to a grid" {
    var h = try Harness.init(std.testing.allocator,
        \\failures = 0
        \\wm.arrange.on_error = function(name, err)
        \\    assert(name == "broken" and tostring(err):find("nope"))
        \\    failures = failures + 1
        \\end
        \\wm.arrange.set_default(wm.arrange.arranger("broken", function(s) error("nope") end))
    );
    defer h.deinit();
    h.map(1);
    h.map(2);
    const b = h.backend();
    try std.testing.expect(b.frame_of(1).?.width > 0 and b.frame_of(2).?.width > 0);
    try std.testing.expect(!overlaps(b.frame_of(1).?, b.frame_of(2).?));

    // Reported through on_error (replaced above, so nothing is printed).
    const lua = h.wm.lua.?;
    _ = lua.getGlobal("failures");
    defer lua.pop(1);
    try std.testing.expect(try lua.toInteger(-1) > 0);
}

test "the default config's layouts, on wm.arrange, each lay out three windows" {
    var h = try Harness.init(std.testing.allocator, harness.default_config);
    defer h.deinit();
    const M = types.mod.super;
    h.map(1);
    h.map(2);
    h.map(3);
    const b = h.backend();
    // The default (fair), then Super+Shift+N through fair, grid, dwindle,
    // scroller2d and manual. scroller2d shows one screen-wide window at a
    // time, the others off screen: skipped.
    for (0..6) |i| {
        if (i > 0) h.key(M | types.mod.shift, "n");
        if (i == 4) continue;
        const frames = [_]types.Rect{ b.frame_of(1).?, b.frame_of(2).?, b.frame_of(3).? };
        for (frames, 0..) |f, j| {
            try std.testing.expect(f.width > 0 and f.height > 0);
            for (frames[j + 1 ..]) |g| try std.testing.expect(!overlaps(f, g));
        }
    }
    h.map(4); // manual takes a new window too
    try std.testing.expect(b.frame_of(4).?.width > 0);
}

test "the default config's group keys" {
    var h = try Harness.init(std.testing.allocator, harness.default_config);
    defer h.deinit();
    const M = types.mod.super;
    const C = types.mod.ctrl;
    h.map(1);
    h.key(M | C, "g"); // 1 in a group
    h.map(2); // opens in it
    const id1 = h.wm.window_to_node_id.get(1).?;
    const id2 = h.wm.window_to_node_id.get(2).?;
    const n1 = h.wm.node_registry.get(id1).?;
    const n2 = h.wm.node_registry.get(id2).?;
    try std.testing.expect(n1.owner_graph == n2.owner_graph);
    try std.testing.expect(n1.owner_graph != h.wm.current_graph); // not the workspace: the group

    h.key(M, "a"); // the group itself
    try std.testing.expect(h.wm.focused.?.content == .group);
    h.key(M | C, "a"); // back in
    try std.testing.expect(h.wm.focused.?.content == .window);

    h.key(M | C, "u"); // 2 out of the group
    try std.testing.expect(h.wm.node_registry.get(id2).?.owner_graph == h.wm.current_graph);

    // From 1, still in it: the group goes, 1 back in the workspace.
    h.wm.set_focus(h.wm.node_registry.get(id1).?);
    h.step();
    h.key(M | C | types.mod.shift, "g");
    for (h.wm.current_graph.nodes.items) |n| try std.testing.expect(n.content != .group);
    try std.testing.expectEqual(@as(usize, 2), h.backend().scene.items.len);
}

fn rect_of(h: *Harness, w: types.WindowHandle) types.Rect {
    const n = h.wm.node_registry.get(h.wm.window_to_node_id.get(w).?).?;
    return .{ .x = n.x, .y = n.y, .width = n.width, .height = n.height };
}

test "the default config's pinwheel: arms around the centre, turning with it" {
    var h = try Harness.init(std.testing.allocator, harness.default_config);
    defer h.deinit();
    const M = types.mod.super;
    for (1..6) |w| h.map(w);
    // fair, then Super+Shift+N six times: fair, grid, dwindle, scroller2d, manual, pinwheel.
    for (0..6) |_| h.key(M | types.mod.shift, "n");
    try std.testing.expectEqualStrings("pinwheel", h.wm.current_graph.arranger_name);

    const W: i32 = @intCast(h.backend().screen.width);
    const H: i32 = @intCast(h.backend().screen.height);
    const c = rect_of(&h, 1);
    const cr = c.x + @as(i32, @intCast(c.width));
    const cb = c.y + @as(i32, @intCast(c.height));
    const top = rect_of(&h, 2);
    const right = rect_of(&h, 3);
    const bottom = rect_of(&h, 4);
    const left = rect_of(&h, 5);
    // Each arm runs along one side of the centre and past its corner.
    try std.testing.expectEqual(types.Rect{ .x = 0, .y = 0, .width = @intCast(cr), .height = @intCast(c.y) }, top);
    try std.testing.expectEqual(types.Rect{ .x = cr, .y = 0, .width = @intCast(W - cr), .height = @intCast(cb) }, right);
    try std.testing.expectEqual(types.Rect{ .x = c.x, .y = cb, .width = @intCast(W - c.x), .height = @intCast(H - cb) }, bottom);
    try std.testing.expectEqual(types.Rect{ .x = 0, .y = c.y, .width = @intCast(c.x), .height = @intCast(H - c.y) }, left);

    // Widen the centre to the right: the top arm grows, the right arm shrinks.
    try h.wm.resize_edge(h.wm.node_registry.get(h.wm.window_to_node_id.get(1).?).?, .Right, 100);
    h.step();
    const c2 = rect_of(&h, 1);
    try std.testing.expectEqual(c.width + 100, c2.width);
    try std.testing.expectEqual(c2.x + @as(i32, @intCast(c2.width)), rect_of(&h, 3).x);
    try std.testing.expectEqual(c.x + @as(i32, @intCast(c.width)) + 100, @as(i32, @intCast(rect_of(&h, 2).width)));

    // A sixth window joins the top arm, beside the second.
    h.map(6);
    try std.testing.expectEqual(rect_of(&h, 2).y, rect_of(&h, 6).y);
    try std.testing.expect(!overlaps(rect_of(&h, 2), rect_of(&h, 6)));
}
