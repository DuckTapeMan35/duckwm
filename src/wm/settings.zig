const std = @import("std");
const graph_mod = @import("graph");
const types = @import("types");
const core = @import("core.zig");
const scopes = @import("scopes.zig");
const WM = core.WM;
const Node = graph_mod.Node;

pub const Keybind = union(enum) {
    zig: *const fn (*WM) anyerror!void,
    /// A function the config gave.
    call: types.Callback,
    /// An encoded Request: the commands a bind_commands command gave, run as
    /// one transaction on each press. Owned (wm.allocator).
    commands: struct { bytes: []const u8, source: types.CallbackSource },
};

/// Who a bind belongs to; a press takes the highest. Each keeps its own, so
/// a client dying or the config reloading uncovers the binds beneath.
pub const Layer = enum(u2) {
    /// config.lua (and Zig actions): cleared on reload.
    config,
    /// The commands file (and anything else not from a client): the fallback.
    commands,
    /// A socket client: dropped when it disconnects.
    client,

    pub fn of(source: types.CallbackSource) Layer {
        return if (source == .client) .client else if (source == .lua) .config else .commands;
    }
};

/// A keybind's key: the combo, the workspace whose arranger made it (null:
/// global), its layer, and the path it was made within (0: none).
pub const BindKey = struct {
    combo: types.KeyCombo,
    owner: ?*graph_mod.Graph,
    layer: Layer,
    scope: scopes.Scope = scopes.everywhere,
};

/// Release what a bind owns.
pub fn free_keybind(wm: *WM, kb: Keybind) void {
    switch (kb) {
        .zig => {},
        .call => |cb| wm.release_callback(cb),
        .commands => |cmd| wm.allocator.free(cmd.bytes),
    }
}

/// Store a bind, replacing (and freeing) whatever the key had.
pub fn put_keybind(wm: *WM, key: BindKey, kb: Keybind) void {
    const old = wm.keybinds.fetchPut(wm.allocator, key, kb) catch {
        free_keybind(wm, kb);
        return;
    };
    if (old) |o| free_keybind(wm, o.value);
    wm.backend.grab_key(key.combo);
}

/// Remove a key's bind, whoever made it.
pub fn remove_keybind(wm: *WM, key: BindKey) void {
    const old = wm.keybinds.fetchRemove(key) orelse return;
    free_keybind(wm, old.value);
    // The backend can only drop every grab, so grab the remaining keys again.
    wm.ungrab_keys();
    wm.regrab_keys();
}

/// Drop the binds g's arranger made: it's being replaced, reset, or g is going away.
pub fn drop_owned_binds(wm: *WM, g: *graph_mod.Graph) void {
    var doomed: std.ArrayListUnmanaged(BindKey) = .empty;
    defer doomed.deinit(wm.allocator);
    var it = wm.keybinds.iterator();
    while (it.next()) |e| {
        if (e.key_ptr.owner == g) doomed.append(wm.allocator, e.key_ptr.*) catch {};
    }
    if (doomed.items.len == 0) return;
    for (doomed.items) |key| {
        const old = wm.keybinds.fetchRemove(key) orelse continue;
        free_keybind(wm, old.value);
    }
    wm.ungrab_keys();
    wm.regrab_keys();
}

pub fn set_preview_max_icon_size(wm: *WM, size: u32) void {
    wm.preview_defaults.max_icon_size = if (size == 0) null else size;
}

pub fn set_preview_colors(wm: *WM, bg: u32, win_bg: u32, border: u32, text: u32) void {
    wm.preview_defaults.bg = bg;
    wm.preview_defaults.win_bg = win_bg;
    wm.preview_defaults.border = border;
    wm.preview_defaults.text = text;
}

pub fn set_preview_font(wm: *WM, name: []const u8) void {
    wm.preview_defaults.set_font(name);
}

/// false if the backend could tell right away that the keymap is invalid.
pub fn set_keyboard_layout(wm: *WM, km: types.Keymap) bool {
    return wm.backend.set_keymap(km);
}

