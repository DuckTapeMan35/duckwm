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
            // Each global is one interface, so at most one of these binds it.
            if (bind(registry, g, river.WindowManagerV1, wm_version)) |o| s.wm = o;
            if (bind(registry, g, river.XkbBindingsV1, xkb_bindings_version)) |o| s.xkb_bindings = o;
            // Binding this is what tells river duckwm supports layer shell (bars).
            if (bind(registry, g, river.LayerShellV1, layer_shell_version)) |o| s.layer_shell = o;
            if (bind(registry, g, wl.Compositor, 4)) |o| s.compositor = o;
            if (bind(registry, g, wl.Shm, 1)) |o| s.shm = o;
            // One seat until there's a reason for more, as with river_seat_v1.
            if (s.wl_seat == null) if (bind(registry, g, wl.Seat, 5)) |o| {
                s.wl_seat = o;
                o.setListener(*State, keyboard.wl_seat_listener, s);
            };
            if (bind(registry, g, river.XkbConfigV1, 1)) |o| {
                s.xkb_config = o;
                o.setListener(*State, keyboard.xkb_config_listener, s);
            }
            if (std.mem.orderZ(u8, g.interface, wl.Output.interface.name) == .eq) {
                s.wl_outputs.put(s.allocator, g.name, g.version) catch {};
            }
        },
        .global_remove => |g| _ = s.wl_outputs.remove(g.name),
    }
}

/// The global g bound as a T, at version max or the compositor's if lower;
/// null if g is another interface (or binding fails).
fn bind(registry: *wl.Registry, g: anytype, comptime T: type, max: u32) ?*T {
    if (std.mem.orderZ(u8, g.interface, T.interface.name) != .eq) return null;
    return registry.bind(g.name, T, @min(g.version, max)) catch null;
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
