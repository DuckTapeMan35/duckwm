const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const pointer = @import("pointer.zig");
const outputs = @import("outputs.zig");
const sharing = @import("sharing.zig");

const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;

pub const Window = struct {
    state: *State,
    obj: *wayluck.WmWindowV1,
    handle: types.WindowHandle,
    info: types.WindowInfo = .{},
    /// map_request has been sent to core.
    announced: bool = false,
    /// When core last raised it: floating windows stack by it.
    raise_serial: u64 = 0,
    /// Its client asked to be fullscreen before core knew it: core reads
    /// it in window_hints when it maps it.
    wants_fullscreen: bool = false,
    /// The window it belongs to (a dialog's main window): it floats.
    parent: ?types.WindowHandle = null,
    /// Its client's smallest and largest size (0: no limit).
    min: types.Size = .{ .width = 0, .height = 0 },
    max: types.Size = .{ .width = 0, .height = 0 },
};

/// A size for core until the client has one (it's used if the window floats).
const default_size: types.Size = .{ .width = 640, .height = 480 };

/// The protocol's edges bits: top, bottom, left, right.
const all_edges: u32 = 1 | 2 | 4 | 8;

const null_colors: types.BorderColors = .{ .top = 0, .bottom = 0, .left = 0, .right = 0 };

/// wayluck announced a window, with its id: the window's handle, so wayluck's
/// log, core and quack all call it the same. What its client set up follows
/// in the same burst, so core hears of it at the end of the dispatch
/// (announce_fresh), names and all.
pub fn add(s: *State, obj: *wayluck.WmWindowV1, id: u32) void {
    const w = s.allocator.create(Window) catch return obj.destroy();
    w.* = .{ .state = s, .obj = obj, .handle = id };
    s.windows.put(s.allocator, w.handle, w) catch {
        s.allocator.destroy(w);
        return obj.destroy();
    };
    s.fresh.append(s.allocator, w) catch {};
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

/// A window with a parent (a dialog) floats, over it.
pub fn traits_of(w: *const Window) types.WindowTraits {
    return .{
        .kind = if (w.parent != null) .floating else .normal,
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

/// Repaint h's border (its colours changed: focus moved, say).
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
        tx.setListener(?*anyopaque, tx_listener, null);
    }
    if (s.dirty) place_all(s, tx);
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
        tx.sceneSize(scene, @intCast(o.rect.width), @intCast(o.rect.height));
        tx.show(o.obj, scene);
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

    for (order.items) |st| {
        const w = s.windows.get(st.handle) orelse continue; // a preview
        if (!w.announced) continue;
        // In the scene of the output it's on, relative to that output.
        const o = outputs.of(s, st.frame) orelse continue;
        const scene = o.scene orelse continue;
        place_window(tx, scene, o, w, st, s.fullscreen == st.handle);
    }
    // The picker's hidden workspaces, in scenes of their own.
    sharing.place(s, tx);
    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        const h = wp.*.handle;
        if (wp.*.announced and find(s.scene.items, h) == null and !sharing.holds(s, h)) tx.hide(wp.*.obj);
    }
}

/// Place w in scene as st says, relative to o's corner.
pub fn place_window(
    tx: *wayluck.WmTransactionV1,
    scene: *wayluck.WmSceneV1,
    o: *const outputs.Output,
    w: *Window,
    st: types.WindowState,
    fullscreen: bool,
) void {
    // core's rect is the whole footprint, borders included; wayluck
    // places the content, and draws the border around it.
    const bw = st.border_width;
    tx.place(
        scene,
        w.obj,
        st.frame.x - o.rect.x + @as(i32, @intCast(bw)),
        st.frame.y - o.rect.y + @as(i32, @intCast(bw)),
        @intCast(@max(1, st.frame.width -| 2 * bw)),
        @intCast(@max(1, st.frame.height -| 2 * bw)),
    );
    // Tiled windows are told so: clients square their corners, and size
    // themselves exactly (foot rounds a floating one to whole cells).
    // A fullscreen one is told that instead, and drops its own chrome.
    tx.tiled(w.obj, if (st.tiled and !fullscreen) all_edges else 0);
    tx.fullscreen(w.obj, @intFromBool(fullscreen));
    // null: no border (fullscreen, or borders turned off).
    if (st.borders) |b| set_border(tx, w, bw, b) else set_border(tx, w, 0, null_colors);
}

fn serial(s: *State, h: types.WindowHandle) u64 {
    return if (s.windows.get(h)) |w| w.raise_serial else 0;
}

/// duckwm's colours are 0xRRGGBB; wayluck's have alpha too, opaque here.
fn set_border(tx: *wayluck.WmTransactionV1, w: *Window, width: u32, b: types.BorderColors) void {
    const opaque_ = 0xff000000;
    tx.border(w.obj, width, b.top | opaque_, b.right | opaque_, b.bottom | opaque_, b.left | opaque_);
}

fn find(states: []const types.WindowState, h: types.WindowHandle) ?types.WindowState {
    for (states) |st| if (st.handle == h) return st;
    return null;
}

/// A transaction is done with once wayluck answers.
fn tx_listener(tx: *wayluck.WmTransactionV1, event: wayluck.WmTransactionV1.Event, _: ?*anyopaque) void {
    switch (event) {
        .applied => {},
        // A window closed before wayluck got it, say: the next scene fixes it.
        .failed => |e| std.debug.print("duckwm: wayluck didn't apply a transaction: {s}\n", .{e.reason}),
    }
    tx.destroy();
}

/// As tx_listener, and then wayluck hears of the workspaces it laid out.
fn offers_listener(tx: *wayluck.WmTransactionV1, event: wayluck.WmTransactionV1.Event, s: *State) void {
    tx_listener(tx, event, null);
    sharing.announce(s);
}
