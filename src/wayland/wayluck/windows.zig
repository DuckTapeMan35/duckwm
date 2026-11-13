const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const pointer = @import("pointer.zig");
const outputs = @import("outputs.zig");
const sharing = @import("sharing.zig");
const workspaces = @import("workspaces.zig");
const layers = @import("layers.zig");

const wl = wayland.client.wl;
const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;

pub const Window = struct {
    state: *State,
    obj: *wayluck.WmWindowV1,
    handle: types.WindowHandle,
    info: types.WindowInfo = .{},
    /// wayluck has said all it has to about it (its first done): core hears
    /// of it at the end of the dispatch.
    ready: bool = false,
    /// map_request has been sent to core.
    announced: bool = false,
    /// When core last raised it: floating windows stack by it.
    raise_serial: u64 = 0,
    /// Its client asked to be fullscreen before core knew it: core reads
    /// it in window_hints when it maps it.
    wants_fullscreen: bool = false,
    /// The window it belongs to (a dialog's main window): it floats.
    parent: ?types.WindowHandle = null,
    /// What its client says it is.
    kind: wayluck.WmWindowV1.Kind = .normal,
    /// How its client would like it kept (above the others, its aspect).
    hints: wayluck.WmWindowV1.Hint = .{},
    /// It wants the user's attention (urgent).
    attention: bool = false,
    /// Its client's smallest and largest size (0: no limit).
    min: types.Size = .{ .width = 0, .height = 0 },
    max: types.Size = .{ .width = 0, .height = 0 },
    /// The number of the workspace core published it's on.
    workspace: ?u32 = null,
    /// What wayluck was last told about it: a transaction says only what changed.
    sent: Sent = .{},
};

/// null: not told yet. A window hidden keeps all but where it was.
pub const Sent = struct {
    /// Its scene and place's rectangle there (null: in none).
    at: ?At = null,
    tiled: ?u32 = null,
    fullscreen: ?bool = null,
    border: ?Border = null,
    shadow: ?types.Shadow = null,
    blur: ?types.Blur = null,
    workspace: ?*wayluck.WmWorkspaceV1 = null,
};

const Border = struct { width: u32, colors: types.BorderColors, radius: u32 };

/// order: when it was placed (State.place_clock); a scene stacks its
/// windows by it, the last placed on top.
const At = struct { scene: *wayluck.WmSceneV1, rect: types.Rect, order: u64 };

/// A size for core until the client has one (it's used if the window floats).
const default_size: types.Size = .{ .width = 640, .height = 480 };

/// The protocol's edges bits: top, bottom, left, right.
const all_edges: u32 = 1 | 2 | 4 | 8;

const null_colors: types.BorderColors = .{ .top = 0, .bottom = 0, .left = 0, .right = 0 };

/// wayluck announced a window, with its id: the window's handle, so wayluck's
/// log, core and quack all call it the same. What its client set up follows,
/// up to its first done: then core hears of it, names and all
/// (announce_fresh, at the end of the dispatch).
pub fn add(s: *State, obj: *wayluck.WmWindowV1, id: u32) void {
    const w = s.allocator.create(Window) catch return obj.destroy();
    w.* = .{ .state = s, .obj = obj, .handle = id };
    s.windows.put(s.allocator, w.handle, w) catch {
        s.allocator.destroy(w);
        return obj.destroy();
    };
    obj.setListener(*Window, listener, w);
}

/// Tell core about the windows that came in the last dispatch.
pub fn announce_fresh(s: *State) void {
    for (s.fresh.items) |w| {
        w.announced = true;
        s.push(.{ .map_request = .{
            .window = w.handle,
            .size = initial_size(w),
            .traits = traits_of(w),
        } });
    }
    s.fresh.clearRetainingCapacity();
}

