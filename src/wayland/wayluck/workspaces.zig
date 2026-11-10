const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;

pub const Workspace = struct {
    state: *State,
    obj: *wayluck.WmWorkspaceV1,
    /// What wayluck was last told of it: its name (its number), and
    /// whether it's the current one (null: nothing yet).
    named: bool = false,
    active: ?bool = null,
};

/// What core last published.
pub const Published = struct { count: u32, current: u32 };

/// Core has count workspaces, current the one shown: wayluck hears in the
/// turn's transaction.
pub fn publish(s: *State, count: u32, current: u32) void {
    s.published = .{ .count = count, .current = current };
    s.dirty = true;
}

/// Window h is on the workspace core published as index.
pub fn publish_window(s: *State, h: types.WindowHandle, index: u32) void {
    const w = s.windows.get(h) orelse return;
    w.workspace = index;
    s.dirty = true;
}

/// In the turn's transaction: as many workspaces as core has, named by
/// their number, the current one active, and each window on its own.
pub fn tell(s: *State, tx: *wayluck.WmTransactionV1) void {
    const manager = s.manager orelse return;
    const published = s.published orelse return;
    // Made and destroyed at the end only: each number keeps its object.
    while (s.workspaces.items.len > published.count) {
        const ws = s.workspaces.pop().?;
        var it = s.windows.valueIterator();
        while (it.next()) |w| if (w.*.sent.workspace == ws.obj) {
            w.*.sent.workspace = null;
        };
        ws.obj.destroy();
        s.allocator.destroy(ws);
    }
    while (s.workspaces.items.len < published.count) {
        const obj = manager.workspace() catch return;
        const ws = s.allocator.create(Workspace) catch return obj.destroy();
        ws.* = .{ .state = s, .obj = obj };
        s.workspaces.append(s.allocator, ws) catch {
            s.allocator.destroy(ws);
            return obj.destroy();
        };
        obj.setListener(*Workspace, listener, ws);
    }
    for (s.workspaces.items, 0..) |ws, i| {
        if (!ws.named) {
            var buf: [12]u8 = undefined;
            const name = std.mem.printSentinel(&buf, "{d}", .{i + 1}, 0) catch unreachable;
            tx.workspaceName(ws.obj, name);
            ws.named = true;
        }
        const active = i == published.current;
        if (ws.active != active) tx.workspaceState(ws.obj, .{ .active = active });
        ws.active = active;
    }
    var it = s.windows.valueIterator();
    while (it.next()) |wp| {
        const w = wp.*;
        const index = w.workspace orelse continue;
        if (index >= s.workspaces.items.len) continue;
        const obj = s.workspaces.items[index].obj;
        if (w.sent.workspace == obj) continue;
        tx.windowWorkspace(w.obj, obj);
        w.sent.workspace = obj;
    }
}

/// A transaction failed: the next says everything again.
pub fn forget_sent(s: *State) void {
    for (s.workspaces.items) |ws| {
        ws.named = false;
        ws.active = null;
    }
}

/// The number of the workspace behind obj.
pub fn number_of(s: *State, obj: *wayluck.WmWorkspaceV1) ?u32 {
    for (s.workspaces.items, 0..) |ws, i| if (ws.obj == obj) return @intCast(i);
    return null;
}

pub fn destroy_all(s: *State) void {
    for (s.workspaces.items) |ws| {
        ws.obj.destroy();
        s.allocator.destroy(ws);
    }
    s.workspaces.deinit(s.allocator);
}

fn listener(obj: *wayluck.WmWorkspaceV1, event: wayluck.WmWorkspaceV1.Event, ws: *Workspace) void {
    const s = ws.state;
    switch (event) {
        .activate_request => if (number_of(s, obj)) |n| s.push(.{ .workspace_request = n }),
    }
}
