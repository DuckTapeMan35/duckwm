const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const river = wayland.client.river;
const surface = @import("surface.zig");
const State = @import("backend.zig").State;
const util = @import("util.zig");
const size_eql = util.size_eql;
const nonneg = util.nonneg;

pub const all_edges: u32 = 1 | 2 | 4 | 8; // top | bottom | left | right

/// Size reported for a new window that gave no size hints. Tiled windows are
/// resized by the solver anyway; this is what an unhinted dialog starts at.
const default_size: types.Size = .{ .width = 800, .height = 600 };

/// A side drawn in a color of its own, over river's one-color border.
pub const Odd = struct { side: types.Side, color: u32 };

/// Where a window is on screen right now (mid-animation, not where it's going).
pub const Shown = struct { pos: types.Point, size: types.Size };

pub const Window = struct {
    state: *State,
    obj: *river.WindowV1,
    node: *river.NodeV1,
    handle: types.WindowHandle,

    info: types.WindowInfo = .{},
    parent: ?types.WindowHandle = null,
    min: types.Size = .{ .width = 0, .height = 0 },
    max: types.Size = .{ .width = 0, .height = 0 },
    wants_fullscreen: bool = false,
    /// map_request has been sent to core.
    announced: bool = false,
    closed: bool = false,

    // What core wants (apply_windows, draw_borders, hide_window, raise_window).
    in_scene: bool = false,
    want_pos: types.Point = .{ .x = 0, .y = 0 },
    want_size: types.Size = .{ .width = 0, .height = 0 },
    want_tiled: bool = false,
    want_border_width: u32 = 0,
    want_border_color: ?u32 = null,
    raise_serial: u64 = 0,

    // What river has been told.
    configured: bool = false,
    proposed: types.Size = .{ .width = 0, .height = 0 },
    tiled: ?bool = null,
    fullscreen: bool = false,
    shown: bool = true, // the protocol's initial state
    pos: ?types.Point = null,
    border_width: u32 = 0,
    border_color: ?u32 = null,
    /// Propose again at the next manage, even though the size hasn't changed.
    repropose: bool = false,
    /// Times re-proposed since the target last changed: a few, so stale commits
    /// don't use it up, but clients that round can't loop.
    insists: u8 = 0,

    // animation fields
    anim_active: bool = false,
    /// 0 = start at the next render, once river has the new sizes on screen.
    anim_start_ms: i64 = 0,
    anim_from_pos: types.Point = .{ .x = 0, .y = 0 },
    anim_from_size: types.Size = .{ .width = 0, .height = 0 },
    /// Content clip box last sent.
    clip: ?types.Size = null,
    /// The output core keeps it on (tiled only), and the clip box last sent for it.
    want_out: ?types.Rect = null,
    out_clip: ?types.Rect = null,
    /// The odd side core wants, and the surface drawing it.
    want_odd: ?Odd = null,
    ind: ?surface.ShellSurface = null,
    ind_size: types.Size = .{ .width = 0, .height = 0 },
    ind_color: u32 = 0,
};

// ---- lifetime ----
/// river announced a window: announced to core at the next manage_start.
pub fn add(s: *State, obj: *river.WindowV1) void {
    const w = s.allocator.create(Window) catch return obj.destroy();
    const node = obj.getNode() catch {
        s.allocator.destroy(w);
        return obj.destroy();
    };
    w.* = .{ .state = s, .obj = obj, .node = node, .handle = s.next_handle };
    s.next_handle += 1;
    s.windows.put(s.allocator, w.handle, w) catch {};
    s.by_obj.put(s.allocator, obj, w) catch {};
    s.fresh.append(s.allocator, w) catch {};
    obj.setListener(*Window, window_listener, w);
}

fn closed(s: *State, w: *Window) void {
    w.closed = true;
    if (w.announced) {
        s.push(.{ .window_gone = w.handle });
    } else {
        for (s.fresh.items, 0..) |f, i| {
            if (f == w) {
                _ = s.fresh.swapRemove(i);
                break;
            }
        }
    }
    if (s.hovered == w.handle) s.hovered = null;
    s.dead.append(s.allocator, w) catch {};
}

/// Free the windows closed during this dispatch.
pub fn destroy_dead(s: *State) void {
    for (s.dead.items) |w| {
        _ = s.windows.remove(w.handle);
        _ = s.by_obj.remove(w.obj);
        if (w.ind) |*ind| ind.destroy();
        w.node.destroy();
        w.obj.destroy();
        s.allocator.destroy(w);
    }
    s.dead.clearRetainingCapacity();
}

/// The handle core knows a river window by, if it knows it.
pub fn handle_of(s: *State, obj: ?*river.WindowV1) ?types.WindowHandle {
    const o = obj orelse return null;
    const w = s.by_obj.get(o) orelse return null;
    return if (w.announced and !w.closed) w.handle else null;
}

