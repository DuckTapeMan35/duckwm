const std = @import("std");
const types = @import("types");
const surface = @import("surface.zig");
const State = @import("state.zig").State;
const windows = @import("windows.zig");
const util = @import("util.zig");
const size_eql = util.size_eql;
const opt_eql = util.opt_eql;

pub const Preview = struct {
    surf: surface.ShellSurface,
    handle: types.WindowHandle,
    /// Owns the copied style and items; reset on every content change.
    arena: std.heap.ArenaAllocator,
    style: ?types.PreviewStyle = null,
    items: []types.PreviewItem = &.{},
    content_dirty: bool = true,

    in_scene: bool = false,
    want_pos: types.Point = .{ .x = 0, .y = 0 },
    want_size: types.Size = .{ .width = 0, .height = 0 },
    want_tiled: bool = true,
    want_border_width: u32 = 0,
    want_border_color: ?u32 = null,
    raise_serial: u64 = 0,

    // What was last drawn and placed.
    size: types.Size = .{ .width = 0, .height = 0 },
    border_width: u32 = 0,
    border_color: ?u32 = null,
    pos: ?types.Point = null,
};

// ---- lifetime ----
/// A new preview, under a handle from the same counter as windows.
pub fn create(s: *State) !types.WindowHandle {
    const wm = s.wm orelse return error.NoWindowManager;
    const comp = s.compositor orelse return error.NoCompositor;
    const p = try s.allocator.create(Preview);
    errdefer s.allocator.destroy(p);
    p.* = .{
        .surf = try surface.ShellSurface.create(wm, comp),
        .handle = s.next_handle,
        .arena = std.heap.ArenaAllocator.init(s.allocator),
    };
    s.next_handle += 1;
    try s.previews.put(s.allocator, p.handle, p);
    return p.handle;
}

pub fn destroy(s: *State, h: types.WindowHandle) void {
    const p = (s.previews.fetchRemove(h) orelse return).value;
    free(s, p);
}

/// Every preview, at shutdown.
pub fn destroy_all(s: *State) void {
    var it = s.previews.valueIterator();
    while (it.next()) |pp| free(s, pp.*);
    s.previews.deinit(s.allocator);
}

fn free(s: *State, p: *Preview) void {
    p.surf.destroy();
    p.arena.deinit();
    s.allocator.destroy(p);
}

// ---- content ----
/// Copies the content; the buffer itself follows the scene rect at render time.
pub fn set_content(s: *State, h: types.WindowHandle, style: types.PreviewStyle, items: []const types.PreviewItem) void {
    const p = s.previews.get(h) orelse return;
    // Core repaints every visible preview on every commit; skip identical content.
    if (p.style) |old| if (same_content(old, p.items, style, items)) return;

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
    p.content_dirty = true;
    s.mark();
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

// ---- scene ----
/// Record what core wants of it, from its entry in apply_windows. A preview is
/// its own buffer: it covers the whole rect and paints its border inside it.
pub fn apply(p: *Preview, st: types.WindowState) void {
    p.in_scene = true;
    p.want_pos = .{ .x = st.frame.x, .y = st.frame.y };
    p.want_size = .{ .width = @max(1, st.frame.width), .height = @max(1, st.frame.height) };
    p.want_tiled = st.tiled;
    p.want_border_width = st.border_width;
    p.want_border_color = if (st.borders) |b| windows.base_color(b) else null;
}

/// Repaint it if what it shows changed, and move it where core wants it.
pub fn render(s: *State, p: *Preview) void {
    const shm = s.shm orelse return;
    const style = p.style orelse return; // core hasn't drawn it yet
    const changed = p.content_dirty or !p.surf.mapped or
        !size_eql(p.size, p.want_size) or
        p.border_width != p.want_border_width or
        !opt_eql(p.border_color, p.want_border_color);
    if (changed) {
        const content: surface.PreviewContent = .{
            .style = style,
            .items = p.items,
            .border_width = p.want_border_width,
            .border_color = p.want_border_color,
            .font = s.fonts.get(s.allocator, style.font),
        };
        p.surf.draw(shm, p.want_size.width, p.want_size.height, &content, surface.paint_preview) catch return;
        p.content_dirty = false;
        p.size = p.want_size;
        p.border_width = p.want_border_width;
        p.border_color = p.want_border_color;
    }
    if (p.pos == null or p.pos.?.x != p.want_pos.x or p.pos.?.y != p.want_pos.y) {
        p.surf.node.setPosition(p.want_pos.x, p.want_pos.y);
        p.pos = p.want_pos;
    }
}
