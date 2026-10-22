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
const xkb = @import("xkbcommon");
const c = @import("rc");
const wl = wayland.client.wl;
const river = wayland.client.river;
const Window = windows.Window;
const now_ms = util.now_ms;
const size_eql = util.size_eql;
const opt_eql = util.opt_eql;
const nonneg = util.nonneg;

const wm_version = 4;
const xkb_bindings_version = 1;
const layer_shell_version = 1;

/// river_seat_v1.modifiers has no Lock (2) or Mod2/NumLock (16) bit.
const cap_fullscreen: u32 = 4;

const frame_interval_ms: i64 = 16;

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

const Stacked = struct { node: *river.NodeV1, serial: u64 };

// State is heap-allocated, because libwayland keeps pointers to it in listeners
// and the Backend value itself gets copied into WM.
pub const State = struct {
    allocator: std.mem.Allocator,
    display: *wl.Display,
    next_output_id: u32 = 1,
    registry: *wl.Registry,

    wm: ?*river.WindowManagerV1 = null,
    xkb_bindings: ?*river.XkbBindingsV1 = null,
    layout_index: ?u32 = null,
    layer_shell: ?*river.LayerShellV1 = null,
    seat: ?*river.SeatV1 = null,
    layer_seat: ?*river.LayerShellSeatV1 = null,
    outputs: std.ArrayListUnmanaged(*output.Output) = .empty,
    /// The output the pointer was last on, to report crossings.
    pointer_output: u32 = 0,
    /// Until multimonitor: the first output is "the screen".
    primary: ?*output.Output = null,

    unavailable: bool = false,
    finished: bool = false,

    // Sequence bookkeeping.
    in_manage: bool = false,
    render_pending: bool = false,
    want_manage: bool = false,
    dirty_sent: bool = false,
    pumped: bool = false,

    // Events for core, in order.
    events: std.ArrayListUnmanaged(types.Event) = .empty,
    event_head: usize = 0,

    // Windows.
    next_handle: types.WindowHandle = 1,
    windows: std.AutoHashMapUnmanaged(types.WindowHandle, *Window) = .empty,
    by_obj: std.AutoHashMapUnmanaged(*river.WindowV1, *Window) = .empty,
    /// Created, properties still arriving: announced at the next manage_start.
    fresh: std.ArrayListUnmanaged(*Window) = .empty,
    /// Closed this dispatch: destroyed once dispatching is done.
    dead: std.ArrayListUnmanaged(*Window) = .empty,

    // Desired state recorded from core.
    order: std.ArrayListUnmanaged(types.WindowHandle) = .empty,
    fullscreen: ?types.WindowHandle = null,
    focus: ?types.WindowHandle = null,
    focus_dirty: bool = false,
    closes: std.ArrayListUnmanaged(types.WindowHandle) = .empty,
    raise_clock: u64 = 0,
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    fonts: surface.Fonts = .{},
    previews: std.AutoHashMapUnmanaged(types.WindowHandle, *previews.Preview) = .empty,
    /// Group outlines, by core's key.
    outlines: std.AutoHashMapUnmanaged(u64, *outlines.Outline) = .empty,
    error_bar: ?*bars.ErrorBar = null,
    prompt_bar: ?*bars.PromptBar = null,
    scratch: std.ArrayListUnmanaged(Stacked) = .empty,

    // Input.
    keys: std.ArrayListUnmanaged(*input.KeyBinding) = .empty,
    buttons: std.ArrayListUnmanaged(*input.ButtonBinding) = .empty,
    click_to_focus: bool = false,
    hovered: ?types.WindowHandle = null,
    pointer_pos: types.Point = .{ .x = 0, .y = 0 },
    op_active: bool = false,
    op_start_pending: bool = false,
    op_end_pending: bool = false,
    op_origin: types.Point = .{ .x = 0, .y = 0 },
    op_button: types.Button = 1,
    /// op_release already reported the release; swallow the binding's own.
    suppress_release: bool = false,
    warp: ?types.Point = null,
    layer_focus_exclusive: bool = false,
    cursor_theme: ?[:0]u8 = null,
    cursor_size: u32 = 24,
    xkb_config: ?*river.XkbConfigV1 = null,
    keyboards: std.ArrayListUnmanaged(*river.XkbKeyboardV1) = .empty,
    /// Accepted by river and applied to every keyboard, including new ones.
    keymap: ?*river.XkbKeymapV1 = null,
    /// Sent, waiting for river's success/failure.
    pending_keymap: ?*river.XkbKeymapV1 = null,
    // The keyboard as a plain Wayland client sees it: keys typed into the input bar.
    wl_seat: ?*wl.Seat = null,
    keyboard: ?*wl.Keyboard = null,
    xkb_ctx: ?*xkb.Context = null,
    xkb_keymap: ?*xkb.Keymap = null,
    xkb_state: ?*xkb.State = null,
    repeat_rate: i32 = 25,
    repeat_delay: i32 = 600,
    /// The held key being repeated into the bar (an xkb keycode).
    repeat_key: ?u32 = null,
    repeat_next_ms: i64 = 0,

    // Animations.
    anim: types.Animation = .{},
    /// Some window is mid-animation: keep requesting frames.
    animating: bool = false,
    last_frame_ms: i64 = 0,
    /// An animation just ended: final sizes must be proposed.
    settle: bool = false,
    /// Hovered window reported this batch; acted on at manage_start.
    pending_enter: ?types.WindowHandle = null,
    pos_at_last_manage: types.Point = .{ .x = 0, .y = 0 },

    pub fn push(s: *State, ev: types.Event) void {
        // Coalesce: only the latest pointer position and one relayout matter.
        if (s.events.items.len > s.event_head) {
            const last = &s.events.items[s.events.items.len - 1];
            if (ev == .pointer_motion and last.* == .pointer_motion) {
                last.* = ev;
                return;
            }
            if (ev == .reserved_area_changed and last.* == .reserved_area_changed) return;
        }
        s.events.append(s.allocator, ev) catch {};
    }

    /// Core changed something that river must hear about.
    pub fn mark(s: *State) void {
        if (!s.in_manage) s.want_manage = true;
    }

    pub fn live(s: *State, h: types.WindowHandle) ?*Window {
        const w = s.windows.get(h) orelse return null;
        return if (w.closed) null else w;
    }

    // --- keyboard ---
    fn configure_keyboard(s: *State, kb: *river.XkbKeyboardV1) void {
        if (s.keymap) |km| kb.setKeymap(km);
        if (s.layout_index) |i| kb.setLayoutByIndex(@intCast(i));
    }

    fn keymap_ready(s: *State, km: *river.XkbKeymapV1) void {
        if (s.pending_keymap != km) return km.destroy(); // superseded by a newer one
        s.pending_keymap = null;
        if (s.keymap) |old| old.destroy();
        s.keymap = km;
        for (s.keyboards.items) |kb| s.configure_keyboard(kb);
    }

    // ---- sequences ----

    fn start_manage(s: *State) void {
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
    fn send_manage(s: *State) void {
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
            if (!w.fullscreen and (w.repropose or !size_eql(w.proposed, target))) {
                if (!size_eql(w.proposed, target)) w.insists = 0;
                w.obj.proposeDimensions(@intCast(target.width), @intCast(target.height));
                w.proposed = target;
            }
            w.repropose = false;
        }

        input.manage_seat(s);
    }

    fn send_render(s: *State) void {
        const wm = s.wm orelse return;
        const now = now_ms();
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
            if (!w.fullscreen and (w.clip == null or !size_eql(w.clip.?, r.size))) {
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
            if (w.border_width != w.want_border_width or !opt_eql(w.border_color, w.want_border_color)) {
                windows.send_borders(w);
            }

            const ind_node = s.render_indicator(w, r);

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

    // ---- reading the socket ----

    /// Read whatever the socket has, without blocking, and dispatch it.
    fn pump(s: *State) void {
        const d = s.display;
        while (!d.prepareRead()) {
            if (d.dispatchPending() != .SUCCESS) return s.lost_connection();
        }
        _ = d.flush();

        // The main loop's poll may have woken for IPC or inotify, so the
        // socket isn't necessarily readable; readEvents would block.
        var pfd = [1]std.posix.pollfd{.{ .fd = d.getFd(), .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = std.posix.poll(&pfd, 0) catch 0;
        if (ready > 0) {
            if (d.readEvents() != .SUCCESS) return s.lost_connection();
        } else {
            d.cancelRead();
        }
        if (d.dispatchPending() != .SUCCESS) return s.lost_connection();
        windows.destroy_dead(s);
    }

    fn lost_connection(s: *State) void {
        _ = s;
        // river exited (or killed us). Nothing left to manage.
        std.debug.print("duckwm: lost connection to river, exiting\n", .{});
        std.process.exit(0);
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
        if (!ind.mapped or !size_eql(size, w.ind_size) or w.ind_color != want.color) {
            const color = want.color;
            ind.draw(shm, size.width, size.height, &color, paint_solid) catch return null;
            w.ind_size = size;
            w.ind_color = color;
        }
        ind.node.setPosition(rect.x, rect.y);
        return ind.node;
    }

    /// One key into the bar, as keysym, X-style modifiers and UTF-8 text.
    fn push_prompt_key(s: *State, keycode: u32) void {
        const st = s.xkb_state orelse return;
        var k: types.PromptKey = .{
            .keysym = @intCast(@intFromEnum(st.keyGetOneSym(keycode))),
            .mods = s.xkb_mods(),
        };
        var buf: [16]u8 = undefined;
        const n = st.keyGetUtf8(keycode, &buf);
        if (n <= k.text_buf.len) {
            @memcpy(k.text_buf[0..n], buf[0..n]);
            k.text_len = @intCast(n);
        }
        s.push(.{ .prompt_key = k });
    }

    fn xkb_mods(s: *State) types.Mods {
        const st = s.xkb_state orelse return 0;
        const effective: xkb.State.Component = @enumFromInt(xkb.State.Component.mods_effective);
        var m: types.Mods = 0;
        if (st.modNameIsActive("Shift", effective) > 0) m |= types.mod.shift;
        if (st.modNameIsActive("Control", effective) > 0) m |= types.mod.ctrl;
        if (st.modNameIsActive("Mod1", effective) > 0) m |= types.mod.alt;
        if (st.modNameIsActive("Mod4", effective) > 0) m |= types.mod.super;
        return m;
    }

    fn keyboard_key(s: *State, evdev: u32, pressed: bool) void {
        const keycode = evdev + 8; // evdev to xkb
        if (!pressed) {
            if (s.repeat_key == keycode) s.repeat_key = null;
            return;
        }
        if (!bars.typing(s)) return;
        s.push_prompt_key(keycode);
        const km = s.xkb_keymap orelse return;
        if (s.repeat_rate > 0 and km.keyRepeats(keycode) != 0) {
            s.repeat_key = keycode;
            s.repeat_next_ms = now_ms() + s.repeat_delay;
        }
    }

    /// Wayland leaves key repeat to the client: send the held key again when it's due.
    fn repeat_due(s: *State) void {
        const kc = s.repeat_key orelse return;
        const now = now_ms();
        if (now < s.repeat_next_ms) return;
        s.push_prompt_key(kc);
        s.repeat_next_ms = now + @divTrunc(1000, @max(1, s.repeat_rate));
    }
};

fn paint_solid(cv: surface.Canvas, color: *const u32) void {
    cv.fill(0, 0, cv.width, cv.height, color.*);
}

// --- Listeners ---
fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, s: *State) void {
    switch (event) {
        .global => |g| {
            if (std.mem.orderZ(u8, g.interface, river.WindowManagerV1.interface.name) == .eq) {
                s.wm = registry.bind(g.name, river.WindowManagerV1, @min(g.version, wm_version)) catch return;
            } else if (std.mem.orderZ(u8, g.interface, river.XkbBindingsV1.interface.name) == .eq) {
                s.xkb_bindings = registry.bind(g.name, river.XkbBindingsV1, @min(g.version, xkb_bindings_version)) catch return;
            } else if (std.mem.orderZ(u8, g.interface, river.LayerShellV1.interface.name) == .eq) {
                // Binding this is what tells river duckwm supports layer shell (bars).
                s.layer_shell = registry.bind(g.name, river.LayerShellV1, @min(g.version, layer_shell_version)) catch return;
            } else if (std.mem.orderZ(u8, g.interface, wl.Compositor.interface.name) == .eq) {
                s.compositor = registry.bind(g.name, wl.Compositor, @min(g.version, 4)) catch return;
            } else if (std.mem.orderZ(u8, g.interface, wl.Shm.interface.name) == .eq) {
                s.shm = registry.bind(g.name, wl.Shm, 1) catch return;
            } else if (std.mem.orderZ(u8, g.interface, wl.Seat.interface.name) == .eq) {
                // One seat until there's a reason for more, as with river_seat_v1.
                if (s.wl_seat != null) return;
                s.wl_seat = registry.bind(g.name, wl.Seat, @min(g.version, 5)) catch return;
                s.wl_seat.?.setListener(*State, wl_seat_listener, s);
            } else if (std.mem.orderZ(u8, g.interface, river.XkbConfigV1.interface.name) == .eq) {
                s.xkb_config = registry.bind(g.name, river.XkbConfigV1, 1) catch return;
                s.xkb_config.?.setListener(*State, xkb_config_listener, s);
            }
        },
        .global_remove => {},
    }
}

fn wm_listener(_: *river.WindowManagerV1, event: river.WindowManagerV1.Event, s: *State) void {
    switch (event) {
        .unavailable => s.unavailable = true,
        .finished => s.finished = true,
        .manage_start => s.start_manage(),
        .render_start => s.render_pending = true,
        .window => |e| windows.add(s, e.id),
        .output => |e| output.add(s, e.id),
        .seat => |e| input.add_seat(s, e.id),
        else => {},
    }
}

fn xkb_config_listener(_: *river.XkbConfigV1, event: river.XkbConfigV1.Event, s: *State) void {
    switch (event) {
        .xkb_keyboard => |e| {
            s.keyboards.append(s.allocator, e.id) catch return e.id.destroy();
            e.id.setListener(*State, keyboard_listener, s);
            s.configure_keyboard(e.id);
        },
        .finished => {},
    }
}

fn keyboard_listener(kb: *river.XkbKeyboardV1, event: river.XkbKeyboardV1.Event, s: *State) void {
    switch (event) {
        .removed => {
            for (s.keyboards.items, 0..) |k, i| {
                if (k == kb) {
                    _ = s.keyboards.swapRemove(i);
                    break;
                }
            }
            kb.destroy();
        },
        else => {},
    }
}

fn keymap_listener(km: *river.XkbKeymapV1, event: river.XkbKeymapV1.Event, s: *State) void {
    switch (event) {
        .success => s.keymap_ready(km),
        .failure => |e| {
            std.debug.print("duckwm: river rejected keymap: {s}\n", .{e.error_msg});
            if (s.pending_keymap == km) s.pending_keymap = null;
            km.destroy();
        },
    }
}

fn wl_seat_listener(seat: *wl.Seat, event: wl.Seat.Event, s: *State) void {
    switch (event) {
        .capabilities => |e| {
            if (e.capabilities.keyboard and s.keyboard == null) {
                const kb = seat.getKeyboard() catch return;
                kb.setListener(*State, wl_keyboard_listener, s);
                s.keyboard = kb;
            } else if (!e.capabilities.keyboard) {
                if (s.keyboard) |kb| kb.release();
                s.keyboard = null;
            }
        },
        else => {},
    }
}

fn wl_keyboard_listener(_: *wl.Keyboard, event: wl.Keyboard.Event, s: *State) void {
    switch (event) {
        .keymap => |e| {
            defer _ = c.close(e.fd);
            if (e.format != .xkb_v1 or e.size == 0) return;
            const mem = c.mmap(null, e.size, c.PROT_READ, c.MAP_PRIVATE, e.fd, 0);
            if (mem == null or @intFromPtr(mem) == std.math.maxInt(usize)) return;
            defer _ = c.munmap(mem, e.size);
            const ctx = s.xkb_ctx orelse (xkb.Context.new(.no_flags) orelse return);
            s.xkb_ctx = ctx;
            const bytes: [*]const u8 = @ptrCast(mem.?);
            const km = xkb.Keymap.newFromBuffer(ctx, bytes, e.size - 1, .text_v1, .no_flags) orelse return;
            const st = xkb.State.new(km) orelse return km.unref();
            if (s.xkb_state) |old| old.unref();
            if (s.xkb_keymap) |old| old.unref();
            s.xkb_keymap = km;
            s.xkb_state = st;
        },
        .enter, .leave => s.repeat_key = null,
        .modifiers => |e| if (s.xkb_state) |st| {
            _ = st.updateMask(e.mods_depressed, e.mods_latched, e.mods_locked, 0, 0, e.group);
        },
        .key => |e| s.keyboard_key(e.key, e.state == .pressed),
        .repeat_info => |e| {
            s.repeat_rate = e.rate;
            s.repeat_delay = e.delay;
        },
    }
}

fn seat_listener(_: *river.SeatV1, event: river.SeatV1.Event, s: *State) void {
    switch (event) {
        .pointer_position => |e| {
            s.pointer_pos = .{ .x = e.x, .y = e.y };
            if (output.at(s, s.pointer_pos)) |o| if (o.id != s.pointer_output) {
                s.pointer_output = o.id;
                s.push(.{ .pointer_output = o.id });
            };
        },
        .pointer_enter => |e| {
            const h = windows.handle_of(s, e.window);
            s.hovered = h;
            s.pending_enter = h;
        },
        .pointer_leave => s.hovered = null,
        .window_interaction => |e| {
            // Click-to-focus: core treats an unmodified press as "focus this".
            if (!s.click_to_focus) return;
            const h = windows.handle_of(s, e.window) orelse return;
            s.push(.{ .button_press = .{ .window = h, .button = 1, .mods = 0, .pos = s.pointer_pos } });
        },
        .op_delta => |e| {
            if (!s.op_active) return;
            s.push(.{ .pointer_motion = .{ .x = s.op_origin.x + e.dx, .y = s.op_origin.y + e.dy } });
        },
        .op_release => {
            if (!s.op_active) return;
            s.suppress_release = true;
            s.push(.{ .button_release = .{ .window = s.hovered, .button = s.op_button, .mods = 0, .pos = s.pointer_pos } });
        },
        .shell_surface_interaction => |e| s.shell_clicked(e.shell_surface),
        .removed => {},
        else => {},
    }
}

fn layer_seat_listener(_: *river.LayerShellSeatV1, event: river.LayerShellSeatV1.Event, s: *State) void {
    switch (event) {
        .focus_exclusive => s.layer_focus_exclusive = true,
        .focus_non_exclusive => {},
        .focus_none => {
            // A launcher or similar let go: give focus back to the WM's choice.
            s.layer_focus_exclusive = false;
            s.push(.refocus);
        },
    }
}

// The backend interface core uses (see wm/backend.zig's required).
pub const Backend = struct {
    allocator: std.mem.Allocator,
    state: *State,

    // ---- lifecycle ----

    pub fn init(allocator: std.mem.Allocator) !Backend {
        surface.init();
        const display = wl.Display.connect(null) catch return error.CannotOpenDisplay;
        errdefer display.disconnect();
        const registry = try display.getRegistry();

        const s = try allocator.create(State);
        errdefer allocator.destroy(s);
        s.* = .{ .allocator = allocator, .display = display, .registry = registry };

        // Bind the globals now rather than in start(): core reads the screen
        // size in WM.create, and that comes from the first output.
        registry.setListener(*State, registry_listener, s);
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        const wm = s.wm orelse return error.NotRunningUnderRiver;
        wm.setListener(*State, wm_listener, s);
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        if (s.unavailable) return error.AnotherWmRunning;

        return .{ .allocator = allocator, .state = s };
    }

    pub fn deinit(self: *Backend) void {
        const s = self.state;
        self.ungrab_all_keys();
        self.set_pointer_grabs(&.{});
        var it = s.windows.valueIterator();
        while (it.next()) |wp| {
            if (wp.*.ind) |*ind| ind.destroy();
            s.allocator.destroy(wp.*);
        }
        s.windows.deinit(s.allocator);
        s.by_obj.deinit(s.allocator);
        for (s.outputs.items) |o| s.allocator.destroy(o);
        s.outputs.deinit(s.allocator);
        s.fresh.deinit(s.allocator);
        s.dead.deinit(s.allocator);
        s.events.deinit(s.allocator);
        s.order.deinit(s.allocator);
        s.closes.deinit(s.allocator);
        s.scratch.deinit(s.allocator);
        s.keys.deinit(s.allocator);
        s.buttons.deinit(s.allocator);
        if (s.cursor_theme) |t| s.allocator.free(t);
        previews.destroy_all(s);
        s.previews.deinit(s.allocator);
        outlines.destroy_all(s);
        _ = bars.hide_error(s);
        _ = bars.hide_prompt(s);
        if (s.keyboard) |kb| kb.release();
        if (s.wl_seat) |ws| ws.release();
        if (s.xkb_state) |x| x.unref();
        if (s.xkb_keymap) |x| x.unref();
        if (s.xkb_ctx) |x| x.unref();
        s.fonts.deinit(s.allocator);
        surface.deinit();
        s.display.disconnect();
        self.allocator.destroy(s);
    }

    pub fn start(self: *Backend) !void {
        _ = self; // everything happens in init
    }

    pub fn event_fd(self: *const Backend) i32 {
        return self.state.display.getFd();
    }

    pub fn next_event(self: *Backend) ?types.Event {
        const s = self.state;
        if (!s.pumped) {
            s.pump();
            s.pumped = true;
        }
        if (s.prompt_bar) |b| if (b.deadline) |d| if (now_ms() >= d) {
            _ = bars.hide_prompt(s);
        };
        s.repeat_due();
        if (s.render_pending) {
            s.render_pending = false;
            s.send_render();
        }
        if (s.event_head < s.events.items.len) {
            const ev = s.events.items[s.event_head];
            s.event_head += 1;
            return ev;
        }
        s.events.clearRetainingCapacity();
        s.event_head = 0;
        return null;
    }

    /// End of the loop iteration: close the manage sequence, or ask for one.
    pub fn flush_output(self: *const Backend) void {
        const s = self.state;
        if ((s.settle or (s.animating and now_ms() - s.last_frame_ms >= frame_interval_ms)) and !s.in_manage) {
            s.want_manage = true;
        }
        if (s.wm) |wm| {
            if (s.in_manage) {
                s.send_manage();
                wm.manageFinish();
                s.in_manage = false;
                s.want_manage = false;
            } else if (s.want_manage and !s.dirty_sent) {
                wm.manageDirty();
                s.dirty_sent = true;
                s.want_manage = false;
            }
        }
        _ = s.display.flush();
        s.pumped = false;
    }

    /// river renders frame-perfectly on its own; nothing to wait for.
    pub fn sync(self: *const Backend) void {
        _ = self;
    }

    /// End the whole Wayland session: river exits, and every client with it.
    pub fn end_session(self: *Backend) void {
        const s = self.state;
        if (s.wm) |wm| wm.exitSession();
        _ = s.display.flush();
    }

    // ---- screen ----

    pub fn screen_size(self: *const Backend) types.Size {
        const o = self.state.primary orelse return .{ .width = 1920, .height = 1080 };
        return .{ .width = nonneg(o.width), .height = nonneg(o.height) };
    }

    pub fn reserved_insets(self: *const Backend) types.Insets {
        const s = self.state;
        var r: types.Insets = .{};
        if (s.primary) |o| if (o.usable) |a| {
            const aw: i32 = @intCast(a.width);
            const ah: i32 = @intCast(a.height);
            r = .{
                .left = nonneg(a.x - o.x),
                .top = nonneg(a.y - o.y),
                .right = nonneg((o.x + o.width) - (a.x + aw)),
                .bottom = nonneg((o.y + o.height) - (a.y + ah)),
            };
        };
        if (s.error_bar) |bar| r.top += bar.height;
        return r;
    }

    // ---- publishing (EWMH on X; river runs foreign-toplevel itself) ----

    pub fn publish_work_area(self: *const Backend, r: types.Rect) void {
        _ = self;
        _ = r;
    }
    pub fn publish_workspaces(self: *const Backend, count: u32, current: u32) void {
        _ = self;
        _ = count;
        _ = current;
    }
    pub fn publish_window_list(self: *const Backend, hs: []const types.WindowHandle) void {
        _ = self;
        _ = hs;
    }
    pub fn publish_window_workspace(self: *const Backend, h: types.WindowHandle, i: u32) void {
        _ = self;
        _ = h;
        _ = i;
    }
    pub fn publish_window_fullscreen(self: *const Backend, h: types.WindowHandle, on: bool) void {
        _ = self;
        _ = h;
        _ = on;
    }
    pub fn publish_frame_extents(self: *const Backend, bw: u32) void {
        _ = self;
        _ = bw;
    }

    // ---- windows ----

    pub fn window_info(self: *const Backend, h: types.WindowHandle) types.WindowInfo {
        const w = self.state.windows.get(h) orelse return .{};
        return w.info;
    }

    pub fn window_traits(self: *const Backend, h: types.WindowHandle) types.WindowTraits {
        const w = self.state.windows.get(h) orelse return .{};
        return windows.traits_of(w);
    }

    pub fn window_hints(self: *const Backend, h: types.WindowHandle) types.InitialHints {
        const w = self.state.windows.get(h) orelse return .{};
        return .{
            .fullscreen = w.wants_fullscreen,
            .fixed_size = windows.fixed_size(w),
        };
    }

    /// No frames on Wayland: river draws borders around the window itself.
    pub fn frame_window(self: *Backend, h: types.WindowHandle, opts: types.FrameOptions) !void {
        _ = self;
        _ = h;
        _ = opts;
    }

    /// Window objects are destroyed when river reports them closed.
    pub fn unframe(self: *Backend, h: types.WindowHandle, keep: bool) void {
        _ = self;
        _ = h;
        _ = keep;
    }

    pub fn close_window(self: *Backend, h: types.WindowHandle) void {
        const s = self.state;
        if (s.live(h) == null) return;
        s.closes.append(s.allocator, h) catch return;
        s.mark();
    }

    /// Docks are layer-shell surfaces on Wayland and never become windows.
    pub fn release_window(self: *Backend, h: types.WindowHandle) void {
        _ = self;
        _ = h;
    }

    pub fn apply_windows(self: *Backend, states: []const types.WindowState, fullscreen: ?types.WindowHandle) void {
        const s = self.state;

        var it = s.windows.valueIterator();
        while (it.next()) |wp| wp.*.in_scene = false;
        s.order.clearRetainingCapacity();

        var pit = s.previews.valueIterator();
        while (pit.next()) |pp| pp.*.in_scene = false;

        for (states) |st| {
            if (s.previews.get(st.handle)) |p| {
                previews.apply(p, st);
                s.order.append(s.allocator, st.handle) catch {};
                continue;
            }
            const w = s.live(st.handle) orelse continue; // e.g. preview placeholders
            const bw = st.border_width;
            // core's rect is the whole footprint; river's geometry is the
            // content, with borders drawn outside it.
            w.in_scene = true;
            const new_pos: types.Point = .{
                .x = st.frame.x + @as(i32, @intCast(bw)),
                .y = st.frame.y + @as(i32, @intCast(bw)),
            };
            const new_size: types.Size = .{
                .width = @max(1, st.frame.width -| 2 * bw),
                .height = @max(1, st.frame.height -| 2 * bw),
            };
            const changed = new_pos.x != w.want_pos.x or new_pos.y != w.want_pos.y or !size_eql(new_size, w.want_size);
            if (changed and s.anim.duration_ms > 0 and w.pos != null and w.shown and
                !w.fullscreen and !st.interactive and !s.op_active)
            {
                const cur = windows.displayed(s, w, now_ms()); // mid-flight retargets start from where it is
                w.anim_from_pos = cur.pos;
                w.anim_from_size = cur.size;
                w.anim_start_ms = 0;
                w.anim_active = true;
            } else if (changed) {
                w.anim_active = false;
            }
            w.want_border_color = if (st.borders) |b| windows.base_color(b) else null;
            w.want_odd = if (st.borders) |b| windows.odd_side(b) else null;
            w.want_pos = new_pos;
            w.want_size = new_size;
            w.want_tiled = st.tiled;
            w.want_out = st.clip;
            w.want_border_width = bw;
            s.order.append(s.allocator, st.handle) catch {};
        }
        s.fullscreen = fullscreen;
        s.mark();
    }

    /// The group outlines to show; any other goes at the next render.
    pub fn apply_outlines(self: *Backend, list: []const types.Outline) void {
        outlines.apply(self.state, list);
    }

    pub fn hide_window(self: *Backend, h: types.WindowHandle) void {
        const s = self.state;
        if (s.previews.get(h)) |p| {
            p.in_scene = false;
            s.mark();
            return;
        }
        const w = s.live(h) orelse return;
        w.in_scene = false;
        s.mark();
    }

    pub fn raise_window(self: *Backend, h: types.WindowHandle) void {
        const s = self.state;
        if (s.previews.get(h)) |p| {
            s.raise_clock += 1;
            p.raise_serial = s.raise_clock;
            s.mark();
            return;
        }
        const w = s.live(h) orelse return;
        s.raise_clock += 1;
        w.raise_serial = s.raise_clock;
        s.mark();
    }

    /// One color for all edges: river's borders don't do per-side colors.
    pub fn draw_borders(self: *Backend, h: types.WindowHandle, colors: types.BorderColors, width: u32, size: ?types.Size) void {
        _ = size;
        const s = self.state;
        if (s.previews.get(h)) |p| {
            p.want_border_color = windows.base_color(colors);
            p.want_border_width = width;
            s.mark();
            return;
        }
        const w = s.live(h) orelse return;
        w.want_border_color = windows.base_color(colors);
        w.want_odd = windows.odd_side(colors);
        w.want_border_width = width;
        s.mark();
    }

    pub fn set_input_focus(self: *Backend, h: ?types.WindowHandle, publish: bool) bool {
        _ = publish; // river publishes the activated toplevel itself
        const s = self.state;
        if (h) |win| if (s.live(win) == null and !s.previews.contains(win)) return false;
        s.focus = h;
        s.focus_dirty = true;
        s.mark();
        return true;
    }

    // ---- WM-owned surfaces (previews, error bar): shell surfaces, later ----
    pub fn create_preview_window(self: *Backend, opts: types.FrameOptions) !types.WindowHandle {
        _ = opts;
        return previews.create(self.state);
    }

    pub fn destroy_preview_window(self: *Backend, h: types.WindowHandle) void {
        previews.destroy(self.state, h);
    }

    /// Copies the content; the buffer itself follows the scene rect at render time.
    pub fn draw_preview(self: *Backend, h: types.WindowHandle, size: types.Size, style: types.PreviewStyle, items: []const types.PreviewItem) void {
        _ = size;
        previews.set_content(self.state, h, style, items);
    }

    pub fn show_error(self: *Backend, msg: []const u8) !void {
        try bars.show_error(self.state, msg);
    }

    pub fn hide_error(self: *Backend) bool {
        return bars.hide_error(self.state);
    }

    /// The input bar, taking the keyboard: keys come back as prompt_key events.
    pub fn show_prompt(self: *Backend, label: []const u8, text: []const u8, cursor: usize, block: bool) !void {
        try bars.show_prompt(self.state, label, text, cursor, block);
    }

    /// Text in the input bar without taking the keyboard; gone after timeout_ms.
    pub fn show_message(self: *Backend, text: []const u8, timeout_ms: u32) !void {
        try bars.show_message(self.state, text, timeout_ms);
    }

    pub fn hide_prompt(self: *Backend) void {
        _ = bars.hide_prompt(self.state);
    }

    // ---- input ----

    pub fn keysym_from_name(self: *const Backend, name: []const u8) ?types.Keysym {
        _ = self;
        var buf: [64]u8 = undefined;
        if (name.len >= buf.len) return null;
        @memcpy(buf[0..name.len], name);
        buf[name.len] = 0;
        const sym = xkb.Keysym.fromName(buf[0..name.len :0], .no_flags);
        if (sym == .NoSymbol) return null;
        return @intCast(@intFromEnum(sym));
    }

    /// Bindings are created and enabled in the next manage sequence.
    pub fn grab_key(self: *const Backend, k: types.KeyCombo) void {
        input.grab_key(self.state, k);
    }

    pub fn ungrab_all_keys(self: *const Backend) void {
        input.ungrab_all_keys(self.state);
    }

    /// A grab with no button covers left, middle and right, like X's AnyButton
    /// for the buttons that matter here.
    pub fn set_pointer_grabs(self: *Backend, grabs: []const types.PointerGrab) void {
        input.set_pointer_grabs(self.state, grabs);
    }

    /// river reports clicks on windows as window_interaction; whether they
    /// focus is decided here rather than by a grab.
    pub fn set_click_to_focus(self: *Backend, enabled: bool) void {
        self.state.click_to_focus = enabled;
    }

    /// Start an interactive pointer op: motion arrives as op_delta.
    pub fn capture_pointer(self: *const Backend) void {
        input.capture_pointer(self.state);
    }

    pub fn release_pointer(self: *const Backend) void {
        input.release_pointer(self.state);
    }

    pub fn pointer_position(self: *const Backend) types.Point {
        return self.state.pointer_pos;
    }

    pub fn warp_pointer(self: *const Backend, p: types.Point) void {
        const s = self.state;
        s.warp = p;
        s.mark();
    }

    pub fn set_cursor_theme(self: *const Backend, theme: []const u8, size: u32) void {
        const s = self.state;
        const owned = s.allocator.dupeZ(u8, theme) catch return;
        if (s.cursor_theme) |old| s.allocator.free(old);
        s.cursor_theme = owned;
        s.cursor_size = size;
        if (s.seat) |seat| seat.setXcursorTheme(owned.ptr, size);
    }

    pub fn set_keymap(self: *Backend, km: types.Keymap) bool {
        const s = self.state;
        const config = s.xkb_config orelse return false;

        var arena = std.heap.ArenaAllocator.init(s.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const z = struct {
            fn f(al: std.mem.Allocator, v: []const u8) ?[*:0]const u8 {
                if (v.len == 0) return null;
                return (al.dupeZ(u8, v) catch return null).ptr;
            }
        }.f;

        const ctx = xkb.Context.new(.no_flags) orelse return false;
        defer ctx.unref();
        var names: xkb.RuleNames = .{
            .rules = null,
            .model = z(a, km.model),
            .layout = z(a, km.layout),
            .variant = z(a, km.variant),
            .options = z(a, km.options),
        };
        const keymap = xkb.Keymap.newFromNames(ctx, &names, .no_flags) orelse return false;
        defer keymap.unref();
        const text = keymap.getAsString(.text_v1) orelse return false;
        defer std.c.free(text);
        const bytes = std.mem.span(text);

        // river mmaps this: a sealed memfd holding the keymap text plus its NUL.
        const fd = c.memfd_create("duckwm-keymap", c.MFD_CLOEXEC | c.MFD_ALLOW_SEALING);
        if (fd < 0) return false;
        defer _ = c.close(fd);
        if (c.write(fd, bytes.ptr, bytes.len + 1) != @as(isize, @intCast(bytes.len + 1))) return false;
        _ = c.fcntl(fd, c.F_ADD_SEALS, c.F_SEAL_SHRINK | c.F_SEAL_GROW | c.F_SEAL_WRITE | c.F_SEAL_SEAL);

        const obj = config.createKeymap(fd, .text_v1) catch return false;
        obj.setListener(*State, keymap_listener, s);
        s.pending_keymap = obj; // any earlier pending one is destroyed when it answers
        return true;
    }

    pub fn set_layout_index(self: *Backend, index: u32) void {
        const s = self.state;
        s.layout_index = index;
        for (s.keyboards.items) |kb| kb.setLayoutByIndex(@intCast(index));
    }

    pub fn set_animation(self: *Backend, a: types.Animation) void {
        const s = self.state;
        s.anim = a;
        if (a.duration_ms == 0) {
            var it = s.windows.valueIterator();
            while (it.next()) |wp| wp.*.anim_active = false;
        }
    }

    /// While animating, wake up in time for the next frame.
    pub fn poll_timeout(self: *const Backend) i32 {
        const s = self.state;
        const now = now_ms();
        var wait: ?i64 = null;
        if (s.animating) wait = s.last_frame_ms + frame_interval_ms - now;
        if (s.repeat_key != null) {
            const w = s.repeat_next_ms - now;
            wait = if (wait) |x| @min(x, w) else w;
        }
        if (s.prompt_bar) |b| if (b.deadline) |d| {
            wait = if (wait) |x| @min(x, d - now) else d - now;
        };
        const w = wait orelse return -1;
        return @intCast(std.math.clamp(w, 0, std.math.maxInt(i32)));
    }

    pub fn outputs(self: *Backend, buf: []types.OutputInfo) []types.OutputInfo {
        return output.list(self.state, buf);
    }
};
