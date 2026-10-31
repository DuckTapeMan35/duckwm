// sharing is caring!

const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;
const outputs = @import("outputs.zig");
const windows = @import("windows.zig");

pub const Offer = struct {
    /// core's: the same for as long as the workspace exists.
    key: usize,
    /// Its output (duckwm's id).
    output: u32,
    name: [:0]u8,
    /// Hidden: its own scene (shown: none, its output's holds it).
    scene: ?*wayluck.WmSceneV1,
    /// Hidden: its windows, where core would put them.
    windows: []types.WindowState,
};

/// A virtual output wayluck made to share a workspace (its offer's key).
pub const Share = struct {
    state: *State,
    obj: *wayluck.WmOutputV1,
    key: usize,
};

/// What core offers now (nothing: the picker closed). A workspace offered
/// again keeps its scene.
pub fn offer(s: *State, offers: []const types.WorkspaceOffer) void {
    var next: std.ArrayListUnmanaged(Offer) = .empty;
    for (offers) |o| {
        const old = take(s, o.key);
        const scene: ?*wayluck.WmSceneV1 = if (o.shown) null else if (old) |x| x.scene else null;
        const name = s.allocator.dupeSentinel(u8, o.name, 0) catch continue;
        const states = s.allocator.dupe(types.WindowState, o.windows) catch {
            s.allocator.free(name);
            continue;
        };
        if (old) |x| free(s, x, scene != null);
        next.append(s.allocator, .{
            .key = o.key,
            .output = o.output,
            .name = name,
            .scene = scene orelse if (o.shown) null else new_scene(s),
            .windows = states,
        }) catch {};
    }
    // Workspaces no longer offered: their scenes go.
    for (s.offers.items) |x| free(s, x, false);
    s.offers.deinit(s.allocator);
    s.offers = next;
    s.offers_changed = true;
    s.dirty = true;
}

/// Before the backend goes: what offers and shares hold.
pub fn deinit(s: *State) void {
    for (s.offers.items) |x| free(s, x, false);
    s.offers.deinit(s.allocator);
    for (s.shares.items) |sh| {
        sh.obj.destroy();
        s.allocator.destroy(sh);
    }
    s.shares.deinit(s.allocator);
}

fn new_scene(s: *State) ?*wayluck.WmSceneV1 {
    const m = s.manager orelse return null;
    return m.scene() catch null;
}

/// The offer with this key, out of the list.
fn take(s: *State, key: usize) ?Offer {
    for (s.offers.items, 0..) |x, i| if (x.key == key) return s.offers.swapRemove(i);
    return null;
}

/// Free what an offer holds; its scene too, unless kept.
fn free(s: *State, x: Offer, keep_scene: bool) void {
    if (!keep_scene) if (x.scene) |scene| scene.destroy();
    s.allocator.free(x.name);
    s.allocator.free(x.windows);
}

/// The user shared the workspace offered with scene: obj shows it (and
/// core keeps it laid out) until capture stops.
pub fn share(s: *State, obj: *wayluck.WmOutputV1, scene: *wayluck.WmSceneV1) void {
    const key = key_of(s, scene) orelse return obj.destroy();
    const sh = s.allocator.create(Share) catch return obj.destroy();
    sh.* = .{ .state = s, .obj = obj, .key = key };
    obj.setListener(*Share, share_listener, sh);
    s.shares.append(s.allocator, sh) catch {};
    s.push(.{ .workspace_shared = key });
    s.dirty = true;
}

/// The key of the workspace offered with scene (its own, or its output's).
fn key_of(s: *State, scene: *wayluck.WmSceneV1) ?usize {
    for (s.offers.items) |x| {
        const own = x.scene orelse if (outputs.find(s, x.output)) |o| o.scene else null;
        if (own == scene) return x.key;
    }
    return null;
}

/// Nothing captures it any more: it goes, and core stops keeping the
/// workspace laid out for it.
fn share_listener(_: *wayluck.WmOutputV1, event: wayluck.WmOutputV1.Event, sh: *Share) void {
    if (event != .capture_stopped) return;
    const s = sh.state;
    for (s.shares.items, 0..) |x, i| if (x == sh) {
        _ = s.shares.swapRemove(i);
        break;
    };
    s.push(.{ .workspace_unshared = sh.key });
    sh.obj.destroy();
    s.allocator.destroy(sh);
    s.dirty = true;
}

/// In the turn's transaction: hidden workspaces laid out in their scenes,
/// each the size of its output; shared ones shown on their outputs.
pub fn place(s: *State, tx: *wayluck.WmTransactionV1) void {
    for (s.offers.items) |x| {
        const scene = x.scene orelse continue;
        const o = outputs.find(s, x.output) orelse continue;
        tx.sceneSize(scene, @intCast(o.rect.width), @intCast(o.rect.height));
        for (x.windows) |st| {
            const w = s.windows.get(st.handle) orelse continue;
            if (w.announced) windows.place_window(tx, scene, o, w, st, false);
        }
    }
    for (s.shares.items) |sh| {
        const x = for (s.offers.items) |x| {
            if (x.key == sh.key) break x;
        } else continue;
        const o = outputs.find(s, x.output) orelse continue;
        if (x.scene orelse o.scene) |scene| tx.show(sh.obj, scene);
    }
}

/// Is h laid out in a hidden workspace offered (so not to be hidden)?
pub fn holds(s: *State, h: types.WindowHandle) bool {
    for (s.offers.items) |x| {
        if (x.scene == null) continue;
        for (x.windows) |st| if (st.handle == h) return true;
    }
    return false;
}

/// The transaction laying them out is applied: wayluck hears of them.
pub fn announce(s: *State) void {
    const m = s.manager orelse return;
    for (s.offers.items) |x| {
        const o = outputs.find(s, x.output) orelse continue;
        const scene = x.scene orelse o.scene orelse continue;
        m.offerWorkspace(scene, o.obj, x.name);
    }
    if (s.picking) {
        m.offersDone();
        s.picking = false;
    }
}
