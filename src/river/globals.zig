const std = @import("std");
const output = @import("outputs.zig");
const windows = @import("windows.zig");
const input = @import("input.zig");
const keyboard = @import("keyboard.zig");
const sequence = @import("sequence.zig");
const wayland = @import("wayland");

const wl = wayland.client.wl;
const river = wayland.client.river;
const State = @import("state.zig").State;

const wm_version = 4;
const xkb_bindings_version = 1;
const layer_shell_version = 1;

/// Bind the globals duckwm uses as the registry announces them.
pub fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, s: *State) void {
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
            } else if (std.mem.orderZ(u8, g.interface, wl.Seat.interface.name) == .eq) {
                // One seat until there's a reason for more, as with river_seat_v1.
                if (s.wl_seat != null) return;
                s.wl_seat = registry.bind(g.name, wl.Seat, @min(g.version, 5)) catch return;
                s.wl_seat.?.setListener(*State, keyboard.wl_seat_listener, s);
            } else if (std.mem.orderZ(u8, g.interface, river.XkbConfigV1.interface.name) == .eq) {
                s.xkb_config = registry.bind(g.name, river.XkbConfigV1, 1) catch return;
                s.xkb_config.?.setListener(*State, keyboard.xkb_config_listener, s);
            }
        },
        .global_remove => {},
    }
}

/// river_window_manager_v1: sequences starting, and new windows, outputs and seats.
pub fn wm_listener(_: *river.WindowManagerV1, event: river.WindowManagerV1.Event, s: *State) void {
    switch (event) {
        .unavailable => s.unavailable = true,
        .finished => s.finished = true,
        .manage_start => sequence.start_manage(s),
        .render_start => s.render_pending = true,
        .window => |e| windows.add(s, e.id),
        .output => |e| output.add(s, e.id),
        .seat => |e| input.add_seat(s, e.id),
        else => {},
    }
}
