const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const c = @import("rc");

pub const Font = c.struct_fcft_font;

pub fn init() void {
    _ = c.fcft_init(c.FCFT_LOG_COLORIZE_NEVER, false, c.FCFT_LOG_CLASS_ERROR);
}

pub fn deinit() void {
    c.fcft_fini();
}

/// Fonts by fontconfig pattern ("monospace:size=10", the same syntax Xft used).
pub const Fonts = struct {
    map: std.StringHashMapUnmanaged(*Font) = .empty,

    pub fn get(self: *Fonts, allocator: std.mem.Allocator, pattern: []const u8) ?*Font {
        const name = if (pattern.len > 0) pattern else "monospace:size=10";
        if (self.map.get(name)) |f| return f;

        const key = allocator.dupeZ(u8, name) catch return null;
        var names = [_][*c]const u8{key.ptr};
        const font = c.fcft_from_name(1, &names, null) orelse {
            allocator.free(key);
            return null;
        };
        self.map.put(allocator, key, font) catch {
            c.fcft_destroy(font);
            allocator.free(key);
            return null;
        };
        return font;
    }

    pub fn deinit(self: *Fonts, allocator: std.mem.Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |e| {
            c.fcft_destroy(e.value_ptr.*);
            allocator.free(e.key_ptr.*);
        }
        self.map.deinit(allocator);
    }
};

// ---------------------------------------------------------------------------
// Drawing
fn pixman_color(rgb: u32) c.pixman_color_t {
    return .{
        .red = @intCast(((rgb >> 16) & 0xff) * 257),
        .green = @intCast(((rgb >> 8) & 0xff) * 257),
        .blue = @intCast((rgb & 0xff) * 257),
        .alpha = 0xffff,
    };
}

pub const Canvas = struct {
    image: *c.pixman_image_t,
    width: i32,
    height: i32,

    pub fn fill(self: Canvas, x: i32, y: i32, w: i32, h: i32, rgb: u32) void {
        if (w <= 0 or h <= 0) return;
        var col = pixman_color(rgb);
        var r = c.pixman_rectangle16_t{
            .x = @intCast(std.math.clamp(x, std.math.minInt(i16), std.math.maxInt(i16))),
            .y = @intCast(std.math.clamp(y, std.math.minInt(i16), std.math.maxInt(i16))),
            .width = @intCast(@min(w, std.math.maxInt(u16))),
            .height = @intCast(@min(h, std.math.maxInt(u16))),
        };
        _ = c.pixman_image_fill_rectangles(c.PIXMAN_OP_SRC, self.image, &col, 1, &r);
    }

    /// A t-pixel outline just inside the given rectangle.
    pub fn outline(self: Canvas, x: i32, y: i32, w: i32, h: i32, t: i32, rgb: u32) void {
        if (t <= 0) return;
        self.fill(x, y, w, t, rgb);
        self.fill(x, y + h - t, w, t, rgb);
        self.fill(x, y + t, t, h - 2 * t, rgb);
        self.fill(x + w - t, y + t, t, h - 2 * t, rgb);
    }

    /// Draw s with its baseline at baseline, stopping before max_x.
    pub fn text(self: Canvas, font: *Font, x: i32, baseline: i32, s: []const u8, rgb: u32, max_x: i32) void {
        var col = pixman_color(rgb);
        const solid = c.pixman_image_create_solid_fill(&col) orelse return;
        defer _ = c.pixman_image_unref(solid);

        var pen = x;
        const view = std.unicode.Utf8View.init(s) catch return;
        var it = view.iterator();
        while (it.nextCodepoint()) |cp| {
            const g = c.fcft_rasterize_char_utf32(font, cp, c.FCFT_SUBPIXEL_NONE) orelse continue;
            if (pen + g.*.advance.x > max_x) break;
            const dx = pen + g.*.x;
            const dy = baseline - g.*.y;
            if (c.pixman_image_get_format(g.*.pix) == c.PIXMAN_a8r8g8b8) {
                // Color glyph (emoji): composite as is.
                c.pixman_image_composite32(c.PIXMAN_OP_OVER, g.*.pix, null, self.image, 0, 0, 0, 0, dx, dy, g.*.width, g.*.height);
            } else {
                // Coverage mask: paint the text color through it.
                c.pixman_image_composite32(c.PIXMAN_OP_OVER, solid, g.*.pix, self.image, 0, 0, 0, 0, dx, dy, g.*.width, g.*.height);
            }
            pen += g.*.advance.x;
        }
    }
};

pub fn text_width(font: *Font, s: []const u8) i32 {
    var w: i32 = 0;
    const view = std.unicode.Utf8View.init(s) catch return 0;
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        const g = c.fcft_rasterize_char_utf32(font, cp, c.FCFT_SUBPIXEL_NONE) orelse continue;
        w += g.*.advance.x;
    }
    return w;
}

pub fn font_height(font: *Font) i32 {
    return font.height;
}

// ---------------------------------------------------------------------------
// Content

pub const PreviewContent = struct {
    style: types.PreviewStyle,
    items: []const types.PreviewItem,
    border_width: u32,
    border_color: ?u32,
    font: ?*Font,
};

