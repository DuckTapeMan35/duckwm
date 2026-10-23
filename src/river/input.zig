const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const river = wayland.client.river;
const State = @import("state.zig").State;
const output = @import("outputs.zig");
const windows = @import("windows.zig");
const bars = @import("bars.zig");

/// river_seat_v1.modifiers has no Lock (2) or Mod2/NumLock (16) bit.
const valid_mods: u32 = 1 | 4 | 8 | 32 | 64 | 128;

pub const KeyBinding = struct {
    state: *State,
    combo: types.KeyCombo,
    obj: ?*river.XkbBindingV1 = null,
    enabled: bool = false,
};

pub const ButtonBinding = struct {
    state: *State,
    /// X-style button number, which is what core speaks.
    button: types.Button,
    evdev: u32,
    mods: types.Mods,
    obj: ?*river.PointerBindingV1 = null,
    enabled: bool = false,
};

// ---- seat ----

/// river announced a seat; duckwm drives the first one.
pub fn add_seat(s: *State, obj: *river.SeatV1) void {
    if (s.seat != null) return obj.destroy(); // one seat until there's a reason for more
    s.seat = obj;
    obj.setListener(*State, seat_listener, s);
    if (s.layer_shell) |ls| {
        if (ls.getSeat(obj)) |lseat| {
            s.layer_seat = lseat;
            lseat.setListener(*State, layer_seat_listener, s);
        } else |_| {}
    }
    if (s.cursor_theme) |t| obj.setXcursorTheme(t.ptr, s.cursor_size);
    s.mark(); // bindings waiting for a seat
}

// ---- bindings ----

/// Bindings are created and enabled in the next manage sequence.
pub fn grab_key(s: *State, k: types.KeyCombo) void {
    const kb = s.allocator.create(KeyBinding) catch return;
    kb.* = .{ .state = s, .combo = k };
    s.keys.append(s.allocator, kb) catch return s.allocator.destroy(kb);
    s.mark();
}

pub fn ungrab_all_keys(s: *State) void {
    for (s.keys.items) |k| {
        if (k.obj) |o| o.destroy();
        s.allocator.destroy(k);
    }
    s.keys.clearRetainingCapacity();
}

/// A grab with no button covers left, middle and right, like X's AnyButton
/// for the buttons that matter here.
pub fn set_pointer_grabs(s: *State, grabs: []const types.PointerGrab) void {
    for (s.buttons.items) |b| {
        if (b.obj) |o| o.destroy();
        s.allocator.destroy(b);
    }
    s.buttons.clearRetainingCapacity();

    for (grabs) |g| {
        const any = [_]types.Button{ 1, 2, 3 };
        const one = [_]types.Button{g.button orelse 1};
        const list: []const types.Button = if (g.button != null) &one else &any;
        for (list) |btn| {
            const ev = evdev_button(btn) orelse continue;
            const b = s.allocator.create(ButtonBinding) catch continue;
            b.* = .{ .state = s, .button = btn, .evdev = ev, .mods = g.mods };
            s.buttons.append(s.allocator, b) catch {
                s.allocator.destroy(b);
                continue;
            };
        }
    }
    s.mark();
}

fn river_mods(m: types.Mods) river.SeatV1.Modifiers {
    return @bitCast(@as(u32, @intCast(m)) & valid_mods);
}

fn evdev_button(b: types.Button) ?u32 {
    return switch (b) {
        1 => 0x110, // BTN_LEFT
        2 => 0x112, // BTN_MIDDLE
        3 => 0x111, // BTN_RIGHT
        8 => 0x113, // BTN_SIDE
        9 => 0x114, // BTN_EXTRA
        else => null, // 4-7 are scroll axes, not buttons, on Wayland
    };
}

/// Create the bindings river doesn't have yet, and enable them; keys are off
/// while a prompt has the keyboard.
pub fn manage_bindings(s: *State) void {
    if (s.seat) |seat| {
        if (s.xkb_bindings) |kb| {
            const tp = bars.typing(s);
            for (s.keys.items) |k| {
                if (k.obj == null) {
                    const obj = kb.getXkbBinding(seat, @intCast(k.combo.keysym), river_mods(k.combo.mods)) catch continue;
                    obj.setListener(*KeyBinding, key_listener, k);
                    k.obj = obj;
                }
                if (tp and k.enabled) {
                    k.obj.?.disable();
                    k.enabled = false;
                } else if (!tp and !k.enabled) {
                    k.obj.?.enable();
                    k.enabled = true;
                }
            }
        }
        for (s.buttons.items) |b| {
            if (b.obj == null) {
                const obj = seat.getPointerBinding(b.evdev, river_mods(b.mods)) catch continue;
                obj.setListener(*ButtonBinding, button_listener, b);
                b.obj = obj;
            }
            if (!b.enabled) {
                b.obj.?.enable();
                b.enabled = true;
            }
        }
    }
}

// ---- pointer ----

/// Start an interactive pointer op: motion arrives as op_delta.
pub fn capture_pointer(s: *State) void {
    if (s.op_active) return;
    s.op_active = true;
    s.op_start_pending = true;
    s.op_end_pending = false;
    s.op_origin = s.pointer_pos;
    s.mark();
}

