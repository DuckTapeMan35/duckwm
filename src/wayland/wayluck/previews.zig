const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const paint = @import("paint");
const State = @import("state.zig").State;
const Window = @import("windows.zig").Window;

pub const Preview = struct {
    state: *State,
    surface: *wl.Surface,
    xdg_surface: *xdg.Surface,
    toplevel: *xdg.Toplevel,
    /// What core places, hides and borders, as it does windows.
    window: *Window,
    /// Owns the copied style and items; reset on every content change.
    arena: std.heap.ArenaAllocator,
    style: ?types.PreviewStyle = null,
    items: []types.PreviewItem = &.{},
    /// The size core laid the items out for: its whole frame, border
    /// included. It's drawn inside the border, smaller: they're scaled.
    laid_out: types.Size = .{ .width = 0, .height = 0 },
    /// The size wayluck configured it to (0: not yet), and the one its
    /// next configure brings.
    size: types.Size = .{ .width = 0, .height = 0 },
    pending: types.Size = .{ .width = 0, .height = 0 },
};

/// A new preview: a toplevel of duckwm's own, which wayluck makes a window
/// of (it isn't drawn until core places it, and wayluck configures it).
pub fn create(s: *State) !types.WindowHandle {
    const compositor = s.compositor orelse return error.NoCompositor;
    const wm_base = s.wm_base orelse return error.NoXdgShell;
    const manager = s.manager orelse return error.NoManager;

    const surface = try compositor.createSurface();
    errdefer surface.destroy();
    const xdg_surface = try wm_base.getXdgSurface(surface);
    errdefer xdg_surface.destroy();
    const toplevel = try xdg_surface.getToplevel();
    errdefer toplevel.destroy();
    toplevel.setTitle("duckwm preview");
    toplevel.setAppId("duckwm");
    const obj = try manager.ownWindow(surface);
    errdefer obj.destroy();

    const w = try s.allocator.create(Window);
    errdefer s.allocator.destroy(w);
    // Placed as soon as core gives it a place (announced: core made it).
    w.* = .{ .state = s, .obj = obj, .handle = s.next_preview, .announced = true };
    const p = try s.allocator.create(Preview);
    errdefer s.allocator.destroy(p);
    p.* = .{
        .state = s,
        .surface = surface,
        .xdg_surface = xdg_surface,
        .toplevel = toplevel,
        .window = w,
        .arena = std.heap.ArenaAllocator.init(s.allocator),
    };
    try s.windows.put(s.allocator, w.handle, w);
    errdefer _ = s.windows.remove(w.handle);
    try s.previews.put(s.allocator, w.handle, p);
    s.next_preview += 1;

    toplevel.setListener(*Preview, toplevel_listener, p);
    xdg_surface.setListener(*Preview, xdg_surface_listener, p);
    // The first commit, with no buffer: wayluck configures it once core
    // has placed it.
    surface.commit();
    return w.handle;
}

pub fn destroy(s: *State, h: types.WindowHandle) void {
    const p = (s.previews.fetchRemove(h) orelse return).value;
    _ = s.windows.remove(h);
    free(s, p);
}

/// Every preview, at shutdown.
pub fn destroy_all(s: *State) void {
    var it = s.previews.valueIterator();
    while (it.next()) |pp| {
        _ = s.windows.remove(pp.*.window.handle);
        free(s, pp.*);
    }
    s.previews.deinit(s.allocator);
}

fn free(s: *State, p: *Preview) void {
    p.window.obj.destroy();
    s.allocator.destroy(p.window);
    p.toplevel.destroy();
    p.xdg_surface.destroy();
    p.surface.destroy();
    p.arena.deinit();
    s.allocator.destroy(p);
}

