const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const pointer = @import("pointer.zig");
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
};

/// A size for core until the client has one (it's used if the window floats).
const default_size: types.Size = .{ .width = 640, .height = 480 };

/// The protocol's edges bits: top, bottom, left, right.
const all_edges: u32 = 1 | 2 | 4 | 8;

const null_colors: types.BorderColors = .{ .top = 0, .bottom = 0, .left = 0, .right = 0 };

/// wayluck announced a window. Its names follow in the same burst, so core
/// hears of it at the end of the dispatch (announce_fresh), names and all.
pub fn add(s: *State, obj: *wayluck.WmWindowV1) void {
    const w = s.allocator.create(Window) catch return obj.destroy();
    w.* = .{ .state = s, .obj = obj, .handle = s.next_handle };
    s.next_handle += 1;
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
        s.push(.{ .map_request = .{ .window = w.handle, .size = default_size, .traits = .{} } });
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
    tx.setListener(?*anyopaque, tx_listener, null);
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
/// by when they were raised, then the fullscreen one. Every other window
/// is hidden.
fn place_all(s: *State, tx: *wayluck.WmTransactionV1) void {
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
        // core's rect is the whole footprint, borders included; wayluck
        // places the content, and draws the border around it.
        const bw = st.border_width;
        tx.place(
            w.obj,
            st.frame.x + @as(i32, @intCast(bw)),
            st.frame.y + @as(i32, @intCast(bw)),
            @intCast(@max(1, st.frame.width -| 2 * bw)),
            @intCast(@max(1, st.frame.height -| 2 * bw)),
        );
        // Tiled windows are told so: clients square their corners, and size
        // themselves exactly (foot rounds a floating one to whole cells).
        // A fullscreen one is told that instead, and drops its own chrome.
        const fullscreen = s.fullscreen == st.handle;
        tx.tiled(w.obj, if (st.tiled and !fullscreen) all_edges else 0);
        tx.fullscreen(w.obj, @intFromBool(fullscreen));
        // null: no border (fullscreen, or borders turned off).
        if (st.borders) |b| set_border(tx, w, bw, b) else set_border(tx, w, 0, null_colors);
    }
    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        if (wp.*.announced and find(s.scene.items, wp.*.handle) == null) tx.hide(wp.*.obj);
    }
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