fn listener(obj: *wayluck.WmWindowV1, event: wayluck.WmWindowV1.Event, w: *Window) void {
    const s = w.state;
    switch (event) {
        .app_id => |e| {
            // Wayland has one id where X had class and instance: fill both,
            // so rules written against either still match.
            const id = std.mem.span(e.app_id);
            w.info.set_class(id);
            w.info.set_instance(id);
            if (w.announced) s.push(.{ .info_changed = w.handle });
        },
        .title => |e| {
            w.info.set_title(std.mem.span(e.title));
            if (w.announced) s.push(.{ .info_changed = w.handle });
        },
        .focus_request => if (w.announced) pointer.clicked(s, w.handle),
        .pointer_enter => if (w.announced) pointer.entered(s, w.handle),
        .pointer_leave => pointer.left(s, w.handle),
        .fullscreen_request => fullscreen_request(s, w, .add),
        .unfullscreen_request => fullscreen_request(s, w, .remove),
        .parent => |e| w.parent = if (e.parent) |p| window_of(p).handle else null,
        .kind => |e| w.kind = e.kind,
        .hints => |e| w.hints = e.hints,
        .attention => |e| {
            w.attention = e.on != 0;
            if (w.announced) s.push(.{ .urgency_hint = .{ .window = w.handle, .urgent = w.attention } });
        },
        .activate_request => if (w.announced) s.push(.{ .activate_request = w.handle }),
        // Core has no workspace that's all of them: on all (null) is let be.
        .workspace_request => |e| if (w.announced) if (e.workspace) |ws| {
            if (workspaces.number_of(s, ws)) |n| {
                s.push(.{ .window_workspace_request = .{ .window = w.handle, .workspace = n } });
            }
        },
        .done => if (!w.announced and !w.ready) {
            w.ready = true;
            s.fresh.append(s.allocator, w) catch {};
        },
        .size_hints => |e| {
            w.min = .{ .width = nonneg(e.min_width), .height = nonneg(e.min_height) };
            w.max = .{ .width = nonneg(e.max_width), .height = nonneg(e.max_height) };
        },
        .closed => {
            if (w.announced) {
                s.push(.{ .window_gone = w.handle });
            } else for (s.fresh.items, 0..) |f, i| if (f == w) {
                _ = s.fresh.swapRemove(i);
                break;
            };
            if (s.hovered == w.handle) s.hovered = null;
            _ = s.windows.remove(w.handle);
            obj.destroy();
            s.allocator.destroy(w);
        },
    }
}

/// The handle of the window wayluck's object stands for.
fn handle_of(s: *State, obj: *wayluck.WmWindowV1) ?types.WindowHandle {
    var it = s.windows.valueIterator();
    while (it.next()) |w| if (w.*.obj == obj) return w.*.handle;
    return null;
}

/// The window behind wayluck's object: add() gives every window object its
/// *Window as listener data, and the two live and die together (and an
/// event never hands over an object already destroyed: libwayland makes it
/// null).
fn window_of(obj: *wayluck.WmWindowV1) *Window {
    return @ptrCast(@alignCast(obj.getUserData().?));
}

fn nonneg(v: i32) u32 {
    return @intCast(@max(v, 0));
}

// ---- what core is told ----
/// A window of one size (the same smallest and largest): it floats at it.
pub fn fixed_size(w: *const Window) ?types.Size {
    if (w.min.width == 0 or w.min.height == 0) return null;
    if (w.min.width != w.max.width or w.min.height != w.max.height) return null;
    return w.min;
}

/// Its size if it floats, until its client has drawn one.
fn initial_size(w: *const Window) types.Size {
    if (fixed_size(w)) |size| return size;
    return .{
        .width = @max(w.min.width, default_size.width),
        .height = @max(w.min.height, default_size.height),
    };
}

/// As the X backend reads an X window's type: one with a parent, or of a
/// passing kind (a dialog, a splash screen), floats over the others.
pub fn traits_of(w: *const Window) types.WindowTraits {
    const kind: types.WindowKind = switch (w.kind) {
        .dialog, .utility, .splash, .notification, .menu => .floating,
        .toolbar => .dock,
        .normal => .normal,
        _ => .normal,
    };
    return .{
        .kind = if (w.parent != null) .floating else kind,
        .transient_for = w.parent,
    };
}

/// A client asked to be fullscreen (add) or to stop (remove): core decides,
/// as for an X client's _NET_WM_STATE request.
fn fullscreen_request(s: *State, w: *Window, action: types.StateAction) void {
    if (!w.announced) {
        w.wants_fullscreen = action == .add;
        return;
    }
    s.push(.{ .state_request = .{ .window = w.handle, .action = action, .fullscreen = true, .attention = false } });
}

// ---- placing ----
// What core asks for in a turn is kept here, and sent as one transaction
// when the turn ends (commit): the order windows are placed in is their
// stacking, and core can still raise one after giving the scene.

/// Show what's in states (in this order) and hide every other window.
pub fn apply(s: *State, states: []const types.WindowState, fullscreen: ?types.WindowHandle) void {
    s.scene.clearRetainingCapacity();
    s.scene.appendSlice(s.allocator, states) catch {};
    s.fullscreen = fullscreen;
    s.dirty = true;
}

