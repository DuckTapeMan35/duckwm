const std = @import("std");
const types = @import("types");
const wm_mod = @import("wm");
const fake = @import("platform");
const config = @import("config");
const WM = wm_mod.WM;

/// config/default.lua, as shipped.
pub const default_config = @embedFile("default_config");

pub const Harness = struct {
    allocator: std.mem.Allocator,
    /// On the heap: core keeps pointers into it.
    wm: *WM,

    /// A WM with one 1920x1080 output, set up as at startup with the given
    /// Lua config (null: none, as with --no-lua).
    pub fn init(allocator: std.mem.Allocator, lua_config: ?[:0]const u8) !Harness {
        const wm = try allocator.create(WM);
        errdefer allocator.destroy(wm);
        wm.* = try WM.create(allocator);
        errdefer wm.deinit();
        try wm_mod.output.init_all(wm);
        if (lua_config) |src| try config.load_source(wm, src);
        try wm.backend.start();
        try wm.start();
        return .{ .allocator = allocator, .wm = wm };
    }

    pub fn deinit(h: *Harness) void {
        h.wm.deinit();
        h.allocator.destroy(h.wm);
    }

    pub fn backend(h: *Harness) *fake.Backend {
        return &h.wm.backend;
    }

    /// One turn of the event loop: core handles every queued event, then
    /// commits, so the backend has the resulting scene.
    pub fn step(h: *Harness) void {
        while (h.wm.backend.next_event()) |ev| h.wm.handle_event(ev);
        h.wm.commit();
    }

    /// A plain client window maps, and core handles it.
    pub fn map(h: *Harness, handle: types.WindowHandle) void {
        h.backend().map(handle, .{});
        h.step();
    }

    /// A bound key is pressed: mods (types.mod bits) and the key's name.
    pub fn key(h: *Harness, mods: types.Mods, name: []const u8) void {
        h.backend().push(.{ .key = .{ .mods = mods, .keysym = fake.Backend.keysym(name) } });
        h.step();
    }

    /// The handle of the window core has focused, if it's a window.
    pub fn focused(h: *Harness) ?types.WindowHandle {
        const n = h.wm.focused orelse return null;
        return switch (n.content) {
            .window => |w| w,
            else => null,
        };
    }
};