pub fn set_keyboard_layout_index(wm: *WM, index: u32) void {
    wm.backend.set_layout_index(index);
}

pub fn end_session(wm: *WM) void {
    wm.backend.end_session();
}

pub fn set_autoclean(wm: *WM, enabled: bool) void {
    wm.autoclean = enabled;
}

pub fn watch_file(wm: *WM, path: [:0]const u8) void {
    if (wm.inotify_fd < 0) {
        wm.inotify_fd = @intCast(std.os.linux.inotify_init1(std.os.linux.IN.CLOEXEC) catch return);
    }
    if (wm.inotify_wd >= 0) {
        _ = std.os.linux.inotify_rm_watch(wm.inotify_fd, wm.inotify_wd);
    }
    wm.inotify_wd = @intCast(std.os.linux.inotify_add_watch(
        wm.inotify_fd,
        path,
        std.os.linux.IN.CLOSE_WRITE | std.os.linux.IN.MOVED_TO,
    ));
}

pub fn watch_config_dir(wm: *WM, dir_path: [:0]const u8) void {
    if (wm.inotify_fd < 0) {
        const fd = std.os.linux.inotify_init1(std.os.linux.IN.CLOEXEC);
        if (fd < 0) return;
        wm.inotify_fd = @intCast(fd);
    }
    if (wm.inotify_wd >= 0) {
        _ = std.os.linux.inotify_rm_watch(wm.inotify_fd, wm.inotify_wd);
    }
    const wd = std.os.linux.inotify_add_watch(
        wm.inotify_fd,
        dir_path,
        std.os.linux.IN.CLOSE_WRITE | std.os.linux.IN.MOVED_TO,
    );
    if (wd >= 0) wm.inotify_wd = @intCast(wd);
}

pub fn unwatch_file(wm: *WM) void {
    if (wm.inotify_fd >= 0) {
        if (wm.inotify_wd >= 0) {
            _ = std.os.linux.inotify_rm_watch(wm.inotify_fd, wm.inotify_wd);
            wm.inotify_wd = -1;
        }
        _ = std.os.linux.close(wm.inotify_fd);
        wm.inotify_fd = -1;
    }
}

pub fn set_click_to_focus(wm: *WM, enabled: bool) void {
    wm.click_to_focus = enabled;
    wm.backend.set_click_to_focus(enabled);
}

/// Derive the root pointer grabs from the current modifier/button settings.
pub fn sync_pointer_grabs(wm: *WM) void {
    wm.effect(.sync_pointer_grabs);
}

pub fn apply_pointer_grabs(wm: *WM) void {
    var grabs: [3]types.PointerGrab = undefined;
    var n: usize = 0;
    if (wm.resize_modifier) |m| {
        grabs[n] = .{ .mods = m, .button = null };
        n += 1;
    }
    if (wm.float_move_modifier) |m| {
        grabs[n] = .{ .mods = m, .button = null };
        n += 1;
    }
    if (wm.pan_modifier) |m| {
        grabs[n] = .{ .mods = m, .button = wm.pan_button };
        n += 1;
    }
    wm.backend.set_pointer_grabs(grabs[0..n]);
}

/// Drop the binds the Lua config made, before it is re-run or its VM is
/// replaced. Call while the old VM still exists, so Lua refs are released.
pub fn clear_config_binds(wm: *WM) void {
    var doomed: std.ArrayListUnmanaged(BindKey) = .empty;
    defer doomed.deinit(wm.allocator);
    var it = wm.keybinds.iterator();
    while (it.next()) |e| {
        if (e.key_ptr.layer == .config) doomed.append(wm.allocator, e.key_ptr.*) catch {};
    }
    for (doomed.items) |key| {
        const old = wm.keybinds.fetchRemove(key) orelse continue;
        free_keybind(wm, old.value);
    }
    wm.ungrab_keys();
    wm.regrab_keys();
}

