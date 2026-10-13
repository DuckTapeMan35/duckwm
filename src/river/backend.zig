const std = @import("std");
const surface = @import("surface.zig");
const types = @import("types");
const wayland = @import("wayland");
const xkb = @import("xkbcommon");
const c = @import("rc");
const wl = wayland.client.wl;
const river = wayland.client.river;

const wm_version = 4;
const xkb_bindings_version = 1;
const layer_shell_version = 1;

/// river_seat_v1.modifiers has no Lock (2) or Mod2/NumLock (16) bit.
const valid_mods: u32 = 1 | 4 | 8 | 32 | 64 | 128;
const all_edges: u32 = 1 | 2 | 4 | 8; // top | bottom | left | right
const cap_fullscreen: u32 = 4;

/// Size reported for a new window that gave no size hints. Tiled windows are
/// resized by the solver anyway; this is what an unhinted dialog starts at.
const default_size: types.Size = .{ .width = 800, .height = 600 };

const error_bg: u32 = 0x8b1a1a;
const error_fg: u32 = 0xffffff;
const error_pad: i32 = 4;

const Preview = struct {
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

const ErrorBar = struct {
    surf: surface.ShellSurface,
    msg: []u8,
    height: u32,
    width: u32 = 0,
    dirty: bool = true,
};

const Stacked = struct { node: *river.NodeV1, serial: u64 };

const Window = struct {
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
};

const Output = struct {
    state: *State,
    obj: *river.OutputV1,
    layer: ?*river.LayerShellOutputV1 = null,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    /// Area left after layer-shell exclusive zones, in global coordinates.
    usable: ?types.Rect = null,
    default_pending: bool = false,
};

const KeyBinding = struct {
    state: *State,
    combo: types.KeyCombo,
    obj: ?*river.XkbBindingV1 = null,
    enabled: bool = false,
};

const ButtonBinding = struct {
    state: *State,
    /// X-style button number, which is what core speaks.
    button: types.Button,
    evdev: u32,
    mods: types.Mods,
    obj: ?*river.PointerBindingV1 = null,
    enabled: bool = false,
};

// State is heap-allocated, because libwayland keeps pointers to it in listeners
// and the Backend value itself gets copied into WM.
const State = struct {
    allocator: std.mem.Allocator,
    display: *wl.Display,
    registry: *wl.Registry,

    wm: ?*river.WindowManagerV1 = null,
    xkb_bindings: ?*river.XkbBindingsV1 = null,
    xkb_config: ?*river.XkbConfigV1 = null,
    keyboards: std.ArrayListUnmanaged(*river.XkbKeyboardV1) = .empty,
    /// Accepted by river and applied to every keyboard, including new ones.
    keymap: ?*river.XkbKeymapV1 = null,
    /// Sent, waiting for river's success/failure.
    pending_keymap: ?*river.XkbKeymapV1 = null,
    layout_index: ?u32 = null,
    layer_shell: ?*river.LayerShellV1 = null,
    seat: ?*river.SeatV1 = null,
    layer_seat: ?*river.LayerShellSeatV1 = null,
    outputs: std.ArrayListUnmanaged(*Output) = .empty,
    /// Until multimonitor: the first output is "the screen".
    primary: ?*Output = null,

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
    previews: std.AutoHashMapUnmanaged(types.WindowHandle, *Preview) = .empty,
    error_bar: ?*ErrorBar = null,
    scratch: std.ArrayListUnmanaged(Stacked) = .empty,

    // Input.
    keys: std.ArrayListUnmanaged(*KeyBinding) = .empty,
    buttons: std.ArrayListUnmanaged(*ButtonBinding) = .empty,
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

    fn push(s: *State, ev: types.Event) void {
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
    fn mark(s: *State) void {
        if (!s.in_manage) s.want_manage = true;
    }

    fn live(s: *State, h: types.WindowHandle) ?*Window {
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

    // ---- windows ----

    fn add_window(s: *State, obj: *river.WindowV1) void {
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

    fn window_closed(s: *State, w: *Window) void {
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

    fn destroy_dead(s: *State) void {
        for (s.dead.items) |w| {
            _ = s.windows.remove(w.handle);
            _ = s.by_obj.remove(w.obj);
            w.node.destroy();
            w.obj.destroy();
            s.allocator.destroy(w);
        }
        s.dead.clearRetainingCapacity();
    }

    fn handle_of(s: *State, obj: ?*river.WindowV1) ?types.WindowHandle {
        const o = obj orelse return null;
        const w = s.by_obj.get(o) orelse return null;
        return if (w.announced and !w.closed) w.handle else null;
    }

    // ---- outputs ----

    fn add_output(s: *State, obj: *river.OutputV1) void {
        const o = s.allocator.create(Output) catch return obj.destroy();
        o.* = .{ .state = s, .obj = obj };
        obj.setListener(*Output, output_listener, o);
        if (s.layer_shell) |ls| {
            if (ls.getOutput(obj)) |lo| {
                o.layer = lo;
                lo.setListener(*Output, layer_output_listener, o);
            } else |_| {}
        }
        s.outputs.append(s.allocator, o) catch {};
        if (s.primary == null) s.set_primary(o);
    }

    fn set_primary(s: *State, o: ?*Output) void {
        s.primary = o;
        if (o) |p| p.default_pending = true;
        s.push(.reserved_area_changed);
        s.mark();
    }

    fn remove_output(s: *State, o: *Output) void {
        for (s.outputs.items, 0..) |x, i| {
            if (x == o) {
                _ = s.outputs.orderedRemove(i);
                break;
            }
        }
        if (o.layer) |l| l.destroy();
        o.obj.destroy();
        if (s.primary == o) s.set_primary(if (s.outputs.items.len > 0) s.outputs.items[0] else null);
        s.allocator.destroy(o);
    }

    // ---- seats ----

    fn add_seat(s: *State, obj: *river.SeatV1) void {
        if (s.seat != null) return obj.destroy(); // one seat until there's a reason for more
        s.seat = obj;
        obj.setListener(*State, seat_listener, s);
        if (s.layer_shell) |ls| {
            if (ls.getSeat(obj)) |lseat| {
                s.layer_seat = lseat;
                lseat.setListener(*State, layer_seat_listener, s);
            } else |_| {}
        }
        if (s.cursor_theme) |t| obj.setXcursorTheme(t.ptr, s.cursor_size);
        s.mark(); // bindings waiting for a seat
    }

    // ---- sequences ----

    fn start_manage(s: *State) void {
        // Properties of new windows arrive before manage_start, so this is
        // the first point where a map_request carries complete information.
        for (s.fresh.items) |w| {
            if (w.closed) continue;
            w.announced = true;
            s.push(.{ .map_request = .{
                .window = w.handle,
                .size = initial_size(w),
                .traits = traits_of(w),
            } });
        }
        s.fresh.clearRetainingCapacity();
        s.in_manage = true;
        s.dirty_sent = false;
    }

    /// The window-management half: everything that must happen inside a manage sequence.
    fn send_manage(s: *State) void {
        if (s.primary) |p| {
            if (p.default_pending) {
                if (p.layer) |l| l.setDefault();
                p.default_pending = false;
            }
        }

        if (s.seat) |seat| {
            if (s.xkb_bindings) |kb| {
                for (s.keys.items) |k| {
                    if (k.obj == null) {
                        const obj = kb.getXkbBinding(seat, @intCast(k.combo.keysym), river_mods(k.combo.mods)) catch continue;
                        obj.setListener(*KeyBinding, key_listener, k);
                        k.obj = obj;
                    }
                    if (!k.enabled) {
                        k.obj.?.enable();
                        k.enabled = true;
                    }
                }
            }
            for (s.buttons.items) |b| {
                if (b.obj == null) {
                    const obj = seat.getPointerBinding(b.evdev, river_mods(b.mods)) catch continue;
                    obj.setListener(*ButtonBinding, button_listener, b);
                    b.obj = obj;
                }
                if (!b.enabled) {
                    b.obj.?.enable();
                    b.enabled = true;
                }
            }
        }

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
                if (s.primary) |p| {
                    w.obj.fullscreen(p.obj);
                    w.obj.informFullscreen();
                    w.fullscreen = true;
                }
            }

            if (!w.fullscreen and !size_eql(w.proposed, w.want_size)) {
                w.obj.proposeDimensions(@intCast(w.want_size.width), @intCast(w.want_size.height));
                w.proposed = w.want_size;
            }

            if (w.tiled == null or w.tiled.? != w.want_tiled) {
                w.obj.setTiled(@bitCast(if (w.want_tiled) all_edges else 0));
                w.tiled = w.want_tiled;
            }
        }

        if (s.focus_dirty) {
            s.focus_dirty = false;
            // While a layer surface holds exclusive focus, river ignores these anyway.
            if (s.seat) |seat| {
                if (!s.layer_focus_exclusive) {
                    if (s.focus) |h| {
                        if (s.live(h)) |w| {
                            seat.focusWindow(w.obj);
                        } else if (s.previews.get(h)) |p| {
                            seat.focusShellSurface(p.surf.shell);
                        }
                    } else {
                        seat.clearFocus();
                    }
                }
            }
        }

        if (s.seat) |seat| {
            if (s.op_start_pending) {
                seat.opStartPointer();
                s.op_start_pending = false;
            }
            if (s.op_end_pending) {
                seat.opEnd();
                s.op_end_pending = false;
            }
            if (s.warp) |p| {
                seat.pointerWarp(p.x, p.y);
                s.warp = null;
            }
        }
    }

    fn send_render(s: *State) void {
        const wm = s.wm orelse return;

        var it = s.windows.valueIterator();
        while (it.next()) |wp| {
            const w = wp.*;
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
                s.render_preview(p);
                if (p.want_tiled) {
                    p.surf.node.placeTop();
                } else {
                    s.scratch.append(s.allocator, .{ .node = p.surf.node, .serial = p.raise_serial }) catch {};
                }
                continue;
            }

            const w = s.live(h) orelse continue;
            if (!w.in_scene) continue;
            if (!w.shown) {
                w.obj.show();
                w.shown = true;
            }
            if (w.pos == null or w.pos.?.x != w.want_pos.x or w.pos.?.y != w.want_pos.y) {
                w.node.setPosition(w.want_pos.x, w.want_pos.y);
                w.pos = w.want_pos;
            }
            if (w.border_width != w.want_border_width or !opt_eql(w.border_color, w.want_border_color)) {
                send_borders(w);
            }

            if (s.fullscreen == w.handle) {
                fullscreen_node = w.node;
            } else if (w.want_tiled) {
                w.node.placeTop();
            } else {
                s.scratch.append(s.allocator, .{ .node = w.node, .serial = w.raise_serial }) catch {};
            }
        }

        std.mem.sort(Stacked, s.scratch.items, {}, struct {
            fn lt(_: void, a: Stacked, b: Stacked) bool {
                return a.serial < b.serial;
            }
        }.lt);
        for (s.scratch.items) |e| e.node.placeTop();
        if (fullscreen_node) |n| n.placeTop();
        s.render_error_bar();

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
        s.destroy_dead();
    }

    fn lost_connection(s: *State) void {
        _ = s;
        // river exited (or killed us). Nothing left to manage.
        std.debug.print("duckwm: lost connection to river, exiting\n", .{});
        std.process.exit(0);
    }

    fn render_preview(s: *State, p: *Preview) void {
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

    /// Across the top of the usable area; reserved_insets makes room for it.
    fn render_error_bar(s: *State) void {
        const bar = s.error_bar orelse return;
        const shm = s.shm orelse return;
        const o = s.primary orelse return;
        const area: types.Rect = o.usable orelse
            .{ .x = o.x, .y = o.y, .width = nonneg(o.width), .height = nonneg(o.height) };
        if (bar.dirty or !bar.surf.mapped or bar.width != area.width) {
            const content: surface.ErrorContent = .{
                .msg = bar.msg,
                .font = s.fonts.get(s.allocator, ""),
                .bg = error_bg,
                .fg = error_fg,
                .pad = error_pad,
            };
            bar.surf.draw(shm, area.width, bar.height, &content, surface.paint_error) catch return;
            bar.dirty = false;
            bar.width = area.width;
        }
        bar.surf.node.setPosition(area.x, area.y);
        bar.surf.node.placeTop();
    }

    fn destroy_error_bar(s: *State) bool {
        const bar = s.error_bar orelse return false;
        s.error_bar = null;
        bar.surf.destroy();
        s.allocator.free(bar.msg);
        s.allocator.destroy(bar);
        s.mark();
        return true;
    }

    fn shell_clicked(s: *State, shell: ?*river.ShellSurfaceV1) void {
        const sh = shell orelse return;
        if (s.error_bar) |bar| {
            if (bar.surf.shell == sh) {
                if (s.destroy_error_bar()) s.push(.reserved_area_changed);
                return;
            }
        }
        if (!s.click_to_focus) return;
        var it = s.previews.valueIterator();
        while (it.next()) |pp| {
            if (pp.*.surf.shell != sh) continue;
            s.push(.{ .button_press = .{ .window = pp.*.handle, .button = 1, .mods = 0, .pos = s.pointer_pos } });
            return;
        }
    }
};

// --- Helpers ---
fn river_mods(m: types.Mods) river.SeatV1.Modifiers {
    return @bitCast(@as(u32, @intCast(m)) & valid_mods);
}

fn evdev_button(b: types.Button) ?u32 {
    return switch (b) {
        1 => 0x110, // BTN_LEFT
        2 => 0x112, // BTN_MIDDLE
        3 => 0x111, // BTN_RIGHT
        8 => 0x113, // BTN_SIDE
        9 => 0x114, // BTN_EXTRA
        else => null, // 4-7 are scroll axes, not buttons, on Wayland
    };
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

fn size_eql(a: types.Size, b: types.Size) bool {
    return a.width == b.width and a.height == b.height;
}

fn opt_eql(a: ?u32, b: ?u32) bool {
    if (a == null or b == null) return a == null and b == null;
    return a.? == b.?;
}

/// 0xRRGGBB to the protocol's four 32-bit (pre-multiplied, here opaque) components.
fn send_borders(w: *Window) void {
    const edges: river.WindowV1.Edges = @bitCast(if (w.want_border_color != null and w.want_border_width > 0) all_edges else 0);
    const bc = w.want_border_color orelse 0;
    const r: u32 = (bc >> 16) & 0xff;
    const g: u32 = (bc >> 8) & 0xff;
    const b: u32 = bc & 0xff;
    w.obj.setBorders(edges, @intCast(w.want_border_width), r * 0x01010101, g * 0x01010101, b * 0x01010101, 0xffffffff);
    w.border_width = w.want_border_width;
    w.border_color = w.want_border_color;
}

fn fixed_size(w: *const Window) ?types.Size {
    if (w.min.width == 0 or w.min.height == 0) return null;
    if (w.min.width != w.max.width or w.min.height != w.max.height) return null;
    return w.min;
}

fn initial_size(w: *const Window) types.Size {
    if (fixed_size(w)) |s| return s;
    return .{
        .width = @max(w.min.width, default_size.width),
        .height = @max(w.min.height, default_size.height),
    };
}

fn traits_of(w: *const Window) types.WindowTraits {
    return .{
        .kind = if (w.parent != null) .floating else .normal,
        .transient_for = w.parent,
    };
}

fn nonneg(v: i32) u32 {
    return @intCast(@max(0, v));
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
        .window => |e| s.add_window(e.id),
        .output => |e| s.add_output(e.id),
        .seat => |e| s.add_seat(e.id),
        else => {},
    }
}

fn window_listener(_: *river.WindowV1, event: river.WindowV1.Event, w: *Window) void {
    const s = w.state;
    switch (event) {
        .closed => s.window_closed(w),
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
        // dimensions: river positions content by the node, and core's
        // geometry is authoritative, so the actual size isn't needed yet.
        // Interactive move/resize requests from CSD, maximize, minimize and
        // the window menu are ignored for now (capabilities say so).
        else => {},
    }
}

fn output_listener(_: *river.OutputV1, event: river.OutputV1.Event, o: *Output) void {
    const s = o.state;
    switch (event) {
        .position => |e| {
            o.x = e.x;
            o.y = e.y;
            if (s.primary == o) s.push(.reserved_area_changed);
        },
        .dimensions => |e| {
            o.width = e.width;
            o.height = e.height;
            if (s.primary == o) s.push(.reserved_area_changed);
        },
        .removed => s.remove_output(o),
        else => {},
    }
}

fn layer_output_listener(_: *river.LayerShellOutputV1, event: river.LayerShellOutputV1.Event, o: *Output) void {
    switch (event) {
        .non_exclusive_area => |e| {
            o.usable = .{ .x = e.x, .y = e.y, .width = nonneg(e.width), .height = nonneg(e.height) };
            if (o.state.primary == o) o.state.push(.reserved_area_changed);
        },
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

fn seat_listener(_: *river.SeatV1, event: river.SeatV1.Event, s: *State) void {
    switch (event) {
        .pointer_position => |e| s.pointer_pos = .{ .x = e.x, .y = e.y },
        .pointer_enter => |e| {
            const h = s.handle_of(e.window);
            s.hovered = h;
            if (h) |win| s.push(.{ .pointer_enter = win });
        },
        .pointer_leave => s.hovered = null,
        .window_interaction => |e| {
            // Click-to-focus: core treats an unmodified press as "focus this".
            if (!s.click_to_focus) return;
            const h = s.handle_of(e.window) orelse return;
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

fn key_listener(_: *river.XkbBindingV1, event: river.XkbBindingV1.Event, k: *KeyBinding) void {
    switch (event) {
        .pressed => k.state.push(.{ .key = k.combo }),
        else => {},
    }
}

fn button_listener(_: *river.PointerBindingV1, event: river.PointerBindingV1.Event, b: *ButtonBinding) void {
    const s = b.state;
    switch (event) {
        .pressed => {
            s.op_button = b.button;
            s.push(.{ .button_press = .{ .window = s.hovered, .button = b.button, .mods = b.mods, .pos = s.pointer_pos } });
        },
        .released => {
            if (s.suppress_release) {
                s.suppress_release = false;
                return;
            }
            s.push(.{ .button_release = .{ .window = s.hovered, .button = b.button, .mods = b.mods, .pos = s.pointer_pos } });
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
        while (it.next()) |wp| s.allocator.destroy(wp.*);
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
        var pit = s.previews.valueIterator();
        while (pit.next()) |pp| {
            pp.*.surf.destroy();
            pp.*.arena.deinit();
            s.allocator.destroy(pp.*);
        }
        s.previews.deinit(s.allocator);
        _ = s.destroy_error_bar();
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
        return traits_of(w);
    }

    pub fn window_hints(self: *const Backend, h: types.WindowHandle) types.InitialHints {
        const w = self.state.windows.get(h) orelse return .{};
        return .{
            .fullscreen = w.wants_fullscreen,
            .fixed_size = fixed_size(w),
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
                // A preview is its own buffer: it covers the whole rect and paints
                // its border inside it.
                p.in_scene = true;
                p.want_pos = .{ .x = st.frame.x, .y = st.frame.y };
                p.want_size = .{ .width = @max(1, st.frame.width), .height = @max(1, st.frame.height) };
                p.want_tiled = st.tiled;
                p.want_border_width = st.border_width;
                p.want_border_color = if (st.borders) |b| b.top else null;
                s.order.append(s.allocator, st.handle) catch {};
                continue;
            }
            const w = s.live(st.handle) orelse continue; // e.g. preview placeholders
            const bw = st.border_width;
            // core's rect is the whole footprint; river's geometry is the
            // content, with borders drawn outside it.
            w.in_scene = true;
            w.want_pos = .{ .x = st.frame.x + @as(i32, @intCast(bw)), .y = st.frame.y + @as(i32, @intCast(bw)) };
            w.want_size = .{
                .width = @max(1, st.frame.width -| 2 * bw),
                .height = @max(1, st.frame.height -| 2 * bw),
            };
            w.want_tiled = st.tiled;
            w.want_border_width = bw;
            w.want_border_color = if (st.borders) |b| b.top else null;
            s.order.append(s.allocator, st.handle) catch {};
        }
        s.fullscreen = fullscreen;
        s.mark();
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
            p.want_border_color = colors.top;
            p.want_border_width = width;
            s.mark();
            return;
        }
        const w = s.live(h) orelse return;
        w.want_border_color = colors.top;
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
        const s = self.state;
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

    pub fn destroy_preview_window(self: *Backend, h: types.WindowHandle) void {
        const s = self.state;
        const p = (s.previews.fetchRemove(h) orelse return).value;
        p.surf.destroy();
        p.arena.deinit();
        s.allocator.destroy(p);
    }

    /// Copies the content; the buffer itself follows the scene rect at render time.
    pub fn draw_preview(self: *Backend, h: types.WindowHandle, size: types.Size, style: types.PreviewStyle, items: []const types.PreviewItem) void {
        _ = size;
        const s = self.state;
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

    pub fn show_error(self: *Backend, msg: []const u8) !void {
        const s = self.state;
        std.debug.print("duckwm error: {s}\n", .{msg});
        const wm = s.wm orelse return;
        const comp = s.compositor orelse return;
        const bar = s.error_bar orelse blk: {
            const b = try s.allocator.create(ErrorBar);
            errdefer s.allocator.destroy(b);
            b.* = .{ .surf = try surface.ShellSurface.create(wm, comp), .msg = &.{}, .height = 0 };
            s.error_bar = b;
            break :blk b;
        };
        const owned = try s.allocator.dupe(u8, msg);
        s.allocator.free(bar.msg);
        bar.msg = owned;
        const font_h: i32 = if (s.fonts.get(s.allocator, "")) |f| f.height else 16;
        bar.height = @intCast(font_h + 2 * error_pad);
        bar.dirty = true;
        s.mark();
    }

    pub fn hide_error(self: *Backend) bool {
        return self.state.destroy_error_bar();
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
        const s = self.state;
        const kb = s.allocator.create(KeyBinding) catch return;
        kb.* = .{ .state = s, .combo = k };
        s.keys.append(s.allocator, kb) catch return s.allocator.destroy(kb);
        s.mark();
    }

    pub fn ungrab_all_keys(self: *const Backend) void {
        const s = self.state;
        for (s.keys.items) |k| {
            if (k.obj) |o| o.destroy();
            s.allocator.destroy(k);
        }
        s.keys.clearRetainingCapacity();
    }

    /// A grab with no button covers left, middle and right, like X's AnyButton
    /// for the buttons that matter here.
    pub fn set_pointer_grabs(self: *Backend, grabs: []const types.PointerGrab) void {
        const s = self.state;
        for (s.buttons.items) |b| {
            if (b.obj) |o| o.destroy();
            s.allocator.destroy(b);
        }
        s.buttons.clearRetainingCapacity();

        for (grabs) |g| {
            const any = [_]types.Button{ 1, 2, 3 };
            const one = [_]types.Button{g.button orelse 1};
            const list: []const types.Button = if (g.button != null) &one else &any;
            for (list) |btn| {
                const ev = evdev_button(btn) orelse continue;
                const b = s.allocator.create(ButtonBinding) catch continue;
                b.* = .{ .state = s, .button = btn, .evdev = ev, .mods = g.mods };
                s.buttons.append(s.allocator, b) catch {
                    s.allocator.destroy(b);
                    continue;
                };
            }
        }
        s.mark();
    }

    /// river reports clicks on windows as window_interaction; whether they
    /// focus is decided here rather than by a grab.
    pub fn set_click_to_focus(self: *Backend, enabled: bool) void {
        self.state.click_to_focus = enabled;
    }

    /// Start an interactive pointer op: motion arrives as op_delta.
    pub fn capture_pointer(self: *const Backend) void {
        const s = self.state;
        if (s.op_active) return;
        s.op_active = true;
        s.op_start_pending = true;
        s.op_end_pending = false;
        s.op_origin = s.pointer_pos;
        s.mark();
    }

    pub fn release_pointer(self: *const Backend) void {
        const s = self.state;
        if (!s.op_active) return;
        s.op_active = false;
        if (s.op_start_pending) {
            s.op_start_pending = false; // never sent; nothing to end
        } else {
            s.op_end_pending = true;
            s.mark();
        }
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
};