/// The group outlines to draw from now on.
pub fn outlines(s: *State, list: []const types.Outline) void {
    s.outlines.clearRetainingCapacity();
    s.outlines.appendSlice(s.allocator, list) catch {};
    s.dirty = true;
}

/// Hide one window.
pub fn hide(s: *State, h: types.WindowHandle) void {
    for (s.scene.items, 0..) |st, i| if (st.handle == h) {
        _ = s.scene.orderedRemove(i);
        s.dirty = true;
        return;
    };
}

/// Put h above the other floating windows.
pub fn raise(s: *State, h: types.WindowHandle) void {
    const w = s.windows.get(h) orelse return;
    s.raise_clock += 1;
    w.raise_serial = s.raise_clock;
    s.dirty = true;
}

/// Repaint h's border.
pub fn border(s: *State, h: types.WindowHandle, colors: types.BorderColors, width: u32) void {
    for (s.scene.items) |*st| if (st.handle == h) {
        st.borders = colors;
        st.border_width = width;
        s.dirty = true;
        return;
    };
}

/// Give h the keyboard (null: no window). false: h isn't a window wayluck has.
pub fn focus(s: *State, h: ?types.WindowHandle) bool {
    if (h) |handle| if (s.windows.get(handle) == null) return false;
    s.focus = .{ .to = h };
    return true;
}

/// End of core's turn: what it asked for, as one transaction.
pub fn commit(s: *State) void {
    if (!s.dirty and s.focus == null) return;
    const manager = s.manager orelse return;
    const tx = manager.transaction() catch return;
    // New offers are announced once it's applied, their windows placed.
    if (s.offers_changed) {
        s.offers_changed = false;
        tx.setListener(*State, offers_listener, s);
    } else {
        tx.setListener(*State, tx_listener, s);
    }
    // While core has the pointer (moving, resizing), every window it
    // places follows it at once.
    if (s.captured) tx.instant(null);
    if (s.dirty) {
        place_all(s, tx);
        workspaces.tell(s, tx);
        layers.tell(s, tx);
    }
    if (s.focus) |f| {
        const w: ?*Window = if (f.to) |h| s.windows.get(h) else null;
        tx.focus(if (w) |x| x.obj else null);
    }
    tx.commit();
    s.dirty = false;
    s.focus = null;
}

/// Bottom to top: tiled windows in the scene's order, then floating ones
/// by when they were raised, then the fullscreen one. Every other window is hidden.
fn place_all(s: *State, tx: *wayluck.WmTransactionV1) void {
    // Each output shows its own scene, laid out for its size.
    for (s.outputs.items) |o| if (o.scene) |scene| {
        const size: types.Size = .{ .width = o.rect.width, .height = o.rect.height };
        if (o.sent.size == null or !std.meta.eql(o.sent.size.?, size)) {
            tx.sceneSize(scene, @intCast(size.width), @intCast(size.height));
        }
        o.sent.size = size;
        if (!o.sent.shown) tx.show(o.obj, scene);
        o.sent.shown = true;
        place_outlines(s, tx, o, scene);
    };

    var order: std.ArrayListUnmanaged(types.WindowState) = .empty;
    defer order.deinit(s.allocator);
    for (s.scene.items) |st| {
        if (st.tiled and st.handle != s.fullscreen) order.append(s.allocator, st) catch return;
    }

    const floating_from = order.items.len;
    for (s.scene.items) |st| {
        if (!st.tiled and st.handle != s.fullscreen) order.append(s.allocator, st) catch return;
    }
    std.mem.sort(types.WindowState, order.items[floating_from..], s, struct {
        fn lt(st: *State, a: types.WindowState, b: types.WindowState) bool {
            return serial(st, a.handle) < serial(st, b.handle);
        }
    }.lt);
    if (s.fullscreen) |h| if (find(s.scene.items, h)) |st| order.append(s.allocator, st) catch return;

    // Each window in the scene of the output it's on.
    var on: std.ArrayListUnmanaged(types.WindowState) = .empty;
    defer on.deinit(s.allocator);
    for (s.outputs.items) |o| if (o.scene) |scene| {
        on.clearRetainingCapacity();
        for (order.items) |st| {
            if (outputs.of(s, st.frame) == o) on.append(s.allocator, st) catch return;
        }
        place_scene(s, tx, scene, o, on.items, s.fullscreen);
    };

    // The picker's hidden workspaces, in scenes of their own.
    sharing.place(s, tx);
    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        if (wp.*.sent.at == null) continue; // in no scene already
        const h = wp.*.handle;
        if (find(s.scene.items, h) == null and !sharing.holds(s, h)) {
            tx.hide(wp.*.obj);
            wp.*.sent.at = null;
        }
    }
}

