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
pub fn monitors(self: *const Backend, buf: []types.Rect, ids: []u32) usize {
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
        if (m.primary != 0 and count > 0) {
            buf[count] = buf[0];
            ids[count] = ids[0];
            buf[0] = r;
            ids[0] = id;
        } else {
            buf[count] = r;
            ids[count] = id;
        }
        count += 1;
    }
    if (count == 0) {
        const s = self.screen_size();
        buf[0] = .{ .x = 0, .y = 0, .width = s.width, .height = s.height };
        ids[0] = 0;
        count = 1;
    }
    return count;
}

/// Every monitor for core, the primary first, with what docks leave free.
pub fn list(self: *Backend, buf: []types.OutputInfo) []types.OutputInfo {
    var rects: [16]types.Rect = undefined;
    var ids: [16]u32 = undefined;
    const n = @min(monitors(self, &rects, &ids), buf.len);
    for (buf[0..n], rects[0..n], ids[0..n]) |*o, r, id| {
        o.* = .{ .id = id, .rect = r, .usable = r.inset(self.docks.insets_on(r)) };
    }
    return buf[0..n];
}
