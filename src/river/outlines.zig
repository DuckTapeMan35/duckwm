const std = @import("std");
const types = @import("types");
const surface = @import("surface.zig");
const State = @import("backend.zig").State;

/// A group's outline: one surface covering the visible part of its frame,
/// transparent in the middle and taking no input.
pub const Outline = struct {
    surf: surface.ShellSurface,
    in_scene: bool = false,
    want: types.Outline,
    /// What its buffer was last painted for (null: never).
    drawn: ?Paint = null,
    pos: ?types.Point = null,
};

/// What an outline's buffer depends on: everything but where it is.
const Paint = struct {
    /// The buffer: the visible part of the frame.
    w: u32,
    h: u32,
    /// The whole frame, relative to the buffer (it may stick out of it).
    x: i32,
    y: i32,
    fw: i32,
    fh: i32,
    t: i32,
    color: u32,
};

/// The group outlines to show; any other goes at the next render.
pub fn apply(s: *State, list: []const types.Outline) void {
    var it = s.outlines.valueIterator();
    while (it.next()) |op| op.*.in_scene = false;
    for (list) |o| {
        const os = s.outlines.get(o.key) orelse blk: {
            const new = s.allocator.create(Outline) catch continue;
            const surf = create_surface(s) catch {
                s.allocator.destroy(new);
                continue;
            };
            new.* = .{ .surf = surf, .want = o };
            s.outlines.put(s.allocator, o.key, new) catch {
                free(s, new);
                continue;
            };
            break :blk new;
        };
        os.want = o;
        os.in_scene = true;
    }
    s.mark();
}

/// A surface for an outline: it mustn't take clicks meant for what's under it.
fn create_surface(s: *State) !surface.ShellSurface {
    const wm = s.wm orelse return error.NoWindowManager;
    const comp = s.compositor orelse return error.NoCompositor;
    var surf = try surface.ShellSurface.create(wm, comp);
    errdefer surf.destroy();
    // An empty input region (applied with its first buffer).
    const region = try comp.createRegion();
    defer region.destroy();
    surf.surface.setInputRegion(region);
    return surf;
}

/// Every outline, at shutdown.
pub fn destroy_all(s: *State) void {
    var it = s.outlines.valueIterator();
    while (it.next()) |op| free(s, op.*);
    s.outlines.deinit(s.allocator);
}

fn free(s: *State, os: *Outline) void {
    os.surf.destroy();
    s.allocator.destroy(os);
}

/// Drop the outlines that left the scene; paint, place and raise the rest.
pub fn render(s: *State) void {
    var gone: std.ArrayListUnmanaged(u64) = .empty;
    defer gone.deinit(s.allocator);
    var it = s.outlines.iterator();
    while (it.next()) |e| {
        if (!e.value_ptr.*.in_scene) gone.append(s.allocator, e.key_ptr.*) catch {};
    }
    for (gone.items) |k| {
        free(s, s.outlines.fetchRemove(k).?.value);
    }

    const shm = s.shm orelse return;
    var vit = s.outlines.valueIterator();
    while (vit.next()) |op| {
        const os = op.*;
        const o = os.want;
        const want: Paint = .{
            .w = o.clip.width,
            .h = o.clip.height,
            .x = o.rect.x - o.clip.x,
            .y = o.rect.y - o.clip.y,
            .fw = @intCast(o.rect.width),
            .fh = @intCast(o.rect.height),
            .t = @intCast(o.width),
            .color = o.color,
        };
        if (!os.surf.mapped or os.drawn == null or !std.meta.eql(os.drawn.?, want)) {
            os.surf.draw(shm, want.w, want.h, &want, paint) catch continue;
            os.drawn = want;
        }
        const pos: types.Point = .{ .x = o.clip.x, .y = o.clip.y };
        if (os.pos == null or os.pos.?.x != pos.x or os.pos.?.y != pos.y) {
            os.surf.node.setPosition(pos.x, pos.y);
            os.pos = pos;
        }
        os.surf.node.placeTop();
    }
}

/// The frame's outline; the rest stays as the new buffer starts: transparent.
fn paint(cv: surface.Canvas, p: *const Paint) void {
    cv.outline(p.x, p.y, p.fw, p.fh, p.t, p.color);
}
