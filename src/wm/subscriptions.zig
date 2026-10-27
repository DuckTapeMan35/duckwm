const std = @import("std");
const protocol = @import("protocol");
const types = @import("types");
const core = @import("core.zig");
const callbacks = @import("callbacks.zig");
const ipc = @import("ipc.zig");
const WM = core.WM;

pub const Subscription = struct { id: u32, topic: protocol.Topic, cb: types.Callback };

/// A change to tell subscribers about once its transaction commits (queued as
/// an effect, so a rolled-back one never is).
pub const Pending = struct { topic: protocol.Topic, id: ?u32 = null };

/// Queue p for the next deliver.
pub fn queue(wm: *WM, p: Pending) void {
    wm.effect(.{ .notice = p });
}

pub fn add(wm: *WM, topic: protocol.Topic, cb: types.Callback) !u32 {
    const id = wm.next_subscription_id;
    try wm.subscriptions.append(wm.allocator, .{ .id = id, .topic = topic, .cb = cb });
    wm.next_subscription_id += 1;
    return id;
}

pub fn remove(wm: *WM, id: u32) !void {
    for (wm.subscriptions.items, 0..) |s, i| {
        if (s.id != id) continue;
        wm.release_callback(s.cb);
        _ = wm.subscriptions.orderedRemove(i);
        return;
    }
    return error.UnknownSubscription;
}

/// Drop the subscriptions a client made (it's gone), or the Lua config's
/// (client null: it's about to run again).
pub fn drop(wm: *WM, client: ?u32) void {
    var i = wm.subscriptions.items.len;
    while (i > 0) {
        i -= 1;
        const mine = switch (wm.subscriptions.items[i].cb) {
            .lua => client == null,
            .remote => |r| client != null and r.client == client.?,
        };
        if (!mine) continue;
        wm.release_callback(wm.subscriptions.orderedRemove(i).cb);
    }
}

/// After a commit: tell the subscribers what changed since last time. Called
/// once the scene and focus have gone to the backend, so what they're told is
/// on screen.
pub fn deliver(wm: *WM) void {
    if (wm.scene_serial != wm.told_serial) {
        wm.told_serial = wm.scene_serial;
        tell(wm, .scene, null);
    }
    const focused: ?u32 = if (wm.focused) |f| wm.get_id_for_node(f) else null;
    if (focused != wm.told_focus) {
        wm.told_focus = focused;
        tell(wm, .focus, focused);
    }
    // Taken whole: what subscribers queue while being told waits for the
    // next commit, so one renaming on every rename can't spin here.
    var batch = wm.pending_notices;
    wm.pending_notices = .empty;
    defer batch.deinit(wm.allocator);
    for (batch.items) |p| tell(wm, p.topic, p.id);
}

/// Tell every subscription to topic. A Lua one runs in a transaction of its
/// own; a client's gets an Event, queued.
fn tell(wm: *WM, topic: protocol.Topic, id: ?u32) void {
    const notice: protocol.Notice = .{ .topic = topic, .serial = wm.scene_serial, .id = id };
    // By index, copying each: a callback may subscribe or unsubscribe.
    var i: usize = 0;
    while (i < wm.subscriptions.items.len) : (i += 1) {
        const s = wm.subscriptions.items[i];
        if (s.topic != topic) continue;
        switch (s.cb) {
            .remote => |r| ipc.send_event(wm, r.client, r.id, notice),
            .lua => {
                const m = wm.tx_begin();
                var arena = std.heap.ArenaAllocator.init(wm.allocator);
                defer arena.deinit();
                _ = callbacks.invoke(wm, s.cb, .{ .notice = notice }, arena.allocator()) catch {
                    wm.tx_end(m, false);
                    continue;
                };
                wm.tx_end(m, true);
            },
        }
    }
}

pub fn deinit(wm: *WM) void {
    wm.subscriptions.deinit(wm.allocator);
    wm.pending_notices.deinit(wm.allocator);
}
