const std = @import("std");
const types = @import("types");
const xkb = @import("xkbcommon");
const wayland = @import("wayland");
const wayluck = wayland.client.wayluck;
const State = @import("state.zig").State;

/// A key combination core grabbed, as wayluck holds it.
pub const Binding = struct {
    state: *State,
    obj: *wayluck.WmKeyBindingV1,
    combo: types.KeyCombo,
};

/// The modifiers wayluck knows: the protocol numbers them as X does, like
/// duckwm, so they pass through; Caps and Num Lock don't take part.
pub const known_mods: types.Mods = types.mod.shift | types.mod.ctrl | types.mod.alt |
    types.mod.mod3 | types.mod.super | types.mod.mod5;

/// Take k from clients: pressing it becomes core's key event.
pub fn grab(s: *State, k: types.KeyCombo) void {
    const manager = s.manager orelse return;
    const b = s.allocator.create(Binding) catch return;
    const obj = manager.bindKey(@intCast(k.keysym), k.mods & known_mods) catch {
        s.allocator.destroy(b);
        return;
    };
    b.* = .{ .state = s, .obj = obj, .combo = k };
    obj.setListener(*Binding, listener, b);
    s.bindings.append(s.allocator, b) catch {
        obj.destroy();
        s.allocator.destroy(b);
    };
}

/// Give every key back to clients.
pub fn ungrab_all(s: *State) void {
    for (s.bindings.items) |b| {
        b.obj.destroy();
        s.allocator.destroy(b);
    }
    s.bindings.clearRetainingCapacity();
}

fn listener(_: *wayluck.WmKeyBindingV1, event: wayluck.WmKeyBindingV1.Event, b: *Binding) void {
    switch (event) {
        .pressed => b.state.push(.{ .key = b.combo }),
    }
}

// ---- the keyboard's layout ----
/// Give wayluck km. false: XKB can't make it (core's caller hears so at
/// once), and wayluck isn't asked.
pub fn set_keymap(s: *State, km: types.Keymap) bool {
    const manager = s.manager orelse return false;
    var arena = std.heap.ArenaAllocator.init(s.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const model = a.dupeSentinel(u8, km.model, 0) catch return false;
    const layout = a.dupeSentinel(u8, km.layout, 0) catch return false;
    const variant = a.dupeSentinel(u8, km.variant, 0) catch return false;
    const options = a.dupeSentinel(u8, km.options, 0) catch return false;

    // Made here first, as wayluck will: the same names, the same XKB data.
    const ctx = xkb.Context.new(.no_flags) orelse return false;
    defer ctx.unref();
    const opt = struct {
        fn f(v: [:0]const u8) ?[*:0]const u8 {
            return if (v.len == 0) null else v.ptr;
        }
    }.f;
    var names: xkb.RuleNames = .{
        .rules = null,
        .model = opt(model),
        .layout = opt(layout),
        .variant = opt(variant),
        .options = opt(options),
    };
    const keymap = xkb.Keymap.newFromNames(ctx, &names, .no_flags) orelse return false;
    keymap.unref();

    manager.setKeymap(model.ptr, layout.ptr, variant.ptr, options.ptr);
    return true;
}

/// Switch to the keymap's layout at index.
pub fn set_layout(s: *State, index: u32) void {
    if (s.manager) |m| m.setLayout(index);
}

// ---- key names ----
/// The keysym called name ("Return", "h"), or null if there's none.
pub fn keysym_from_name(name: []const u8) ?types.Keysym {
    var buf: [64]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    const sym = xkb.Keysym.fromName(buf[0..name.len :0], .no_flags);
    if (sym == .NoSymbol) return null;
    return @intCast(@backingInt(sym));
}

/// The keysym's name written into buf, or null if it has none.
pub fn keysym_name(ks: types.Keysym, buf: []u8) ?[]const u8 {
    const sym: xkb.Keysym = @fromBackingInt(@intCast(ks));
    const n = sym.getName(buf.ptr, buf.len);
    if (n <= 0 or n >= buf.len) return null;
    return buf[0..@intCast(n)];
}