pub fn release_pointer(s: *State) void {
    if (!s.op_active) return;
    s.op_active = false;
    if (s.op_start_pending) {
        s.op_start_pending = false; // never sent; nothing to end
    } else {
        s.op_end_pending = true;
        s.mark();
    }
}

fn shell_clicked(s: *State, shell: ?*river.ShellSurfaceV1) void {
    const sh = shell orelse return;
    if (s.error_bar) |bar| {
        if (bar.surf.shell == sh) {
            if (bars.hide_error(s)) s.push(.reserved_area_changed);
            return;
        }
    }
    if (!s.click_to_focus) return;
    var it = s.previews.valueIterator();
    while (it.next()) |pp| {
        if (pp.*.surf.shell != sh) continue;
        s.push(.{ .button_press = .{ .window = pp.*.handle, .button = 1, .mods = 0, .pos = s.pointer_pos } });
        return;
    }
}

// ---- manage sequence ----

/// Focus, pointer ops and warps: the seat requests that wait for a manage sequence.
pub fn manage_seat(s: *State) void {
    if (s.focus_dirty) {
        s.focus_dirty = false;
        if (s.seat) |seat| {
            if (s.prompt_bar) |bar| if (bar.grabbed) {
                if (bar.surf.mapped) {
                    seat.focusShellSurface(bar.surf.shell);
                    bar.focused = true;
                } else {
                    s.focus_dirty = true; // try again after it's rendered
                }
            };
            // While a layer surface holds exclusive focus, river ignores these anyway.
            if (!bars.typing(s) and !s.layer_focus_exclusive) {
                if (s.focus) |h| {
                    if (s.placed(h)) |p| switch (p) {
                        .window => |w| seat.focusWindow(w.obj),
                        .preview => |pv| seat.focusShellSurface(pv.surf.shell),
                    };
                } else {
                    seat.clearFocus();
                }
            }
        }
    }

    if (s.seat) |seat| {
        if (s.op_start_pending) {
            seat.opStartPointer();
            s.op_start_pending = false;
        }
        if (s.op_end_pending) {
            seat.opEnd();
            s.op_end_pending = false;
        }
        if (s.warp) |p| {
            seat.pointerWarp(p.x, p.y);
            s.warp = null;
        }
    }
}

// ---- listeners ----

fn seat_listener(_: *river.SeatV1, event: river.SeatV1.Event, s: *State) void {
    switch (event) {
        .pointer_position => |e| {
            s.pointer_pos = .{ .x = e.x, .y = e.y };
            if (output.at(s, s.pointer_pos)) |o| if (o.id != s.pointer_output) {
                s.pointer_output = o.id;
                s.push(.{ .pointer_output = o.id });
            };
        },
        .pointer_enter => |e| {
            const h = windows.handle_of(s, e.window);
            s.hovered = h;
            s.pending_enter = h;
        },
        .pointer_leave => s.hovered = null,
        .window_interaction => |e| {
            // Click-to-focus: core treats an unmodified press as "focus this".
            if (!s.click_to_focus) return;
            const h = windows.handle_of(s, e.window) orelse return;
            s.push(.{ .button_press = .{ .window = h, .button = 1, .mods = 0, .pos = s.pointer_pos } });
        },
        .op_delta => |e| {
            if (!s.op_active) return;
            s.push(.{ .pointer_motion = .{ .x = s.op_origin.x + e.dx, .y = s.op_origin.y + e.dy } });
        },
        .op_release => {
            if (!s.op_active) return;
            s.suppress_release = true;
            s.push(.{ .button_release = .{ .window = s.hovered, .button = s.op_button, .mods = 0, .pos = s.pointer_pos } });
        },
        .shell_surface_interaction => |e| shell_clicked(s, e.shell_surface),
        .removed => {},
        else => {},
    }
}

fn layer_seat_listener(_: *river.LayerShellSeatV1, event: river.LayerShellSeatV1.Event, s: *State) void {
    switch (event) {
        .focus_exclusive => s.layer_focus_exclusive = true,
        .focus_non_exclusive => {},
        .focus_none => {
            // A launcher or similar let go: give focus back to the WM's choice.
            s.layer_focus_exclusive = false;
            s.push(.refocus);
        },
    }
}

fn key_listener(_: *river.XkbBindingV1, event: river.XkbBindingV1.Event, k: *KeyBinding) void {
    switch (event) {
        .pressed => k.state.push(.{ .key = k.combo }),
        else => {},
    }
}

fn button_listener(_: *river.PointerBindingV1, event: river.PointerBindingV1.Event, b: *ButtonBinding) void {
    const s = b.state;
    switch (event) {
        .pressed => {
            s.op_button = b.button;
            s.push(.{ .button_press = .{ .window = s.hovered, .button = b.button, .mods = b.mods, .pos = s.pointer_pos } });
        },
        .released => {
            if (s.suppress_release) {
                s.suppress_release = false;
                return;
            }
            s.push(.{ .button_release = .{ .window = s.hovered, .button = b.button, .mods = b.mods, .pos = s.pointer_pos } });
        },
    }
}
