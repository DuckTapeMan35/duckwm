const std = @import("std");
const c = @import("c").c;
const graph_mod = @import("graph");
const Graph = graph_mod.Graph;
const Node = graph_mod.Node;

pub const PreviewColors = struct {
    bg: u32 = 0xFF1a1a2e,
    win_bg: u32 = 0xFF16213e,
    border: u32 = 0xFF4488ff,
    text: u32 = 0xe0e0e0,
};

pub var preview_colors: PreviewColors = .{};

fn get_wm_class(display: *c.Display, win: c.Window, buf: []u8) []const u8 {
    var hint: c.XClassHint = undefined;
    if (c.XGetClassHint(display, win, &hint) == 0) return "";
    defer {
        if (hint.res_name != null) _ = c.XFree(hint.res_name);
        if (hint.res_class != null) _ = c.XFree(hint.res_class);
    }
    const class = std.mem.span(hint.res_class orelse return "");
    const len = @min(class.len, buf.len);
    @memcpy(buf[0..len], class[0..len]);
    return buf[0..len];
}

pub fn draw_preview(display: *c.Display, pw: c.Window, sub: *Graph, preview_w: u32, preview_h: u32) void {
    var src_x1: i32 = std.math.maxInt(i32);
    var src_y1: i32 = std.math.maxInt(i32);
    var src_x2: i32 = std.math.minInt(i32);
    var src_y2: i32 = std.math.minInt(i32);

    for (sub.nodes.items) |node| {
        if (node.floating) continue;
        switch (node.content) {
            .window, .workspace => {},
            .empty => continue,
        }
        src_x1 = @min(src_x1, node.x);
        src_y1 = @min(src_y1, node.y);
        src_x2 = @max(src_x2, node.x + @as(i32, @intCast(node.width)));
        src_y2 = @max(src_y2, node.y + @as(i32, @intCast(node.height)));
    }

    const gc = c.XCreateGC(display, pw, 0, null);
    defer _ = c.XFreeGC(display, gc);

    // Background
    _ = c.XSetForeground(display, gc, preview_colors.bg & 0xFFFFFF);
    _ = c.XFillRectangle(display, pw, gc, 0, 0, preview_w, preview_h);

    if (src_x1 == std.math.maxInt(i32)) return;

    const src_w = src_x2 - src_x1;
    const src_h = src_y2 - src_y1;
    if (src_w <= 0 or src_h <= 0) return;

    const pad: i32 = 6;
    const dst_w = @as(f32, @floatFromInt(preview_w)) - @as(f32, @floatFromInt(pad * 2));
    const dst_h = @as(f32, @floatFromInt(preview_h)) - @as(f32, @floatFromInt(pad * 2));
    const scale_x = dst_w / @as(f32, @floatFromInt(src_w));
    const scale_y = dst_h / @as(f32, @floatFromInt(src_h));
    const scale = @min(scale_x, scale_y);

    const screen = c.XDefaultScreen(display);
    const visual = c.XDefaultVisual(display, screen);
    const colormap = c.XDefaultColormap(display, screen);

    var xft_color: c.XftColor = undefined;
    var render_color = c.XRenderColor{
        .red   = @intCast(((preview_colors.text >> 16) & 0xFF) * 0x101),
        .green = @intCast(((preview_colors.text >> 8)  & 0xFF) * 0x101),
        .blue  = @intCast(((preview_colors.text)       & 0xFF) * 0x101),
        .alpha = 0xffff,
    };
    _ = c.XftColorAllocValue(display, visual, colormap, &render_color, &xft_color);
    defer c.XftColorFree(display, visual, colormap, &xft_color);

    const font = c.XftFontOpenName(display, screen, "sans:pixelsize=9") orelse
                 c.XftFontOpenName(display, screen, "fixed:pixelsize=9");
    defer if (font != null) c.XftFontClose(display, font);

    const draw = c.XftDrawCreate(display, pw, visual, colormap);
    defer c.XftDrawDestroy(draw);

    for (sub.nodes.items) |node| {
        if (node.floating) continue;
        switch (node.content) {
            .window, .workspace => {},
            .empty => continue,
        }

        const rx = @as(f32, @floatFromInt(node.x - src_x1)) * scale + @as(f32, @floatFromInt(pad));
        const ry = @as(f32, @floatFromInt(node.y - src_y1)) * scale + @as(f32, @floatFromInt(pad));
        const rw = @max(4, @as(u32, @intFromFloat(@as(f32, @floatFromInt(node.width))  * scale)));
        const rh = @max(4, @as(u32, @intFromFloat(@as(f32, @floatFromInt(node.height)) * scale)));
        const ix: i32 = @intFromFloat(rx);
        const iy: i32 = @intFromFloat(ry);

        // Window background
        _ = c.XSetForeground(display, gc, preview_colors.win_bg & 0xFFFFFF);
        _ = c.XFillRectangle(display, pw, gc, ix, iy, rw, rh);

        // Border
        _ = c.XSetForeground(display, gc, preview_colors.border & 0xFFFFFF);
        _ = c.XDrawRectangle(display, pw, gc, ix, iy, rw - 1, rh - 1);

        if (rw > 8 and rh > 8) {
            const cx = ix + @as(i32, @intCast(rw / 2));
            const cy = iy + @as(i32, @intCast(rh / 2));
            const icon_size = @max(8, @min(rw, rh) * 2 / 3);

            const drew_icon = switch (node.content) {
                .window => |win| draw_net_wm_icon(display, win, pw, gc, cx, cy, icon_size),
                else => false,
            };

            if (!drew_icon) {
                if (font) |f| {
                    var class_buf: [64]u8 = undefined;
                    const full_label: []const u8 = switch (node.content) {
                        .window => |win| blk: {
                            const cls = get_wm_class(display, win, &class_buf);
                            break :blk if (cls.len > 0) cls else "?";
                        },
                        .workspace => "ws",
                        else => unreachable,
                    };
                    const label = if (rw < 40) full_label[0..1] else full_label;

                    var ext: c.XGlyphInfo = undefined;
                    c.XftTextExtentsUtf8(display, f, label.ptr, @intCast(label.len), &ext);
                    const tx = cx - @as(i32, ext.width / 2);
                    const ty = cy + @divTrunc(f.*.ascent, 2);
                    c.XftDrawStringUtf8(draw, &xft_color, f, tx, ty, label.ptr, @intCast(label.len));
                }
            }
        }
    }

    _ = c.XFlush(display);
}

