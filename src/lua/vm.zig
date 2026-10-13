const ziglua = @import("ziglua");
const wm_mod = @import("wm");
const types = @import("types");
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
}

pub fn reset_vm(wm: *WM) !*Lua {
    if (wm.lua) |old| {
        for (wm.rules.items) |ref| {
            old.unref(ziglua.registry_index, ref);
        }
        wm.rules.clearRetainingCapacity();
        old.deinit();
    }
    const lua = try Lua.init(wm.allocator);
    wm.lua = lua;
    setup_lua(wm, lua);
    wm.ungrab_keys();
    wm.keybinds.clearRetainingCapacity();
    wm.default_arranger_ref = 0;
    wm.reset_arranger_refs(&wm.graph);
    wm.clear_rgb_frame_classes();
    return lua;
}
