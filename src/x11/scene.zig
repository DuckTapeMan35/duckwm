const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const Backend = @import("backend.zig").Backend;
const util = @import("util.zig");
const clamp16 = util.clamp16;
const rect_eql = util.rect_eql;
const colors_eql = util.colors_eql;
const docks = @import("docks.zig");
const frames = @import("frames.zig");
const outlines = @import("outlines.zig");

/// What was last sent for a client, so the next apply sends only changes.
pub const Applied = struct {
    frame: types.Rect,
    configure_pending: bool,
    border_width: u32,
    borders: ?types.BorderColors,
    mapped: bool,
    gen: u32,
};

/// Requests sent in one batch, by serial.
pub const SerialRange = struct { start: c_ulong, end: c_ulong };

/// Bring the screen in line with states, sending only what changed.
pub fn apply(self: *Backend, states: []const types.WindowState, fullscreen: ?types.WindowHandle) void {
    const batch = begin_batch(self);
    self.apply_gen +%= 1;
    for (states) |s| apply_one(self, s);

    // Shown before but not in this scene: hide. Runs after the maps, so
    // switching workspaces never flashes an empty screen.
    var it = self.applied.iterator();
    while (it.next()) |e| {
        const a = e.value_ptr;
        if (a.gen == self.apply_gen or !a.mapped) continue;
        if (self.frames.frame_of(e.key_ptr.*)) |f| _ = c.XUnmapWindow(self.display, f);
        a.mapped = false;
    }

    // Stacking: docks on top, tiled frames at the bottom, fullscreen above everything.
    // Outlines first, so the tiled frames lowered after them end up below.
    docks.raise_all(self);
    outlines.lower_all(self);
    for (states) |s| {
        if (!s.tiled) continue;
        if (self.frames.frame_of(@intCast(s.handle))) |f| _ = c.XLowerWindow(self.display, f);
    }
    if (fullscreen) |h| {
        if (self.frames.frame_of(@intCast(h))) |f| _ = c.XRaiseWindow(self.display, f);
    }
    end_batch(self, batch);
    _ = c.XFlush(self.display);
}

fn apply_one(self: *Backend, s: types.WindowState) void {
    const client: c.Window = @intCast(s.handle);
    const frame = self.frames.frame_of(client) orelse return;
    const prev = self.applied.get(client);

    const geometry_changed = if (prev) |p|
        !rect_eql(p.frame, s.frame) or p.border_width != s.border_width
    else
        true;
    const colors_changed = if (prev) |p| !colors_eql(p.borders, s.borders) else true;

    const bw = s.border_width;
    const ibw: i32 = @intCast(bw);
    const cw: u32 = @max(1, s.frame.width -| 2 * bw);
    const ch: u32 = @max(1, s.frame.height -| 2 * bw);

    // X coordinates are 16-bit; panned layouts can exceed that.
    const x = clamp16(s.frame.x);
    const y = clamp16(s.frame.y);
    var configure_pending = if (prev) |p| p.configure_pending else false;
    if (geometry_changed) {
        _ = c.XMoveResizeWindow(self.display, frame, x, y, s.frame.width, s.frame.height);
        _ = c.XMoveResizeWindow(self.display, client, ibw, ibw, cw, ch);
        _ = c.XSetWindowBorderWidth(self.display, client, 0);
        configure_pending = true;
    }
    if (configure_pending and !s.interactive) {
        send_configure(self, client, x + ibw, y + ibw, cw, ch);
        configure_pending = false;
    }

    const was_mapped = if (prev) |p| p.mapped else false;
    if (!was_mapped) {
        _ = c.XMapWindow(self.display, client);
        _ = c.XMapWindow(self.display, frame);
    }

    if (s.borders) |colors| {
        if (geometry_changed or colors_changed) {
            paint(self, frame, colors, bw, .{ .width = s.frame.width, .height = s.frame.height });
        }
    }

    self.applied.put(self.allocator, client, .{
        .frame = s.frame,
        .configure_pending = configure_pending,
        .border_width = bw,
        .borders = s.borders,
        .mapped = true,
        .gen = self.apply_gen,
    }) catch {};
}

/// Hide h now, without waiting for the next apply.
pub fn hide(self: *Backend, client: c.Window) void {
    const frame = self.frames.frame_of(client) orelse return;
    if (self.applied.getPtr(client)) |a| {
        if (!a.mapped) return;
        a.mapped = false;
    }
    const batch = begin_batch(self);
    _ = c.XUnmapWindow(self.display, frame);
    end_batch(self, batch);
}

/// Bring h above other windows (but below docks).
pub fn raise(self: *Backend, client: c.Window) void {
    const f = self.frames.frame_of(client) orelse return;
    const batch = begin_batch(self);
    _ = c.XSelectInput(self.display, f, frames.event_mask & ~@as(c_long, c.EnterWindowMask | c.LeaveWindowMask));
    docks.stack_below(self, f);
    _ = c.XSelectInput(self.display, f, frames.event_mask);
    end_batch(self, batch);
}