/// Show states in scene, bottom to top, relative to o's corner. Placing a
/// window puts it on top, so the windows below the lowest one that moved
/// (or isn't where it stacks) aren't placed again; it and all above it are.
pub fn place_scene(
    s: *State,
    tx: *wayluck.WmTransactionV1,
    scene: *wayluck.WmSceneV1,
    o: *const outputs.Output,
    states: []const types.WindowState,
    fullscreen: ?types.WindowHandle,
) void {
    // Those of them wayluck has there, as it stacks them.
    var now: std.ArrayListUnmanaged(*Window) = .empty;
    defer now.deinit(s.allocator);
    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        const at = wp.*.sent.at orelse continue;
        if (at.scene == scene and find(states, wp.*.handle) != null) now.append(s.allocator, wp.*) catch return;
    }
    std.mem.sort(*Window, now.items, {}, struct {
        fn lt(_: void, a: *Window, b: *Window) bool {
            return a.sent.at.?.order < b.sent.at.?.order;
        }
    }.lt);

    var i: usize = 0;
    var restack = false;
    for (states) |st| {
        const w = s.windows.get(st.handle) orelse continue; // a preview
        if (!w.announced) continue;
        const rect = rect_in(o, st);
        if (!restack) {
            restack = i >= now.items.len or now.items[i] != w or !std.meta.eql(w.sent.at.?.rect, rect);
            i += 1;
        }
        place_window(s, tx, scene, w, rect, st, fullscreen == st.handle, restack);
    }
}

/// Where st puts its window, relative to o's corner: core's rect is the
/// whole footprint, borders included; wayluck places the content, and
/// draws the border around it.
fn rect_in(o: *const outputs.Output, st: types.WindowState) types.Rect {
    const bw = st.border_width;
    return .{
        .x = st.frame.x - o.rect.x + @as(i32, @intCast(bw)),
        .y = st.frame.y - o.rect.y + @as(i32, @intCast(bw)),
        .width = @max(1, st.frame.width -| 2 * bw),
        .height = @max(1, st.frame.height -| 2 * bw),
    };
}

/// w as st says, at rect in scene; placed there (on top) if restack.
fn place_window(
    s: *State,
    tx: *wayluck.WmTransactionV1,
    scene: *wayluck.WmSceneV1,
    w: *Window,
    rect: types.Rect,
    st: types.WindowState,
    fullscreen: bool,
    restack: bool,
) void {
    if (restack) {
        tx.place(scene, w.obj, rect.x, rect.y, @intCast(rect.width), @intCast(rect.height));
        // Being dragged: it follows the pointer, not animated.
        if (st.interactive) tx.instant(w.obj);
        s.place_clock += 1;
        w.sent.at = .{ .scene = scene, .rect = rect, .order = s.place_clock };
    }
    const bw = st.border_width;

    // Tiled windows are told so: clients square their corners, and size
    // themselves exactly (foot rounds a floating one to whole cells).
    // A fullscreen one is told that instead, and drops its own chrome.
    const edges: u32 = if (st.tiled and !fullscreen) all_edges else 0;
    if (w.sent.tiled != edges) tx.tiled(w.obj, edges);
    w.sent.tiled = edges;
    if (w.sent.fullscreen != fullscreen) tx.fullscreen(w.obj, @intFromBool(fullscreen));
    w.sent.fullscreen = fullscreen;

    // null: no border (fullscreen, or borders turned off).
    const b: Border = if (st.borders) |colors|
        .{ .width = bw, .colors = colors, .radius = st.corner_radius }
    else
        .{ .width = 0, .colors = null_colors, .radius = st.corner_radius };
    if (w.sent.border == null or !std.meta.eql(w.sent.border.?, b)) set_border(tx, w, b);
    w.sent.border = b;
    const sh = st.shadow;
    if (w.sent.shadow == null or !std.meta.eql(w.sent.shadow.?, sh)) tx.shadow(w.obj, sh.blur, sh.spread, sh.x, sh.y, sh.color);
    w.sent.shadow = sh;
    if (w.sent.blur != st.blur) tx.blur(w.obj, switch (st.blur) {
        .client => .client,
        .on => .on,
        .off => .off,
    });
    w.sent.blur = st.blur;
}

