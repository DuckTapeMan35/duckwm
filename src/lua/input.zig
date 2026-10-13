const ziglua = @import("ziglua");
const util = @import("util.zig");
const Lua = ziglua.Lua;

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