fn window_listener(_: *river.WindowV1, event: river.WindowV1.Event, w: *Window) void {
    const s = w.state;
    switch (event) {
        .closed => closed(s, w),
        .app_id => |e| {
            const id: []const u8 = if (e.app_id) |p| std.mem.span(p) else "";
            // Wayland has one id where X had class and instance: fill both,
            // so rules and swallow pairs written against either still match.
            w.info.set_class(id);
            w.info.set_instance(id);
            if (w.announced) s.push(.{ .info_changed = w.handle });
        },
        .title => |e| {
            w.info.set_title(if (e.title) |p| std.mem.span(p) else "");
            if (w.announced) s.push(.{ .info_changed = w.handle });
        },
        .unreliable_pid => |e| {
            w.info.pid = if (e.unreliable_pid > 0) @intCast(e.unreliable_pid) else null;
        },
        .parent => |e| {
            const p: ?*river.WindowV1 = e.parent;
            w.parent = if (p) |po| (if (s.by_obj.get(po)) |pw| pw.handle else null) else null;
        },
        .dimensions_hint => |e| {
            w.min = .{ .width = nonneg(e.min_width), .height = nonneg(e.min_height) };
            w.max = .{ .width = nonneg(e.max_width), .height = nonneg(e.max_height) };
        },
        .fullscreen_requested => {
            if (w.announced) {
                s.push(.{ .state_request = .{ .window = w.handle, .action = .add, .fullscreen = true, .attention = false } });
            } else {
                w.wants_fullscreen = true;
            }
        },
        .exit_fullscreen_requested => {
            if (w.announced) {
                s.push(.{ .state_request = .{ .window = w.handle, .action = .remove, .fullscreen = true, .attention = false } });
            } else {
                w.wants_fullscreen = false;
            }
        },
        .dimensions => |e| {
            const got: types.Size = .{ .width = nonneg(e.width), .height = nonneg(e.height) };
            if (w.announced and w.tiled == false and w.insists < 3 and !size_eql(got, w.proposed) and !s.op_active) {
                w.insists += 1;
                w.repropose = true;
                s.mark();
            }
        },
        else => {},
    }
}

// ---- what core is told ----
pub fn fixed_size(w: *const Window) ?types.Size {
    if (w.min.width == 0 or w.min.height == 0) return null;
    if (w.min.width != w.max.width or w.min.height != w.max.height) return null;
    return w.min;
}

pub fn initial_size(w: *const Window) types.Size {
    if (fixed_size(w)) |s| return s;
    return .{
        .width = @max(w.min.width, default_size.width),
        .height = @max(w.min.height, default_size.height),
    };
}

pub fn traits_of(w: *const Window) types.WindowTraits {
    return .{
        .kind = if (w.parent != null) .floating else .normal,
        .transient_for = w.parent,
    };
}

// ---- borders ----
/// 0xRRGGBB to the protocol's four 32-bit (pre-multiplied, here opaque) components.
pub fn send_borders(w: *Window) void {
    const edges: river.WindowV1.Edges = @bitCast(if (w.want_border_color != null and w.want_border_width > 0) all_edges else 0);
    const bc = w.want_border_color orelse 0;
    const r: u32 = (bc >> 16) & 0xff;
    const g: u32 = (bc >> 8) & 0xff;
    const b: u32 = bc & 0xff;
    w.obj.setBorders(edges, @intCast(w.want_border_width), r * 0x01010101, g * 0x01010101, b * 0x01010101, 0xffffffff);
    w.border_width = w.want_border_width;
    w.border_color = w.want_border_color;
}

/// The color most sides share: river's border color.
pub fn base_color(b: types.BorderColors) u32 {
    return if (b.top == b.bottom or b.top == b.left or b.top == b.right) b.top else b.bottom;
}

/// The first side that isn't the base color (the indicator), if any.
pub fn odd_side(b: types.BorderColors) ?Odd {
    const base = base_color(b);
    if (b.top != base) return .{ .side = .top, .color = b.top };
    if (b.bottom != base) return .{ .side = .bottom, .color = b.bottom };
    if (b.left != base) return .{ .side = .left, .color = b.left };
    if (b.right != base) return .{ .side = .right, .color = b.right };
    return null;
}

// ---- animation ----
fn lerp_u(a: u32, b: u32, e: f32) u32 {
    return @intCast(@max(1, lerp(@intCast(a), @intCast(b), e)));
}

fn lerp(a: i32, b: i32, e: f32) i32 {
    return a + @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(b - a)) * e)));
}

/// The rectangle a window occupies on screen right now.
pub fn displayed(s: *const State, w: *const Window, now: i64) Shown {
    if (!w.anim_active or s.anim.duration_ms == 0) return .{ .pos = w.want_pos, .size = w.want_size };
    const t: f32 = if (w.anim_start_ms == 0) 0 else @min(1.0, @as(f32, @floatFromInt(now - w.anim_start_ms)) /
        @as(f32, @floatFromInt(s.anim.duration_ms)));
    const e = ease(&s.anim.curve, t);
    return .{
        .pos = .{ .x = lerp(w.anim_from_pos.x, w.want_pos.x, e), .y = lerp(w.anim_from_pos.y, w.want_pos.y, e) },
        .size = .{
            .width = lerp_u(w.anim_from_size.width, w.want_size.width, e),
            .height = lerp_u(w.anim_from_size.height, w.want_size.height, e),
        },
    };
}

pub fn ease(curve: *const types.CurveTable, t: f32) f32 {
    const pos = std.math.clamp(t, 0, 1) * types.curve_samples;
    const i: usize = @intFromFloat(@floor(pos));
    if (i >= types.curve_samples) return curve[types.curve_samples];
    const f = pos - @floor(pos);
    return curve[i] + (curve[i + 1] - curve[i]) * f;
}
