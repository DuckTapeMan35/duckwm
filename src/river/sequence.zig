const std = @import("std");
const surface = @import("surface.zig");
const util = @import("util.zig");
const output = @import("outputs.zig");
const windows = @import("windows.zig");
const bars = @import("bars.zig");
const previews = @import("previews.zig");
const outlines = @import("outlines.zig");
const input = @import("input.zig");
const types = @import("types");
const wayland = @import("wayland");
const river = wayland.client.river;
const State = @import("state.zig").State;
const Window = windows.Window;

const cap_fullscreen: u32 = 4;

/// A node to raise, in raise order: floating windows and their indicators.
pub const Stacked = struct { node: *river.NodeV1, serial: u64 };

/// river opened a manage sequence: announce new windows to core first.
pub fn start_manage(s: *State) void {
    // Properties of new windows arrive before manage_start, so this is
    // the first point where a map_request carries complete information.
    if (s.pending_enter) |h| {
        const moved = s.pointer_pos.x != s.pos_at_last_manage.x or s.pointer_pos.y != s.pos_at_last_manage.y;
        if (moved) s.push(.{ .pointer_enter = h });
    }
    s.pending_enter = null;
    s.pos_at_last_manage = s.pointer_pos;
    for (s.fresh.items) |w| {
        if (w.closed) continue;
        w.announced = true;
        s.push(.{ .map_request = .{
            .window = w.handle,
            .size = windows.initial_size(w),
            .traits = windows.traits_of(w),
        } });
    }
    s.fresh.clearRetainingCapacity();
    s.in_manage = true;
    s.dirty_sent = false;
}

/// The window-management half: everything that must happen inside a manage sequence.
pub fn send_manage(s: *State) void {
    s.settle = false;
    if (s.primary) |p| {
        if (p.default_pending) {
            if (p.layer) |l| l.setDefault();
            p.default_pending = false;
        }
    }

    input.manage_bindings(s);

    for (s.closes.items) |h| {
        if (s.live(h)) |w| w.obj.close();
    }
    s.closes.clearRetainingCapacity();

    // Leave fullscreen first, so the dimensions proposed below take effect
    // in the same sequence (the protocol's frame-perfect exit).
    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        const w = wp.*;
        if (w.closed or !w.fullscreen or s.fullscreen == w.handle) continue;
        w.obj.exitFullscreen();
        w.obj.informNotFullscreen();
        w.fullscreen = false;
        w.proposed = .{ .width = 0, .height = 0 }; // force a proposal
        w.clip = null;
    }

    for (s.order.items) |h| {
        const w = s.live(h) orelse continue;
        if (!w.in_scene) continue;

        if (!w.configured) {
            w.obj.useSsd();
            w.obj.setCapabilities(@bitCast(cap_fullscreen));
            w.configured = true;
        }

        if (s.fullscreen == w.handle and !w.fullscreen) {
            if (output.at(s, w.want_pos)) |o| {
                w.obj.fullscreen(o.obj);
                w.obj.informFullscreen();
                w.fullscreen = true;
            }
        }

        // Tiled state first: a client that just lost (or regained) it may
        // pick its own size, so the change always gets a fresh proposal.
        if (w.tiled == null or w.tiled.? != w.want_tiled) {
            w.obj.setTiled(@bitCast(if (w.want_tiled) windows.all_edges else 0));
            w.tiled = w.want_tiled;
            w.proposed = .{ .width = 0, .height = 0 }; // force a proposal
        }

        const target: types.Size = if (w.anim_active) .{
            .width = @max(w.anim_from_size.width, w.want_size.width),
            .height = @max(w.anim_from_size.height, w.want_size.height),
        } else w.want_size;
        if (!w.fullscreen and (w.repropose or !util.size_eql(w.proposed, target))) {
            if (!util.size_eql(w.proposed, target)) w.insists = 0;
            w.obj.proposeDimensions(@intCast(target.width), @intCast(target.height));
            w.proposed = target;
        }
        w.repropose = false;
    }

    input.manage_seat(s);
}

