const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const paint = @import("paint");

pub const Font = paint.Font;
pub const Fonts = paint.Fonts;
pub const Canvas = paint.Canvas;
pub const init = paint.init;
pub const deinit = paint.deinit;
pub const text_width = paint.text_width;
pub const font_height = paint.font_height;
pub const PreviewContent = paint.PreviewContent;
pub const paint_preview = paint.paint_preview;
pub const ErrorContent = paint.ErrorContent;
pub const paint_error = paint.paint_error;
pub const PromptContent = paint.PromptContent;
pub const paint_prompt = paint.paint_prompt;

// ---- Shell surfaces ----
pub const ShellSurface = struct {
    surface: *wl.Surface,
    shell: *river.ShellSurfaceV1,
    node: *river.NodeV1,
    mapped: bool = false,
    pos: ?types.Point = null,

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

    /// Put its node at p, telling river only when that's a change.
    pub fn place(self: *ShellSurface, p: types.Point) void {
        if (self.pos) |cur| if (cur.x == p.x and cur.y == p.y) return;
        self.node.setPosition(p.x, p.y);
        self.pos = p;
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
        comptime paint_fn: fn (Canvas, @TypeOf(ctx)) void,
    ) !void {
        if (w == 0 or h == 0) return;
        const buf = try paint.buffer(shm, w, h, ctx, paint_fn);
        self.surface.attach(buf, 0, 0);
        self.surface.damageBuffer(0, 0, @intCast(w), @intCast(h));
        self.surface.commit();
        self.mapped = true;
    }
};
