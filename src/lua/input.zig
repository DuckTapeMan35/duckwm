const ziglua = @import("ziglua");
const types = @import("types");
const util = @import("util.zig");
const Lua = ziglua.Lua;

// ---- key bindings ----
pub fn l_bind(lua: *Lua) i32 {
    const mods = lua.checkInteger(1);
    if (mods < 0) util.luaL_error_str(lua, "bind: invalid modifier mask");
    const key = lua.checkString(2);
    lua.checkType(3, .function);
    const wm = util.global_wm;
    const keysym = wm.backend.keysym_from_name(key) orelse
        util.luaL_error_str(lua, "bind: unknown keysym");
    lua.pushValue(3);
    const ref = lua.ref(ziglua.registry_index);
    wm.bind_lua(@intCast(mods), keysym, ref) catch {
        lua.unref(ziglua.registry_index, ref);
        util.luaL_error_str(lua, "bind: failed to bind key");
    };
    return 0;
}

// ---- pointer bindings ----
pub fn l_set_resize_modifier(lua: *Lua) i32 {
    util.global_wm.resize_modifier = util.check_mods(lua, 1);
    util.global_wm.sync_pointer_grabs();
    return 0;
}

pub fn l_set_float_modifier(lua: *Lua) i32 {
    util.global_wm.float_move_modifier = util.check_mods(lua, 1);
    util.global_wm.sync_pointer_grabs();
    return 0;
}

pub fn l_set_pan_modifier(lua: *Lua) i32 {
    util.global_wm.pan_modifier = util.check_mods(lua, 1);
    util.global_wm.sync_pointer_grabs();
    return 0;
}

pub fn l_set_pan_button(lua: *Lua) i32 {
    util.global_wm.pan_button = util.check_button(lua, 1);
    util.global_wm.sync_pointer_grabs();
    return 0;
}

pub fn l_set_float_move_button(lua: *Lua) i32 {
    util.global_wm.float_move_button = util.check_button(lua, 1);
    return 0;
}

pub fn l_set_float_resize_button(lua: *Lua) i32 {
    util.global_wm.float_resize_button = util.check_button(lua, 1);
    return 0;
}

// ---- focus behavior ----
pub fn l_set_click_to_focus(lua: *Lua) i32 {
    util.global_wm.set_click_to_focus(lua.toBoolean(1));
    return 0;
}

pub fn l_set_focus_follows_mouse(lua: *Lua) i32 {
    const enabled = lua.toBoolean(1);
    const wm = util.global_wm;
    if (wm.ffm_suspended) {
        wm.saved_focus_follows_mouse = enabled;
    } else {
        wm.focus_follows_mouse = enabled;
    }
    return 0;
}

// ---- cursor ----
pub fn l_get_cursor_pos(lua: *Lua) i32 {
    const p = util.global_wm.backend.pointer_position();
    lua.pushInteger(p.x);
    lua.pushInteger(p.y);
    return 2;
}

pub fn l_get_cursor_relative_to_focused(lua: *Lua) i32 {
    const wm = util.global_wm;
    const p = wm.backend.pointer_position();
    const focused = wm.focused orelse {
        lua.pushInteger(0);
        lua.pushInteger(0);
        return 2;
    };
    const center = node_center(focused);
    lua.pushInteger(p.x - center.x);
    lua.pushInteger(p.y - center.y);
    return 2;
}

pub fn l_warp_cursor(lua: *Lua) i32 {
    const x: i32 = @intCast(lua.checkInteger(1));
    const y: i32 = @intCast(lua.checkInteger(2));
    util.global_wm.backend.warp_pointer(.{ .x = x, .y = y });
    return 0;
}

pub fn l_warp_cursor_to_node(lua: *Lua) i32 {
    const id = util.check_node_id(lua, 1) orelse return 0;
    const node = util.global_wm.get_node_by_id(id) orelse return 0;
    util.global_wm.backend.warp_pointer(node_center(node));
    return 0;
}

pub fn l_get_mouse_node(lua: *Lua) i32 {
    const wm = util.global_wm;
    const p = wm.backend.pointer_position();
    if (wm.node_at(p)) |node| {
        if (wm.get_id_for_node(node)) |id| {
            lua.pushInteger(@intCast(id));
            return 1;
        }
    }
    lua.pushNil();
    return 1;
}

pub fn l_set_cursor_theme(lua: *Lua) i32 {
    const theme = lua.checkString(1);
    const size = lua.checkInteger(2);
    if (size < 0) util.luaL_error_str(lua, "set_cursor_theme: size must be non-negative");
    util.global_wm.backend.set_cursor_theme(theme, @intCast(size));
    return 0;
}

// ---- keyboard layout ----
pub fn l_set_keyboard_layout(lua: *Lua) i32 {
    const km: types.Keymap = .{
        .layout = lua.checkString(1),
        .variant = util.opt_str(lua, 2),
        .options = util.opt_str(lua, 3),
        .model = util.opt_str(lua, 4),
    };
    if (!util.global_wm.set_keyboard_layout(km))
        util.luaL_error_str(lua, "set_keyboard_layout: invalid layout, variant, options or model");
    return 0;
}

pub fn l_set_keyboard_layout_index(lua: *Lua) i32 {
    const i = lua.checkInteger(1);
    if (i < 0) util.luaL_error_str(lua, "set_keyboard_layout_index: index must be >= 0");
    util.global_wm.set_keyboard_layout_index(@intCast(i));
    return 0;
}

// ---- helpers ----
fn node_center(node: anytype) types.Point {
    return .{
        .x = node.x + @divTrunc(@as(i32, @intCast(node.width)), 2),
        .y = node.y + @divTrunc(@as(i32, @intCast(node.height)), 2),
    };
}
