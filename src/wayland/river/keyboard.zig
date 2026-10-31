const std = @import("std");
const types = @import("types");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const xkb = @import("xkbcommon");
const c = @import("rc");
const State = @import("state.zig").State;
const bars = @import("bars.zig");
const now_ms = @import("util.zig").now_ms;

// ---- river's keyboards ----
/// Compile the keymap and hand it to river, which applies it to every keyboard
/// once it says success.
pub fn set_keymap(s: *State, km: types.Keymap) bool {
    const config = s.xkb_config orelse return false;

    var arena = std.heap.ArenaAllocator.init(s.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const z = struct {
        fn f(al: std.mem.Allocator, v: []const u8) ?[*:0]const u8 {
            if (v.len == 0) return null;
            return (al.dupeSentinel(u8, v, 0) catch return null).ptr;
        }
    }.f;

    const ctx = xkb.Context.new(.no_flags) orelse return false;
    defer ctx.unref();
    var names: xkb.RuleNames = .{
        .rules = null,
        .model = z(a, km.model),
        .layout = z(a, km.layout),
        .variant = z(a, km.variant),
        .options = z(a, km.options),
    };
    const keymap = xkb.Keymap.newFromNames(ctx, &names, .no_flags) orelse return false;
    defer keymap.unref();
    const text = keymap.getAsString(.text_v1) orelse return false;
    defer std.c.free(text);
    const bytes = std.mem.span(text);

    // river mmaps this: a sealed memfd holding the keymap text plus its NUL.
    const fd = c.memfd_create("duckwm-keymap", c.MFD_CLOEXEC | c.MFD_ALLOW_SEALING);
    if (fd < 0) return false;
    defer _ = c.close(fd);
    if (c.write(fd, bytes.ptr, bytes.len + 1) != @as(isize, @intCast(bytes.len + 1))) return false;
    _ = c.fcntl(fd, c.F_ADD_SEALS, c.F_SEAL_SHRINK | c.F_SEAL_GROW | c.F_SEAL_WRITE | c.F_SEAL_SEAL);

    const obj = config.createKeymap(fd, .text_v1) catch return false;
    obj.setListener(*State, keymap_listener, s);
    s.pending_keymap = obj; // any earlier pending one is destroyed when it answers
    return true;
}

pub fn set_layout_index(s: *State, index: u32) void {
    s.layout_index = index;
    for (s.keyboards.items) |kb| kb.setLayoutByIndex(@intCast(index));
}

/// Give a keyboard the current keymap and layout.
fn configure(s: *State, kb: *river.XkbKeyboardV1) void {
    if (s.keymap) |km| kb.setKeymap(km);
    if (s.layout_index) |i| kb.setLayoutByIndex(@intCast(i));
}

/// river accepted a keymap: it replaces the current one on every keyboard.
fn keymap_ready(s: *State, km: *river.XkbKeymapV1) void {
    if (s.pending_keymap != km) return km.destroy(); // superseded by a newer one
    s.pending_keymap = null;
    if (s.keymap) |old| old.destroy();
    s.keymap = km;
    for (s.keyboards.items) |kb| configure(s, kb);
}

pub fn keysym_from_name(name: []const u8) ?types.Keysym {
    var buf: [64]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    const sym = xkb.Keysym.fromName(buf[0..name.len :0], .no_flags);
    if (sym == .NoSymbol) return null;
    return @intCast(@backingInt(sym));
}

/// The keysym's name ("Return", "h") written into buf, or null if it has none.
pub fn keysym_name(ks: types.Keysym, buf: []u8) ?[]const u8 {
    const sym: xkb.Keysym = @fromBackingInt(@intCast(ks));
    const n = sym.getName(buf.ptr, buf.len);
    if (n <= 0 or n >= buf.len) return null;
    return buf[0..@intCast(n)];
}

// ---- typing into the input bar ----
/// One key into the bar, as keysym, X-style modifiers and UTF-8 text.
fn push_prompt_key(s: *State, keycode: u32) void {
    const st = s.xkb_state orelse return;
    var k: types.PromptKey = .{
        .keysym = @intCast(@backingInt(st.keyGetOneSym(keycode))),
        .mods = xkb_mods(s),
    };
    var buf: [16]u8 = undefined;
    const n = st.keyGetUtf8(keycode, &buf);
    if (n <= k.text_buf.len) {
        @memcpy(k.text_buf[0..n], buf[0..n]);
        k.text_len = @intCast(n);
    }
    s.push(.{ .prompt_key = k });
}

fn xkb_mods(s: *State) types.Mods {
    const st = s.xkb_state orelse return 0;
    const effective: xkb.State.Component = @fromBackingInt(@intCast(xkb.State.Component.mods_effective));
    var m: types.Mods = 0;
    if (st.modNameIsActive("Shift", effective) > 0) m |= types.mod.shift;
    if (st.modNameIsActive("Control", effective) > 0) m |= types.mod.ctrl;
    if (st.modNameIsActive("Mod1", effective) > 0) m |= types.mod.alt;
    if (st.modNameIsActive("Mod4", effective) > 0) m |= types.mod.super;
    return m;
}

/// A key from the plain wl_keyboard: into the input bar while it has the keyboard.
fn key(s: *State, evdev: u32, pressed: bool) void {
    const keycode = evdev + 8; // evdev to xkb
    if (!pressed) {
        if (s.repeat_key == keycode) s.repeat_key = null;
        return;
    }
    if (!bars.typing(s)) return;
    push_prompt_key(s, keycode);
    const km = s.xkb_keymap orelse return;
    if (s.repeat_rate > 0 and km.keyRepeats(keycode) != 0) {
        s.repeat_key = keycode;
        s.repeat_next_ms = now_ms() + s.repeat_delay;
    }
}

/// Wayland leaves key repeat to the client: send the held key again when it's due.
pub fn repeat_due(s: *State) void {
    const kc = s.repeat_key orelse return;
    const now = now_ms();
    if (now < s.repeat_next_ms) return;
    push_prompt_key(s, kc);
    s.repeat_next_ms = now + @divTrunc(1000, @max(1, s.repeat_rate));
}

/// Release the plain keyboard and the xkb state, at shutdown.
pub fn deinit(s: *State) void {
    if (s.keyboard) |kb| kb.release();
    if (s.wl_seat) |ws| ws.release();
    if (s.xkb_state) |x| x.unref();
    if (s.xkb_keymap) |x| x.unref();
    if (s.xkb_ctx) |x| x.unref();
}

// ---- listeners ----
pub fn xkb_config_listener(_: *river.XkbConfigV1, event: river.XkbConfigV1.Event, s: *State) void {
    switch (event) {
        .xkb_keyboard => |e| {
            s.keyboards.append(s.allocator, e.id) catch return e.id.destroy();
            e.id.setListener(*State, keyboard_listener, s);
            configure(s, e.id);
        },
        .finished => {},
    }
}

fn keyboard_listener(kb: *river.XkbKeyboardV1, event: river.XkbKeyboardV1.Event, s: *State) void {
    switch (event) {
        .removed => {
            for (s.keyboards.items, 0..) |k, i| {
                if (k == kb) {
                    _ = s.keyboards.swapRemove(i);
                    break;
                }
            }
            kb.destroy();
        },
        else => {},
    }
}

fn keymap_listener(km: *river.XkbKeymapV1, event: river.XkbKeymapV1.Event, s: *State) void {
    switch (event) {
        .success => keymap_ready(s, km),
        .failure => |e| {
            std.debug.print("duckwm: river rejected keymap: {s}\n", .{e.error_msg});
            if (s.pending_keymap == km) s.pending_keymap = null;
            km.destroy();
        },
    }
}

pub fn wl_seat_listener(seat: *wl.Seat, event: wl.Seat.Event, s: *State) void {
    switch (event) {
        .capabilities => |e| {
            if (e.capabilities.keyboard and s.keyboard == null) {
                const kb = seat.getKeyboard() catch return;
                kb.setListener(*State, wl_keyboard_listener, s);
                s.keyboard = kb;
            } else if (!e.capabilities.keyboard) {
                if (s.keyboard) |kb| kb.release();
                s.keyboard = null;
            }
        },
        else => {},
    }
}

fn wl_keyboard_listener(_: *wl.Keyboard, event: wl.Keyboard.Event, s: *State) void {
    switch (event) {
        .keymap => |e| {
            defer _ = c.close(e.fd);
            if (e.format != .xkb_v1 or e.size == 0) return;
            const mem = c.mmap(null, e.size, c.PROT_READ, c.MAP_PRIVATE, e.fd, 0);
            if (mem == null or @intFromPtr(mem) == std.math.maxInt(usize)) return;
            defer _ = c.munmap(mem, e.size);
            const ctx = s.xkb_ctx orelse (xkb.Context.new(.no_flags) orelse return);
            s.xkb_ctx = ctx;
            const bytes: [*]const u8 = @ptrCast(mem.?);
            const km = xkb.Keymap.newFromBuffer(ctx, bytes, e.size - 1, .text_v1, .no_flags) orelse return;
            const st = xkb.State.new(km) orelse return km.unref();
            if (s.xkb_state) |old| old.unref();
            if (s.xkb_keymap) |old| old.unref();
            s.xkb_keymap = km;
            s.xkb_state = st;
        },
        .enter, .leave => s.repeat_key = null,
        .modifiers => |e| if (s.xkb_state) |st| {
            _ = st.updateMask(e.mods_depressed, e.mods_latched, e.mods_locked, 0, 0, e.group);
        },
        .key => |e| key(s, e.key, e.state == .pressed),
        .repeat_info => |e| {
            s.repeat_rate = e.rate;
            s.repeat_delay = e.delay;
        },
    }
}
