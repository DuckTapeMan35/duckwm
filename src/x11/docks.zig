const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const Backend = @import("backend.zig").Backend;

pub const Strut = struct { left: u32 = 0, right: u32 = 0, top: u32 = 0, bottom: u32 = 0 };

const Dock = struct { strut: Strut, rect: types.Rect };

/// Is r's middle on monitor m?
pub fn on(m: types.Rect, r: types.Rect) bool {
    const cx = r.x + @as(i32, @intCast(r.width / 2));
    const cy = r.y + @as(i32, @intCast(r.height / 2));
    return cx >= m.x and cx < m.x + @as(i32, @intCast(m.width)) and
        cy >= m.y and cy < m.y + @as(i32, @intCast(m.height));
}

pub const Docks = struct {
    map: std.AutoHashMapUnmanaged(c.Window, Dock) = .empty,

    pub fn deinit(self: *Docks, gpa: std.mem.Allocator) void {
        self.map.deinit(gpa);
    }

    pub fn contains(self: *const Docks, win: c.Window) bool {
        return self.map.contains(win);
    }

    pub fn put(self: *Docks, gpa: std.mem.Allocator, win: c.Window, strut: Strut, rect: types.Rect) !void {
        try self.map.put(gpa, win, .{ .strut = strut, .rect = rect });
    }

    pub fn remove(self: *Docks, win: c.Window) bool {
        return self.map.remove(win);
    }

    pub fn set_strut(self: *Docks, win: c.Window, strut: Strut) bool {
        const d = self.map.getPtr(win) orelse return false;
        d.strut = strut;
        return true;
    }

    pub fn set_rect(self: *Docks, win: c.Window, rect: types.Rect) bool {
        const d = self.map.getPtr(win) orelse return false;
        if (std.meta.eql(d.rect, rect)) return false;
        d.rect = rect;
        return true;
    }

    pub fn insets(self: *const Docks, screen: types.Size) types.Insets {
        var top: i32 = 0;
        var bottom: i32 = 0;
        var left: i32 = 0;
        var right: i32 = 0;
        const sw: i32 = @intCast(screen.width);
        const sh: i32 = @intCast(screen.height);

        var it = self.map.valueIterator();
        while (it.next()) |d| {
            const r = d.rect;
            const s = d.strut;
            const w: i32 = @intCast(r.width);
            const h: i32 = @intCast(r.height);
            if (s.top > 0) {
                top = @max(top, r.y + h);
            } else if (s.bottom > 0) {
                bottom = @max(bottom, sh - r.y);
            } else if (s.left > 0) {
                left = @max(left, r.x + w);
            } else if (s.right > 0) {
                right = @max(right, sw - r.x);
            }
        }
        return .{
            .top = @intCast(@max(0, top)),
            .bottom = @intCast(@max(0, bottom)),
            .left = @intCast(@max(0, left)),
            .right = @intCast(@max(0, right)),
        };
    }

    /// How far the docks on monitor m reach into it from each edge.
    pub fn insets_on(self: *const Docks, m: types.Rect) types.Insets {
        var r_: types.Insets = .{};
        const mx1 = m.x + @as(i32, @intCast(m.width));
        const my1 = m.y + @as(i32, @intCast(m.height));
        var it = self.map.valueIterator();
        while (it.next()) |d| {
            if (!on(m, d.rect)) continue;
            const r = d.rect;
            const w: i32 = @intCast(r.width);
            const h: i32 = @intCast(r.height);
            const s = d.strut;
            if (s.top > 0) {
                r_.top = @max(r_.top, @as(u32, @intCast(@max(0, r.y + h - m.y))));
            } else if (s.bottom > 0) {
                r_.bottom = @max(r_.bottom, @as(u32, @intCast(@max(0, my1 - r.y))));
            } else if (s.left > 0) {
                r_.left = @max(r_.left, @as(u32, @intCast(@max(0, r.x + w - m.x))));
            } else if (s.right > 0) {
                r_.right = @max(r_.right, @as(u32, @intCast(@max(0, mx1 - r.x))));
            }
        }
        return r_;
    }
};

// ---- the X side: what the docks' windows are told ----

/// Start tracking a dock. Reads its geometry once.
pub fn add(self: *Backend, win: c.Window, strut: Strut) !void {
    var attrs: c.XWindowAttributes = undefined;
    const rect: types.Rect = if (c.XGetWindowAttributes(self.display, win, &attrs) != 0) .{
        .x = attrs.x,
        .y = attrs.y,
        .width = @intCast(attrs.width),
        .height = @intCast(attrs.height),
    } else .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    try self.docks.put(self.allocator, win, strut, rect);
}

/// Returns true if win is a dock. A null strut stops tracking it.
pub fn update_strut(self: *Backend, win: c.Window, strut: ?Strut) bool {
    if (!self.docks.contains(win)) return false;
    if (strut) |s| {
        _ = self.docks.set_strut(win, s);
    } else {
        _ = self.docks.remove(win);
    }
    return true;
}

/// Line the docks up along their monitors' edges, stacking ones that share an edge.
pub fn restack(self: *Backend) void {
    var rects: [16]types.Rect = undefined;
    var ids: [16]u32 = undefined;
    const n = self.monitor_rects(&rects, &ids);
    // Per monitor, how far its top, bottom, left and right are taken so far.
    var used = std.mem.zeroes([16][4]i32);
    var it = self.docks.map.iterator();
    while (it.next()) |e| {
        const win = e.key_ptr.*;
        const d = e.value_ptr;
        const mi = for (rects[0..n], 0..) |m, i| {
            if (on(m, d.rect)) break i;
        } else 0;
        const m = rects[mi];
        const mw: i32 = @intCast(m.width);
        const mh: i32 = @intCast(m.height);
        const w: i32 = @intCast(d.rect.width);
        const h: i32 = @intCast(d.rect.height);
        const s = d.strut;
        if (s.top > 0) {
            d.rect.x = m.x;
            d.rect.y = m.y + used[mi][0];
            used[mi][0] += h;
        } else if (s.bottom > 0) {
            used[mi][1] += h;
            d.rect.x = m.x;
            d.rect.y = m.y + mh - used[mi][1];
        } else if (s.left > 0) {
            d.rect.x = m.x + used[mi][2];
            d.rect.y = m.y;
            used[mi][2] += w;
        } else if (s.right > 0) {
            used[mi][3] += w;
            d.rect.x = m.x + mw - used[mi][3];
            d.rect.y = m.y;
        } else continue;
        _ = c.XMoveWindow(self.display, win, d.rect.x, d.rect.y);
    }
    _ = c.XFlush(self.display);
}

pub fn raise_all(self: *const Backend) void {
    var it = self.docks.map.keyIterator();
    while (it.next()) |win| _ = c.XRaiseWindow(self.display, win.*);
}

/// Put frame just under the docks (on top of everything else).
pub fn stack_below(self: *const Backend, frame: c.Window) void {
    var lowest: ?c.Window = null;
    var it = self.docks.map.keyIterator();
    while (it.next()) |win| {
        _ = c.XRaiseWindow(self.display, win.*);
        if (lowest == null) lowest = win.*;
    }
    if (lowest) |d| {
        var changes: c.XWindowChanges = std.mem.zeroes(c.XWindowChanges);
        changes.sibling = d;
        changes.stack_mode = c.Below;
        _ = c.XConfigureWindow(self.display, frame, c.CWSibling | c.CWStackMode, &changes);
    } else {
        _ = c.XRaiseWindow(self.display, frame);
    }
}
