const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;
const keys = @import("keys.zig");

/// A button combination core grabbed, as wayluck holds it.
pub const Binding = struct {
    state: *State,
    obj: *wayluck.WmButtonBindingV1,
    /// X-style (1 left, 2 middle, 3 right), which is what core speaks.
    button: types.Button,
    mods: types.Mods,
};

/// Replace every button grab with grabs. A grab with no button covers left,
/// middle and right, like X's AnyButton for the buttons that matter here.
pub fn set_grabs(s: *State, grabs: []const types.PointerGrab) void {
    ungrab_all(s);
    const manager = s.manager orelse return;
    for (grabs) |g| {
        const any = [_]types.Button{ 1, 2, 3 };
        const one = [_]types.Button{g.button orelse 1};
        const list: []const types.Button = if (g.button != null) &one else &any;
        for (list) |button| {
            const code = linux_button(button) orelse continue;
            const b = s.allocator.create(Binding) catch continue;
            const obj = manager.bindButton(code, g.mods & keys.known_mods) catch {
                s.allocator.destroy(b);
                continue;
            };
            b.* = .{ .state = s, .obj = obj, .button = button, .mods = g.mods };
            obj.setListener(*Binding, listener, b);
            s.buttons.append(s.allocator, b) catch {
                obj.destroy();
                s.allocator.destroy(b);
            };
        }
    }
}

pub fn ungrab_all(s: *State) void {
    for (s.buttons.items) |b| {
        b.obj.destroy();
        s.allocator.destroy(b);
    }
    s.buttons.clearRetainingCapacity();
}

/// X's button numbers as Linux's codes (BTN_LEFT, ...).
fn linux_button(b: types.Button) ?u32 {
    return switch (b) {
        1 => 0x110, // BTN_LEFT
        2 => 0x112, // BTN_MIDDLE
        3 => 0x111, // BTN_RIGHT
        8 => 0x113, // BTN_SIDE
        9 => 0x114, // BTN_EXTRA
        else => null, // 4-7 are scroll axes, not buttons, on Wayland
    };
}

fn listener(_: *wayluck.WmButtonBindingV1, event: wayluck.WmButtonBindingV1.Event, b: *Binding) void {
    const s = b.state;
    const ev: types.PointerButton = .{ .window = s.hovered, .button = b.button, .mods = b.mods, .pos = s.pointer_pos };
    switch (event) {
        .pressed => s.push(.{ .button_press = ev }),
        .released => s.push(.{ .button_release = ev }),
    }
}

// ---- what wayluck tells us ----
/// The pointer moved: during a drag, core hears it.
pub fn moved(s: *State, p: types.Point) void {
    s.pointer_pos = p;
    if (s.captured) s.push(.{ .pointer_motion = p });
    for (s.outputs.items) |o| {
        const r = o.rect;
        const inside = p.x >= r.x and p.y >= r.y and
            p.x < r.x + @as(i32, @intCast(r.width)) and p.y < r.y + @as(i32, @intCast(r.height));
        if (inside and o.id != s.pointer_output) {
            s.pointer_output = o.id;
            s.push(.{ .pointer_output = o.id });
        }
    }
}

/// The pointer went over h (for focus-follows-mouse), or off it.
pub fn entered(s: *State, h: types.WindowHandle) void {
    s.hovered = h;
    s.push(.{ .pointer_enter = h });
}

pub fn left(s: *State, h: types.WindowHandle) void {
    if (s.hovered == h) s.hovered = null;
}

/// A plain click on h: with click-to-focus, core treats it as a left
/// press, which focuses it (and raises it, floating).
pub fn clicked(s: *State, h: types.WindowHandle) void {
    if (!s.click_to_focus) return;
    s.push(.{ .button_press = .{ .window = h, .button = 1, .mods = 0, .pos = s.pointer_pos } });
}

// ---- drags ----
/// A drag starts: the pointer is core's until release.
pub fn capture(s: *State) void {
    if (s.captured) return;
    const manager = s.manager orelse return;
    s.captured = true;
    manager.grabPointer();
}

pub fn release(s: *State) void {
    if (!s.captured) return;
    s.captured = false;
    if (s.manager) |m| m.ungrabPointer();
}
