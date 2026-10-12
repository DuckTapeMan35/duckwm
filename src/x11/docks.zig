const std = @import("std");
const c = @import("xlib");
const types = @import("types");

pub const Strut = struct { left: u32 = 0, right: u32 = 0, top: u32 = 0, bottom: u32 = 0 };

const Dock = struct { strut: Strut, rect: types.Rect };

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
};
