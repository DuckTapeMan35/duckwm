const std = @import("std");
const ziglua = @import("ziglua");
const wm_mod = @import("wm");
const types = @import("types");
const repl = @import("repl.zig");
const registrations = @import("registrations.zig");
const Lua = ziglua.Lua;
const WM = wm_mod.WM;

pub fn setup_lua(wm: *WM, lua: *Lua) void {
    _ = wm;
    lua.openLibs();
    lua.newTable();
    lua.pushInteger(types.mod.super);
    lua.setField(-2, "MOD_SUPER");
    lua.pushInteger(types.mod.alt);
    lua.setField(-2, "MOD_ALT");
    lua.pushInteger(types.mod.shift);
    lua.setField(-2, "MOD_SHIFT");
    lua.pushInteger(types.mod.ctrl);
    lua.setField(-2, "MOD_CTRL");
    lua.pushInteger(types.mod.num_lock);
    lua.setField(-2, "MOD_MOD2");
    lua.pushInteger(types.mod.mod3);
    lua.setField(-2, "MOD_MOD3");
    lua.pushInteger(types.mod.mod5);
    lua.setField(-2, "MOD_MOD5");
    lua.pushInteger(types.button.left);
    lua.setField(-2, "BUTTON_LEFT");
    lua.pushInteger(types.button.middle);
    lua.setField(-2, "BUTTON_MIDDLE");
    lua.pushInteger(types.button.right);
    lua.setField(-2, "BUTTON_RIGHT");
    lua.pushInteger(types.button.scroll_up);
    lua.setField(-2, "BUTTON_SCROLL_UP");
    lua.pushInteger(types.button.scroll_down);
    lua.setField(-2, "BUTTON_SCROLL_DOWN");
    lua.pushInteger(types.platform.x11);
    lua.setField(-2, "PLATFORM_X11");
    lua.pushInteger(types.platform.river);
    lua.setField(-2, "PLATFORM_RIVER");
    lua.pushInteger(wm_mod.platform_id);
    lua.setField(-2, "PLATFORM");
    for (registrations.all) |reg| {
        lua.pushFunction(reg.func);
        lua.setField(-2, reg.name);
    }
    lua.setGlobal("wm");
    repl.install(lua);
    install_arrange(lua);
}

/// wm.arrange, written in Lua: rows and columns, rectangles, track, and the
/// ready-made arrangers. It sets wm.arrange itself.
fn install_arrange(lua: *Lua) void {
    lua.loadBuffer(@embedFile("arrange.lua"), "=duckwm/arrange.lua", .text) catch {
        std.debug.print("wm.arrange: {s}\n", .{lua.toString(-1) catch "failed to load"});
        lua.pop(1);
        return;
    };
    lua.protectedCall(.{ .results = 0 }) catch {
        std.debug.print("wm.arrange: {s}\n", .{lua.toString(-1) catch "failed to run"});
        lua.pop(1);
    };
}

pub fn reset_vm(wm: *WM) !*Lua {
    wm.clear_config_binds();
    wm.lua_scope = 0;
    wm_mod.workspace_settings.clear_layer(wm, .config);
    for (wm.rules.items) |r| wm.release_callback(r.cb);
    wm.rules.clearRetainingCapacity();
    if (wm.default_arranger) |cb| wm.release_callback(cb);
    wm.default_arranger = null;
    for (wm.outputs.items) |o| wm.reset_arrangers(&o.root);
    wm.cancel_prompt();
    if (wm.lua) |old| old.deinit();
    wm.lua = null;

    const lua = try Lua.init(wm.allocator);
    wm.lua = lua;
    setup_lua(wm, lua);
    wm.clear_swallow_pairs();
    wm.clear_rgb_frame_classes();
    return lua;
}
