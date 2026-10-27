const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;

pub const Window = struct {
    state: *State,
    obj: *wayluck.WmWindowV1,
    handle: types.WindowHandle,
    info: types.WindowInfo = .{},
    /// map_request has been sent to core.
    announced: bool = false,
};

/// A size for core until the client has one (it's used if the window floats).
const default_size: types.Size = .{ .width = 640, .height = 480 };

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
        // A click: core decides, as for any request to activate a window.
        .focus_request => if (w.announced) s.push(.{ .activate_request = w.handle }),
        .closed => {
            if (w.announced) {
                s.push(.{ .window_gone = w.handle });
            } else for (s.fresh.items, 0..) |f, i| if (f == w) {
                _ = s.fresh.swapRemove(i);
                break;
            };
            _ = s.windows.remove(w.handle);
            obj.destroy();
            s.allocator.destroy(w);
        },
    }
}

// ---- placing ----
/// Show what's in states and hide every other window
pub fn apply(s: *State, states: []const types.WindowState) void {
    const tx = transaction(s) orelse return;
    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        const w = wp.*;
        if (!w.announced) continue;
        if (find(states, w.handle)) |st| {
            // core's rect is the whole footprint, borders included; wayluck
            // places the content. (It draws no borders yet: they're a gap.)
            const bw = st.border_width;
            tx.place(
                w.obj,
                st.frame.x + @as(i32, @intCast(bw)),
                st.frame.y + @as(i32, @intCast(bw)),
                @intCast(@max(1, st.frame.width -| 2 * bw)),
                @intCast(@max(1, st.frame.height -| 2 * bw)),
            );
        } else {
            tx.hide(w.obj);
        }
    }
}

/// Hide one window.
pub fn hide(s: *State, h: types.WindowHandle) void {
    const w = s.windows.get(h) orelse return;
    const tx = transaction(s) orelse return;
    tx.hide(w.obj);
}

/// Give h the keyboard (null: no window). false: h isn't a window wayluck has.
pub fn focus(s: *State, h: ?types.WindowHandle) bool {
    const w: ?*Window = if (h) |handle| s.windows.get(handle) orelse return false else null;
    const tx = transaction(s) orelse return false;
    tx.focus(if (w) |x| x.obj else null);
    return true;
}

/// The transaction this turn's changes go into, started by the first.
fn transaction(s: *State) ?*wayluck.WmTransactionV1 {
    if (s.tx) |tx| return tx;
    const manager = s.manager orelse return null;
    const tx = manager.transaction() catch return null;
    tx.setListener(?*anyopaque, tx_listener, null);
    s.tx = tx;
    return tx;
}

/// End of core's turn: apply everything it asked for, together.
pub fn commit(s: *State) void {
    const tx = s.tx orelse return;
    tx.commit();
    s.tx = null;
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
