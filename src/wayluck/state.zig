const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const windows = @import("windows.zig");

const wl = wayland.client.wl;
const wayluck = wayland.client.wayluck;

const Output = @import("outputs.zig").Output;
const Window = windows.Window;

pub const State = struct {
    allocator: std.mem.Allocator,
    display: *wl.Display,
    registry: *wl.Registry,
    manager: ?*wayluck.WmManagerV1 = null,
    /// Another window manager is bound: this one does nothing.
    unavailable: bool = false,
    /// wayluck has sent everything that existed when we bound.
    ready: bool = false,

    outputs: std.ArrayListUnmanaged(*Output) = .empty,
    next_output_id: u32 = 1,
    windows: std.AutoHashMapUnmanaged(types.WindowHandle, *Window) = .empty,
    /// Announced by wayluck in this dispatch, not yet to core.
    fresh: std.ArrayListUnmanaged(*Window) = .empty,
    next_handle: types.WindowHandle = 1,
    /// What core has asked for this turn, committed by flush_output.
    tx: ?*wayluck.WmTransactionV1 = null,
    /// Previews get handles far from the ones windows get.
    next_preview: types.WindowHandle = 1 << 32,

    /// Events for core, oldest first.
    events: std.ArrayListUnmanaged(types.Event) = .empty,
    event_head: usize = 0,

    /// Queue an event for core.
    pub fn push(s: *State, ev: types.Event) void {
        s.events.append(s.allocator, ev) catch {};
    }

    /// Read and dispatch whatever wayluck has sent, without blocking.
    pub fn pump(s: *State) void {
        const d = s.display;
        while (!d.prepareRead()) {
            if (d.dispatchPending() != .SUCCESS) return lost_connection();
        }
        _ = d.flush();
        // The main loop's poll may have woken for IPC, so the socket isn't
        // necessarily readable; readEvents would block.
        var pfd = [1]std.posix.pollfd{.{ .fd = d.getFd(), .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = std.posix.poll(&pfd, 0) catch 0;
        if (ready > 0) {
            if (d.readEvents() != .SUCCESS) return lost_connection();
        } else {
            d.cancelRead();
        }
        if (d.dispatchPending() != .SUCCESS) return lost_connection();
        windows.announce_fresh(s);
    }

    fn lost_connection() void {
        std.debug.print("duckwm: lost connection to wayluck, exiting\n", .{});
        std.process.exit(0);
    }
};