/// scene is going: wayluck takes its windows out of it.
pub fn forget_scene(s: *State, scene: *wayluck.WmSceneV1) void {
    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        if (wp.*.sent.at) |at| {
            if (at.scene == scene) wp.*.sent.at = null;
        }
    }
}

/// How strongly what's behind windows is blurred: halved passes times and
/// doubled back, sampled offset pixels apart.
pub fn set_blur(s: *State, passes: u32, offset: f32) void {
    const manager = s.manager orelse return;
    manager.setBlur(passes, wayland.client.wl.Fixed.fromDouble(offset));
}

/// How windows move to where they're placed: wayluck draws them on their
/// way there, over a.duration_ms, along a's curve (core's table, at evenly
/// spaced times, sent as it is). A duration of 0: they don't move.
pub fn set_animation(s: *State, a: types.Animation) void {
    const manager = s.manager orelse return;
    var curve = a.curve;
    var array: wl.Array = .{
        .size = @sizeOf(types.CurveTable),
        .alloc = @sizeOf(types.CurveTable),
        .data = &curve,
    };
    manager.setAnimation(a.duration_ms, &array);
}

/// The outlines on o, in its scene, relative to its corner (all of them:
/// the transaction says every outline the scene has).
fn place_outlines(s: *State, tx: *wayluck.WmTransactionV1, o: *outputs.Output, scene: *wayluck.WmSceneV1) void {
    // The same as last time: nothing to say.
    var hash = std.hash.Wyhash.init(0);
    hash.update(std.mem.asBytes(&o.rect));
    for (s.outlines.items) |ol| {
        if (outputs.of(s, ol.rect) != o) continue;
        hash.update(std.mem.asBytes(&ol.rect));
        hash.update(std.mem.asBytes(&ol.clip));
        hash.update(std.mem.asBytes(&ol.width));
        hash.update(std.mem.asBytes(&ol.color));
        hash.update(std.mem.asBytes(&ol.corner_radius));
    }
    const sum = hash.final();
    if (o.sent.outlines == sum) return;
    o.sent.outlines = sum;
    tx.outlines(scene);
    for (s.outlines.items) |ol| {
        if (outputs.of(s, ol.rect) != o) continue;
        const opaque_ = 0xff000000;
        tx.outline(
            scene,
            ol.rect.x - o.rect.x,
            ol.rect.y - o.rect.y,
            @intCast(ol.rect.width),
            @intCast(ol.rect.height),
            ol.clip.x - o.rect.x,
            ol.clip.y - o.rect.y,
            @intCast(ol.clip.width),
            @intCast(ol.clip.height),
            ol.width,
            ol.color | opaque_,
            ol.corner_radius,
        );
    }
}

fn serial(s: *State, h: types.WindowHandle) u64 {
    return if (s.windows.get(h)) |w| w.raise_serial else 0;
}

/// duckwm's colours are 0xRRGGBB; wayluck's have alpha too, opaque here.
fn set_border(tx: *wayluck.WmTransactionV1, w: *Window, b: Border) void {
    const opaque_ = 0xff000000;
    const c = b.colors;
    tx.border(w.obj, b.width, c.top | opaque_, c.right | opaque_, c.bottom | opaque_, c.left | opaque_, b.radius);
}

fn find(states: []const types.WindowState, h: types.WindowHandle) ?types.WindowState {
    for (states) |st| if (st.handle == h) return st;
    return null;
}

/// A transaction is done with once wayluck answers.
fn tx_listener(tx: *wayluck.WmTransactionV1, event: wayluck.WmTransactionV1.Event, s: *State) void {
    switch (event) {
        .applied => {},
        // A window closed before wayluck got it, say: none of it was
        // applied, so the next transaction says everything again.
        .failed => |e| {
            std.debug.print("duckwm: wayluck didn't apply a transaction: {s}\n", .{e.reason});
            var it = s.windows.valueIterator();
            while (it.next()) |w| w.*.sent = .{};
            for (s.outputs.items) |o| o.sent = .{};
            workspaces.forget_sent(s);
            layers.forget_sent(s);
            s.dirty = true;
        },
    }
    tx.destroy();
}

/// As tx_listener, and then wayluck hears of the workspaces it laid out.
fn offers_listener(tx: *wayluck.WmTransactionV1, event: wayluck.WmTransactionV1.Event, s: *State) void {
    tx_listener(tx, event, s);
    sharing.announce(s);
}
