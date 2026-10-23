const std = @import("std");
const builtin = @import("builtin");
const c = @import("xlib");
const types = @import("types");
const info = @import("info.zig");
const util = @import("util.zig");

const Atoms = @import("atoms.zig").Atoms;

const Icon = struct {
    size: u32,
    w: u32,
    h: u32,
    pixels: []u32, // ARGB, w * h; empty when the window has no icon
};

pub const Renderer = struct {
    fonts: std.StringHashMapUnmanaged(?*c.XftFont) = .empty,
    icons: std.AutoHashMapUnmanaged(c.Window, Icon) = .empty,

    pub fn deinit(self: *Renderer, gpa: std.mem.Allocator, display: *c.Display) void {
        var fit = self.fonts.iterator();
        while (fit.next()) |e| {
            if (e.value_ptr.*) |f| c.XftFontClose(display, f);
            gpa.free(e.key_ptr.*);
        }
        self.fonts.deinit(gpa);
        var iit = self.icons.valueIterator();
        while (iit.next()) |ic| gpa.free(ic.pixels);
        self.icons.deinit(gpa);
    }

    /// Drop the cached icon for win (its _NET_WM_ICON changed, or it's gone).
    pub fn forget_icon(self: *Renderer, gpa: std.mem.Allocator, win: c.Window) void {
        if (self.icons.fetchRemove(win)) |kv| gpa.free(kv.value.pixels);
    }

    pub fn draw(
        self: *Renderer,
        gpa: std.mem.Allocator,
        display: *c.Display,
        atoms: *const Atoms,
        pw: c.Window,
        size: types.Size,
        style: types.PreviewStyle,
        items: []const types.PreviewItem,
    ) void {
        const screen = c.XDefaultScreen(display);
        const visual = c.XDefaultVisual(display, screen);
        const colormap = c.XDefaultColormap(display, screen);
        const depth: c_uint = @intCast(c.XDefaultDepth(display, screen));

        const gc = c.XCreateGC(display, pw, 0, null);
        defer _ = c.XFreeGC(display, gc);

        _ = c.XSetForeground(display, gc, style.bg & 0xFFFFFF);
        _ = c.XFillRectangle(display, pw, gc, 0, 0, size.width, size.height);
        defer _ = c.XFlush(display);
        if (items.len == 0) return;

        const font = self.font_for(gpa, display, screen, style.font);

        var text_color = util.alloc_color(display, style.text);
        defer if (text_color) |*col| util.free_color(display, col);

        const xft_draw = c.XftDrawCreate(display, pw, visual, colormap);
        defer if (xft_draw != null) c.XftDrawDestroy(xft_draw);

        for (items) |it| {
            const r = it.rect;
            _ = c.XSetForeground(display, gc, style.win_bg & 0xFFFFFF);
            _ = c.XFillRectangle(display, pw, gc, r.x, r.y, r.width, r.height);
            _ = c.XSetForeground(display, gc, style.border & 0xFFFFFF);
            _ = c.XDrawRectangle(display, pw, gc, r.x, r.y, r.width - 1, r.height - 1);

            if (it.icon_size == 0) continue;
            const cx = r.x + @as(i32, @intCast(r.width / 2));
            const cy = r.y + @as(i32, @intCast(r.height / 2));

            if (it.window) |w| {
                if (self.draw_icon(gpa, display, atoms, visual, depth, gc, pw, @intCast(w), cx, cy, it.icon_size, style.win_bg)) continue;
            }

            if (it.label.len == 0 or text_color == null or xft_draw == null) continue;
            const f = font orelse continue;
            var ext: c.XGlyphInfo = undefined;
            c.XftTextExtentsUtf8(display, f, it.label.ptr, @intCast(it.label.len), &ext);
            const tx = cx - @divTrunc(@as(i32, ext.width), 2);
            const ty = cy + @divTrunc(f.*.ascent, 2);
            c.XftDrawStringUtf8(xft_draw, &text_color.?, f, tx, ty, it.label.ptr, @intCast(it.label.len));
        }
    }

    fn font_for(self: *Renderer, gpa: std.mem.Allocator, display: *c.Display, screen: c_int, name: []const u8) ?*c.XftFont {
        if (self.fonts.get(name)) |f| return f;

        var buf: [257]u8 = undefined;
        const z = std.fmt.bufPrintZ(&buf, "{s}", .{name}) catch return null;
        const f = c.XftFontOpenName(display, screen, z.ptr) orelse
            c.XftFontOpenName(display, screen, "fixed:pixelsize=9");

        // Cache failures too, so a bad font name isn't retried on every repaint.
        const key = gpa.dupe(u8, name) catch return f;
        self.fonts.put(gpa, key, f) catch {
            gpa.free(key);
        };
        return f;
    }

    fn draw_icon(
        self: *Renderer,
        gpa: std.mem.Allocator,
        display: *c.Display,
        atoms: *const Atoms,
        visual: [*c]c.Visual,
        depth: c_uint,
        gc: c.GC,
        pw: c.Window,
        win: c.Window,
        cx: i32,
        cy: i32,
        size: u32,
        bg: u32,
    ) bool {
        const icon = self.icon_for(gpa, display, atoms, win, size) orelse return false;

        // Blend against the window background once, then send it in one request.
        const buf = gpa.alloc(u32, icon.pixels.len) catch return false;
        defer gpa.free(buf);
        const br = (bg >> 16) & 0xFF;
        const bgc = (bg >> 8) & 0xFF;
        const bb = bg & 0xFF;
        for (icon.pixels, 0..) |argb, i| {
            const a = argb >> 24;
            const r = (((argb >> 16) & 0xFF) * a + br * (255 - a)) / 255;
            const g = (((argb >> 8) & 0xFF) * a + bgc * (255 - a)) / 255;
            const b = ((argb & 0xFF) * a + bb * (255 - a)) / 255;
            buf[i] = (r << 16) | (g << 8) | b;
        }

        const img = c.XCreateImage(display, visual, depth, c.ZPixmap, 0, @ptrCast(buf.ptr), icon.w, icon.h, 32, 0);
        if (img == null) return false;
        defer _ = c.XFree(img); // frees only the struct; `buf` is ours
        img.*.byte_order = if (builtin.cpu.arch.endian() == .little) c.LSBFirst else c.MSBFirst;

        _ = c.XPutImage(display, pw, gc, img, 0, 0, cx - @as(i32, @intCast(icon.w / 2)), cy - @as(i32, @intCast(icon.h / 2)), icon.w, icon.h);
        return true;
    }

    fn icon_for(self: *Renderer, gpa: std.mem.Allocator, display: *c.Display, atoms: *const Atoms, win: c.Window, size: u32) ?*const Icon {
        if (self.icons.getPtr(win)) |ic| {
            if (ic.w == 0) return null; // known to have no icon
            if (ic.size == size) return ic;
            gpa.free(ic.pixels);
            _ = self.icons.remove(win);
        }
        const ic = load_icon(gpa, display, atoms, win, size) orelse
            Icon{ .size = size, .w = 0, .h = 0, .pixels = &.{} };
        self.icons.put(gpa, win, ic) catch {
            gpa.free(ic.pixels);
            return null;
        };
        return if (ic.w == 0) null else self.icons.getPtr(win);
    }
};