/// The rendering half: positions, clips, borders and stacking, then renderFinish.
pub fn send_render(s: *State) void {
    const wm = s.wm orelse return;
    const now = util.now_ms();
    s.animating = false;

    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        const w = wp.*;
        if (!w.closed and !w.in_scene) if (w.ind) |*ind| ind.unmap();
        if (w.closed or w.in_scene or !w.shown) continue;
        w.obj.hide();
        w.shown = false;
    }
    var pit = s.previews.valueIterator();
    while (pit.next()) |pp| {
        if (!pp.*.in_scene) pp.*.surf.unmap();
    }

    s.scratch.clearRetainingCapacity();
    var fullscreen_node: ?*river.NodeV1 = null;

    for (s.order.items) |h| {
        if (s.previews.get(h)) |p| {
            if (!p.in_scene) continue;
            previews.render(s, p);
            if (p.want_tiled) {
                p.surf.node.placeTop();
            } else {
                s.scratch.append(s.allocator, .{ .node = p.surf.node, .serial = p.raise_serial * 2 }) catch {};
            }
            continue;
        }

        const w = s.live(h) orelse continue;
        if (!w.in_scene) continue;
        if (!w.shown) {
            w.obj.show();
            w.shown = true;
        }
        if (w.anim_active and w.anim_start_ms == 0) w.anim_start_ms = now;
        var r = windows.displayed(s, w, now);
        if (w.anim_active) {
            if (now - w.anim_start_ms >= s.anim.duration_ms) {
                w.anim_active = false;
                r = .{ .pos = w.want_pos, .size = w.want_size };
                s.settle = true;
            } else {
                s.animating = true;
            }
        }
        if (w.pos == null or w.pos.?.x != r.pos.x or w.pos.?.y != r.pos.y) {
            w.node.setPosition(r.pos.x, r.pos.y);
            w.pos = r.pos;
        }
        // The window's visible rectangle, borders included. Outside animations it's
        // the tile, which also crops clients that pick a larger size than proposed.
        if (!w.fullscreen and (w.clip == null or !util.size_eql(w.clip.?, r.size))) {
            w.obj.setContentClipBox(0, 0, @intCast(r.size.width), @intCast(r.size.height));
            w.clip = r.size;
        }
        if (!w.fullscreen) {
            const box = out_clip_box(r, w.want_border_width, w.want_out);
            if (!std.meta.eql(w.out_clip, box)) {
                if (box) |b| w.obj.setClipBox(b.x, b.y, @intCast(b.width), @intCast(b.height)) else w.obj.setClipBox(0, 0, 0, 0);
                w.out_clip = box;
            }
        }
        if (w.border_width != w.want_border_width or !util.opt_eql(w.border_color, w.want_border_color)) {
            windows.send_borders(w);
        }

        const ind_node = render_indicator(s, w, r);

        if (s.fullscreen == w.handle) {
            fullscreen_node = w.node;
        } else if (w.want_tiled) {
            w.node.placeTop();
            if (ind_node) |n| n.placeTop();
        } else {
            s.scratch.append(s.allocator, .{ .node = w.node, .serial = w.raise_serial * 2 }) catch {};
            if (ind_node) |n| s.scratch.append(s.allocator, .{ .node = n, .serial = w.raise_serial * 2 + 1 }) catch {};
        }
    }

    // Above the tiled windows, below floating ones.
    outlines.render(s);

    std.mem.sort(Stacked, s.scratch.items, {}, struct {
        fn lt(_: void, a: Stacked, b: Stacked) bool {
            return a.serial < b.serial;
        }
    }.lt);
    for (s.scratch.items) |e| e.node.placeTop();
    if (fullscreen_node) |n| n.placeTop();
    bars.render_error(s);
    bars.render_prompt(s);

    if (s.animating) s.last_frame_ms = now;
    wm.renderFinish();
}

// ---- window decoration ----

/// The part of a window, borders included, inside its output, relative to its
/// content's corner. Null when all of it is inside: no clipping needed.
fn out_clip_box(r: anytype, bw: u32, out: ?types.Rect) ?types.Rect {
    const o = out orelse return null;
    const b: i32 = @intCast(bw);
    const fx0 = r.pos.x - b;
    const fy0 = r.pos.y - b;
    const fx1 = r.pos.x + @as(i32, @intCast(r.size.width)) + b;
    const fy1 = r.pos.y + @as(i32, @intCast(r.size.height)) + b;
    const x0 = @max(fx0, o.x);
    const y0 = @max(fy0, o.y);
    const x1 = @min(fx1, o.x + @as(i32, @intCast(o.width)));
    const y1 = @min(fy1, o.y + @as(i32, @intCast(o.height)));
    if (x0 == fx0 and y0 == fy0 and x1 == fx1 and y1 == fy1) return null;
    return .{
        .x = x0 - r.pos.x,
        .y = y0 - r.pos.y,
        .width = @intCast(@max(1, x1 - x0)), // 0 would mean "don't clip"
        .height = @intCast(@max(1, y1 - y0)),
    };
}

/// The odd side's strip, just outside the content at r. Its node, to stack
/// right above the window, or null when there's nothing to show.
fn render_indicator(s: *State, w: *Window, r: windows.Shown) ?*river.NodeV1 {
    const want = w.want_odd orelse {
        if (w.ind) |*ind| ind.unmap();
        return null;
    };
    const bw: i32 = @intCast(w.want_border_width);
    if (bw == 0 or w.fullscreen) {
        if (w.ind) |*ind| ind.unmap();
        return null;
    }
    const shm = s.shm orelse return null;
    if (w.ind == null) {
        const wm = s.wm orelse return null;
        const comp = s.compositor orelse return null;
        w.ind = surface.ShellSurface.create(wm, comp) catch return null;
    }
    const ind = &w.ind.?;
    const rw: i32 = @intCast(r.size.width);
    const rh: i32 = @intCast(r.size.height);
    const rect: types.Rect = switch (want.side) {
        .top => .{ .x = r.pos.x - bw, .y = r.pos.y - bw, .width = @intCast(rw + 2 * bw), .height = @intCast(bw) },
        .bottom => .{ .x = r.pos.x - bw, .y = r.pos.y + rh, .width = @intCast(rw + 2 * bw), .height = @intCast(bw) },
        .left => .{ .x = r.pos.x - bw, .y = r.pos.y - bw, .width = @intCast(bw), .height = @intCast(rh + 2 * bw) },
        .right => .{ .x = r.pos.x + rw, .y = r.pos.y - bw, .width = @intCast(bw), .height = @intCast(rh + 2 * bw) },
    };
    const size: types.Size = .{ .width = rect.width, .height = rect.height };
    if (!ind.mapped or !util.size_eql(size, w.ind_size) or w.ind_color != want.color) {
        const color = want.color;
        ind.draw(shm, size.width, size.height, &color, paint_solid) catch return null;
        w.ind_size = size;
        w.ind_color = color;
    }
    ind.node.setPosition(rect.x, rect.y);
    return ind.node;
}

fn paint_solid(cv: surface.Canvas, color: *const u32) void {
    cv.fill(0, 0, cv.width, cv.height, color.*);
}
