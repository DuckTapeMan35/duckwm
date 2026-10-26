const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const Backend = @import("backend.zig").Backend;

/// Hear about monitors changing (RRScreenChangeNotify), if XRandR is there.
pub fn watch(self: *Backend) void {
    var ev_base: c_int = 0;
    var err_base: c_int = 0;
    if (c.XRRQueryExtension(self.display, &ev_base, &err_base) != 0) {
        self.rr_event_base = ev_base;
        c.XRRSelectInput(self.display, self.root, c.RRScreenChangeNotifyMask);
    }
}

/// The monitors' rectangles, primary first; the whole screen without XRandR.
pub fn monitors(self: *const Backend, buf: []types.Rect, ids: []u32, names: ?[]types.OutputInfo.Name) usize {
    var n: c_int = 0;
    const mons = c.XRRGetMonitors(self.display, self.root, 1, &n);
    defer if (mons != null) {
        c.XRRFreeMonitors(mons);
    };
    var count: usize = 0;
    var i: usize = 0;
    while (mons != null and i < @as(usize, @intCast(@max(0, n))) and count < buf.len) : (i += 1) {
        const m = mons[i];
        const r: types.Rect = .{ .x = m.x, .y = m.y, .width = @intCast(m.width), .height = @intCast(m.height) };
        const id: u32 = @truncate(m.name);
        const name: types.OutputInfo.Name = if (names != null) atom_name(self, m.name) else .{};
        if (m.primary != 0 and count > 0) {
            buf[count] = buf[0];
            ids[count] = ids[0];
            buf[0] = r;
            ids[0] = id;
            if (names) |ns| {
                ns[count] = ns[0];
                ns[0] = name;
            }
        } else {
            buf[count] = r;
            ids[count] = id;
            if (names) |ns| ns[count] = name;
        }
        count += 1;
    }
    if (count == 0) {
        const s = self.screen_size();
        buf[0] = .{ .x = 0, .y = 0, .width = s.width, .height = s.height };
        ids[0] = 0;
        if (names) |ns| ns[0] = .{};
        count = 1;
    }
    return count;
}

/// A monitor's name: XRandR names it after its output ("DP-1") unless
/// someone set it up with xrandr --setmonitor.
fn atom_name(self: *const Backend, atom: c.Atom) types.OutputInfo.Name {
    const s = c.XGetAtomName(self.display, atom) orelse return .{};
    defer _ = c.XFree(s);
    return .init(std.mem.span(s));
}

/// Every monitor for core, the primary first, with what docks leave free.
pub fn list(self: *Backend, buf: []types.OutputInfo) []types.OutputInfo {
    var rects: [16]types.Rect = undefined;
    var ids: [16]u32 = undefined;
    var names: [16]types.OutputInfo.Name = undefined;
    const n = @min(monitors(self, &rects, &ids, &names), buf.len);
    for (buf[0..n], rects[0..n], ids[0..n], names[0..n]) |*o, r, id, name| {
        o.* = .{ .id = id, .rect = r, .usable = r.inset(self.docks.insets_on(r)), .name = name };
    }
    return buf[0..n];
}