/// Pick the _NET_WM_ICON entry closest to target and scale it to fit (nearest neighbor).
fn load_icon(gpa: std.mem.Allocator, display: *c.Display, atoms: *const Atoms, win: c.Window, target: u32) ?Icon {
    const prop = info.get_prop(display, win, atoms._NET_WM_ICON, atoms.CARDINAL, 65536) orelse return null;
    defer prop.deinit();
    if (prop.len < 2 or prop.format != 32) return null;
    const data = prop.longs();
    const nitems = data.len;
    var best: usize = 0;
    var best_diff: u64 = std.math.maxInt(u64);
    var off: usize = 0;
    while (off + 2 <= nitems) {
        const w = data[off];
        const h = data[off + 1];
        if (w == 0 or h == 0 or off + 2 + w * h > nitems) break;
        const s: u64 = @intCast(w);
        const diff = if (s > target) s - target else target - s;
        if (diff < best_diff) {
            best_diff = diff;
            best = off;
        }
        off += 2 + w * h;
    }
    if (best_diff == std.math.maxInt(u64)) return null;

    const iw: u32 = @intCast(data[best]);
    const ih: u32 = @intCast(data[best + 1]);
    const src = data[best + 2 ..][0 .. iw * ih];

    const scale = @as(f32, @floatFromInt(target)) / @as(f32, @floatFromInt(@max(iw, ih)));
    const dw: u32 = @intFromFloat(@as(f32, @floatFromInt(iw)) * scale);
    const dh: u32 = @intFromFloat(@as(f32, @floatFromInt(ih)) * scale);
    if (dw == 0 or dh == 0) return null;

    const px = gpa.alloc(u32, dw * dh) catch return null;
    for (0..dh) |dy| {
        const sy = @min(ih - 1, @as(u32, @intFromFloat(@as(f32, @floatFromInt(dy)) / scale)));
        for (0..dw) |dx| {
            const sx = @min(iw - 1, @as(u32, @intFromFloat(@as(f32, @floatFromInt(dx)) / scale)));
            px[dy * dw + dx] = @truncate(src[sy * iw + sx]);
        }
    }
    return .{ .size = target, .w = dw, .h = dh, .pixels = px };
}
