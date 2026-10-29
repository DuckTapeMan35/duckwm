const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const windows = @import("windows.zig");

const wl = wayland.client.wl;
const wayluck = wayland.client.wayluck;

const Output = @import("outputs.zig").Output;
const Binding = @import("keys.zig").Binding;
const ButtonBinding = @import("pointer.zig").Binding;
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
    /// The keys core grabbed.
    bindings: std.ArrayListUnmanaged(*Binding) = .empty,
    /// The buttons core grabbed.
    buttons: std.ArrayListUnmanaged(*ButtonBinding) = .empty,
    pointer_pos: types.Point = .{ .x = 0, .y = 0 },
    /// The output it's on (duckwm's id); 0: not known yet.
    pointer_output: u32 = 0,
    /// The window it's over.
    hovered: ?types.WindowHandle = null,
    /// A drag is on: it's core's (capture_pointer).
    captured: bool = false,
    click_to_focus: bool = false,
    /// The windows to show, as core last gave them.
    scene: std.ArrayListUnmanaged(types.WindowState) = .empty,
    fullscreen: ?types.WindowHandle = null,
    /// The scene, a raise or a border changed since the last commit.
    dirty: bool = false,
    /// Focus to give, if core changed it.
    focus: ?struct { to: ?types.WindowHandle } = null,
    raise_clock: u64 = 0,
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