fn draw_net_wm_icon(display: *c.Display, win: c.Window, pw: c.Window, gc: c.GC, cx: i32, cy: i32, target_size: u32) bool {
    const net_wm_icon = c.XInternAtom(display, "_NET_WM_ICON", 0);
    const XA_CARDINAL = c.XInternAtom(display, "CARDINAL", 0);

    var actual_type: c.Atom = 0;
    var actual_format: c_int = 0;
    var nitems: c_ulong = 0;
    var bytes_after: c_ulong = 0;
    var prop: ?*c_ulong = null;

    if (c.XGetWindowProperty(display, win, net_wm_icon,
        0, 65536, 0, XA_CARDINAL,
        &actual_type, &actual_format, &nitems, &bytes_after,
        @ptrCast(&prop)) != c.Success) return false;

    defer if (prop) |p| { _ = c.XFree(@ptrCast(p)); };
    if (nitems == 0 or actual_format != 32) return false;

    const data: [*]c_ulong = @ptrCast(prop);

    // Find best icon — closest to target_size
    var best_offset: usize = 0;
    var best_diff: u32 = std.math.maxInt(u32);
    var offset: usize = 0;
    while (offset + 2 <= nitems) {
        const iw = data[offset];
        const ih = data[offset + 1];
        if (offset + 2 + iw * ih > nitems) break;
        const size: u32 = @intCast(iw);
        const diff = if (size > target_size) size - target_size else target_size - size;
        if (diff < best_diff) {
            best_diff = diff;
            best_offset = offset;
        }
        offset += 2 + iw * ih;
    }

    const iw: u32 = @intCast(data[best_offset]);
    const ih: u32 = @intCast(data[best_offset + 1]);
    if (iw == 0 or ih == 0) return false;
    const pixels = data[best_offset + 2 ..][0 .. iw * ih];

    // Scale to target_size
    const scale = @as(f32, @floatFromInt(target_size)) / @as(f32, @floatFromInt(@max(iw, ih)));
    const dw: u32 = @intFromFloat(@as(f32, @floatFromInt(iw)) * scale);
    const dh: u32 = @intFromFloat(@as(f32, @floatFromInt(ih)) * scale);
    if (dw == 0 or dh == 0) return false;

    const draw_x = cx - @as(i32, @intCast(dw / 2));
    const draw_y = cy - @as(i32, @intCast(dh / 2));

    // Draw pixel by pixel (scaled nearest-neighbor)
    var dy: u32 = 0;
    while (dy < dh) : (dy += 1) {
        const sy: u32 = @intFromFloat(@as(f32, @floatFromInt(dy)) / scale);
        var dx: u32 = 0;
        while (dx < dw) : (dx += 1) {
            const sx: u32 = @intFromFloat(@as(f32, @floatFromInt(dx)) / scale);
            const argb: u32 = @truncate(pixels[sy * iw + sx]);
            const alpha = (argb >> 24) & 0xFF;
            if (alpha < 32) continue; // skip transparent
            const rgb = argb & 0xFFFFFF;
            _ = c.XSetForeground(display, gc, rgb);
            _ = c.XDrawPoint(display, pw, gc,
                draw_x + @as(i32, @intCast(dx)),
                draw_y + @as(i32, @intCast(dy)));
        }
    }
    return true;
}