pub fn bind(wm: *WM, mods: types.Mods, keysym: types.Keysym, action: *const fn (*WM) anyerror!void) !void {
    wm.effect(.{
        .bind = .{
            .key = .{
                .combo = .{ .mods = mods, .keysym = keysym },
                .owner = wm.bind_owner,
                .scope = scopes.current(wm),
                .layer = .config,
            },
            .action = .{ .zig = action },
        },
    });
}

pub fn bind_callback(wm: *WM, mods: types.Mods, keysym: types.Keysym, cb: types.Callback) void {
    wm.effect(.{
        .bind = .{
            .key = .{
                .combo = .{ .mods = mods, .keysym = keysym },
                .owner = wm.bind_owner,
                .scope = scopes.current(wm),
                .layer = .of(wm.callback_source),
            },
            .action = .{ .call = cb },
        },
    });
}

pub fn bind_commands(wm: *WM, combo: types.KeyCombo, encoded: []const u8) void {
    wm.effect(.{
        .bind = .{
            .key = .{
                .combo = combo,
                .owner = wm.bind_owner,
                .scope = scopes.current(wm),
                .layer = .of(wm.callback_source),
            },
            .action = .{
                .commands = .{ .bytes = encoded, .source = wm.callback_source },
            },
        },
    });
}

pub fn unbind(wm: *WM, combo: types.KeyCombo) void {
    wm.effect(.{ .unbind = .{
        .combo = combo,
        .owner = wm.bind_owner,
        .scope = scopes.current(wm),
        .layer = .of(wm.callback_source),
    } });
}

pub fn ungrab_keys(wm: *WM) void {
    wm.backend.ungrab_all_keys();
}

pub fn regrab_keys(wm: *WM) void {
    var it = wm.keybinds.keyIterator();
    while (it.next()) |k| wm.backend.grab_key(k.combo);
}

pub fn forces_rgb(wm: *WM, node: *Node) bool {
    for (wm.rgb_frame_classes.items) |name| {
        if (std.mem.eql(u8, name, node.info.class()) or
            std.mem.eql(u8, name, node.info.instance())) return true;
    }
    return false;
}

pub fn clear_rgb_frame_classes(wm: *WM) void {
    for (wm.rgb_frame_classes.items) |name| wm.allocator.free(name);
    wm.rgb_frame_classes.clearRetainingCapacity();
}

pub fn reset_arrangers(wm: *WM, g: *graph_mod.Graph) void {
    wm.drop_owned_binds(g);
    if (g.arranger) |cb| wm.release_callback(cb);
    g.arranger = null;
    for (g.nodes.items) |node| {
        if (node.content == .workspace) reset_arrangers(wm, node.content.workspace);
    }
}

pub fn show_error(wm: *WM, msg: []const u8) void {
    std.debug.print("duckwm error: {s}\n", .{msg});
    wm.backend.show_error(msg) catch |err| {
        std.debug.print("duckwm: could not show error bar: {}\n", .{err});
        return;
    };
    wm.relayout();
}

pub fn hide_error(wm: *WM) void {
    if (wm.backend.hide_error()) wm.relayout();
}

/// The config directory changed: drain the pending inotify events and
/// reload, at most once per 200 ms (editors often write several times).
pub fn handle_config_events(self: *WM) void {
    var ibuf: [4096]u8 align(@alignOf(std.os.linux.inotify_event)) = undefined;
    while (true) {
        const n = std.posix.read(self.inotify_fd, &ibuf) catch break;
        if (n == 0) break;
        var drain_fds = [1]std.posix.pollfd{.{
            .fd = self.inotify_fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&drain_fds, 0) catch break;
        if (ready == 0 or drain_fds[0].revents & std.posix.POLL.IN == 0) break;
    }

    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
    const now_ms: i64 = ts.sec * 1000 + @divTrunc(ts.nsec, 1_000_000);
    if (now_ms - self.last_reload_time > 200) {
        self.last_reload_time = now_ms;
        if (self.reload_fn) |f| f(self);
    }
}