/// What it shows from now on: copied, and painted if it has a size.
pub fn set_content(s: *State, h: types.WindowHandle, size: types.Size, style: types.PreviewStyle, items: []const types.PreviewItem) void {
    const p = s.previews.get(h) orelse return;
    // Core repaints every visible preview on every commit; skip identical content.
    const same_size = p.laid_out.width == size.width and p.laid_out.height == size.height;
    if (p.style) |old| if (same_size and same_content(old, p.items, style, items)) return;

    _ = p.arena.reset(.retain_capacity);
    const a = p.arena.allocator();
    var st = style;
    st.font = a.dupe(u8, style.font) catch return;
    const copy = a.alloc(types.PreviewItem, items.len) catch return;
    for (items, copy) |src, *dst| {
        dst.* = src;
        dst.label = a.dupe(u8, src.label) catch "";
    }
    p.style = st;
    p.items = copy;
    p.laid_out = size;
    draw(p);
}

fn same_content(a: types.PreviewStyle, a_items: []const types.PreviewItem, b: types.PreviewStyle, b_items: []const types.PreviewItem) bool {
    if (a.bg != b.bg or a.win_bg != b.win_bg or a.border != b.border or a.text != b.text) return false;
    if (!std.mem.eql(u8, a.font, b.font) or a_items.len != b_items.len) return false;
    for (a_items, b_items) |x, y| {
        if (x.rect.x != y.rect.x or x.rect.y != y.rect.y or
            x.rect.width != y.rect.width or x.rect.height != y.rect.height) return false;
        if (x.icon_size != y.icon_size or !std.mem.eql(u8, x.label, y.label)) return false;
    }
    return true;
}

/// Paint it at the size it was configured to, and commit (before core has
/// drawn it: blank).
fn draw(p: *Preview) void {
    const s = p.state;
    const shm = s.shm orelse return;
    if (p.size.width == 0 or p.size.height == 0) return;
    const items = s.allocator.dupe(types.PreviewItem, p.items) catch return;
    defer s.allocator.free(items);
    for (items) |*item| item.rect = fit(item.rect, p.laid_out, p.size);
    const content: paint.PreviewContent = .{
        .style = p.style orelse .{ .bg = 0, .win_bg = 0, .border = 0, .text = 0, .font = "" },
        .items = items,
        // wayluck draws the border, outside it.
        .border_width = 0,
        .border_color = null,
        .font = if (p.style) |st| s.fonts.get(s.allocator, st.font) else null,
    };
    const buffer = paint.buffer(shm, p.size.width, p.size.height, &content, paint.paint_preview) catch return;
    p.surface.attach(buffer, 0, 0);
    p.surface.damageBuffer(0, 0, @intCast(p.size.width), @intCast(p.size.height));
    p.surface.commit();
}

/// r, laid out in a from's size, in one of to's.
fn fit(r: types.Rect, from: types.Size, to: types.Size) types.Rect {
    if (from.width == 0 or from.height == 0) return r;
    const sx = @as(f32, @floatFromInt(to.width)) / @as(f32, @floatFromInt(from.width));
    const sy = @as(f32, @floatFromInt(to.height)) / @as(f32, @floatFromInt(from.height));
    return .{
        .x = @intFromFloat(@as(f32, @floatFromInt(r.x)) * sx),
        .y = @intFromFloat(@as(f32, @floatFromInt(r.y)) * sy),
        .width = @intFromFloat(@as(f32, @floatFromInt(r.width)) * sx),
        .height = @intFromFloat(@as(f32, @floatFromInt(r.height)) * sy),
    };
}

fn toplevel_listener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, p: *Preview) void {
    switch (event) {
        .configure => |e| p.pending = .{
            .width = @intCast(@max(e.width, 1)),
            .height = @intCast(@max(e.height, 1)),
        },
        // Closed by core, not by anyone asking.
        else => {},
    }
}

/// A configure is done: answer it with a buffer of the new size (a
/// transaction that resized it waits for that).
fn xdg_surface_listener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, p: *Preview) void {
    switch (event) {
        .configure => |e| {
            xdg_surface.ackConfigure(e.serial);
            p.size = p.pending;
            draw(p);
        },
    }
}