/// Tell the client its real root-relative geometry (ICCCM 4.1.5).
fn send_configure(self: *const Backend, client: c.Window, x: i32, y: i32, w: u32, h: u32) void {
    var ce: c.XEvent = std.mem.zeroes(c.XEvent);
    ce.xconfigure.type = c.ConfigureNotify;
    ce.xconfigure.display = self.display;
    ce.xconfigure.event = client;
    ce.xconfigure.window = client;
    ce.xconfigure.x = x;
    ce.xconfigure.y = y;
    ce.xconfigure.width = @intCast(w);
    ce.xconfigure.height = @intCast(h);
    ce.xconfigure.border_width = 0;
    ce.xconfigure.above = c.None;
    ce.xconfigure.override_redirect = 0;
    _ = c.XSendEvent(self.display, client, 0, c.StructureNotifyMask, &ce);
}

/// Paint the border of window handle inside its frame.
/// size is the frame size if the caller knows it; otherwise it's queried.
pub fn draw_borders(self: *Backend, client: c.Window, colors: types.BorderColors, width: u32, size: ?types.Size) void {
    if (width == 0) return;
    const frame = self.frames.frame_of(client) orelse return;

    const sz: types.Size = if (size) |s| s else if (self.applied.get(client)) |a|
        .{ .width = a.frame.width, .height = a.frame.height }
    else
        (frame_size(self, frame) orelse return);

    paint(self, frame, colors, width, sz);
    if (self.applied.getPtr(client)) |a| a.borders = colors;
}

fn paint(self: *const Backend, frame: c.Window, colors: types.BorderColors, width: u32, sz: types.Size) void {
    if (width == 0) return;
    const gc = c.XCreateGC(self.display, frame, 0, null);
    defer _ = c.XFreeGC(self.display, gc);

    const bw: c_uint = width;
    const w: c_uint = sz.width;
    const h: c_uint = sz.height;
    const ibw: c_int = @intCast(width);
    const iw: c_int = @intCast(sz.width);
    const ih: c_int = @intCast(sz.height);

    _ = c.XSetForeground(self.display, gc, pixel(self, frame, colors.top));
    _ = c.XFillRectangle(self.display, frame, gc, 0, 0, w, bw);
    _ = c.XSetForeground(self.display, gc, pixel(self, frame, colors.bottom));
    _ = c.XFillRectangle(self.display, frame, gc, 0, ih - ibw, w, bw);
    _ = c.XSetForeground(self.display, gc, pixel(self, frame, colors.left));
    _ = c.XFillRectangle(self.display, frame, gc, 0, 0, bw, h);
    _ = c.XSetForeground(self.display, gc, pixel(self, frame, colors.right));
    _ = c.XFillRectangle(self.display, frame, gc, iw - ibw, 0, bw, h);
}

/// ARGB frames need an alpha byte; colors given without one are opaque.
fn pixel(self: *const Backend, frame: c.Window, rgb: u32) c_ulong {
    if (self.frames.is_argb(frame) and (rgb >> 24) == 0) return rgb | 0xFF000000;
    return rgb;
}

fn frame_size(self: *const Backend, frame: c.Window) ?types.Size {
    var root_ret: c.Window = undefined;
    var x: c_int = 0;
    var y: c_int = 0;
    var w: c_uint = 0;
    var h: c_uint = 0;
    var bw: c_uint = 0;
    var depth: c_uint = 0;
    if (c.XGetGeometry(self.display, frame, &root_ret, &x, &y, &w, &h, &bw, &depth) == 0) return null;
    return .{ .width = w, .height = h };
}

// ---- crossings we caused ----

/// Start of a batch of requests whose side-effect crossings should be ignored.
fn begin_batch(self: *const Backend) c_ulong {
    return c.XNextRequest(self.display);
}

/// End of the batch: remember its serial range, then send a no-op so that
/// later, genuine events carry a serial outside of it.
fn end_batch(self: *Backend, batch_start: c_ulong) void {
    const end = c.XNextRequest(self.display);
    if (end == batch_start) return; // nothing was sent
    _ = c.XNoOp(self.display);
    self.self_inflicted[self.self_inflicted_next] = .{ .start = batch_start, .end = end };
    self.self_inflicted_next = (self.self_inflicted_next + 1) % self.self_inflicted.len;
    self.self_inflicted_len = @min(self.self_inflicted_len + 1, self.self_inflicted.len);
}

/// Was the event with this serial a side effect of one of our batches?
pub fn caused_by_us(self: *const Backend, serial: c_ulong) bool {
    for (self.self_inflicted[0..self.self_inflicted_len]) |r| {
        if (serial >= r.start and serial < r.end) return true;
    }
    return false;
}
