const std = @import("std");
const c = @import("xlib");
const types = @import("types");
const Backend = @import("backend.zig").Backend;

/// The same binding with CapsLock and NumLock on and off, so neither stops it.
const key_lock_masks = [_]c_uint{ 0, c.LockMask, c.Mod2Mask, c.LockMask | c.Mod2Mask };

// ---- keys ----
pub fn keysym_from_name(name: []const u8) ?types.Keysym {
    var buf: [64]u8 = undefined;
    const z = std.mem.printSentinel(&buf, "{s}", .{name}, 0) catch return null;
    const ks = c.XStringToKeysym(z.ptr);
    if (ks == c.NoSymbol) return null;
    return @intCast(ks);
}

pub fn grab_key(self: *const Backend, k: types.KeyCombo) void {
    const keycode = c.XKeysymToKeycode(self.display, k.keysym);
    if (keycode == 0) return;
    const mods: c_uint = k.mods;
    for (key_lock_masks) |lock| {
        _ = c.XGrabKey(self.display, keycode, mods | lock, self.root, 1, c.GrabModeAsync, c.GrabModeAsync);
    }
}

pub fn ungrab_all_keys(self: *const Backend) void {
    _ = c.XUngrabKey(self.display, c.AnyKey, c.AnyModifier, self.root);
    _ = c.XSync(self.display, 0);
}

/// Let go of the keyboard (unless the input bar holds it), e.g. when the
/// pointer moves over something duckwm doesn't manage.
pub fn release_keyboard_grab(self: *const Backend) void {
    if (self.bar) |b| if (b.grabbed) return; // the input bar holds it
    _ = c.XUngrabKeyboard(self.display, c.CurrentTime);
    _ = c.XSync(self.display, 0);
}

// ---- pointer ----
pub fn set_pointer_grabs(self: *Backend, grabs: []const types.PointerGrab) void {
    for (self.pointer_grabs[0..self.pointer_grab_count]) |g| {
        const btn: c_uint = if (g.button) |b| b else c.AnyButton;
        const mods: c_uint = g.mods;
        for (key_lock_masks) |lock| {
            _ = c.XUngrabButton(self.display, btn, mods | lock, self.root);
        }
    }

    const n = @min(grabs.len, self.pointer_grabs.len);
    for (grabs[0..n], 0..) |g, i| {
        self.pointer_grabs[i] = g;
        const btn: c_uint = if (g.button) |b| b else c.AnyButton;
        const mods: c_uint = g.mods;
        for (key_lock_masks) |lock| {
            _ = c.XGrabButton(
                self.display,
                btn,
                mods | lock,
                self.root,
                0,
                c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
                c.GrabModeAsync,
                c.GrabModeAsync,
                c.None,
                c.None,
            );
        }
    }
    self.pointer_grab_count = n;
    _ = c.XFlush(self.display);
}

/// Route all pointer motion and the button release to the WM (for a drag).
pub fn capture_pointer(self: *const Backend) void {
    _ = c.XGrabPointer(
        self.display,
        self.root,
        0,
        c.PointerMotionMask | c.ButtonReleaseMask,
        c.GrabModeAsync,
        c.GrabModeAsync,
        c.None,
        c.None,
        c.CurrentTime,
    );
}

/// End any pointer grab (e.g. an interrupted drag).
pub fn release_pointer(self: *const Backend) void {
    _ = c.XUngrabPointer(self.display, c.CurrentTime);
}

// ---- keymap ----
/// Runs setxkbmap; the server's MappingNotify then triggers keymap_changed.
pub fn set_keymap(self: *Backend, km: types.Keymap) bool {
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var argv: std.ArrayListUnmanaged(?[*:0]const u8) = .empty;
    const add = struct {
        fn f(al: std.mem.Allocator, list: *std.ArrayListUnmanaged(?[*:0]const u8), s: []const u8) void {
            const zs = al.dupeSentinel(u8, s, 0) catch return;
            list.append(al, zs.ptr) catch {};
        }
    }.f;
    add(a, &argv, "setxkbmap");
    add(a, &argv, "-layout");
    add(a, &argv, km.layout);
    if (km.variant.len > 0) {
        add(a, &argv, "-variant");
        add(a, &argv, km.variant);
    }
    if (km.model.len > 0) {
        add(a, &argv, "-model");
        add(a, &argv, km.model);
    }
    // An empty -option clears what's set; setxkbmap otherwise appends.
    add(a, &argv, "-option");
    add(a, &argv, "");
    if (km.options.len > 0) {
        add(a, &argv, "-option");
        add(a, &argv, km.options);
    }
    argv.append(a, null) catch return false;

    const pid = c.fork();
    if (pid < 0) return false;
    if (pid == 0) {
        _ = c.execvp("setxkbmap", @ptrCast(argv.items.ptr));
        c._exit(127);
    }
    var status: c_int = 0;
    _ = c.waitpid(pid, &status, 0);
    return true;
}

pub fn set_layout_index(self: *Backend, index: u32) void {
    _ = c.XkbLockGroup(self.display, c.XkbUseCoreKbd, index);
}
