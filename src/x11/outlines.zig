//! Group outlines: four thin override-redirect windows per group, one per side.
const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const Backend = @import("backend.zig").Backend;
const clamp16 = @import("util.zig").clamp16;

/// A group's outline: four thin windows, one per side.
pub const Outline = struct {
    wins: [4]c.Window,
    color: u32,
    gen: u32,
};

/// The group outlines to show (before apply_windows, which stacks them);
/// any other is destroyed.
pub fn apply(self: *Backend, list: []const types.Outline) void {
    self.outline_gen +%= 1;
    for (list) |o| {
        const e = self.outlines.getOrPut(self.allocator, o.key) catch continue;
        if (!e.found_existing) {
            var wins: [4]c.Window = undefined;
            for (&wins) |*w| w.* = create_strip(self, o.color);
            e.value_ptr.* = .{ .wins = wins, .color = o.color, .gen = 0 };
        } else if (e.value_ptr.color != o.color) {
            for (e.value_ptr.wins) |w| {
                _ = c.XSetWindowBackground(self.display, w, o.color);
                _ = c.XClearWindow(self.display, w);
            }
            e.value_ptr.color = o.color;
        }
        e.value_ptr.gen = self.outline_gen;
        for (e.value_ptr.wins, outline_strips(o)) |w, strip| {
            if (strip) |r| {
                _ = c.XMoveResizeWindow(self.display, w, clamp16(r.x), clamp16(r.y), r.width, r.height);
                _ = c.XMapWindow(self.display, w);
            } else {
                _ = c.XUnmapWindow(self.display, w);
            }
        }
    }

    // Not in this list: its group is gone or off screen.
    var gone: std.ArrayListUnmanaged(u64) = .empty;
    defer gone.deinit(self.allocator);
    var it = self.outlines.iterator();
    while (it.next()) |e| {
        if (e.value_ptr.gen != self.outline_gen) gone.append(self.allocator, e.key_ptr.*) catch {};
    }
    for (gone.items) |k| {
        free(self, self.outlines.fetchRemove(k).?.value);
    }
}

/// One side of an outline: an override-redirect window that's all background.
fn create_strip(self: *Backend, color: u32) c.Window {
    const win = c.XCreateSimpleWindow(self.display, self.root, 0, 0, 1, 1, 0, 0, color);
    var wa: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
    wa.override_redirect = 1;
    _ = c.XChangeWindowAttributes(self.display, win, c.CWOverrideRedirect, &wa);
    return win;
}

/// Lower every outline, so the tiled frames apply_windows lowers after them
/// end up below.
pub fn lower_all(self: *Backend) void {
    var it = self.outlines.valueIterator();
    while (it.next()) |o| {
        for (o.wins) |w| _ = c.XLowerWindow(self.display, w);
    }
}

/// Every outline, at shutdown.
pub fn destroy_all(self: *Backend) void {
    var it = self.outlines.valueIterator();
    while (it.next()) |o| free(self, o.*);
    self.outlines.deinit(self.allocator);
}

fn free(self: *Backend, o: Outline) void {
    for (o.wins) |w| _ = c.XDestroyWindow(self.display, w);
}

/// The four sides of an outline (top, bottom, left, right), each cut to its
/// clip; null where nothing of a side is visible.
fn outline_strips(o: types.Outline) [4]?types.Rect {
    const x = o.rect.x;
    const y = o.rect.y;
    const w: i32 = @intCast(o.rect.width);
    const h: i32 = @intCast(o.rect.height);
    const t: i32 = @intCast(@min(o.width, @min(o.rect.width, o.rect.height) / 2));
    const sides = [4][4]i32{
        .{ x, y, w, t },
        .{ x, y + h - t, w, t },
        .{ x, y + t, t, h - 2 * t },
        .{ x + w - t, y + t, t, h - 2 * t },
    };
    var out: [4]?types.Rect = undefined;
    for (sides, &out) |s, *r| {
        const x0 = @max(s[0], o.clip.x);
        const y0 = @max(s[1], o.clip.y);
        const x1 = @min(s[0] + s[2], o.clip.x + @as(i32, @intCast(o.clip.width)));
        const y1 = @min(s[1] + s[3], o.clip.y + @as(i32, @intCast(o.clip.height)));
        r.* = if (x1 > x0 and y1 > y0)
            .{ .x = x0, .y = y0, .width = @intCast(x1 - x0), .height = @intCast(y1 - y0) }
        else
            null;
    }
    return out;
}