/// Port of the X renderer, minus icons: Wayland gives the WM no window icons,
/// so every item shows its label.
pub fn paint_preview(cv: Canvas, p: *const PreviewContent) void {
    cv.fill(0, 0, cv.width, cv.height, p.style.bg);
    const bw: i32 = @intCast(p.border_width);
    if (p.border_color) |bc| cv.outline(0, 0, cv.width, cv.height, bw, bc);

    for (p.items) |item| {
        const x = bw + item.rect.x;
        const y = bw + item.rect.y;
        const w: i32 = @intCast(item.rect.width);
        const h: i32 = @intCast(item.rect.height);
        cv.fill(x, y, w, h, p.style.win_bg);
        cv.outline(x, y, w, h, 1, p.style.border);

        const font = p.font orelse continue;
        if (item.label.len == 0 or h < font.height) continue;
        const tw = text_width(font, item.label);
        const tx = x + @max(2, @divTrunc(w - tw, 2));
        const baseline = y + @divTrunc(h + font.ascent - font.descent, 2);
        cv.text(font, tx, baseline, item.label, p.style.text, x + w - 2);
    }
}

pub const ErrorContent = struct {
    msg: []const u8,
    font: ?*Font,
    bg: u32,
    fg: u32,
    pad: i32,
};

pub fn paint_error(cv: Canvas, e: *const ErrorContent) void {
    cv.fill(0, 0, cv.width, cv.height, e.bg);
    const font = e.font orelse return;
    cv.text(font, e.pad, e.pad + font.ascent, e.msg, e.fg, cv.width - e.pad);
}

pub const PromptContent = struct {
    /// The label then the text.
    text: []const u8,
    label_len: usize,
    /// Byte offset into the text; null for a message.
    cursor: ?usize,
    /// A block over a character (vi normal mode) rather than a bar between two.
    block: bool,
    font: ?*Font,
    bg: u32,
    fg: u32,
    pad: i32,
};

pub fn paint_prompt(cv: Canvas, p: *const PromptContent) void {
    cv.fill(0, 0, cv.width, cv.height, p.bg);
    const font = p.font orelse return;
    const baseline = p.pad + font.ascent;
    cv.text(font, p.pad, baseline, p.text, p.fg, cv.width - p.pad);
    const cur = p.cursor orelse return;
    const at = p.label_len + cur;
    const x = p.pad + text_width(font, p.text[0..at]);
    if (p.block) {
        // A block over the character, which is drawn again in the background color.
        const end = if (at < p.text.len) @min(p.text.len, at + (std.unicode.utf8ByteSequenceLength(p.text[at]) catch 1)) else at;
        const ch: []const u8 = if (end > at) p.text[at..end] else " ";
        cv.fill(x, p.pad, @max(1, text_width(font, ch)), font.height, p.fg);
        cv.text(font, x, baseline, ch, p.bg, cv.width);
    } else {
        cv.fill(x, p.pad, 2, font.height, p.fg);
    }
}

// ---------------------------------------------------------------------------
// Shell surfaces
pub const ShellSurface = struct {
    surface: *wl.Surface,
    shell: *river.ShellSurfaceV1,
    node: *river.NodeV1,
    mapped: bool = false,

    pub fn create(wm: *river.WindowManagerV1, compositor: *wl.Compositor) !ShellSurface {
        const surface = try compositor.createSurface();
        errdefer surface.destroy();
        const shell = try wm.getShellSurface(surface);
        errdefer shell.destroy();
        const node = try shell.getNode();
        return .{ .surface = surface, .shell = shell, .node = node };
    }

    pub fn destroy(self: *ShellSurface) void {
        self.node.destroy();
        self.shell.destroy();
        self.surface.destroy();
    }

    pub fn unmap(self: *ShellSurface) void {
        if (!self.mapped) return;
        self.surface.attach(null, 0, 0);
        self.surface.commit();
        self.mapped = false;
    }

    /// Paint a fresh w×h buffer with paint(canvas, ctx) and commit it.
    /// Each draw gets its own buffer, destroyed when river releases it.
    pub fn draw(
        self: *ShellSurface,
        shm: *wl.Shm,
        w: u32,
        h: u32,
        ctx: anytype,
        comptime paint: fn (Canvas, @TypeOf(ctx)) void,
    ) !void {
        if (w == 0 or h == 0) return;
        const stride = w * 4;
        const len: usize = @as(usize, stride) * h;

        const fd = c.memfd_create("duckwm-surface", c.MFD_CLOEXEC);
        if (fd < 0) return error.ShmFailed;
        defer _ = c.close(fd);
        if (c.ftruncate(fd, @intCast(len)) != 0) return error.ShmFailed;

        const mem = c.mmap(null, len, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
        if (mem == null or @intFromPtr(mem) == std.math.maxInt(usize)) return error.ShmFailed;
        defer _ = c.munmap(mem, len);

        const image = c.pixman_image_create_bits_no_clear(
            c.PIXMAN_a8r8g8b8,
            @intCast(w),
            @intCast(h),
            @ptrCast(@alignCast(mem)),
            @intCast(stride),
        ) orelse return error.PixmanFailed;
        defer _ = c.pixman_image_unref(image);
        paint(.{ .image = image, .width = @intCast(w), .height = @intCast(h) }, ctx);

        // The pool and fd can go right away: the buffer keeps the memory alive
        // on river's side.
        const pool = try shm.createPool(fd, @intCast(len));
        defer pool.destroy();
        const buffer = try pool.createBuffer(0, @intCast(w), @intCast(h), @intCast(stride), .argb8888);
        buffer.setListener(?*anyopaque, buffer_listener, null);

        self.surface.attach(buffer, 0, 0);
        self.surface.damageBuffer(0, 0, @intCast(w), @intCast(h));
        self.surface.commit();
        self.mapped = true;
    }
};

fn buffer_listener(buffer: *wl.Buffer, event: wl.Buffer.Event, _: ?*anyopaque) void {
    switch (event) {
        .release => buffer.destroy(),
    }
}
